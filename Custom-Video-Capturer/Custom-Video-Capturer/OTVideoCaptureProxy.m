//
//
//  Created Rajkiran Talusani
//
//

#include "OTVideoCaptureProxy.h"
#include "OTMacDefaultVideoCapturer.h"

@implementation OTVideoCaptureProxy {
    struct otc_video_capturer_callbacks _otcVideoCapture;
    otc_video_capturer * _capturer;
    __strong id<OTVideoCapture> _videoCapture;
}
static NSString *const kVideoContentHintKeyPath = @"_videoCapture.videoContentHint";

#pragma mark - Object Lifecycle


- (id)init{
    self = [super init];
    if (self) {
        _videoCapture = [[OTMacDefaultVideoCapturer alloc] init];
        _otcVideoCapture.init =
        otc_video_capture_init;
        _otcVideoCapture.destroy =
        otc_video_capture_release;
        _otcVideoCapture.start =
        otc_video_capture_start;
        _otcVideoCapture.stop =
        otc_video_capture_stop;
        _otcVideoCapture.get_capture_settings =
        otc_video_capture_settings;
        _otcVideoCapture.user_data = (__bridge void *)_videoCapture;
        
    }
    return self;
}

- (struct otc_video_capturer_callbacks*) otc_video_capture_driver {
    return &_otcVideoCapture;
}

- (void)dealloc {
}

- (void)beginDestroy {
    
}

#pragma mark - Public API


otc_bool otc_video_capture_init(const otc_video_capturer *capturer,
                                void *user_data)
{
    NSLog(@"Init called");
    struct otc_video_capturer_callbacks *capturer_cb = (struct otc_video_capturer_callbacks *)capturer;
    OTMacDefaultVideoCapturer* proxy = (__bridge OTMacDefaultVideoCapturer *)(capturer_cb->user_data);
    proxy.otcVideoCapturer = capturer;
    [proxy initCapture];
    return true;
}

otc_bool otc_video_capture_release(const otc_video_capturer *capturer,
                                   void *user_data)
{
    struct otc_video_capturer_callbacks *capturer_cb = (struct otc_video_capturer_callbacks *)capturer;
    OTMacDefaultVideoCapturer* proxy = (__bridge OTMacDefaultVideoCapturer *)(capturer_cb->user_data);
    [proxy releaseCapture];
    return true;
}

otc_bool otc_video_capture_start(const otc_video_capturer *capturer,
                                 void *user_data)
{
    NSLog(@"Start called");
    struct otc_video_capturer_callbacks *capturer_cb = (struct otc_video_capturer_callbacks *)capturer;
    OTMacDefaultVideoCapturer* proxy = (__bridge OTMacDefaultVideoCapturer *)(capturer_cb->user_data);
    bool result = [proxy startCapture];
    return (result == 0);
}

otc_bool otc_video_capture_stop(const otc_video_capturer *capturer,
                                void *user_data)
{
    struct otc_video_capturer_callbacks *capturer_cb = (struct otc_video_capturer_callbacks *)capturer;
    OTMacDefaultVideoCapturer* proxy = (__bridge OTMacDefaultVideoCapturer *)(capturer_cb->user_data);
    bool result = [proxy stopCapture];
    return (result == 0);
}

otc_bool otc_video_capture_settings(const otc_video_capturer *capturer,
                                    void *user_data,
                                    struct otc_video_capturer_settings *settings)
{
    NSLog(@"Settings called");
    struct otc_video_capturer_callbacks *capturer_cb = (struct otc_video_capturer_callbacks *)capturer;
    OTMacDefaultVideoCapturer* proxy = (__bridge OTMacDefaultVideoCapturer *)(capturer_cb->user_data);
    OTVideoFormat* videoFormat = [[OTVideoFormat alloc] init];
    int32_t result = [proxy captureSettings:videoFormat];
    return (result == 0);
}

@end
