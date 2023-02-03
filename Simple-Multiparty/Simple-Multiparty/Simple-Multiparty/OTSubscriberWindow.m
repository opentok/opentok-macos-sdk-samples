//
//  OTSubscriberWindow.m
//  Simple-Multiparty
//
//  Created by Jerónimo Valli on 1/5/23.
//

#import "OTSubscriberWindow.h"
#import <Foundation/Foundation.h>
#import <opentok/opentok.h>

@interface OTSubscriberWindow () {
    otc_subscriber *subscriber;
}

@end

@implementation OTSubscriberWindow {
    
}

- (void)windowDidLoad {
    [super windowDidLoad];
    
    subscriber = NULL;
}

- (void)setSubscriber:(otc_subscriber *)subs {
    subscriber = subs;
    
    [_streamLabel setStringValue:[NSString stringWithUTF8String:otc_stream_get_id(otc_subscriber_get_stream(subs))]];
}

- (otc_subscriber *) getSubscriber {
    return subscriber;
}

-(IBAction)onVideo:(id)sender {
    int state = (int)[(NSButton *)sender state];
    if(subscriber) {
        otc_subscriber_set_subscribe_to_video(subscriber, state == 1 ? OTC_TRUE : OTC_FALSE );
    }
}

-(IBAction)onAudio:(id)sender {
    int state = (int)[(NSButton *)sender state];
    if(subscriber) {
        otc_subscriber_set_subscribe_to_audio(subscriber, state == 1 ? OTC_TRUE : OTC_FALSE );
    }
}

-(IBAction)onSave:(id)sender {
    int state = (int)[(NSButton *)sender state];
    if (state == 1) {
        //[_videoView startRecording];
    } else {
        //[_videoView stopRecording];
    }
}


@end
