//
//  OTDefaultAudioDevice-Mac.m
//
//  Copyright (c) 2022 TokBox, Inc. All rights reserved.
//

#import "OTDefaultAudioDevice-Mac.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include <mach/mach.h>
#include <mach/mach_time.h>

#define kSampleRate 44100

#define OT_ENABLE_AUDIO_DEBUG 1
#define RETRY_COUNT 5

#if OT_ENABLE_AUDIO_DEBUG
#define OT_AUDIO_DEBUG(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#else
#define OT_AUDIO_DEBUG(fmt, ...)
#endif

static mach_timebase_info_data_t info;

static OSStatus recording_cb(void *ref_con,
                             AudioUnitRenderActionFlags *action_flags,
                             const AudioTimeStamp *time_stamp,
                             UInt32 bus_num,
                             UInt32 num_frames,
                             AudioBufferList *data);

static OSStatus playout_cb(void *ref_con,
                           AudioUnitRenderActionFlags *action_flags,
                           const AudioTimeStamp *time_stamp,
                           UInt32 bus_num,
                           UInt32 num_frames,
                           AudioBufferList *data);

@interface OTDefaultAudioDeviceMac ()
- (BOOL) setupAudioUnit:(AudioUnit *)voice_unit playout:(BOOL)isPlayout;
@end

@implementation OTDefaultAudioDeviceMac
{
    OTAudioFormat *_audioFormat;
    
    AudioUnit recording_voice_unit;
    AudioUnit playout_voice_unit;
    BOOL playing;
    BOOL playout_initialized;
    BOOL recording;
    BOOL recording_initialized;
    BOOL isRecorderInterrupted;
    BOOL isPlayerInterrupted;
    BOOL areListenerBlocksSetup;
    BOOL _isResetting;
    int _restartRetryCount;
    
    /* synchronize all access to the audio subsystem */
    dispatch_queue_t _safetyQueue;
    
@public
    id _audioBus;
    
    AudioBufferList *buffer_list;
    uint32_t buffer_num_frames;
    uint32_t buffer_size;
    uint32_t _recordingDelay;
    uint32_t _playoutDelay;
    uint32_t _playoutDelayMeasurementCounter;
    uint32_t _recordingDelayHWAndOS;
    uint32_t _recordingDelayMeasurementCounter;
    Float64 _playout_AudioUnitProperty_Latency;
    Float64 _recording_AudioUnitProperty_Latency;
}

#pragma mark - OTAudioDeviceImplementation

- (instancetype)init
{
    self = [super init];
    if (self) {
        _audioFormat = [[OTAudioFormat alloc] init];
        _audioFormat.sampleRate = kSampleRate;
        _audioFormat.numChannels = 1;
        _safetyQueue = dispatch_queue_create("ot-audio-driver",
                                             DISPATCH_QUEUE_SERIAL);
        _restartRetryCount = 0;
        
        struct AudioObjectPropertyAddress devicePropertyAddress;
        devicePropertyAddress.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
        devicePropertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
        devicePropertyAddress.mElement = kAudioObjectPropertyElementMain;
        
        AudioObjectPropertyListenerBlock audioObjectPropertyListenerBlock = ^(UInt32 numberAddresses, const AudioObjectPropertyAddress* addresses) {
            NSLog(@"AudioObjectPropertyListenerBlock");
            UInt32 index = 0;
            while (index < numberAddresses) {
                AudioObjectPropertyAddress address = addresses[index];
                switch (address.mSelector) {
                    case kAudioHardwarePropertyDefaultOutputDevice:
                        [self setDefaultOutput];
                        break;
                    default:
                        break;
                }
                index++;
            }
        };
        
        OSStatus status = AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &devicePropertyAddress, nil, audioObjectPropertyListenerBlock);
        if (status != noErr) {
            NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
            NSLog(@"error: %@", error.localizedDescription);
        }
    }
    return self;
}

- (BOOL)setAudioBus:(id<OTAudioBus>)audioBus
{
    _audioBus = audioBus;
    _audioFormat = [[OTAudioFormat alloc] init];
    _audioFormat.sampleRate = kSampleRate;
    _audioFormat.numChannels = 1;
    
    return YES;
}

