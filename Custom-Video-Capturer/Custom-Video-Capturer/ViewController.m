//
//  ViewController.m
//  Basic-Sample-Mac-C
//
//  Created by Rajkiran Talusani on 27/9/22.
//

#import "ViewController.h"
#import <OpenTok/opentok.h>
#import "OTMTLVideoView.h"
#import "OTMacDefaultVideoCapturer.h"
#import "OTVideoCaptureProxy.h"
// Replace with your OpenTok API key
static char* const kApiKey = "46183452";
// Replace with your generated session ID
static char* const kSessionId = "2_MX40NjE4MzQ1Mn5-MTY3NzU1MTE3Njc2OH56eDN0SWc4OHlXMlBHQVVsbUMvRStqSnh-fn4";
// Replace with your generated token
static char* const kToken = "T1==cGFydG5lcl9pZD00NjE4MzQ1MiZzaWc9YTFiOWNkYzhlODdiZDI1Y2NkMGEzNGMwYmQwNGYzNzE4MTIwZGEzMzpzZXNzaW9uX2lkPTJfTVg0ME5qRTRNelExTW41LU1UWTNOelUxTVRFM05qYzJPSDU2ZUROMFNXYzRPSGxYTWxCSFFWVnNiVU12UlN0cVNuaC1mbjQmY3JlYXRlX3RpbWU9MTY3NzU1MTE3NyZub25jZT0wLjA0NjQxODAxNzc4MTI2ODUzJnJvbGU9bW9kZXJhdG9yJmV4cGlyZV90aW1lPTE2ODAxNDMxNzcmaW5pdGlhbF9sYXlvdXRfY2xhc3NfbGlzdD0=";

otc_session *session = NULL;
otc_publisher *publisher = NULL;
OTMTLVideoView *pubView = NULL;
OTMTLVideoView *subscriberView = NULL;
OTVideoCaptureProxy *videoProxy = NULL;
bool isConnected = false;
bool isCamMuted = false;
bool isMicMuted = false;

@implementation ViewController
@synthesize statusLbl;
@synthesize connectBtn;
@synthesize muteCamBtn;
@synthesize muteMicBtn;

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view setFrameSize:CGSizeMake(700, 330)];
    [self setPreferredContentSize:self.view.frame.size];
    otc_init(NULL);
    pubView = [[OTMTLVideoView alloc] initWithFrame:(CGRectMake(0,0,320,240))];
    [self.view addSubview:pubView];
    pubView.wantsLayer = YES;
    pubView.layer.borderWidth = 5;
    
    subscriberView = [[OTMTLVideoView alloc] initWithFrame:(CGRectMake(325,0,320,240))];
    [self.view addSubview:subscriberView];
    subscriberView.wantsLayer = YES;
    subscriberView.layer.borderWidth = 5;
    subscriberView.hidden = TRUE;
    setupPublisher((__bridge void*)self);
    
}
- (IBAction)connectBtn:(id)sender {
    NSLog(@"Connect Clicked");
    [connectBtn setEnabled:FALSE];
    if(isConnected == true){
        otc_session_disconnect(session);
    }
    else{
        setupOpentokSession((__bridge void*)self);
    }
}
- (IBAction)muteCamBtn:(id)sender {
    if(isCamMuted == TRUE){
        otc_publisher_set_publish_video(publisher, OTC_TRUE);
        isCamMuted = false;
        muteCamBtn.bezelColor = NSColor.systemGreenColor;
        [muteCamBtn setTitle:@"Mute Cam"];
    }
    else{
        otc_publisher_set_publish_video(publisher, OTC_FALSE);
        isCamMuted = true;
        muteCamBtn.bezelColor = NSColor.redColor;
        [muteCamBtn setTitle:@"Unmute Cam"];
    }
}

- (IBAction)muteMicBtn:(id)sender {
    if(isMicMuted == TRUE){
        otc_publisher_set_publish_audio(publisher, OTC_TRUE);
        isMicMuted = false;
        muteMicBtn.bezelColor = NSColor.systemGreenColor;
        [muteMicBtn setTitle:@"Mute Mic"];
    }
    else{
        otc_publisher_set_publish_audio(publisher, OTC_FALSE);
        isMicMuted = true;
        muteMicBtn.bezelColor = NSColor.redColor;
        [muteMicBtn setTitle:@"Unmute Mic"];
    }
}

void session_logger_func(const char* message) {
    NSLog(@"%s",message);
}

