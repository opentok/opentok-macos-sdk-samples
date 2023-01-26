//
//  ViewController.h
//  Basic-Sample-Mac-C
//
//  Created by Rajkiran Talusani on 27/9/22.
//

#import <Cocoa/Cocoa.h>
#import "OTMTLVideoView.h"
@interface ViewController : NSViewController
@property (weak) IBOutlet NSTextField *statusLbl;
@property (weak) IBOutlet NSButton *connectBtn;
@property (weak) IBOutlet NSButton *muteMicBtn;
@property (weak) IBOutlet NSButton *muteCamBtn;
@end