- (void)dealloc
{
    [self removeObservers];
    [self teardownAudio];
    _audioFormat = nil;
   // [super dealloc];
}

- (OTAudioFormat*)captureFormat
{
    return _audioFormat;
}

- (OTAudioFormat*)renderFormat
{
    return _audioFormat;
}

- (BOOL)renderingIsAvailable
{
    return YES;
}

// Audio Unit lifecycle is bound to start/stop cycles, so we don't have much
// to do here.
- (BOOL)initializeRendering
{
    if (playing) {
        return NO;
    }
    if (playout_initialized) {
        return YES;
    }
    playout_initialized = true;
    return YES;
}

- (BOOL)renderingIsInitialized
{
    return playout_initialized;
}

- (BOOL)captureIsAvailable
{
    return YES;
}

// Audio Unit lifecycle is bound to start/stop cycles, so we don't have much
// to do here.
- (BOOL)initializeCapture
{
    if (recording) {
        return NO;
    }
    if (recording_initialized) {
        return YES;
    }
    recording_initialized = true;
    return YES;
}

- (BOOL)captureIsInitialized
{
    return recording_initialized;
}

- (BOOL)startRendering
{
    @synchronized(self) {
        OT_AUDIO_DEBUG(@"AudioDevice - startRendering started with playing flag = %d", playing);
        
        if (playing) {
            return YES;
        }
        
        playing = YES;
        // Initialize only when playout voice unit is already teardown
        if(playout_voice_unit == NULL)
        {
            OT_AUDIO_DEBUG(@"AudioDevice - setupAudioUnit for playout");
            
            if (NO == [self setupAudioUnit:&playout_voice_unit playout:YES]) {
                OT_AUDIO_DEBUG(@"AudioDevice - setupAudioUnit - failed");
                playing = NO;
                return NO;
            }
        }
        
        OSStatus result = AudioOutputUnitStart(playout_voice_unit);
        if (CheckError(result, @"startRendering.AudioOutputUnitStart")) {
            playing = NO;
        }
        OT_AUDIO_DEBUG(@"startRendering ended with playing flag = %d", playing);
        return playing;
    }
}

- (BOOL)stopRendering
{
    @synchronized(self) {
        OT_AUDIO_DEBUG(@"stopRendering started with playing flag = %d", playing);

        if (!playing) {
            return YES;
        }
        
        playing = NO;
        
        OSStatus result = AudioOutputUnitStop(playout_voice_unit);
        if (CheckError(result, @"stopRendering.AudioOutputUnitStop")) {
            return NO;
        }
        
        // publisher is already closed
        // Furthermore in compact mode of ansering phone the
        // AVAudioSessionInterruptionTypeEnded is not fired if audio is teared down.
        // So we don't tearDownAudio often , as before.
        
        if (!recording && !isPlayerInterrupted && !_isResetting)
        {
            OT_AUDIO_DEBUG(@"teardownAudio from stopRendering");
            [self teardownAudio];
        }
        OT_AUDIO_DEBUG(@"stopRendering finshed properly");
        return YES;
    }
}

- (BOOL)isRendering
{
    return playing;
}

- (BOOL)startCapture
{
    NSLog(@"Starting capture");
    @synchronized(self) {
        OT_AUDIO_DEBUG(@"startCapture started with recording flag = %d", recording);
        
        if (recording) {
            return YES;
        }
        
        recording = YES;
        // Initialize only when recording voice unit is already teardown
        if(recording_voice_unit == NULL)
        {
            if (NO == [self setupAudioUnit:&recording_voice_unit playout:NO]) {
                recording = NO;
                return NO;
            }
        }
        
        OSStatus result = AudioOutputUnitStart(recording_voice_unit);
        if (CheckError(result, @"startCapture.AudioOutputUnitStart")) {
            recording = NO;
        }
        OT_AUDIO_DEBUG(@"startCapture finished with recording flag = %d", recording);
        return recording;
    }
}

