//
//  OpenTokWrapper.cpp
//  Media-Transformers
//
//  Created by Jerónimo Valli on 11/16/22.
//

#include "OpenTokWrapper.h"

#define API_KEY ""
// Replace with your generated session ID
#define SESSION_ID ""
// Replace with your generated token
#define TOKEN ""

typedef struct {
  otc_session *session;
  otc_publisher *publisher;
  const otc_stream* pub_stream;
  otc_subscriber *subscriber;
  const otc_stream* sub_stream;
  void *open_tok_controller;
} SessionData;


static void on_subscriber_connected(otc_subscriber *subscriber,
                                    void *user_data,
                                    const otc_stream *stream) {
  NSLog(@"on_subscriber_connected: streamId=%s ", otc_stream_get_id(stream));
  SessionData *session_data_local = (SessionData *)user_data;
  OpenTokWrapper *openTokWrapper = (__bridge OpenTokWrapper*)session_data_local->open_tok_controller;
  if (openTokWrapper != NULL && openTokWrapper.delegate) {
    [openTokWrapper.delegate onSubscriberConnected];
  }
}

static void on_subscriber_render_frame(otc_subscriber *subscriber,
                                       void *user_data,
                                       const otc_video_frame *frame) {
  SessionData *session_data_local = (SessionData *)user_data;
  OpenTokWrapper *openTokWrapper = (__bridge OpenTokWrapper*)session_data_local->open_tok_controller;
  if (openTokWrapper != NULL && openTokWrapper.delegate) {
      [openTokWrapper.delegate onSubscriberRenderFrame:frame];
  }
}

static void on_subscriber_error(otc_subscriber* subscriber,
                                void *user_data,
                                const char* error_string,
                                enum otc_subscriber_error_code error_code) {
  NSLog(@"on_subscriber_error: errorString=%s - errorCode=%i", error_string, error_code);
  SessionData *session_data_local = (SessionData *)user_data;
  OpenTokWrapper *openTokWrapper = (__bridge OpenTokWrapper*)session_data_local->open_tok_controller;
  if (openTokWrapper != NULL && openTokWrapper.delegate) {
    [openTokWrapper.delegate onSubscriberError];
  }
}

static void on_subscriber_disconnected(otc_subscriber *subscriber,
                                       void *user_data) {
  NSLog(@"on_subscriber_disconnected");
  SessionData *session_data_local = (SessionData *)user_data;
  OpenTokWrapper *openTokWrapper = (__bridge OpenTokWrapper*)session_data_local->open_tok_controller;
  if (openTokWrapper != NULL && openTokWrapper.delegate) {
    [openTokWrapper.delegate onSubscriberDisconnected];
  }
}

static void on_session_connected(otc_session *session, void *user_data) {
  const char *session_id = otc_session_get_id(session);
  NSLog(@"on_session_connected: sessionId=%s ", session_id);

  SessionData *session_data_local = (SessionData *)user_data;
  OpenTokWrapper *openTokWrapper = (__bridge OpenTokWrapper*)session_data_local->open_tok_controller;
  if (openTokWrapper != NULL && openTokWrapper.delegate && session_id) {
    NSString *sessionId = [NSString stringWithCString:session_id encoding:NSUTF8StringEncoding];
    [openTokWrapper.delegate onSessionConnected:sessionId];
  }
}

static void on_session_connection_created(otc_session *session,
                                          void *user_data,
                                          const otc_connection *connection) {
  NSLog(@"on_session_connection_created: sessionId=%s - connectionId=%s", otc_session_get_id(session), otc_connection_get_id(connection));
}

static void on_session_connection_dropped(otc_session *session,
                                          void *user_data,
                                          const otc_connection *connection) {
  NSLog(@"on_session_connection_dropped: sessionId=%s - connectionId=%s", otc_session_get_id(session), otc_connection_get_id(connection));
}

