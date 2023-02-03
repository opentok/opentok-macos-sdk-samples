//
//  OTSubscriberWindow.h
//  Simple-Multiparty
//
//  Created by Jerónimo Valli on 1/5/23.
//

#import <Cocoa/Cocoa.h>
#import "ViewController.h"
#import "OTMTLVideoView.h"
#include <OpenTok/opentok.h>

@interface OTSubscriberWindow : NSWindowController

@property (weak) ViewController *viewController;
@property (assign) IBOutlet OTMTLVideoView *videoView;
@property (assign) IBOutlet NSTextField *streamLabel;

- (void) setSubscriber:(otc_subscriber *)subs;
- (otc_subscriber *) getSubscriber;

@end
