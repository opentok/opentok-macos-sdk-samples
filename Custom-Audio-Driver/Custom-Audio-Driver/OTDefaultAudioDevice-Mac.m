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

#define kSampleRate 48000

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
static NSInteger channelState;
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
    
    NSTimer *channelTimer;

    
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
        _audioFormat.numChannels = 2;
        _safetyQueue = dispatch_queue_create("ot-audio-driver",
                                             DISPATCH_QUEUE_SERIAL);
        _restartRetryCount = 0;
    }
    return self;
}

- (BOOL)setAudioBus:(id<OTAudioBus>)audioBus
{
    _audioBus = audioBus;
    _audioFormat = [[OTAudioFormat alloc] init];
    _audioFormat.sampleRate =  kSampleRate;
    _audioFormat.numChannels = 2;
    
    channelState = 1;  // Start with state 1
    channelTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                         target:self
                                                       selector:@selector(updateChannelState)
                                                       userInfo:nil
                                                        repeats:YES];
    
    return YES;
}
- (void)updateChannelState {
    channelState = (channelState % 6) + 1;
    NSLog(@"Channel State Updated to: %ld", (long)channelState);

    // Implement any additional functionality you need when the channel state changes
    // For example, update audio routing or processing here
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

#define TONE_FREQUENCY 440
#define M_TAU 2.0 * M_PI


static OSStatus recording_cb(void *ref_con,
                             AudioUnitRenderActionFlags *action_flags,
                             const AudioTimeStamp *time_stamp,
                             UInt32 bus_num,
                             UInt32 inNumberFrames,
                             AudioBufferList *ioData)
{
    OTDefaultAudioDeviceMac *dev = (__bridge OTDefaultAudioDeviceMac*) ref_con;
 
  
    
    if (dev->recording) {
        static float theta;

        // Assuming ioData has only one buffer for interleaved data
        SInt16 *buffer = (SInt16 *)ioData->mBuffers[0].mData;
        for (UInt32 frame = 0; frame < inNumberFrames; ++frame) {
            if (channelState == 1) {
                // Write left channel
                buffer[2 * frame] = (SInt16)(sin(theta) * 32767.0f);
                // Write right channel (silenced in your original example)
                buffer[2 * frame + 1] = 0;
            } else if (channelState == 2) {
                // Write left channel
                buffer[2 * frame] = 0;
                // Write right channel (silenced in your original example)
                buffer[2 * frame + 1] = 0; //0;
            } else if (channelState == 3) {
                // Write left channel
                buffer[2 * frame] = (SInt16)(sin(theta) * 32767.0f);;
                // Write right channel (silenced in your original example)
                buffer[2 * frame + 1] = (SInt16)(sin(theta) * 32767.0f);
            }else if (channelState == 4) {
                // Write left channel
                buffer[2 * frame] = 0;
                // Write right channel (silenced in your original example)
                buffer[2 * frame + 1] = 0;
            } else if (channelState == 5) {
                // Write left channel
                buffer[2 * frame] = 0;
                // Write right channel (silenced in your original example)
                buffer[2 * frame + 1] = (SInt16)(sin(theta) * 32767.0f);
            } else if (channelState == 6) {
                // Write left channel
                buffer[2 * frame] = 0;
                // Write right channel (silenced in your original example)
                buffer[2 * frame + 1] = 0;
            }
 

            // Increment theta for the tone frequency
            theta += M_TAU * TONE_FREQUENCY / kSampleRate;
            if (theta > M_TAU) {
                theta -= M_TAU;
            }
        }
        
  
        // Write the captured data to the audio bus
        [dev->_audioBus writeCaptureData:buffer
                          numberOfSamples:inNumberFrames]; // multiply by 2 because each frame now includes two samples (left and right)
        // Access the interleaved buffer
        SInt16 * interleavedBuffer = (SInt16 *)ioData->mBuffers[0].mData;

        // Set all samples to zero for both left and right channels
        for (UInt32 frame = 0; frame < inNumberFrames; ++frame) {
            interleavedBuffer[2 * frame] = 0;      // Left channel
            interleavedBuffer[2 * frame + 1] = 0;  // Right channel
        }

    }

//    // Ensure the buffer size remains constant
//    if (dev->buffer_size != ioData->mBuffers[0].mDataByteSize)
//        ioData->mBuffers[0].mDataByteSize = dev->buffer_size;
    
    update_recording_delay(dev);
    return noErr;
}

static void update_playout_delay(OTDefaultAudioDeviceMac* device) {
    device->_playoutDelayMeasurementCounter++;
        
    if (device->_playoutDelayMeasurementCounter >= 100) {
            device->_playoutDelay = (int)(device->_playout_AudioUnitProperty_Latency * 1000000);
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

    //
//    static float theta;
//
//     SInt16 *left = (SInt16 *)buffer_list->mBuffers[0].mData;
//     SInt16 *right = (SInt16 *)buffer_list->mBuffers[1].mData;
//     for (UInt32 frame = 0; frame < num_frames; ++frame) {
//         left[frame] =  (SInt16)(sin(theta) * 32767.0f);
//         right[frame] = 0; //(SInt16)(sin(theta) * 32767.0f);
//         theta        swx3e += M_TAU * TONE_FREQUENCY / SAMPLE_RATE;
//         if (theta > M_TAU) {
//             theta -= M_TAU;
//         }
//     }

    //
    uint32_t count =
    [dev->_audioBus readRenderData:buffer_list->mBuffers[0].mData
                   numberOfSamples:  num_frames];
 

    
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
    
    stream_format.mFormatID = kAudioFormatLinearPCM;
    stream_format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked; // Ensure no non-interleaved flag is set
    stream_format.mSampleRate = kSampleRate;
    stream_format.mChannelsPerFrame = 2;
    stream_format.mBitsPerChannel = 16;
    stream_format.mBytesPerFrame = (stream_format.mBitsPerChannel / 8) * stream_format.mChannelsPerFrame;
    stream_format.mFramesPerPacket = 1;
    stream_format.mBytesPerPacket = stream_format.mBytesPerFrame * stream_format.mFramesPerPacket;
      
    AudioComponentDescription audio_unit_description;
    audio_unit_description.componentType = kAudioUnitType_Output;
    audio_unit_description.componentSubType = isPlayout ? kAudioUnitSubType_DefaultOutput : kAudioUnitSubType_DefaultOutput;
    audio_unit_description.componentManufacturer = kAudioUnitManufacturer_Apple ;
    audio_unit_description.componentFlags = 0;
    audio_unit_description.componentFlagsMask = 0;
    
    AudioComponent found_vpio_unit_ref = AudioComponentFindNext(NULL, &audio_unit_description);
    
    AudioComponentInstanceNew(found_vpio_unit_ref, voice_unit);
    
    if (!isPlayout)
    {
        
        AURenderCallbackStruct input_callback;
        input_callback.inputProc = recording_cb;
        input_callback.inputProcRefCon = (__bridge void *)(self);
        
        CheckError(AudioUnitSetProperty(*voice_unit,
                                        kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Input, kOutputBus, &input_callback,
                                        sizeof(input_callback)),@"error 3");

        CheckError(AudioUnitSetProperty(*voice_unit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, kOutputBus,
                                        &stream_format, sizeof (stream_format)),@"playout AudioUnitSetProperty error");


        
    } else
    {


        CheckError(AudioUnitSetProperty(*voice_unit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, kOutputBus,
                                        &stream_format, sizeof (stream_format)),@"error b");
        AURenderCallbackStruct render_callback;
        render_callback.inputProc = playout_cb;;
        render_callback.inputProcRefCon = (__bridge void *)(self);
            CheckError(AudioUnitSetProperty(*voice_unit, kAudioUnitProperty_SetRenderCallback,
                                     kAudioUnitScope_Input, kOutputBus, &render_callback,
                                            sizeof(render_callback)),@"error last");
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
    int failed_initalize_attempts = 0;
    int kMaxInitalizeAttempts = 5;
    while (result != noErr) {
        ++failed_initalize_attempts;
        if (failed_initalize_attempts == kMaxInitalizeAttempts) {
            // Max number of initialization attempts exceeded, hence abort.
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
