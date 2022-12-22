//
//  OTBaseVideoView.m
//  OpenTok
//
//  Created by Sridhar Bollam on 10/30/18.
//  Copyright © 2018 TokBox. All rights reserved.
//

#import "OTBaseVideoView.h"
#import "OTMTLVideoView.h"

@implementation OTBaseVideoView

+ (OTBaseVideoView *)createVideoView
{
    if (MTLCreateSystemDefaultDevice())
    {
        OTBaseVideoView *mtlView = [[OTMTLVideoView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
        return mtlView;
    }
    
    return NULL;
}

- (void)getVideoViewSize:(int *)width height:(int *)height
{
    [NSException exceptionWithName:NSInternalInconsistencyException
                            reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                          userInfo:nil];
}

- (void)renderVideoFrame:(nonnull otc_video_frame*) frame
{
    [NSException exceptionWithName:NSInternalInconsistencyException
                            reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                          userInfo:nil];
}

#pragma mark - Public

- (void)setScalesToFit:(BOOL)scalesToFit {
    [NSException exceptionWithName:NSInternalInconsistencyException
                            reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                          userInfo:nil];
}

- (BOOL)scalesToFit {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (BOOL)mirroring {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (void)setMirroring:(BOOL)mirroring {
    [NSException exceptionWithName:NSInternalInconsistencyException
                            reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                          userInfo:nil];
}

- (BOOL)renderingEnabled {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

- (void)setRenderingEnabled:(BOOL)renderingEnabled {
    [NSException exceptionWithName:NSInternalInconsistencyException
                            reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                          userInfo:nil];
    
}

- (void)clearRenderBuffer {
    [NSException exceptionWithName:NSInternalInconsistencyException
                            reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                          userInfo:nil];
}

@end