void setupOpentokSession(void * userdata){
    
   // otc_log_enable(OTC_LOG_LEVEL_INFO);
    //otc_log_set_logger_callback(session_logger_func);
    
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
    isConnected = true;
    otc_session_publish(session, publisher);

    ViewController *v = (__bridge ViewController *)user_data;
    dispatch_async(dispatch_get_main_queue(), ^{
        [v.statusLbl setStringValue:@"Connected"];
        [v.connectBtn setEnabled:TRUE];
        [v.connectBtn setTitle:@"Disconnect"];
        v.connectBtn.bezelColor = NSColor.redColor;
    });
   
}

void session_on_disconnected(otc_session *session, void *user_data) {
    NSLog(@"Session Disconnected");
    ViewController *v = (__bridge ViewController *)user_data;
    dispatch_async(dispatch_get_main_queue(), ^{
        [v.statusLbl setStringValue:@"Disconnected"];
        [v.connectBtn setEnabled:TRUE];
        [v.connectBtn setTitle:@"Connect"];
        v.connectBtn.bezelColor = NSColor.systemGreenColor;
        subscriberView.hidden = TRUE;
    });
    isConnected = false;
    
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
    
    //ViewController *v = (__bridge ViewController *)user_data;
    
    struct otc_subscriber_callbacks callbacks = {0};
    callbacks.on_render_frame = subscriber_on_render_frame;
    callbacks.on_connected = subscriber_on_connected;
    callbacks.on_video_disabled = subscriber_on_video_disabled;
    callbacks.on_video_enabled = subscriber_on_video_enabled;
    callbacks.on_error = subscriber_on_error;
    callbacks.user_data = user_data;
    otc_subscriber *subscriber= otc_subscriber_new(stream, &callbacks);
    otc_session_subscribe(session, subscriber);
}

void session_on_stream_dropped(otc_session *session, void *user_data, const otc_stream *stream) {
    NSLog(@"Stream Dropped");
}

void session_on_error(otc_session *session, void *user_data, const char * msg, enum otc_session_error_code error_code) {
    NSLog(@"Connection Error: %s, code=%d",msg,error_code);
}

void session_on_signal_received(otc_session *session, void *user_data, const char *type, const char *signal,
                                const otc_connection *connection) {
    NSLog(@"Received: %s",signal);
    
}

void session_on_reconnect_start(otc_session *session, void *user_data) {

}

void session_on_reconnect_succeess(otc_session *session, void *user_data) {

}

void session_on_mute_forced(otc_session *session, void *user_data, otc_on_mute_forced_info *mute_info) {
    
}
void setupPublisher(void * userdata){
    videoProxy = [[OTVideoCaptureProxy alloc] init];
    struct otc_publisher_callbacks publisher_callbacks = {0};
    publisher_callbacks.on_stream_created = publisher_on_stream_created;
    publisher_callbacks.on_render_frame = publisher_on_render_frame;
    publisher_callbacks.user_data = userdata;
    publisher_callbacks.on_stream_destroyed = publisher_on_stream_destroyed;
    publisher_callbacks.on_error = publisher_on_error;
    
    publisher = otc_publisher_new("Mac Publisher", videoProxy.otc_video_capture_driver, &publisher_callbacks);
    NSLog(@"Publisher created : %p",publisher);
  
}

void publisher_on_stream_created(otc_publisher *publisher, void *user_data, const otc_stream *stream) {
   
    NSLog(@"Publisher stream created");
}

void publisher_on_stream_destroyed(otc_publisher *publisher, void *user_data, const otc_stream *stream){
    NSLog(@"Publisher stream destroyed");
}

static void publisher_on_render_frame(otc_publisher *publisher, void *user_data, const otc_video_frame *frame) {
    //ViewController *v = (__bridge ViewController *)user_data;
    [pubView renderVideoFrame:(otc_video_frame*)frame];
}

static void publisher_on_error(otc_publisher *publisher, void *user_data, const char *error_string, enum otc_publisher_error_code error_code){
    NSLog(@"Publisher error: %s, code: %d",error_string,error_code);
}

static void subscriber_on_render_frame(otc_subscriber *subscriber, void *user_data, const otc_video_frame *frame) {
    [subscriberView renderVideoFrame:(otc_video_frame*)frame];
}

static void subscriber_on_error(otc_subscriber *subscriber, void *user_data, const char *error_string, enum otc_subscriber_error_code error_code){
    NSLog(@"Subscriber error: %s, code: %d",error_string,error_code);
}

static void subscriber_on_video_disabled(otc_subscriber* subscriber, void *user_data, enum otc_video_reason reason) {
    
}

static void subscriber_on_video_enabled(otc_subscriber* subscriber, void *user_data, enum otc_video_reason reason) {
    
}

static void subscriber_on_connected(otc_subscriber *subscriber, void *user_data, const otc_stream *stream) {
    NSLog(@"Subscriber connected");
    dispatch_async(dispatch_get_main_queue(), ^{
        subscriberView.hidden = FALSE;
    });
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
}




@end