- (BOOL)stopCapture
{
    @synchronized(self) {
        OT_AUDIO_DEBUG(@"stopCapture started with recording flag = %d", recording);

        if (!recording) {
            return YES;
        }
        
        recording = NO;
        
        OSStatus result = AudioOutputUnitStop(recording_voice_unit);
        
        if (CheckError(result, @"stopCapture.AudioOutputUnitStop")) {
            return NO;
        }
        
        [self freeupAudioBuffers];
        
        // subscriber is already closed
        if (!playing && !isRecorderInterrupted && !_isResetting)
        {
            OT_AUDIO_DEBUG(@"teardownAudio from stopCapture");
            [self teardownAudio];
        }
        OT_AUDIO_DEBUG(@"stopCapture finshed properly");
        return YES;
    }
}

- (BOOL)isCapturing
{
    return recording;
}

- (uint16_t)estimatedRenderDelay
{
    return _playoutDelay;
}

- (uint16_t)estimatedCaptureDelay
{
    return _recordingDelay;
}

static NSString* FormatError(OSStatus error)
{
    uint32_t as_int = CFSwapInt32HostToLittle(error);
    uint8_t* as_char = (uint8_t*) &as_int;
    // see if it appears to be a 4-char-code
    if (isprint(as_char[0]) &&
        isprint(as_char[1]) &&
        isprint(as_char[2]) &&
        isprint(as_char[3]))
    {
        return [NSString stringWithFormat:@"%c%c%c%c",
                as_int >> 24, as_int >> 16, as_int >> 8, as_int];
    }
    else
    {
        // no, format it as an integer
        return [NSString stringWithFormat:@"%d", error];
    }
}

/**
 * @return YES if in error
 */
static bool CheckError(OSStatus error, NSString* function) {
    if (!error) return NO;
    
    NSString* error_string = FormatError(error);
    NSLog(@"ERROR[AudioDevice -]:Audio device error: %@ returned error: %@",
          function, error_string);
    
    return YES;
}

- (void)checkAndPrintError:(OSStatus)error function:(NSString *)function
{
    CheckError(error,function);
}

- (void)disposePlayoutUnit
{
    if (playout_voice_unit) {
        AudioUnitUninitialize(playout_voice_unit);
        AudioComponentInstanceDispose(playout_voice_unit);
        playout_voice_unit = NULL;
    }
}

- (void)disposeRecordUnit
{
    if (recording_voice_unit) {
        AudioUnitUninitialize(recording_voice_unit);
        AudioComponentInstanceDispose(recording_voice_unit);
        recording_voice_unit = NULL;
    }
}

- (void) teardownAudio
{
    [self disposePlayoutUnit];
    [self disposeRecordUnit];
    [self freeupAudioBuffers];
}

- (void)freeupAudioBuffers
{
    if (buffer_list && buffer_list->mBuffers[0].mData) {
        free(buffer_list->mBuffers[0].mData);
        buffer_list->mBuffers[0].mData = NULL;
    }
    
    if (buffer_list) {
        free(buffer_list);
        buffer_list = NULL;
        buffer_num_frames = 0;
    }
}

- (void) onRouteChangeEvent:(NSNotification *) notification
{
    OT_AUDIO_DEBUG(@"onRouteChangeEvent %@",notification);
    dispatch_async(_safetyQueue, ^() {
        [self handleRouteChangeEvent:notification];
    });
}

- (void) handleRouteChangeEvent:(NSNotification *) notification
{
    NSDictionary *interruptionDict = notification.userInfo;
    NSInteger routeChangeReason =
    [[interruptionDict valueForKey:AVAudioSessionRouteChangeReasonKey]
     integerValue];

    // We'll receive a routeChangedEvent when the audio unit starts; don't
    // process events we caused internally. And when switching calls using CallKit,
    // iOS system generates a category change which we should Ignore!
    if (AVAudioSessionRouteChangeReasonRouteConfigurationChange == routeChangeReason ||
        AVAudioSessionRouteChangeReasonCategoryChange == routeChangeReason)
    {
        return;
    }

    if(routeChangeReason == AVAudioSessionRouteChangeReasonOverride ||
       routeChangeReason == AVAudioSessionRouteChangeReasonCategoryChange)
    {
        
    }
    
    @synchronized(self) {
        // We've made it here, there's been a legit route change.
        // Restart the audio units with correct sample rate
        _isResetting = YES;
        
        if (recording)
        {
            [self stopCapture];
            [self disposeRecordUnit];
            [self startCapture];
        }
        
        if (playing)
        {
            [self stopRendering];
            [self disposePlayoutUnit];
            [self startRendering];
        }
        
        _isResetting = NO;
    }
}