static void on_session_stream_received(otc_session *session,
                                       void *user_data,
                                       const otc_stream *stream) {
  NSLog(@"on_session_stream_received: sessionId=%s - streamId=%s", otc_session_get_id(session), otc_stream_get_id(stream));
  
  SessionData *session_data_local = (SessionData *)user_data;
  OpenTokWrapper *openTokWrapper = (__bridge OpenTokWrapper*)session_data_local->open_tok_controller;

  otc_stream *strcpy = otc_stream_copy(stream);

  dispatch_async(dispatch_get_main_queue(), ^{

    [openTokWrapper.streamObjectList addPointer:strcpy];

    struct otc_subscriber_callbacks subscriber_callbacks = {0};
    subscriber_callbacks.user_data = session_data_local;
    subscriber_callbacks.on_connected = on_subscriber_connected;
    subscriber_callbacks.on_render_frame = on_subscriber_render_frame;
    subscriber_callbacks.on_error = on_subscriber_error;
    subscriber_callbacks.on_disconnected = on_subscriber_disconnected;

    otc_subscriber *subscriber = otc_subscriber_new(strcpy, &subscriber_callbacks);
    
    if (otc_session_subscribe(session, subscriber) == OTC_SUCCESS) {
      session_data_local->subscriber = subscriber;
      session_data_local->sub_stream = stream;
    }
    otc_stream_delete(strcpy);
  });
}

static void on_session_stream_dropped(otc_session *session,
                                      void *user_data,
                                      const otc_stream *stream) {
  NSLog(@"on_session_stream_received: sessionId=%s - streamId=%s", otc_session_get_id(session), otc_stream_get_id(stream));
  
  SessionData *session_data_local = (SessionData *)user_data;
  OpenTokWrapper *openTokWrapper = (__bridge OpenTokWrapper*)session_data_local->open_tok_controller;

  otc_stream *strcpy = otc_stream_copy(stream);

  dispatch_async(dispatch_get_main_queue(), ^{
    otc_subscriber *subscriber = session_data_local->subscriber;
    otc_stream *sub_stream = otc_subscriber_get_stream(subscriber);
    if (strcmp(otc_stream_get_id(sub_stream), otc_stream_get_id(strcpy)) == 0) {
        otc_session_unsubscribe(session, subscriber);
    }

    for (int i = 0; i < [openTokWrapper.streamObjectList count]; i++) {
      if(strcmp(otc_stream_get_id([openTokWrapper.streamObjectList pointerAtIndex:i]), otc_stream_get_id(strcpy)) == 0)
      {
        otc_stream_delete([openTokWrapper.streamObjectList pointerAtIndex:i]);
        [openTokWrapper.streamObjectList removePointerAtIndex:i];
        break;
      }
    }
    otc_stream_delete(strcpy);
  });
}

static void on_session_disconnected(otc_session *session, void *user_data) {
  const char *session_id = otc_session_get_id(session);
  NSLog(@"on_session_disconnected: %s ", session_id);
  
  SessionData *session_data_local = (SessionData *)user_data;
  OpenTokWrapper *openTokWrapper = (__bridge OpenTokWrapper*)session_data_local->open_tok_controller;
  if (openTokWrapper != NULL && openTokWrapper.delegate && session_id) {
    NSString *sessionId = [NSString stringWithCString:session_id encoding:NSUTF8StringEncoding];
    [openTokWrapper.delegate onSessionDisconnected:sessionId];
  }
}

static void on_session_error(otc_session *session,
                             void *user_data,
                             const char *error_string,
                             enum otc_session_error_code error_code) {
  NSLog(@"on_session_error: errorString=%s - errorCode=%i", error_string, error_code);
  SessionData *session_data_local = (SessionData *)user_data;
  OpenTokWrapper *openTokWrapper = (__bridge OpenTokWrapper*)session_data_local->open_tok_controller;
  if (openTokWrapper != NULL && openTokWrapper.delegate) {
      [openTokWrapper.delegate onSessionError];
  }
}

static void on_publisher_stream_created(otc_publisher *publisher,
                                        void *user_data,
                                        const otc_stream *stream) {
  NSLog(@"on_session_stream_received: streamId=%s", otc_stream_get_id(stream));
  SessionData* session_data_local = (SessionData*) user_data;
  OpenTokWrapper *openTokWrapper = (__bridge OpenTokWrapper*)session_data_local->open_tok_controller;
  session_data_local->pub_stream = stream;
  [openTokWrapper.streamObjectList addPointer:otc_stream_copy(stream)];
}

static void on_publisher_render_frame(otc_publisher *publisher,
                                      void *user_data,
                                      const otc_video_frame *frame) {
  SessionData *session_data_local = (SessionData *)user_data;
  OpenTokWrapper *openTokWrapper = (__bridge OpenTokWrapper*)session_data_local->open_tok_controller;
  if (openTokWrapper != NULL && openTokWrapper.delegate) {
      [openTokWrapper.delegate onPublisherRenderFrame:frame];
  }
}

