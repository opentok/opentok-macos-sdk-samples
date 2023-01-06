//
//  ViewController.m
//  Simple-Multiparty
//
//  Created by Jerónimo Valli on 1/4/23.
//

#import "ViewController.h"
#import <OpenTok/opentok.h>
#import "OTMTLVideoView.h"
#import "OTSubscriberWindow.h"

// Replace with your OpenTok API key
static char* const kApiKey = "";
// Replace with your generated session ID
static char* const kSessionId = "";
// Replace with your generated token
static char* const kToken = "";

otc_session *session = NULL;
otc_publisher *publisher = NULL;
OTMTLVideoView *pubView = NULL;
NSMutableArray<OTSubscriberWindow*> *arraySubscribersView = NULL;

@interface ViewController ()

@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) BOOL isCamMuted;
@property (nonatomic, assign) BOOL isMicMuted;

@end

@implementation ViewController

@synthesize statusLbl;
@synthesize connectBtn;
@synthesize muteCamBtn;
@synthesize muteMicBtn;

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view setFrameSize:CGSizeMake(400, 330)];
    [self setPreferredContentSize:self.view.frame.size];
    otc_init(NULL);
    pubView = [[OTMTLVideoView alloc] initWithFrame:(CGRectMake(40,0,320,240))];
    [self.view addSubview:pubView];
    pubView.wantsLayer = YES;
    pubView.layer.borderWidth = 5;
    
    setupPublisher((__bridge void*)self);
    
    arraySubscribersView = [[NSMutableArray alloc] init];
}
- (IBAction)connectBtn:(id)sender {
    NSLog(@"Connect Clicked");
    [connectBtn setEnabled:FALSE];
    if (_isConnected){
        otc_session_disconnect(session);
    }
    else{
        setupOpentokSession((__bridge void*)self);
    }
}
- (IBAction)muteCamBtn:(id)sender {
    if (_isCamMuted){
        otc_publisher_set_publish_video(publisher, OTC_TRUE);
        _isCamMuted = NO;
        muteCamBtn.bezelColor = NSColor.systemGreenColor;
        [muteCamBtn setTitle:@"Mute Cam"];
    }
    else{
        otc_publisher_set_publish_video(publisher, OTC_FALSE);
        _isCamMuted = YES;
        muteCamBtn.bezelColor = NSColor.redColor;
        [muteCamBtn setTitle:@"Unmute Cam"];
    }
}

- (IBAction)muteMicBtn:(id)sender {
    if  (_isCamMuted) {
        otc_publisher_set_publish_audio(publisher, OTC_TRUE);
        _isCamMuted = NO;
        muteMicBtn.bezelColor = NSColor.systemGreenColor;
        [muteMicBtn setTitle:@"Mute Mic"];
    }
    else{
        otc_publisher_set_publish_audio(publisher, OTC_FALSE);
        _isCamMuted = YES;
        muteMicBtn.bezelColor = NSColor.redColor;
        [muteMicBtn setTitle:@"Unmute Mic"];
    }
}

void session_logger_func(const char* message) {
    NSLog(@"%s",message);
}

void setupOpentokSession(void * userdata){
    
    otc_log_enable(OTC_LOG_LEVEL_INFO);
    otc_log_set_logger_callback(session_logger_func);
    
    struct otc_session_callbacks session_callbacks = {0};
    session_callbacks.on_connected = session_on_connected;
    session_callbacks.on_disconnected = session_on_disconnected;
    session_callbacks.on_connection_created = on_connection_created;
    session_callbacks.on_connection_dropped = on_connection_dropped;
    session_callbacks.on_stream_received = session_on_stream_received;
    session_callbacks.on_stream_dropped = session_on_stream_dropped;
    session_callbacks.on_error = session_on_error;
    session_callbacks.on_signal_received = session_on_signal_received;
    session_callbacks.on_reconnection_started = session_on_reconnect_start;
    session_callbacks.on_reconnected = session_on_reconnect_succeess;
    session_callbacks.on_mute_forced = session_on_mute_forced;
    session_callbacks.user_data = userdata;
    
    if(session != NULL){
        otc_session_delete(session);
    }
    NSLog(@"creating session");
    session = otc_session_new(kApiKey, kSessionId, &session_callbacks);
    NSLog(@"Connecting to video cloud with kApikey=%s, kSessionId=%s and got session: %p", kApiKey, kSessionId, session);
    otc_session_connect(session, kToken);
    
 }

