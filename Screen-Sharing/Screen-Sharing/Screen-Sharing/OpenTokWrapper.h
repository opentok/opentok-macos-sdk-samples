//
//  OpenTokWrapper.h
//  Screen-Sharing
//
//  Created by Jerónimo Valli on 11/16/22.
//

#import <Foundation/Foundation.h>
#import <opentok/opentok.h>
#include "VideoRenderView.h"
#import <CoreMedia/CoreMedia.h>

@protocol OpenTokWrapperDelegate <NSObject>
@optional
- (void)onSessionConnected:(NSString*)sessionId;
- (void)onSessionDisconnected:(NSString*)sessionId;
- (void)onSessionError:(NSString*)error;
- (void)onPublisherRenderFrame:(const otc_video_frame*)frame;
- (void)onSubscriberConnected;
- (void)onSubscriberRenderFrame:(const otc_video_frame*)frame;
- (void)onSubscriberDisconnected;
- (void)onSubscriberError:(NSString*)error;
- (void)onVideoCapturerDestroy:(const otc_video_capturer*)video_capturer;
- (void)onVideoCapturerStart:(const otc_video_capturer*)video_capturer;
@end

@interface OpenTokWrapper : NSObject {
  
}

- (id)initWithDelegate:(id<OpenTokWrapperDelegate>)delegate;

@property (nonatomic, weak) id<OpenTokWrapperDelegate> delegate;
@property (strong) NSPointerArray *streamObjectList;

- (void)connect;
- (void)disconnect;
- (void)publish;
- (void)unpublish;
- (void)consumeFrame:(CMSampleBufferRef)sampleBufferRef;
+ (struct otc_video_frame*)convertPixelBufferToOTCFrame:(CVImageBufferRef)frame;

@end
