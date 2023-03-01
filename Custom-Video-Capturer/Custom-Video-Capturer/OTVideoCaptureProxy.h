//
//  otkit_objc_video_capture_driver.h
//  otkit-objc-libs
//
//  Created by Charley Robinson on 10/11/13.
//
//

#ifndef otkit_objc_libs_otkit_objc_video_driver_h
#define otkit_objc_libs_otkit_objc_video_driver_h

#include <AppKit/AppKit.h>
#include <OpenTok/OpenTok.h>
#include "OTVideoKit.h"

/* .....................................*/

@interface OTVideoCaptureProxy : NSObject

@property (readonly) struct otc_video_capturer_callbacks* otc_video_capture_driver;
@property (strong) id<OTVideoCapture> videoCapture;
- (id)init;
@end

otc_bool otc_video_capture_init(const otc_video_capturer *capturer,
                            void *user_data);

otc_bool otc_video_capture_release(const otc_video_capturer *capturer,
                                     void *user_data);

otc_bool otc_video_capture_start(const otc_video_capturer *capturer,
                                   void *user_data);

otc_bool otc_video_capture_stop(const otc_video_capturer *capturer,
                                  void *user_data);

otc_bool otc_video_capture_settings(const otc_video_capturer *capturer,
                                      void *user_data,
                                      struct otc_video_capturer_settings *settings);
#endif