- (void) removeObservers
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self];
    areListenerBlocksSetup = NO;
}

static void update_recording_delay(OTDefaultAudioDeviceMac* device) {
    device->_recordingDelayMeasurementCounter++;
    
    if (device->_recordingDelayMeasurementCounter >= 100) {
        // Update HW and OS delay every second, unlikely to change
        device->_recordingDelayHWAndOS = 0;
        device->_recordingDelayHWAndOS += (int)(device->_recording_AudioUnitProperty_Latency * 1000000);
        
        // To ms
        device->_recordingDelayHWAndOS = (device->_recordingDelayHWAndOS - 500) / 1000;
    
        // Reset counter
        device->_recordingDelayMeasurementCounter = 0;
    }
    
    device->_recordingDelay = device->_recordingDelayHWAndOS;
}

static OSStatus recording_cb(void *ref_con,
                             AudioUnitRenderActionFlags *action_flags,
                             const AudioTimeStamp *time_stamp,
                             UInt32 bus_num,
                             UInt32 num_frames,
                             AudioBufferList *data)
{
    OTDefaultAudioDeviceMac *dev = (__bridge OTDefaultAudioDeviceMac*) ref_con;
    
    if (!dev->buffer_list || num_frames > dev->buffer_num_frames)
    {
        if (dev->buffer_list) {
            free(dev->buffer_list->mBuffers[0].mData);
            free(dev->buffer_list);
        }
        
        dev->buffer_list =
        (AudioBufferList*)malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer));
        dev->buffer_list->mNumberBuffers = 1;
        dev->buffer_list->mBuffers[0].mNumberChannels = 1;
        
        dev->buffer_list->mBuffers[0].mDataByteSize = num_frames*sizeof(UInt16);
        dev->buffer_list->mBuffers[0].mData = malloc(num_frames*sizeof(UInt16));
        
        dev->buffer_num_frames = num_frames;
        dev->buffer_size = dev->buffer_list->mBuffers[0].mDataByteSize;
    }
    
    OSStatus status;
    status = AudioUnitRender(dev->recording_voice_unit,
                             action_flags,
                             time_stamp,
                             1,
                             num_frames,
                             dev->buffer_list);
    
    if (status != noErr) {
        CheckError(status, @"AudioUnitRender");
    }
    
    if (dev->recording) {
        
        // Some sample code to generate a sine wave instead of use the mic
        //        static double startingFrameCount = 0;
        //        double j = startingFrameCount;
        //        double cycleLength = kSampleRate. / 880.0;
        //        int frame = 0;
        //        for (frame = 0; frame < num_frames; ++frame)
        //        {
        //            int16_t* data = (int16_t*)dev->buffer_list->mBuffers[0].mData;
        //            Float32 sample = (Float32)sin (2 * M_PI * (j / cycleLength));
        //            (data)[frame] = (sample * 32767.0f);
        //            j += 1.0;
        //            if (j > cycleLength)
        //                j -= cycleLength;
        //        }
        //        startingFrameCount = j;
        [dev->_audioBus writeCaptureData:dev->buffer_list->mBuffers[0].mData
                         numberOfSamples:num_frames];
    }
    // some ocassions, AudioUnitRender only renders part of the buffer and then next
    // call to the AudioUnitRender fails with smaller buffer.
    if (dev->buffer_size != dev->buffer_list->mBuffers[0].mDataByteSize)
        dev->buffer_list->mBuffers[0].mDataByteSize = dev->buffer_size;
    
    update_recording_delay(dev);
    
    return noErr;
}

static void update_playout_delay(OTDefaultAudioDeviceMac* device) {
    device->_playoutDelayMeasurementCounter++;
        
    if (device->_playoutDelayMeasurementCounter >= 100) {
            device->_playoutDelay = 0;
            device->_playoutDelay += (int)(device->_playout_AudioUnitProperty_Latency * 1000000);
            // To ms
            if(device->_playoutDelay >= 500)
            {
            	device->_playoutDelay = (device->_playoutDelay - 500) / 1000;
            }
            // Reset counter
            device->_playoutDelayMeasurementCounter = 0;
    }
}

