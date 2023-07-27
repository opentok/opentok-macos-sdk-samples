//
//  VideoRenderView.h
//  Video-Transformers
//
//  Created by Jerónimo Valli on 11/17/22.
//  Copyright (c) 2022 Vonage. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <opentok/opentok.h>

@interface VideoRenderView : NSOpenGLView<NSUserNotificationCenterDelegate>

- (BOOL)drawFrame:(const otc_video_frame*)frame;
- (BOOL)clearFrame;

- (void) startRecording;
- (void) stopRecording;
- (BOOL) isRecording;

@end
