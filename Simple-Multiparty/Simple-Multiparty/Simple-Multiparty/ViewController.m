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

typedef struct {
    otc_session *session;
    otc_publisher *publisher;
    void *view_controller;
} SessionData;

@interface ViewController () {
    SessionData *session_data;
    OTMTLVideoView *pubView;
    NSMutableArray<OTSubscriberWindow*> *arraySubscribersView;
}

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
    
    session_data = calloc(1, sizeof(SessionData));
    session_data->view_controller = (__bridge void *)self;
    
    otc_init(NULL);
    pubView = [[OTMTLVideoView alloc] initWithFrame:(CGRectMake(40,0,320,240))];
    [self.view addSubview:pubView];
    pubView.wantsLayer = YES;
    pubView.layer.borderWidth = 5;
    
    setupPublisher(session_data);
    
    arraySubscribersView = [[NSMutableArray alloc] init];
}
- (void) viewWillDisappear {
    for (OTSubscriberWindow* w in arraySubscribersView) {
        [w close];
    }
    [super viewWillDisappear];
    
}
- (IBAction)connectBtn:(id)sender {
    NSLog(@"Connect Clicked");
    [connectBtn setEnabled:FALSE];
    if (_isConnected){
        for (OTSubscriberWindow* w in arraySubscribersView) {
            [w close];
        }
        otc_session_disconnect(session_data->session);
    }
    else{
        setupOpentokSession(session_data);
    }
}
- (IBAction)muteCamBtn:(id)sender {
    if (_isCamMuted){
        otc_publisher_set_publish_video(session_data->publisher, OTC_TRUE);
        _isCamMuted = NO;
        muteCamBtn.bezelColor = NSColor.systemGreenColor;
        [muteCamBtn setTitle:@"Mute Cam"];
    }
    else{
        otc_publisher_set_publish_video(session_data->publisher, OTC_FALSE);
        _isCamMuted = YES;
        muteCamBtn.bezelColor = NSColor.redColor;
        [muteCamBtn setTitle:@"Unmute Cam"];
    }
}

- (IBAction)muteMicBtn:(id)sender {
    if  (_isCamMuted) {
        otc_publisher_set_publish_audio(session_data->publisher, OTC_TRUE);
        _isCamMuted = NO;
        muteMicBtn.bezelColor = NSColor.systemGreenColor;
        [muteMicBtn setTitle:@"Mute Mic"];
    }
    else{
        otc_publisher_set_publish_audio(session_data->publisher, OTC_FALSE);
        _isCamMuted = YES;
        muteMicBtn.bezelColor = NSColor.redColor;
        [muteMicBtn setTitle:@"Unmute Mic"];
    }
}

void session_logger_func(const char* message) {
    NSLog(@"%s",message);
}

void setupOpentokSession(void *user_data){
    
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
    session_callbacks.user_data = user_data;
    
    SessionData *session_data = (SessionData *)user_data;
    if(session_data->session != NULL){
        otc_session_delete(session_data->session);
    }
    NSLog(@"creating session");
    session_data->session = otc_session_new(kApiKey, kSessionId, &session_callbacks);
    NSLog(@"Connecting to video cloud with kApikey=%s, kSessionId=%s and got session: %p", kApiKey, kSessionId, session_data->session);
    otc_session_connect(session_data->session, kToken);
    
 }

#pragma mark -
#pragma mark Session callbacks

void session_on_connected(otc_session *session, void *user_data) {
    NSLog(@"Session Connected");
    SessionData *session_data = (SessionData *)user_data;
    ViewController *vc = (__bridge ViewController *)session_data->view_controller;
    vc.isConnected = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [vc.statusLbl setStringValue:@"Connected"];
        [vc.connectBtn setEnabled:TRUE];
        [vc.connectBtn setTitle:@"Disconnect"];
        vc.connectBtn.bezelColor = NSColor.redColor;
    });
    otc_session_publish(session_data->session, session_data->publisher);
}

