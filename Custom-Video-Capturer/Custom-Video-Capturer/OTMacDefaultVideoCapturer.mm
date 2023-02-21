#import <Availability.h>
#import "OTMacDefaultVideoCapturer.h"
#import "OTVideoKit.h"
#include <OpenTok/OpenTok.h>
#import <CoreVideo/CoreVideo.h>

#define kTimespanWithNoFramesBeforeRaisingAnError 20.0

@interface OTMacDefaultVideoCapturer()
@property (nonatomic, strong) NSTimer *noFramesCapturedTimer;
@end

@implementation OTMacDefaultVideoCapturer {
    OTVideoFrame* _videoFrame;
    
    uint32_t _captureWidth;
    uint32_t _captureHeight;
    NSString* _capturePreset;
    
    __strong AVCaptureSession *_captureSession;
    __strong AVCaptureDeviceInput *_videoInput;
    __strong AVCaptureVideoDataOutput *_videoOutput;

    BOOL _capturing;
    
    dispatch_source_t _blackFrameTimer;
    uint8_t* _blackFrame;
    double _blackFrameTimeStarted;
    
    enum OTMacDefaultVideoCapturerErrorCode _captureErrorCode;
    
    BOOL isFirstFrame;
}

@synthesize captureSession = _captureSession;
@synthesize delegate = _delegate;
@synthesize videoInput = _videoInput, videoOutput = _videoOutput;

#define OTK_MAC_DEFAULT_VIDEO_CAPTURE_INITIAL_FRAMERATE 20

-(id)init {
    self = [super init];
    if (self) {
        _capturePreset = AVCaptureSessionPreset640x480;
        [OTMacDefaultVideoCapturer dimensionsForCapturePreset:_capturePreset
                                                         width:&_captureWidth
                                                        height:&_captureHeight];
        _capture_queue = dispatch_queue_create("com.tokbox.OTVideoCapture",
                                               DISPATCH_QUEUE_SERIAL);
        _videoFrame = [[OTVideoFrame alloc] initWithFormat:
                      [OTVideoFormat videoFormatNV12WithWidth:_captureWidth
                                                       height:_captureHeight]];
        isFirstFrame = false;
    }
    return self;
}

- (void)setCameraCaptureResolution:(enum otc_camera_capture_resolution)cameraCaptureResolution {
    _cameraCaptureResolution = cameraCaptureResolution;
    NSString *validCapturePreset = [self getValidCaptureSessionPreset:cameraCaptureResolution];
    if (![validCapturePreset isEqualToString:@""]) {
        _capturePreset = validCapturePreset;
        [OTMacDefaultVideoCapturer dimensionsForCapturePreset:_capturePreset
                                                         width:&_captureWidth
                                                        height:&_captureHeight];
        [_videoFrame setFormat:[OTVideoFormat videoFormatNV12WithWidth:_captureWidth
                                                                height:_captureHeight]];
    }
}

- (NSString*)getValidCaptureSessionPreset:(enum otc_camera_capture_resolution)cameraCaptureResolution {
    AVCaptureSessionPreset sessionPreset;
    if (_cameraCaptureResolution == OTC_CAMERA_CAPTURE_RESOLUTION_LOW) {
        sessionPreset = AVCaptureSessionPreset320x240;
    } else if (_cameraCaptureResolution == OTC_CAMERA_CAPTURE_RESOLUTION_MEDIUM) {
        sessionPreset = AVCaptureSessionPreset640x480;
    } else if (_cameraCaptureResolution == OTC_CAMERA_CAPTURE_RESOLUTION_HIGH) {
        sessionPreset = AVCaptureSessionPreset1280x720;
    } else if (_cameraCaptureResolution == OTC_CAMERA_CAPTURE_RESOLUTION_1080P) {
        if (@available(macOS 10.15, *)) {
            sessionPreset = AVCaptureSessionPreset1920x1080;
        } else {
            //AVCaptureSessionPreset1920x1080 is not available
            sessionPreset = AVCaptureSessionPresetPhoto;
        }
    }
    if ([_captureSession canSetSessionPreset:sessionPreset]) {
        return sessionPreset;
    }
    OTError *err = [OTError errorWithDomain:OTK_MAC_PUBLISHER_ERROR_DOMAIN
                                       code:OTMacDefaultVideoCapturerNullOrInvalidParameter
                                   userInfo:nil];
    [self callDelegateOnError:err captureError:nil];
    return @"";
}

