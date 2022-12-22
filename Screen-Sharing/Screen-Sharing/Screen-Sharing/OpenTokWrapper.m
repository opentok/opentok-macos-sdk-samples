//
//  OpenTokWrapper.cpp
//  Screen-Sharing
//
//  Created by Jerónimo Valli on 11/16/22.
//

#include "OpenTokWrapper.h"

#define API_KEY ""
#define SESSION_ID ""
#define TOKEN ""

const uint8_t * consumeImageBuffer_get_plane(void *user_data, enum otc_video_frame_plane plane) {
    CVImageBufferRef frame = (CVImageBufferRef)user_data;
    return (const uint8_t * )CVPixelBufferGetBaseAddressOfPlane(frame, plane);
}

int consumeImageBuffer_get_plane_stride(void *user_data, enum otc_video_frame_plane plane) {
    CVImageBufferRef frame = (CVImageBufferRef)user_data;
    return (int)CVPixelBufferGetBytesPerRowOfPlane(frame, plane);
}

void consumeImageBuffer_release(void *user_data) {
    CVImageBufferRef frame = (CVImageBufferRef)user_data;
    CVPixelBufferUnlockBaseAddress(frame, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferRelease(frame);
}

typedef struct {
  otc_session *session;
  otc_publisher *publisher;
  const otc_stream* pub_stream;
  otc_subscriber *subscriber;
  const otc_stream* sub_stream;
  void *open_tok_controller;
  const otc_video_capturer *video_capturer;
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
      [openTokWrapper.delegate onSubscriberError:[NSString stringWithFormat:@"%s", error_string]];
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
      [openTokWrapper.delegate onSessionError:[NSString stringWithFormat:@"%s", error_string]];
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

static otc_bool video_capturer_init(const otc_video_capturer *capturer, void *user_data) {
    NSLog(@"video_capturer_init");
  SessionData* session_data_local = (SessionData*) user_data;
  session_data_local->video_capturer = capturer;

  return OTC_TRUE;
}

static otc_bool video_capturer_destroy(const otc_video_capturer *capturer, void *user_data) {
    NSLog(@"video_capturer_destroy");
  SessionData* session_data_local = (SessionData*) user_data;
  OpenTokWrapper *openTokWrapper = (__bridge OpenTokWrapper*)session_data_local->open_tok_controller;
  if (session_data_local->video_capturer == NULL) {
    return OTC_FALSE;
  }

  if (openTokWrapper != NULL && openTokWrapper.delegate) {
    [openTokWrapper.delegate onVideoCapturerDestroy:session_data_local->video_capturer];
  }

  return OTC_TRUE;
}

static otc_bool video_capturer_start(const otc_video_capturer *capturer, void *user_data) {
    NSLog(@"video_capturer_start");
  SessionData* session_data_local = (SessionData*) user_data;
  OpenTokWrapper *openTokWrapper = (__bridge OpenTokWrapper*)session_data_local->open_tok_controller;
  if (session_data_local->video_capturer == NULL) {
    return OTC_FALSE;
  }

  if (openTokWrapper != NULL && openTokWrapper.delegate) {
    [openTokWrapper.delegate onVideoCapturerStart:session_data_local->video_capturer];
  }

  return OTC_TRUE;
}

static otc_bool get_video_capturer_capture_settings(const otc_video_capturer *capturer,
                                                    void *user_data,
                                                    struct otc_video_capturer_settings *settings) {
  SessionData* session_data_local = (SessionData*) user_data;
  
  if (session_data_local->video_capturer == NULL) {
    return OTC_FALSE;
  }

  settings->format = OTC_VIDEO_FRAME_FORMAT_NV12;
  settings->width = 1280;
  settings->height = 720;
  settings->fps = 60;
  settings->mirror_on_local_render = OTC_FALSE;
  settings->expected_delay = 0;

  return OTC_TRUE;
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

- (id)initWithDelegate:(id<OpenTokWrapperDelegate>)delegate {
    self = [super init];
    if (self) {
        self.delegate = delegate;
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
    
  struct otc_video_capturer_callbacks video_capturer_callbacks = {0};
    video_capturer_callbacks.user_data = session_data;
    video_capturer_callbacks.init = video_capturer_init;
    video_capturer_callbacks.destroy = video_capturer_destroy;
    video_capturer_callbacks.start = video_capturer_start;
    video_capturer_callbacks.get_capture_settings = get_video_capturer_capture_settings;
    
    otc_publisher_settings* publisher_settings = otc_publisher_settings_new();
    if (publisher_settings == NULL) {
        NSLog(@"Could not create OpenTok publisher settings successfully");
        otc_session_delete(session_data->session);
      return;
    }
    otc_publisher_settings_set_name(publisher_settings, "opentok-macos-sdk-samples");
    otc_publisher_settings_set_video_capturer(publisher_settings,
                                              &video_capturer_callbacks);
    otc_publisher_settings_set_audio_track(publisher_settings, OTC_FALSE);
  
  struct otc_publisher_callbacks publisher_callbacks = {0};
  publisher_callbacks.user_data = session_data;
  publisher_callbacks.on_stream_created = on_publisher_stream_created;
  publisher_callbacks.on_render_frame = on_publisher_render_frame;
  publisher_callbacks.on_stream_destroyed = on_publisher_stream_destroyed;
  publisher_callbacks.on_error = on_publisher_error;
  
  session_data->publisher = otc_publisher_new_with_settings(&publisher_callbacks,
                                                            publisher_settings);
  
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

- (void)consumeFrame:(CMSampleBufferRef)sampleBufferRef {
    if ((session_data->session != NULL) && (session_data->video_capturer != NULL) && sampleBufferRef) {
        CVImageBufferRef frame = CMSampleBufferGetImageBuffer(sampleBufferRef);
        
        if (!frame || CFGetTypeID(frame) != CVPixelBufferGetTypeID()) {
            return;
        }
        
        BOOL success = YES;
        otc_video_frame *otc_frame = [OpenTokWrapper convertPixelBufferToOTCFrame:frame];
        if (otc_frame == NULL)
        {
            success = NO;
        } else
        {
            otc_status status = OTC_SUCCESS;
            // We need to keep the publisher alive when we provide a new frame, because in this same function
            // the publisher preview frame is dispatched. If for some reason the publisher is deallocated in the on_frame
            // function it will cause a deadlock, so keeping the reference here we avoid that situation.
            if (status == OTC_SUCCESS)
            {
                status = otc_video_capturer_provide_frame(session_data->video_capturer,
                                                   0,
                                                   otc_frame);
            }
            if (status != OTC_SUCCESS)
                success = NO;
            otc_video_frame_delete(otc_frame);
        }
    }
}

+ (struct otc_video_frame*)convertPixelBufferToOTCFrame:(CVImageBufferRef)frame
{
    if (!frame || CFGetTypeID(frame) != CVPixelBufferGetTypeID()) {
        return NULL;
    }
    
    enum otc_video_frame_format format = OTC_VIDEO_FRAME_FORMAT_YUV420P;
    
    uint32_t pixelFormat = CVPixelBufferGetPixelFormatType(frame);
    if (kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange == pixelFormat ||
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange == pixelFormat) {
        format = OTC_VIDEO_FRAME_FORMAT_NV12;
    } else if (kCVPixelFormatType_420YpCbCr8Planar == pixelFormat ||
               kCVPixelFormatType_420YpCbCr8PlanarFullRange == pixelFormat) {
        format = OTC_VIDEO_FRAME_FORMAT_YUV420P;
    } else if (kCVPixelFormatType_32ARGB == pixelFormat) {
        format = OTC_VIDEO_FRAME_FORMAT_ARGB32;
    } else if (kCVPixelFormatType_32BGRA == pixelFormat) {
        format = OTC_VIDEO_FRAME_FORMAT_BGRA32;
    } else if (kCVPixelFormatType_24RGB == pixelFormat) {
        format = OTC_VIDEO_FRAME_FORMAT_RGB24;
    } else {
        return NULL;
    }
    
    struct otc_video_frame_planar_memory_callbacks cb = {0};
    cb.user_data =  CVPixelBufferRetain(frame);
    CVPixelBufferLockBaseAddress(frame, kCVPixelBufferLock_ReadOnly);
    cb.get_plane = consumeImageBuffer_get_plane;
    cb.get_plane_stride = consumeImageBuffer_get_plane_stride;
    cb.release = consumeImageBuffer_release;
    
    otc_video_frame *otc_frame = otc_video_frame_new_planar_memory_wrapper(format,
                                                                           (int)CVPixelBufferGetWidth(frame),
                                                                           (int)CVPixelBufferGetHeight(frame),
                                                                           OTC_TRUE,
                                                                           &cb);
    
    return otc_frame;
}

@end