static OSStatus playout_cb(void *ref_con,
                           AudioUnitRenderActionFlags *action_flags,
                           const AudioTimeStamp *time_stamp,
                           UInt32 bus_num,
                           UInt32 num_frames,
                           AudioBufferList *buffer_list)
{
    OTDefaultAudioDeviceMac *dev = (__bridge OTDefaultAudioDeviceMac*) ref_con;
    
    if (!dev->playing) { return 0; }
    
    uint32_t count =
    [dev->_audioBus readRenderData:buffer_list->mBuffers[0].mData
                   numberOfSamples:num_frames];
    
    if (count != num_frames) {
        //TODO: Not really an error, but conerning. Network issues?
    }
    
    update_playout_delay(dev);
    
    return 0;
}

- (BOOL)setupAudioUnit:(AudioUnit *)voice_unit playout:(BOOL)isPlayout;
{
    OSStatus result;
    
    mach_timebase_info(&info);
    
    UInt32 bytesPerSample = sizeof(SInt16);
    stream_format.mFormatID    = kAudioFormatLinearPCM;
    stream_format.mFormatFlags =
    kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    stream_format.mBytesPerPacket  = bytesPerSample;
    stream_format.mFramesPerPacket = 1;
    stream_format.mBytesPerFrame   = bytesPerSample;
    stream_format.mChannelsPerFrame= 1;
    stream_format.mBitsPerChannel  = 8 * bytesPerSample;
    stream_format.mSampleRate = (Float64) kSampleRate;
    
    AudioComponentDescription audio_unit_description;
    audio_unit_description.componentType = kAudioUnitType_Output;
    audio_unit_description.componentSubType = isPlayout ? kAudioUnitSubType_DefaultOutput : kAudioUnitSubType_VoiceProcessingIO;
    audio_unit_description.componentManufacturer = 0;
    audio_unit_description.componentFlags = 0;
    audio_unit_description.componentFlagsMask = 0;
    
    AudioComponent found_vpio_unit_ref =
    AudioComponentFindNext(NULL, &audio_unit_description);
    
    result = AudioComponentInstanceNew(found_vpio_unit_ref, voice_unit);
    
    if (CheckError(result, @"AudioDevice - setupAudioUnit.AudioComponentInstanceNew")) {
        return NO;
    }
    
    if (!isPlayout)
    {
        UInt32 enable_input = 1;
        AudioUnitSetProperty(*voice_unit, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input, kInputBus, &enable_input,
                             sizeof(enable_input));
        AudioUnitSetProperty(*voice_unit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output, kInputBus,
                             &stream_format, sizeof (stream_format));
        AURenderCallbackStruct input_callback;
        input_callback.inputProc = recording_cb;
        input_callback.inputProcRefCon = (__bridge void *)(self);
        
        AudioUnitSetProperty(*voice_unit,
                             kAudioOutputUnitProperty_SetInputCallback,
                             kAudioUnitScope_Global, kInputBus, &input_callback,
                             sizeof(input_callback));
        UInt32 flag = 0;
        AudioUnitSetProperty(*voice_unit, kAudioUnitProperty_ShouldAllocateBuffer,
                             kAudioUnitScope_Output, kInputBus, &flag,
                             sizeof(flag));
        // Disable Output on record
        // see OPENTOK-34229
        UInt32 enable_output = 0;
        AudioUnitSetProperty(*voice_unit, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output, kOutputBus, &enable_output,
                             sizeof(enable_output));
        
    } else
    {
        UInt32 enable_output = 1;
        AudioUnitSetProperty(*voice_unit, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output, kOutputBus, &enable_output,
                             sizeof(enable_output));
        AudioUnitSetProperty(*voice_unit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, kOutputBus,
                             &stream_format, sizeof (stream_format));
        // Disable Input on playout
        // see OPENTOK-34229
        UInt32 enable_input = 0;
        AudioUnitSetProperty(*voice_unit, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input, kInputBus, &enable_input,
                             sizeof(enable_input));

        [self setPlayOutRenderCallback:*voice_unit];
    }
    
    Float64 f64 = 0;
    UInt32 size = sizeof(f64);
    OSStatus latency_result = AudioUnitGetProperty(*voice_unit,
                                                   kAudioUnitProperty_Latency,
                                                   kAudioUnitScope_Global,
                                                   0, &f64, &size);
    if (!isPlayout)
    {
        _recording_AudioUnitProperty_Latency = (0 == latency_result) ? f64 : 0;
    }
    else
    {
        _playout_AudioUnitProperty_Latency = (0 == latency_result) ? f64 : 0;
    }
    
    // Initialize the Voice-Processing I/O unit instance.
    result = AudioUnitInitialize(*voice_unit);
    
    // This patch is pickedup from WebRTC audio implementation and
    // is kind of a workaround. We encountered AudioUnitInitialize
    // failure in iOS 13 with Callkit while switching calls. The failure
    // code is not public so we can't do much.
    int failed_initalize_attempts = 0;
    int kMaxInitalizeAttempts = 5;
    while (result != noErr) {
        ++failed_initalize_attempts;
        if (failed_initalize_attempts == kMaxInitalizeAttempts) {
            // Max number of initialization attempts exceeded, hence abort.
            OT_AUDIO_DEBUG(@"AudioDevice - AudioUnit initialize failed %d",result);
            return false;
        }
        [NSThread sleepForTimeInterval:0.1f];
        result = AudioUnitInitialize(*voice_unit);
    }
    
    if (CheckError(result, @"setupAudioUnit.AudioUnitInitialize")) {
        return NO;
    }
    
    return YES;
}