void session_on_disconnected(otc_session *session, void *user_data) {
    NSLog(@"Session Disconnected");
    SessionData *session_data = (SessionData *)user_data;
    ViewController *vc = (__bridge ViewController *)session_data->view_controller;
    dispatch_async(dispatch_get_main_queue(), ^{
        [vc.statusLbl setStringValue:@"Disconnected"];
        [vc.connectBtn setEnabled:TRUE];
        [vc.connectBtn setTitle:@"Connect"];
        vc.connectBtn.bezelColor = NSColor.systemGreenColor;
        //subscriberView.hidden = TRUE;
    });
    vc.isConnected = NO;
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
    
    SessionData *session_data = (SessionData *)user_data;
    ViewController *vc = (__bridge ViewController *)session_data->view_controller;
    otc_stream *strcpy = otc_stream_copy(stream);

    dispatch_async(dispatch_get_main_queue(), ^{
        
        OTSubscriberWindow *subscriberWindow = [[OTSubscriberWindow alloc] initWithWindowNibName:@"OTSubscriberWindow"];
        subscriberWindow.shouldCascadeWindows = YES;
        [subscriberWindow loadWindow];
        subscriberWindow.videoView.wantsLayer = YES;
        subscriberWindow.videoView.layer.borderWidth = 5;
        subscriberWindow.videoView.hidden = NO;
        
        struct otc_subscriber_callbacks callbacks = {0};
        callbacks.on_video_data_received = subscriber_on_video_data_received;
        callbacks.on_render_frame = subscriber_on_render_frame;
        callbacks.on_connected = subscriber_on_connected;
        callbacks.on_disconnected = subscriber_on_disconnected;
        callbacks.on_video_disabled = subscriber_on_video_disabled;
        callbacks.on_video_enabled = subscriber_on_video_enabled;
        callbacks.user_data = (__bridge void*)subscriberWindow.videoView;
        otc_subscriber *subscriber = otc_subscriber_new(strcpy, &callbacks);
        otc_session_subscribe(session, subscriber);
        
        [subscriberWindow setSubscriber:subscriber];
        [vc->arraySubscribersView addObject:subscriberWindow];
        NSLog(@"subscriber added");
        [subscriberWindow showWindow:vc];
        otc_stream_delete(strcpy);
    });
}

void session_on_stream_dropped(otc_session *session, void *user_data, const otc_stream *stream) {
    NSLog(@"Stream Dropped");
    
    SessionData *session_data = (SessionData *)user_data;
    ViewController *vc = (__bridge ViewController *)session_data->view_controller;
    otc_stream *strcpy = otc_stream_copy(stream);

    dispatch_async(dispatch_get_main_queue(), ^{
        int indexToDelete = -1;
        const char* stream_id = otc_stream_get_id(strcpy);
        for (int i=0; i<[vc->arraySubscribersView count]; i++) {
            OTSubscriberWindow *subscriberWindow = [vc->arraySubscribersView objectAtIndex:i];
            otc_subscriber *subscriber = [subscriberWindow getSubscriber];
            otc_stream *sub_stream = otc_subscriber_get_stream(subscriber);
            const char* sub_stream_id = otc_stream_get_id(sub_stream);
            if (strcmp(sub_stream_id, stream_id) == 0) {
                indexToDelete = i;
                break;
            }
        }
        if (indexToDelete > -1) {
            OTSubscriberWindow *subscriberWindow = [vc->arraySubscribersView objectAtIndex:indexToDelete];
            otc_subscriber *subscriber_to_delete = [subscriberWindow getSubscriber];
            otc_session_unsubscribe(session, subscriber_to_delete);
            [subscriberWindow close];
            [vc->arraySubscribersView removeObjectAtIndex:indexToDelete];
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
void setupPublisher(void *user_data) {
    SessionData *session_data = (SessionData *)user_data;
    ViewController *vc = (__bridge ViewController *)session_data->view_controller;
    
    struct otc_publisher_callbacks publisher_callbacks = {0};
    publisher_callbacks.on_stream_created = publisher_on_stream_created;
    publisher_callbacks.on_render_frame = publisher_on_render_frame;
    publisher_callbacks.user_data = (__bridge void*)vc->pubView;
    publisher_callbacks.on_stream_destroyed = publisher_on_stream_destroyed;
    
    session_data->publisher = otc_publisher_new("Mac Publisher", NULL, &publisher_callbacks);
    NSLog(@"Publisher created : %p", session_data->publisher);
}

void publisher_on_stream_created(otc_publisher *publisher, void *user_data, const otc_stream *stream) {
    
}

void publisher_on_stream_destroyed(otc_publisher *publisher, void *user_data, const otc_stream *stream){
    
}

static void publisher_on_render_frame(otc_publisher *publisher, void *user_data, const otc_video_frame *frame) {
    OTMTLVideoView *videoView = (__bridge OTMTLVideoView *)user_data;
    [videoView renderVideoFrame:(otc_video_frame*)frame];
}

static void subscriber_on_video_data_received(otc_subscriber* subscriber, void* user_data) {
    
}

static void subscriber_on_render_frame(otc_subscriber *subscriber, void *user_data, const otc_video_frame *frame) {
    OTMTLVideoView *videoView = (__bridge OTMTLVideoView *)user_data;
    [videoView renderVideoFrame:(otc_video_frame*)frame];
}

static void subscriber_on_video_disabled(otc_subscriber* subscriber, void *user_data, enum otc_video_reason reason) {
    NSLog(@"subscriber_on_video_disabled");
}

static void subscriber_on_video_enabled(otc_subscriber* subscriber, void *user_data, enum otc_video_reason reason) {
    NSLog(@"subscriber_on_video_enabled");
}

static void subscriber_on_connected(otc_subscriber *subscriber, void *user_data, const otc_stream *stream) {
    NSLog(@"subscriber_on_connected");
}

static void subscriber_on_disconnected(otc_subscriber *subscriber, void *user_data) {
    NSLog(@"subscriber_on_disconnected");
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
}


@end