- (int32_t)captureSettings:(OTVideoFormat*)videoFormat {
    videoFormat.pixelFormat = OTPixelFormatNV12;
    videoFormat.imageWidth = _captureWidth;
    videoFormat.imageHeight = _captureHeight;
    return 0;
}

- (void)dealloc {
    [self stopCapture];
    [self releaseCapture];
    
    if (_capture_queue) {
        _capture_queue = nil;
    }
    _videoFrame = nil;
}

- (int32_t) getCaptureWidth {
    return _captureWidth;
}

- (int32_t) getCaptureHeight {
    return _captureHeight;
}

- (AVCaptureDevice *) cameraWithMediaTypeVideo {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        return device;
    }
    return nil;
}

- (BOOL) hasMultipleCameras {
    return [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count] > 1;
}

- (BOOL) hasTorch {
    return [[[self videoInput] device] hasTorch];
}

- (AVCaptureTorchMode) torchMode {
    return [[[self videoInput] device] torchMode];
}

- (void) setTorchMode:(AVCaptureTorchMode) torchMode {
    
    AVCaptureDevice *device = [[self videoInput] device];
    if ([device isTorchModeSupported:torchMode] &&
        [device torchMode] != torchMode)
    {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            [device setTorchMode:torchMode];
            [device unlockForConfiguration];
        }
    }
}

- (double) maxSupportedFrameRate {
    AVFrameRateRange* firstRange =
    [_videoInput.device.activeFormat.videoSupportedFrameRateRanges
                               objectAtIndex:0];
    
    CMTime bestDuration = firstRange.minFrameDuration;
    double bestFrameRate = bestDuration.timescale / bestDuration.value;
    CMTime currentDuration;
    double currentFrameRate;
    for (AVFrameRateRange* range in
         _videoInput.device.activeFormat.videoSupportedFrameRateRanges)
    {
        currentDuration = range.minFrameDuration;
        currentFrameRate = currentDuration.timescale / currentDuration.value;
        if (currentFrameRate > bestFrameRate) {
            bestFrameRate = currentFrameRate;
        }
    }
    
    return bestFrameRate;
}

- (BOOL)isAvailableActiveFrameRate:(double)frameRate
{
    return (nil != [self frameRateRangeForFrameRate:frameRate]);
}

- (double) activeFrameRate {
    CMTime minFrameDuration = _videoInput.device.activeVideoMinFrameDuration;
    double framesPerSecond = 0;
    if (minFrameDuration.timescale && minFrameDuration.value) {
        framesPerSecond = minFrameDuration.timescale / minFrameDuration.value;
    }
    
    return framesPerSecond;
}

- (AVFrameRateRange*)frameRateRangeForFrameRate:(double)frameRate {
    for (AVFrameRateRange* range in
         _videoInput.device.activeFormat.videoSupportedFrameRateRanges)
    {
        if (range.minFrameRate <= frameRate && frameRate <= range.maxFrameRate)
        {
            return range;
        }
    }
    return nil;
}