#pragma mark -
#pragma mark Session callbacks

void session_on_connected(otc_session *session, void *user_data) {
    NSLog(@"Session Connected");
    ViewController *v = (__bridge ViewController *)user_data;
    v.isConnected = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [v.statusLbl setStringValue:@"Connected"];
        [v.connectBtn setEnabled:TRUE];
        [v.connectBtn setTitle:@"Disconnect"];
        v.connectBtn.bezelColor = NSColor.redColor;
    });
    otc_session_publish(session, publisher);
}

void session_on_disconnected(otc_session *session, void *user_data) {
    NSLog(@"Session Disconnected");
    ViewController *v = (__bridge ViewController *)user_data;
    dispatch_async(dispatch_get_main_queue(), ^{
        [v.statusLbl setStringValue:@"Disconnected"];
        [v.connectBtn setEnabled:TRUE];
        [v.connectBtn setTitle:@"Connect"];
        v.connectBtn.bezelColor = NSColor.systemGreenColor;
        //subscriberView.hidden = TRUE;
    });
    v.isConnected = NO;
}

void on_connection_created(otc_session *session, void *user_data, const otc_connection *connection)
{
    NSLog(@"Connection Created");
}

void on_connection_dropped(otc_session *session, void *user_data, const otc_connection *connection)
{
    NSLog(@"Connection Destroyed");
}

void session_on_stream_received(otc_session *session, void *user_data, const otc_stream *stream) {
    NSLog(@"Stream Received");
    
    ViewController *vc = (__bridge ViewController *)user_data;
    otc_stream *strcpy = otc_stream_copy(stream);

    dispatch_async(dispatch_get_main_queue(), ^{
        
        struct otc_subscriber_callbacks callbacks = {0};
        callbacks.on_render_frame = subscriber_on_render_frame;
        callbacks.on_connected = subscriber_on_connected;
        callbacks.on_disconnected = subscriber_on_disconnected;
        callbacks.on_video_disabled = subscriber_on_video_disabled;
        callbacks.on_video_enabled = subscriber_on_video_enabled;
        callbacks.user_data = user_data;
        otc_subscriber *subscriber= otc_subscriber_new(strcpy, &callbacks);
        otc_session_subscribe(session, subscriber);
        
        bool alreadyExists = false;
        for (OTSubscriberWindow *subscriberWindow in arraySubscribersView) {
            otc_subscriber *oldSubscriber = [subscriberWindow getSubscriber];
            if (strcmp(otc_subscriber_get_subscriber_id(subscriber), otc_subscriber_get_subscriber_id(oldSubscriber)) == 0) {
                alreadyExists = true;
            }
        }
        if (!alreadyExists) {
            OTSubscriberWindow *subscriberWindow = [[OTSubscriberWindow alloc] initWithWindowNibName:@"OTSubscriberWindow"];
            subscriberWindow.shouldCascadeWindows = YES;
            [subscriberWindow loadWindow];
            subscriberWindow.videoView.wantsLayer = YES;
            subscriberWindow.videoView.layer.borderWidth = 5;
            subscriberWindow.videoView.hidden = NO;
            [subscriberWindow setSubscriber:subscriber];
            [arraySubscribersView addObject:subscriberWindow];
            NSLog(@"subscriber added");
            [subscriberWindow showWindow:vc];
        }
        otc_stream_delete(strcpy);
    });
}

