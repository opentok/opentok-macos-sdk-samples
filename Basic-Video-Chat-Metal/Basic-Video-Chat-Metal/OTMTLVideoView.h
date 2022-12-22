//
//  OTGLKVideoRender.h
//  otkit-objc-libs
//
//  Created by Charley Robinson on 5/23/14.
//
//

#import <AppKit/AppKit.h>
#import "OTBaseVideoView.h"
#import "OTMTLVideoRenderer.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

@interface OTMTLVideoView : OTBaseVideoView <MTKViewDelegate, OTVideoRender>

@end