// Yes this "lockConfiguration" is somewhat silly but we're now setting
// the frame rate in initCapture *before* startRunning is called to
// avoid contention, and we already have a config lock at that point.
- (void)setActiveFrameRateImpl:(double)frameRate : (BOOL) lockConfiguration {
    
    if (!_videoOutput || !_videoInput) {
        return;
    }
    
    AVFrameRateRange* frameRateRange =
        [self frameRateRangeForFrameRate:frameRate];
    if (nil == frameRateRange) {
        NSLog(@"unsupported frameRate %f", frameRate);
        return;
    }
    CMTime desiredMinFrameDuration = CMTimeMake(1, frameRate);
    CMTime desiredMaxFrameDuration = CMTimeMake(1, frameRate);
    /*frameRateRange.maxFrameDuration*/;
    
    if(lockConfiguration) [_captureSession beginConfiguration];
    
    AVCaptureConnection *conn =
    [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (conn.supportsVideoMinFrameDuration)
        conn.videoMinFrameDuration = desiredMinFrameDuration;
    if (conn.supportsVideoMaxFrameDuration)
        conn.videoMaxFrameDuration = desiredMaxFrameDuration;
    if(lockConfiguration) [_captureSession commitConfiguration];
}

- (void)setActiveFrameRate:(double)frameRate {
    // Changing all AVCaptureSession configuration calls from async to sync
    // fixes deadlocks causing from external capturer while default capturer
    // deallocating, and also setting framerate and resolution while executing
    // the session setup
    dispatch_sync(_capture_queue, ^{
        return [self setActiveFrameRateImpl : frameRate : TRUE];
    });
}

+ (void)dimensionsForCapturePreset:(NSString*)preset
                             width:(uint32_t*)width
                            height:(uint32_t*)height
{
    if ([preset isEqualToString:AVCaptureSessionPreset320x240]) {
        *width = 320;
        *height = 240;
    } else if ([preset isEqualToString:AVCaptureSessionPreset352x288]) {
        *width = 352;
        *height = 288;
    } else if ([preset isEqualToString:AVCaptureSessionPreset640x480]) {
        *width = 640;
        *height = 480;
    } else if ([preset isEqualToString:AVCaptureSessionPreset1280x720]) {
        *width = 1280;
        *height = 720;
    } else if ([preset isEqualToString:AVCaptureSessionPresetPhoto]) {
        // see AVCaptureSessionPresetLow
        *width = 1920;
        *height = 1080;
    } else if ([preset isEqualToString:AVCaptureSessionPresetHigh]) {
        // see AVCaptureSessionPresetLow
        *width = 640;
        *height = 480;
    } else if ([preset isEqualToString:AVCaptureSessionPresetMedium]) {
        // see AVCaptureSessionPresetLow
        *width = 480;
        *height = 360;
    } else if ([preset isEqualToString:AVCaptureSessionPresetLow]) {
        // WARNING: This is a guess. might be wrong for certain devices.
        // We'll use updeateCaptureFormatWithWidth:height if actual output
        // differs from expected value
        *width = 192;
        *height = 144;
    } else if (@available(macOS 10.15, *)) {
        if ([preset isEqualToString:AVCaptureSessionPreset1920x1080]) {
            *width = 1920;
            *height = 1080;
        }
    }
}

- (void)updateCaptureFormatWithWidth:(uint32_t)width height:(uint32_t)height
{
    _captureWidth = width;
    _captureHeight = height;
    [_videoFrame setFormat:[OTVideoFormat
                           videoFormatNV12WithWidth:_captureWidth
                           height:_captureHeight]];
    
}

- (NSString*)captureSessionPreset {
    return _captureSession.sessionPreset;
}

- (void) setCaptureSessionPreset:(NSString*)preset {
    dispatch_sync(_capture_queue, ^{
        AVCaptureSession *session = [self captureSession];
        
        if ([session canSetSessionPreset:preset] &&
            ![preset isEqualToString:session.sessionPreset]) {
            
            [_captureSession beginConfiguration];
            _captureSession.sessionPreset = preset;
            _capturePreset = preset;
            
            [_videoOutput setVideoSettings:
             [NSDictionary dictionaryWithObjectsAndKeys:
              [NSNumber numberWithInt:
               kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
              kCVPixelBufferPixelFormatTypeKey,
              nil]];
            
            [_captureSession commitConfiguration];
        }
    });
}

- (BOOL) toggleCameraPosition {
    AVCaptureDevicePosition currentPosition = _videoInput.device.position;
    NSArray *cameras = [self availableCameraPositions];
    for (NSNumber* position in cameras) {
        if (position.integerValue != currentPosition) {
            if (position.integerValue == AVCaptureDevicePositionUnspecified) {
                [self setCameraPosition:AVCaptureDevicePositionUnspecified];
            } else if (position.integerValue == AVCaptureDevicePositionBack) {
                [self setCameraPosition:AVCaptureDevicePositionBack];
            } else if (position.integerValue == AVCaptureDevicePositionFront) {
                [self setCameraPosition:AVCaptureDevicePositionFront];
            }
        }
    }
    
    return YES;
}

- (NSArray*)availableCameraPositions {
    NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    NSMutableSet* result = [NSMutableSet setWithCapacity:devices.count];
    for (AVCaptureDevice* device in devices) {
        [result addObject:[NSNumber numberWithInteger:device.position]];
    }
    return [result allObjects];
}

- (AVCaptureDevicePosition)cameraPosition {
    return _videoInput.device.position;
}

- (void)setCameraPosition:(AVCaptureDevicePosition) position {
    __block BOOL success = NO;
    
    NSString* preset = self.captureSession.sessionPreset;
    
    if (![self hasMultipleCameras]) {
        return;
    }
    
    NSError *error;
    AVCaptureDeviceInput *newVideoInput;
    
    if (position == AVCaptureDevicePositionBack) {
        newVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:
                         [self cameraWithMediaTypeVideo] error:&error];
        [self setTorchMode:AVCaptureTorchModeOff];
        _videoOutput.alwaysDiscardsLateVideoFrames = YES;
    } else if (position == AVCaptureDevicePositionFront) {
        newVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:
                         [self cameraWithMediaTypeVideo] error:&error];
        _videoOutput.alwaysDiscardsLateVideoFrames = YES;
    } else {
        return;
    }
    
    dispatch_sync(_capture_queue, ^() {
        AVCaptureSession *session = [self captureSession];
        [session beginConfiguration];
        [session removeInput:_videoInput];
        success = YES;
        if ([session canAddInput:newVideoInput]) {
            [session addInput:newVideoInput];
            _videoInput = newVideoInput;
        } else {
            success = NO;
            [session addInput:_videoInput];
        }
        [session commitConfiguration];
    });
    if (success) {
        [self setCaptureSessionPreset:preset];
    }
    return;
}