void session_on_stream_dropped(otc_session *session, void *user_data, const otc_stream *stream) {
    NSLog(@"Stream Dropped");
    
    //ViewController *vc = (__bridge ViewController *)user_data;
    otc_stream *strcpy = otc_stream_copy(stream);

    dispatch_async(dispatch_get_main_queue(), ^{
        int indexToDelete = -1;
        for (int i = 0; i <= [arraySubscribersView count]; i++) {
            OTSubscriberWindow *subscriberWindow = [arraySubscribersView objectAtIndex:i];
            otc_subscriber *subscriber = [subscriberWindow getSubscriber];
            otc_stream *sub_stream = otc_subscriber_get_stream(subscriber);
            if (strcmp(otc_stream_get_id(sub_stream), otc_stream_get_id(strcpy)) == 0) {
                indexToDelete = i;
                break;
            }
        }
        if (indexToDelete > -1) {
            OTSubscriberWindow *subscriberWindow = [arraySubscribersView objectAtIndex:indexToDelete];
            otc_subscriber *subscriber = [subscriberWindow getSubscriber];
            otc_session_unsubscribe(session, subscriber);
            [subscriberWindow close];
            [arraySubscribersView removeObjectAtIndex:indexToDelete];
        }
        otc_stream_delete(strcpy);
    });
}

void session_on_error(otc_session *session, void *user_data, const char * msg, enum otc_session_error_code error_code) {
    NSLog(@"Connection Error: %s, code=%d",msg,error_code);
}

void session_on_signal_received(otc_session *session, void *user_data, const char *type, const char *signal,
                                const otc_connection *connection) {
    
}

void session_on_reconnect_start(otc_session *session, void *user_data) {

}

void session_on_reconnect_succeess(otc_session *session, void *user_data) {

}

void session_on_mute_forced(otc_session *session, void *user_data, otc_on_mute_forced_info *mute_info) {
    
}
void setupPublisher(void * userdata){
    struct otc_publisher_callbacks publisher_callbacks = {0};
    publisher_callbacks.on_stream_created = publisher_on_stream_created;
    publisher_callbacks.on_render_frame = publisher_on_render_frame;
    publisher_callbacks.user_data = userdata;
    publisher_callbacks.on_stream_destroyed = publisher_on_stream_destroyed;
    
    publisher = otc_publisher_new("Mac Publisher", NULL, &publisher_callbacks);
    NSLog(@"Publisher created : %p",publisher);
}

void publisher_on_stream_created(otc_publisher *publisher, void *user_data, const otc_stream *stream) {
    
}

void publisher_on_stream_destroyed(otc_publisher *publisher, void *user_data, const otc_stream *stream){
    
}

static void publisher_on_render_frame(otc_publisher *publisher, void *user_data, const otc_video_frame *frame) {
    //ViewController *vc = (__bridge ViewController *)user_data;
    otc_video_frame *copy_frame = otc_video_frame_copy(frame);
    dispatch_async(dispatch_get_main_queue(), ^{
        [pubView renderVideoFrame:(otc_video_frame*)copy_frame];
        otc_video_frame_delete(copy_frame);
    });
}


static void subscriber_on_render_frame(otc_subscriber *subscriber, void *user_data, const otc_video_frame *frame) {
    //ViewController *vc = (__bridge ViewController *)user_data;
    otc_video_frame *copy_frame = otc_video_frame_copy(frame);
    const char*subscriber_id = otc_subscriber_get_subscriber_id(subscriber);
    dispatch_async(dispatch_get_main_queue(), ^{
        for (OTSubscriberWindow *subscriberWindow in arraySubscribersView) {
            otc_subscriber *oldSubscriber = [subscriberWindow getSubscriber];
            if (strcmp(subscriber_id, otc_subscriber_get_subscriber_id(oldSubscriber)) == 0) {
                [subscriberWindow.videoView renderVideoFrame:(otc_video_frame*)copy_frame];
            }
        }
        otc_video_frame_delete(copy_frame);
    });
}

static void subscriber_on_video_disabled(otc_subscriber* subscriber, void *user_data, enum otc_video_reason reason) {
    
}

static void subscriber_on_video_enabled(otc_subscriber* subscriber, void *user_data, enum otc_video_reason reason) {
    
}

static void subscriber_on_connected(otc_subscriber *subscriber, void *user_data, const otc_stream *stream) {
    NSLog(@"subscriber_on_connected");
    //ViewController *vc = (__bridge ViewController *)user_data;
}

static void subscriber_on_disconnected(otc_subscriber *subscriber, void *user_data) {
    
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
}


@end
