//
//  OpenTokWrapper.h
//  Basic-Video-Chat
//
//  Created by Jerónimo Valli on 11/16/22.
//

#import <Foundation/Foundation.h>
#import <opentok/opentok.h>
#include "VideoRenderView.h"

@protocol OpenTokWrapperDelegate <NSObject>
@optional
- (void)onSessionConnected:(NSString*)sessionId;
- (void)onSessionDisconnected:(NSString*)sessionId;
- (void)onSessionError;
- (void)onPublisherRenderFrame:(const otc_video_frame*)frame;
- (void)onSubscriberConnected;
- (void)onSubscriberRenderFrame:(const otc_video_frame*)frame;
- (void)onSubscriberDisconnected;
- (void)onSubscriberError;
@end

@interface OpenTokWrapper : NSObject {
  
}

@property (nonatomic, weak) id<OpenTokWrapperDelegate> delegate;
@property (strong) NSPointerArray *streamObjectList;

- (void)connect;
- (void)disconnect;
- (void)publish;
- (void)unpublish;

@end
