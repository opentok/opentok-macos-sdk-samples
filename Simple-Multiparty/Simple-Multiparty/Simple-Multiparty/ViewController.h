//
//  ViewController.h
//  Simple-Multiparty
//
//  Created by Jerónimo Valli on 1/4/23.
//

#import <Cocoa/Cocoa.h>
#import "OTMTLVideoView.h"
@interface ViewController : NSViewController
@property (weak) IBOutlet NSTextField *statusLbl;
@property (weak) IBOutlet NSButton *connectBtn;
@property (weak) IBOutlet NSButton *muteMicBtn;
@property (weak) IBOutlet NSButton *muteCamBtn;
@end