static void on_publisher_stream_destroyed(otc_publisher *publisher,
                                          void *user_data,
                                          const otc_stream *stream) {
  NSLog(@"on_publisher_stream_destroyed: streamId=%s", otc_stream_get_id(stream));
  SessionData* session_data_local = (SessionData*) user_data;
  OpenTokWrapper *openTokWrapper = (__bridge OpenTokWrapper*)session_data_local->open_tok_controller;

  for (int i = 0; i < [openTokWrapper.streamObjectList count]; i++)
  {
      if (strcmp(otc_stream_get_id(stream), otc_stream_get_id([openTokWrapper.streamObjectList pointerAtIndex:i]))== 0) {
          otc_stream_delete([openTokWrapper.streamObjectList pointerAtIndex:i]);
          [openTokWrapper.streamObjectList removePointerAtIndex:i];
          break;
      }
  }
}

static void on_publisher_error(otc_publisher *publisher,
                               void *user_data,
                               const char* error_string,
                               enum otc_publisher_error_code error_code) {
  NSLog(@"on_publisher_error: errorString=%s - errorCode=%i", error_string, error_code);
}

static void on_otc_log_message(const char* message) {
  NSLog(@"on_otc_log_message: message=%s", message);
}

/**
 * Called when video frame is available to be transformed. Transform the
 * data in your implementation of the method.
 * @param frame The audio data to be transformed.
 */
void on_transform_logo(void* user_data, struct otc_video_frame* frame)
{
    // implement transformer
    NSImage* resizedImage = [NSImage imageNamed:@"Vonage_Logo.png"];

    uint32_t videoWidth = otc_video_frame_get_width(frame);
    uint32_t videoHeight = otc_video_frame_get_height(frame);

    // Calculate the desired size of the image
    CGFloat desiredWidth = videoWidth / 8;  // Adjust this value as needed
    CGFloat desiredHeight = resizedImage.size.height * (desiredWidth / resizedImage.size.width);

    // Get pointer to the Y plane
    uint8_t* yPlane = (uint8_t*)otc_video_frame_get_plane_binary_data(frame, OTC_VIDEO_FRAME_PLANE_Y);
    
    // Create a CGContext from the Y plane
    CGContextRef context = CGBitmapContextCreate(yPlane, videoWidth, videoHeight, 8, videoWidth, CGColorSpaceCreateDeviceGray(), kCGImageAlphaNone);
    
    // Location of the image (in this case right bottom corner)
    CGFloat x = videoWidth * 4/5;
    CGFloat y = videoHeight * 1/5;
    
    CGImageRef cgImage = [resizedImage CGImageForProposedRect:NULL context:nil hints:nil];
    // Draw the resized image on top of the Y plane
    CGRect rect = CGRectMake(x, y, desiredWidth, desiredHeight);
    CGContextDrawImage(context, rect, cgImage);
    
    CGContextRelease(context);
}

/**
 * Variables holding media transformers
 */
otc_video_transformer *background_blur;
otc_video_transformer *logo_watermark;
otc_audio_transformer *ns;

/**
 * Disable Video Transformers
 * Make sure to call otc_video_transformer_delete(otc_video_transformer * transformer) to release any dynamically allocated memory
 */
static void disable_tranformers(otc_publisher *publisher) {
    otc_video_transformer_delete(background_blur);
    otc_video_transformer_delete(logo_watermark);
    otc_publisher_set_video_transformers(publisher, NULL, NULL);
    
    otc_audio_transformer_delete(ns);
    otc_publisher_set_audio_transformers(publisher, NULL, NULL);
}

/**
 * Enable Media Transformers
 */
static void enable_tranformers(otc_publisher *publisher) {

    // Create background blur from enum
    background_blur = otc_video_transformer_create(OTC_MEDIA_TRANSFORMER_TYPE_VONAGE, "BackgroundBlur","{\"radius\":\"High\"}", NULL, NULL);

    logo_watermark = otc_video_transformer_create(OTC_MEDIA_TRANSFORMER_TYPE_CUSTOM, "logo", NULL, on_transform_logo, NULL);

    // Array of video transformers
    otc_video_transformer *video_transformers[] = {
        /* Vonage Transformer - Background Blur */
        background_blur,
        /* Vonage Transformer - Logo watermark */
        logo_watermark};

    otc_publisher_set_video_transformers(publisher, video_transformers, sizeof(video_transformers) / sizeof(video_transformers[0]));
    
    // Create noise suppression from enum
    ns = otc_audio_transformer_create(OTC_MEDIA_TRANSFORMER_TYPE_VONAGE, "NoiseSuppression","", NULL, NULL);
    
    // Array of audio transformers
    otc_audio_transformer *audio_transformers[] = {
        /* Vonage Transformer - Noise Suppression */
        ns};
    
    otc_publisher_set_audio_transformers(publisher, audio_transformers, sizeof(audio_transformers) / sizeof(audio_transformers[0]));
}

