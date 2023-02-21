#ifndef otk_mac_default_video_capturer_h
#define otk_mac_default_video_capturer_h

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "OTVideoKit.h"


typedef NS_ENUM(int32_t, OTMacDefaultVideoCapturerErrorCode) {

    OTMacDefaultVideoCapturerSuccess = 0,
    
    /** A parameter passed in to the request is null or invalid. */
    OTMacDefaultVideoCapturerNullOrInvalidParameter = 1011,

    /** Publisher couldn't access to the camera */
    OTMacDefaultVideoCapturerError = 1650,

    /** Publisher's capturer is not capturing frames */
    OTMacDefaultVideoCapturerNoFramesCaptured = 1660,

    /** Publisher's capturer authorization failed */
    OTMacDefaultVideoCapturerAuthorizationDenied = 1670,
};

@protocol OTMacDefaultVideoCaptureDelegate <NSObject>

@optional
- (void)videoCapture:(id<OTVideoCapture>)capturer didFailWithError:(OTError*)error;

@end


@protocol OTMacDefaultVideoCapturerObserver <OTVideoCapture>

@property(atomic, assign) id<OTMacDefaultVideoCaptureDelegate>delegate;

@end

@protocol OTMacDefaultVideoCapture;

@interface OTMacDefaultVideoCapturer : NSObject
    <AVCaptureVideoDataOutputSampleBufferDelegate, OTMacDefaultVideoCapturerObserver>
{
    @protected
    dispatch_queue_t _capture_queue;
}

@property (nonatomic, retain) AVCaptureSession *captureSession;
@property (nonatomic, retain) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, retain) AVCaptureDeviceInput *videoInput;

@property (nonatomic, assign) NSString* captureSessionPreset;

@property (nonatomic, assign) const otc_video_capturer *otcVideoCapturer;
@property (nonatomic, assign) enum otc_camera_capture_resolution cameraCaptureResolution;

@property (nonatomic, assign) double activeFrameRate;
- (BOOL)isAvailableActiveFrameRate:(double)frameRate;

@property (nonatomic, assign) AVCaptureDevicePosition cameraPosition;
@property (readonly) NSArray* availableCameraPositions;
- (BOOL)toggleCameraPosition;

- (enum OTMacDefaultVideoCapturerErrorCode)captureError;
- (void)initCapture;
- (int32_t) startCapture;
- (void) stopRunningAVCaptureSession;

- (int32_t) getCaptureWidth;
- (int32_t) getCaptureHeight;

@end

#endif /* otk_mac_default_video_capturer_h */