- (BOOL)setPlayOutRenderCallback:(AudioUnit)unit
{
    AURenderCallbackStruct render_callback;
    render_callback.inputProc = playout_cb;;
    render_callback.inputProcRefCon = (__bridge void *)(self);
        OSStatus result = AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback,
                                 kAudioUnitScope_Input, kOutputBus, &render_callback,
                                 sizeof(render_callback));
    return (result == 0);
}

- (void)setDefaultOutput
{
    AudioDeviceID deviceID = [OTDefaultAudioDeviceMac getDefaultAudioOutputDeviceID];
    AVAudioEngine *engine = [[AVAudioEngine alloc] init];
    AudioUnit outputAudioUnit = [[engine outputNode] audioUnit];
    if (outputAudioUnit != nil) {
        OSStatus status = AudioUnitSetProperty(outputAudioUnit,
                                               kAudioOutputUnitProperty_CurrentDevice,
                                               kAudioUnitScope_Global,
                                               0,
                                               &deviceID,
                                               sizeof(deviceID));
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        NSLog(@"error: %@", error.localizedDescription);
    }
}

+ (AudioDeviceID)getDefaultAudioOutputDeviceID
{
    // Get the default output device.
    AudioDeviceID deviceID;
    UInt32 defaultOutputPropSize = sizeof(AudioDeviceID);
    AudioObjectPropertyAddress defaultOutputAddress = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    };
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                                 &defaultOutputAddress,
                                                 0,
                                                 NULL,
                                                 &defaultOutputPropSize,
                                                 &deviceID);
    if (status != noErr) {
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        NSLog(@"error: %@", error.localizedDescription);
    }

    NSLog(@" - UID:             %@", getStringProperty(deviceID, kAudioDevicePropertyDeviceUID));
    NSLog(@" - Model UID:       %@", getStringProperty(deviceID, kAudioDevicePropertyModelUID));
    NSLog(@" - Name:            %@", getStringProperty(deviceID, kAudioDevicePropertyDeviceNameCFString));
    NSLog(@" - Manufacturer:    %@", getStringProperty(deviceID, kAudioDevicePropertyDeviceManufacturerCFString));
    NSLog(@" - Input channels:  %@", @(getChannelCount(deviceID, kAudioObjectPropertyScopeInput)));
    NSLog(@" - Output channels: %@", @(getChannelCount(deviceID, kAudioObjectPropertyScopeOutput)));
    NSLog(@" - Input source:    %@", getSourceName(deviceID, kAudioObjectPropertyScopeInput));
    NSLog(@" - Output source:   %@", getSourceName(deviceID, kAudioObjectPropertyScopeOutput));
    NSLog(@" - Transport type:  %@", getCodeProperty(deviceID, kAudioDevicePropertyTransportType));
    NSLog(@" - Icon:            %@", getURLProperty(deviceID, kAudioDevicePropertyIcon));
    return deviceID;
}

