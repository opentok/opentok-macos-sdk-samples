//
//  OTBaseVideoView.h
//  OpenTok
//
//  Created by Sridhar Bollam on 10/30/18.
//  Copyright © 2018 TokBox. All rights reserved.
//

#import <AppKit/AppKit.h>
#import <OpenTok/opentok.h>

NS_ASSUME_NONNULL_BEGIN

@protocol OTVideoRender <NSObject>;
- (void)renderVideoFrame:(nonnull otc_video_frame*) frame;
@end

@protocol OTRendererDelegate;

@interface OTBaseVideoView : NSView<OTVideoRender>

@property (nonatomic, assign) BOOL mirroring;
@property (nonatomic, assign) BOOL renderingEnabled;
@property (nonatomic, weak) id<OTRendererDelegate> delegate;
@property (nonatomic) BOOL scalesToFit;

// This will provide either OTGLKVideoView or OTMTLVideoView based on system capabilities
+ (OTBaseVideoView *)createVideoView;

- (void)clearRenderBuffer;

/* This is a private method for logging rendering view size */
- (void)getVideoViewSize:(int *)width height:(int *)height;

@end

@protocol OTRendererDelegate <NSObject>

- (void)renderer:(OTBaseVideoView *)renderer
 didReceiveFrame:(otc_video_frame*)frame;

@end
NS_ASSUME_NONNULL_END