- (void)releaseCapture {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVCaptureSessionRuntimeErrorNotification
                                                  object:nil];
    [self stopCapture];

    
    _captureSession = nil;
    _videoOutput = nil;
    _videoInput = nil;
    
    if (_blackFrameTimer) {
        _blackFrameTimer = nil;
    }
    
    free(_blackFrame);

}

- (void)setupAudioVideoSession {
    //-- Setup Capture Session.
    _captureErrorCode = OTMacDefaultVideoCapturerSuccess;
    _captureSession = [[AVCaptureSession alloc] init];
    [_captureSession beginConfiguration];
    
    if ([_captureSession canSetSessionPreset:_capturePreset]) {
        [_captureSession setSessionPreset:_capturePreset];
    } else {
        // If for some reason the connected camera doesn't support
        // the default VGA resolution (640x480) we use LOW preset
        _capturePreset = AVCaptureSessionPresetLow;
        [OTMacDefaultVideoCapturer dimensionsForCapturePreset:_capturePreset
                                                         width:&_captureWidth
                                                        height:&_captureHeight];
        [_videoFrame setFormat:[OTVideoFormat videoFormatNV12WithWidth:_captureWidth
                                                                height:_captureHeight]];
        if ([_captureSession canSetSessionPreset:_capturePreset]) {
            [_captureSession setSessionPreset:_capturePreset];
        }
    }
    
    if (@available(macOS 10.14, *)) {
        AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
        if (status != AVAuthorizationStatusAuthorized) {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                [self setupAudioVideoSession];
            }];
            return;
        }
    }
    //-- Create a video device and input from that Device.
    // Add the input to the capture session.
    AVCaptureDevice * videoDevice = [self cameraWithMediaTypeVideo];
    if(videoDevice == nil) {
        NSLog(@"ERROR[OpenTok]: Failed to acquire camera device for video "
              "capture.");
        [self invalidateNoFramesTimerSettingItUpAgain:NO];
        OTError *err = [OTError errorWithDomain:OTK_MAC_PUBLISHER_ERROR_DOMAIN
                                           code:OTMacDefaultVideoCapturerError
                                       userInfo:nil];
        [self callDelegateOnError:err captureError:nil];
        [_captureSession commitConfiguration];
        _captureSession = nil;
        return;
    }
    
    //-- Add the device to the session.
    NSError *error;
    _videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice
                                                         error:&error];
    
    if (AVErrorApplicationIsNotAuthorizedToUseDevice == error.code) {
        [self initBlackFrameSender];
    }
    
    if(error || _videoInput == nil) {
        NSLog(@"ERROR[OpenTok]: Failed to initialize default video caputre "
              "session. (error=%@)", error);
        [self invalidateNoFramesTimerSettingItUpAgain:NO];
        OTError *err = [OTError errorWithDomain:OTK_MAC_PUBLISHER_ERROR_DOMAIN
                                           code:(AVErrorApplicationIsNotAuthorizedToUseDevice
                                                 == error.code) ? OTMacDefaultVideoCapturerAuthorizationDenied :
                                                 OTMacDefaultVideoCapturerError
                                       userInfo:nil];
        [self callDelegateOnError:err captureError:error];
        _videoInput = nil;
        [_captureSession commitConfiguration];
        _captureSession = nil;
        return;
    }
    
    [_captureSession addInput:_videoInput];
    
    //-- Create the output for the capture session.
    _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [_videoOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    [_videoOutput setVideoSettings:
     [NSDictionary dictionaryWithObject:
      [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                                 forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    // The initial queue will be the main queue and then after receiving first frame,
    // we switch to _capture_queue. The reason for this is to detect initial
    // device orientation
    [_videoOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    [_captureSession addOutput:_videoOutput];
    
    [self setActiveFrameRateImpl
     : OTK_MAC_DEFAULT_VIDEO_CAPTURE_INITIAL_FRAMERATE : FALSE];
    
    [_captureSession commitConfiguration];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(captureSessionError:)
                                                 name:AVCaptureSessionRuntimeErrorNotification
                                               object:nil];

    NSLog(@"About to run capture session");
    [_captureSession startRunning];
}

- (void)captureSessionError:(NSNotification *)notification {
    [self invalidateNoFramesTimerSettingItUpAgain:NO];
    OTError *err = [OTError errorWithDomain:OTK_MAC_PUBLISHER_ERROR_DOMAIN
                                       code:OTMacDefaultVideoCapturerError
                                   userInfo:nil];
    NSError *captureSessionError = [notification.userInfo objectForKey:AVCaptureSessionErrorKey];
    [self callDelegateOnError:err captureError:captureSessionError];
}

- (void)initCapture {
    // Changing all AVCaptureSession configuration calls from async to sync
    // fixes deadlocks causing from external capturer while default capturer
    // deallocating, and also setting framerate and resolution while executing
    // the session setup
    dispatch_sync(_capture_queue, ^{
        [self setupAudioVideoSession];
    });
}

- (void)initBlackFrameSender {
    _blackFrameTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                     0, 0, _capture_queue);
    int blackFrameWidth = 320;
    int blackFrameHeight = 240;
    [self updateCaptureFormatWithWidth:blackFrameWidth height:blackFrameHeight];
    
    _blackFrame = static_cast<uint8_t *>(malloc(blackFrameWidth * blackFrameHeight * 3 / 2));
    _blackFrameTimeStarted = CACurrentMediaTime();
    
    uint8_t* yPlane = _blackFrame;
    uint8_t* uvPlane =
    &(_blackFrame[(blackFrameHeight * blackFrameWidth)]);

    memset(yPlane, 0x00, blackFrameWidth * blackFrameHeight);
    memset(uvPlane, 0x7F, blackFrameWidth * blackFrameHeight / 2);
    
    if (_blackFrameTimer)
    {
        dispatch_source_set_timer(_blackFrameTimer, dispatch_walltime(NULL, 0),
                                  250ull * NSEC_PER_MSEC,
                                  1ull * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(_blackFrameTimer, ^{
            if (!self->_capturing) {
                return;
            }
            
            double now = CACurrentMediaTime();
            self->_videoFrame.timestamp =
            CMTimeMake((now - self->_blackFrameTimeStarted) * 90000, 90000);
            self->_videoFrame.format.imageWidth = blackFrameWidth;
            self->_videoFrame.format.imageHeight = blackFrameHeight;
            
            self->_videoFrame.format.estimatedFramesPerSecond = 4;
            self->_videoFrame.format.estimatedCaptureDelay = 0;
            
            [self->_videoFrame clearPlanes];
            
            [self->_videoFrame.planes addPointer:yPlane];
            [self->_videoFrame.planes addPointer:uvPlane];
            
            [self consumeFrame:self->_videoFrame];
        });
        
        dispatch_resume(_blackFrameTimer);
    }
    
}

- (void)consumeFrame:(OTVideoFrame*)objcFrame
{
    enum otc_video_frame_format format = OTC_VIDEO_FRAME_FORMAT_UNKNOWN;
    if (objcFrame.format.pixelFormat == OTPixelFormatI420) {
        format = OTC_VIDEO_FRAME_FORMAT_YUV420P;
    } else if (objcFrame.format.pixelFormat == OTPixelFormatNV12) {
        format = OTC_VIDEO_FRAME_FORMAT_NV12;
    } else if (objcFrame.format.pixelFormat == OTPixelFormatARGB) {
        format = OTC_VIDEO_FRAME_FORMAT_ARGB32;
    }
    
    struct otc_video_frame_planar_memory_callbacks cb = {0};
    cb.user_data =  (__bridge_retained void *)objcFrame;
    cb.get_plane = consumeOBJCFrame_get_plane;
    cb.get_plane_stride = consumeOBJCFrame_get_plane_stride;
    cb.release = consumeOBJCFrame_release;
    
    otc_video_frame *otc_frame = otc_video_frame_new_planar_memory_wrapper(format,
                                                                           objcFrame.format.imageWidth,
                                                                           objcFrame.format.imageHeight,
                                                                           // The frame cannot shallow copied
                                                                           OTC_FALSE,
                                                                           &cb);
    
    if (objcFrame.metadata) {
        otc_video_frame_set_metadata(otc_frame, (uint8_t*)objcFrame.metadata.bytes, objcFrame.metadata.length);
    }
    
    otc_video_capturer_provide_frame(_otcVideoCapturer,
                                     0,
                                     otc_frame);
    otc_video_frame_delete(otc_frame);
}

const uint8_t * consumeOBJCFrame_get_plane(void *user_data, enum otc_video_frame_plane plane) {
    OTVideoFrame* frame = (__bridge OTVideoFrame*)user_data;
    if ([frame.planes pointerAtIndex:plane]) {
        return (uint8_t *)[frame.planes pointerAtIndex:plane];
    }
    return 0;
}

int consumeOBJCFrame_get_plane_stride(void *user_data,  enum otc_video_frame_plane plane) {
    OTVideoFrame* frame = (__bridge OTVideoFrame*)user_data;
    return (int)[[frame.format.bytesPerRow objectAtIndex:plane] integerValue];
}

void consumeOBJCFrame_release(void *user_data) {
    @autoreleasepool {
        OTVideoFrame* frame = (__bridge OTVideoFrame*)user_data;
        // Make sure we dont crash here for empty frames!
        if (frame)
            CFRelease((CFTypeRef)frame);
    }
}

- (BOOL) isCaptureStarted {
    return (_captureSession || _blackFrameTimer) && _capturing;
}

- (int32_t) startCapture {
    _capturing = YES;
    if (!_blackFrameTimer) {
        // Do no set timer if blackframe is being sent
        [self invalidateNoFramesTimerSettingItUpAgain:YES];
    }
    return 0;
}

- (void) stopRunningAVCaptureSession {
    // Dont dispatch the stopRunning to capture_queue synchronously here!
    // The dealloc of publihser may come from publisher render thread
    // which is actually coming from capture_queue and that results a deadlock!

    // OPENTOK-35212 We will catch the Begin/Commit configuration exception
    // and try to commit again to avoid the crash. This is safe since
    // we will be deallocating the AVCapturesession after this call.
    @try {
        [_captureSession stopRunning];
    }
    @catch (NSException *exception) {
        // Log the exception so that in case if there is an issue in
        // capturer behviour we can identify.
        NSDictionary *errorDictionary = @{ NSLocalizedDescriptionKey : exception.reason};
        OTError *err = [OTError errorWithDomain:OTK_MAC_PUBLISHER_ERROR_DOMAIN
                                           code:OTMacDefaultVideoCapturerError
                                       userInfo:errorDictionary];
        [self callDelegateOnError:err captureError:nil];
        // for safe side use try block again.
        @try {
            [_captureSession commitConfiguration];
            [_captureSession stopRunning];
        }
        @catch (NSException *exception) {
        }
    }
}

- (int32_t) stopCapture {
    _capturing = NO;
    [self invalidateNoFramesTimerSettingItUpAgain:NO];
    return 0;
}

- (void)invalidateNoFramesTimerSettingItUpAgain:(BOOL)value {
    [self.noFramesCapturedTimer invalidate];
    self.noFramesCapturedTimer = nil;
    if (value) {
        self.noFramesCapturedTimer = [NSTimer scheduledTimerWithTimeInterval:kTimespanWithNoFramesBeforeRaisingAnError
                                                                      target:self
                                                                    selector:@selector(noFramesTimerFired:)
                                                                    userInfo:nil
                                                                     repeats:NO];
    }
}

- (void)noFramesTimerFired:(NSTimer *)timer {
    if (self.isCaptureStarted) {
        OTError *err = [OTError errorWithDomain:OTK_MAC_PUBLISHER_ERROR_DOMAIN
                                           code:OTMacDefaultVideoCapturerNoFramesCaptured
                                       userInfo:nil];
        [self callDelegateOnError:err captureError:nil];
    }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
  didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{

}
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    
    if (!_capturing) {
        return;
    }
    
    if (isFirstFrame == false)
    {
        isFirstFrame = true;
        [_videoOutput setSampleBufferDelegate:self queue:_capture_queue];
    }
    if (self.noFramesCapturedTimer)
        [self invalidateNoFramesTimerSettingItUpAgain:NO];

    CMTime time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
   
    [self consumeImageBuffer:imageBuffer
                   timestamp:time
                    metadata:nil];
    
}

- (BOOL)consumeImageBuffer:(CVImageBufferRef)frame
                 timestamp:(CMTime)ts
                  metadata:(NSData* _Nullable)metadata {
    if (!frame || CFGetTypeID(frame) != CVPixelBufferGetTypeID()) {
        return NO;
    }
    
    BOOL success = YES;
    otc_video_frame *otc_frame = [OTVideoFrame convertPixelBufferToOTCFrame:frame];
    if (otc_frame == NULL)
    {
        success = NO;
    } else
    {
        otc_status status = OTC_SUCCESS;
        if (metadata) {
            status = otc_video_frame_set_metadata(otc_frame, (uint8_t*)metadata.bytes, metadata.length);
        }
        // We need to keep the publisher alive when we provide a new frame, because in this same function
        // the publisher preview frame is dispatched. If for some reason the publisher is deallocated in the on_frame
        // function it will cause a deadlock, so keeping the reference here we avoid that situation.
        if (status == OTC_SUCCESS)
        {
            status = otc_video_capturer_provide_frame(_otcVideoCapturer,
                                               0,
                                               otc_frame);
        }
        if (status != OTC_SUCCESS){
            success = NO;
        }
        otc_video_frame_delete(otc_frame);
    }
    
    return success;
}

-(void)callDelegateOnError:(OTError*)error captureError:(NSError *)captureError {
    _captureErrorCode = (enum OTMacDefaultVideoCapturerErrorCode)error.code;
    /* Take a look at OPENTOK-29290 for further details */
//    dispatch_async(dispatch_get_main_queue(), ^{
//        if ([self.delegate respondsToSelector:@selector(videoCapture:didFailWithError:)]) {
//            [self.delegate videoCapture:self didFailWithError:error];
//        }
//    });
}

-(enum OTMacDefaultVideoCapturerErrorCode)captureError
{
    return _captureErrorCode;
}

@synthesize videoCaptureConsumer;

@synthesize videoContentHint;

@end