static inline AudioObjectPropertyAddress makeGlobalPropertyAddress(AudioObjectPropertySelector selector)
{
    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,

    };
    return address;
}

static NSString *formatStatusError(OSStatus status)
{
    if (status == noErr) {
        return [NSString stringWithFormat:@"No error (%d)", status];
    }

    return [NSString stringWithFormat:@"Error \"%s\" (%d)",
            codeToString(status),
            status];
}

static char *codeToString(UInt32 code)
{
    static char str[5] = { '\0' };
    UInt32 swapped = CFSwapInt32HostToBig(code);
    memcpy(str, &swapped, sizeof(swapped));
    return str;
}

static NSString *getStringProperty(AudioDeviceID deviceID,
                                   AudioObjectPropertySelector selector)
{
    AudioObjectPropertyAddress address = makeGlobalPropertyAddress(selector);
    CFStringRef prop;
    UInt32 propSize = sizeof(prop);
    OSStatus status = AudioObjectGetPropertyData(deviceID,
                                                 &address,
                                                 0,
                                                 NULL,
                                                 &propSize,
                                                 &prop);
    if (status != noErr) {
        return formatStatusError(status);
    }
    return (__bridge_transfer NSString *)prop;
}

static NSUInteger getChannelCount(AudioDeviceID deviceID,
                                  AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyStreamConfiguration,
        scope,
        kAudioObjectPropertyElementMain,
    };

    AudioBufferList streamConfiguration;
    UInt32 propSize = sizeof(streamConfiguration);
    OSStatus status = AudioObjectGetPropertyData(deviceID,
                                                 &address,
                                                 0,
                                                 NULL,
                                                 &propSize,
                                                 &streamConfiguration);
    if (status != noErr) {
        NSLog(@"%@", formatStatusError(status));
        return 0;
    }

    NSUInteger channelCount = 0;
    for (NSUInteger i = 0; i < streamConfiguration.mNumberBuffers; i++)
    {
        channelCount += streamConfiguration.mBuffers[i].mNumberChannels;
    }

    return channelCount;
}

static NSString *getSourceName(AudioDeviceID deviceID,
                               AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyDataSource,
        scope,
        kAudioObjectPropertyElementMain,
    };

    UInt32 sourceCode;
    UInt32 propSize = sizeof(sourceCode);

    OSStatus status = AudioObjectGetPropertyData(deviceID,
                                                 &address,
                                                 0,
                                                 NULL,
                                                 &propSize,
                                                 &sourceCode);
    if (status != noErr) {
        return formatStatusError(status);
    }

    return [NSString stringWithFormat:@"%s (%d)",
            codeToString(sourceCode),
            sourceCode];
}

static NSString *getCodeProperty(AudioDeviceID deviceID,
                                 AudioObjectPropertySelector selector)
{
    AudioObjectPropertyAddress address = makeGlobalPropertyAddress(selector);
    UInt32 prop;
    UInt32 propSize = sizeof(prop);
    OSStatus status = AudioObjectGetPropertyData(deviceID,
                                                 &address,
                                                 0,
                                                 NULL,
                                                 &propSize,
                                                 &prop);
    if (status != noErr) {
        return formatStatusError(status);
    }

    return [NSString stringWithFormat:@"%s (%d)",
            codeToString(prop),
            prop];
}

static NSString *getURLProperty(AudioDeviceID deviceID,
                                AudioObjectPropertySelector selector)
{
    AudioObjectPropertyAddress address = makeGlobalPropertyAddress(selector);
    CFURLRef prop;
    UInt32 propSize = sizeof(prop);
    OSStatus status = AudioObjectGetPropertyData(deviceID,
                                                 &address,
                                                 0,
                                                 NULL,
                                                 &propSize,
                                                 &prop);
    if (status != noErr) {
        return formatStatusError(status);
    }

    NSURL *url = (__bridge_transfer NSURL *)prop;
    return url.absoluteString;
}

@end