@implementation OpenTokWrapper {
  SessionData *session_data;
}

- (id)init {
    self = [super init];
    if (self) {
        [self initOpenTokSession];
    }
    return self;
}

- (void)initOpenTokSession {
  session_data = calloc(1, sizeof(SessionData));
  session_data->open_tok_controller = (__bridge void *)self;
  session_data->publisher = NULL;
  
  if (otc_init(NULL) != OTC_SUCCESS) {
    NSLog(@"Could not init OpenTok library");
    return;
  }
  
  #ifdef CONSOLE_LOGGING
    otc_log_set_logger_callback(on_otc_log_message);
    otc_log_enable(OTC_LOG_LEVEL_ALL);
  #endif
  
  struct otc_session_callbacks session_callbacks = {0};
  session_callbacks.user_data = session_data;
  session_callbacks.on_connected = on_session_connected;
  session_callbacks.on_connection_created = on_session_connection_created;
  session_callbacks.on_connection_dropped = on_session_connection_dropped;
  session_callbacks.on_stream_received = on_session_stream_received;
  session_callbacks.on_stream_dropped = on_session_stream_dropped;
  session_callbacks.on_disconnected = on_session_disconnected;
  session_callbacks.on_error = on_session_error;
  
  session_data->session = otc_session_new(API_KEY, SESSION_ID, &session_callbacks);
  
  if (session_data->session == NULL) {
    NSLog(@"Could not create OpenTok session successfully");
    return;
  }
  
  struct otc_publisher_callbacks publisher_callbacks = {0};
  publisher_callbacks.user_data = session_data;
  publisher_callbacks.on_stream_created = on_publisher_stream_created;
  publisher_callbacks.on_render_frame = on_publisher_render_frame;
  publisher_callbacks.on_stream_destroyed = on_publisher_stream_destroyed;
  publisher_callbacks.on_error = on_publisher_error;
  
  session_data->publisher = otc_publisher_new("opentok-macos-sdk-samples",
                                              NULL, /* Use WebRTC's video capturer. */
                                              &publisher_callbacks);
  
  if (session_data->publisher == NULL) {
    NSLog(@"Could not create OpenTok publisher successfully");
    otc_session_delete(session_data->session);
    return;
  }
}

- (void)dealloc {
  [self unsubscribe];
  for (int i = 0; i < [_streamObjectList count]; i++)
    otc_stream_delete([_streamObjectList pointerAtIndex:i]);
  if (session_data->subscriber != NULL) {
    otc_subscriber_delete(session_data->subscriber);
    session_data->subscriber = NULL;
  }
  
  [self unpublish];
  if (session_data->publisher != NULL) {
    otc_publisher_delete(session_data->publisher);
    session_data->publisher = NULL;
  }
  
  [self disconnect];
  if (session_data->session != NULL) {
    otc_session_delete(session_data->session);
    session_data->session = NULL;
  }
    
  free(session_data);
  otc_destroy();
}

- (SessionData*)getSessionData {
  return session_data;
}

- (void)connect {
  if (session_data->session != NULL) {
    otc_session_connect(session_data->session, TOKEN);
  }
}

- (void)disconnect {
  [self unpublish];
  
  if (session_data->session != NULL) {
    otc_session_disconnect(session_data->session);
  }
}

- (void)publish {
  if ((session_data->session != NULL) && (session_data->publisher != NULL)) {
      otc_session_publish(session_data->session, session_data->publisher);
      
      enable_tranformers(session_data->publisher);
  }
}

- (void)unpublish {
  if ((session_data->session != NULL) && (session_data->publisher != NULL)) {
    otc_session_unpublish(session_data->session, session_data->publisher);
  }
}

- (void)unsubscribe {
  if ((session_data->session != NULL) && (session_data->subscriber != NULL)) {
    otc_stream *sub_stream = otc_subscriber_get_stream(session_data->subscriber);
    otc_session_unsubscribe(session_data->session, session_data->subscriber);
    for (int i = 0; i < [_streamObjectList count]; i++) {
      if (strcmp(otc_stream_get_id([_streamObjectList pointerAtIndex:i]), otc_stream_get_id(sub_stream)) == 0) {
        otc_stream_delete([_streamObjectList pointerAtIndex:i]);
        [_streamObjectList removePointerAtIndex:i];
        break;
      }
    }
  }
}

@end
