//
//  AppDelegate.m
//  Basic-Sample-Mac-C
//
//  Created by Rajkiran Talusani on 27/9/22.
//

#import "AppDelegate.h"

@interface AppDelegate ()


@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    
    // Insert code here to tear down your application
    [[NSApplication sharedApplication] terminate:nil];
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application
{
    return YES;
}
@end
