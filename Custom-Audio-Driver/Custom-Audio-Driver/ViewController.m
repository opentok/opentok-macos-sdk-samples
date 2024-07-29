//
//  ViewController.m
//  Basic-Sample-Mac-C
//
//  Created by Rajkiran Talusani on 27/9/22.
//

#import "ViewController.h"
#import <OpenTok/opentok.h>
#import "OTMTLVideoView.h"
#import "OTAudioDeviceProxy.h"
#import "OTAudioKit.h"
#import "OTDefaultAudioDevice-Mac.h"

// Replace with your OpenTok API key
static char* const kApiKey = "";
// Replace with your generated session ID
static char* const kSessionId = "";
// Replace with your generated token
static char* const kToken = "";

otc_session *session = NULL;
otc_publisher *publisher = NULL;
OTMTLVideoView *pubView = NULL;
OTMTLVideoView *subscriberView = NULL;

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
    setupCustomAudioDriver();
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

void setupCustomAudioDriver(void){
    OTDefaultAudioDeviceMac *audioDevice = [[OTDefaultAudioDeviceMac alloc] init];
    OTAudioDeviceProxy *audioProxy = [[OTAudioDeviceProxy alloc] initWithAudioDevice:audioDevice];
}
void setupOpentokSession(void * userdata){
    
    //otc_log_enable(OTC_LOG_LEVEL_ALL);
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
    ViewController *v = (__bridge ViewController *)user_data;
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
    
    otc_publisher_settings* publisher_settings = otc_publisher_settings_new();
    if (publisher_settings == NULL) {
        NSLog(@"Could not create OpenTok publisher settings successfully");
        return;
    }
    otc_publisher_settings_set_name(publisher_settings, "opentok-macos-meet-screen-share");
    otc_publisher_settings_set_disable_audio_processing(publisher_settings, OTC_TRUE);
    otc_publisher_settings_set_video_track( publisher_settings, OTC_FALSE);
    otc_publisher_settings_set_stereo(publisher_settings, OTC_TRUE);
    
    publisher = otc_publisher_new_with_settings(&publisher_callbacks,
                                                publisher_settings);
}

void publisher_on_stream_created(otc_publisher *publisher, void *user_data, const otc_stream *stream) {
   // return;
    struct otc_subscriber_callbacks callbacks = {0};
    callbacks.on_render_frame = subscriber_on_render_frame;
    callbacks.on_connected = subscriber_on_connected;
    callbacks.on_video_disabled = subscriber_on_video_disabled;
    callbacks.on_video_enabled = subscriber_on_video_enabled;
    callbacks.user_data = user_data;
    otc_subscriber *subscriber= otc_subscriber_new(stream, &callbacks);
    otc_session_subscribe(session, subscriber);
}

void publisher_on_stream_destroyed(otc_publisher *publisher, void *user_data, const otc_stream *stream){
    
}

static void publisher_on_render_frame(otc_publisher *publisher, void *user_data, const otc_video_frame *frame) {
    //ViewController *v = (__bridge ViewController *)user_data;
    [pubView renderVideoFrame:(otc_video_frame*)frame];
}


static void subscriber_on_render_frame(otc_subscriber *subscriber, void *user_data, const otc_video_frame *frame) {
    [subscriberView renderVideoFrame:(otc_video_frame*)frame];
}

static void subscriber_on_video_disabled(otc_subscriber* subscriber, void *user_data, enum otc_video_reason reason) {
    
}

static void subscriber_on_video_enabled(otc_subscriber* subscriber, void *user_data, enum otc_video_reason reason) {
    
}

static void subscriber_on_connected(otc_subscriber *subscriber, void *user_data, const otc_stream *stream) {
    dispatch_async(dispatch_get_main_queue(), ^{
        subscriberView.hidden = FALSE;
    });
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
}


@end
