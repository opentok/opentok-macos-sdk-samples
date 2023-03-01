#include "OTVideoKit.h"
@implementation OTVideoFormat

@synthesize name, pixelFormat, bytesPerRow, imageHeight, imageWidth,
 estimatedFramesPerSecond, estimatedCaptureDelay;

- (id)init {
    self = [super init];
    if (self) {
        self.name = @"unknown";
        self.bytesPerRow = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [self setName:nil];
    [self setBytesPerRow:nil];
}

+(OTVideoFormat*)videoFormatI420WithWidth:(uint32_t)width
                                   height:(uint32_t)height
{
    OTVideoFormat* videoFormat = [[OTVideoFormat alloc] init];
    [videoFormat setName:@"OTVideoFormat I420"];
    [videoFormat setImageWidth:width];
    [videoFormat setImageHeight:height];
    [videoFormat setPixelFormat:OTPixelFormatI420];
    [videoFormat.bytesPerRow insertObject:[NSNumber numberWithInt:width]
                                  atIndex:0];
    [videoFormat.bytesPerRow insertObject:[NSNumber numberWithInt:(width + 1) / 2]
                                  atIndex:1];
    [videoFormat.bytesPerRow insertObject:[NSNumber numberWithInt:(width + 1) / 2]
                                  atIndex:2];
    return videoFormat;
}


+(OTVideoFormat*)videoFormatNV12WithWidth:(uint32_t)width
                                   height:(uint32_t)height
{
    OTVideoFormat* videoFormat = [[OTVideoFormat alloc] init];
    [videoFormat setName:@"OTVideoFormat NV12"];
    [videoFormat setImageWidth:width];
    [videoFormat setImageHeight:height];
    [videoFormat setPixelFormat:OTPixelFormatNV12];
    [videoFormat.bytesPerRow insertObject:[NSNumber numberWithInt:width]
                                  atIndex:0];
    [videoFormat.bytesPerRow insertObject:[NSNumber numberWithInt:(width + 1) / 2 * 2]
                                  atIndex:1];
    return videoFormat;
}

+(OTVideoFormat*)videoFormatARGBWithWidth:(uint32_t)width
                                   height:(uint32_t)height
{
    OTVideoFormat* videoFormat = [[OTVideoFormat alloc] init];
    [videoFormat setName:@"OTVideoFormat ARGB"];
    [videoFormat setImageWidth:width];
    [videoFormat setImageHeight:height];
    [videoFormat setPixelFormat:OTPixelFormatARGB];
    [videoFormat.bytesPerRow insertObject:[NSNumber numberWithInt:width * 4]
                                  atIndex:0];
    return videoFormat;
}

- (void)writeToOTKitFormat:(struct otc_video_capturer_settings*)format {
    format->height = self.imageHeight;
    format->width = self.imageWidth;
    format->fps = self.estimatedFramesPerSecond;
    format->expected_delay = self.estimatedCaptureDelay;
}

@end

enum otc_video_frame_format otkitPixelFormatFromObjcPixelFormat
(OTPixelFormat pixelFormat)
{
    switch(pixelFormat) {
        case OTPixelFormatNV12:
            return OTC_VIDEO_FRAME_FORMAT_NV12;
        case OTPixelFormatARGB:
            return OTC_VIDEO_FRAME_FORMAT_ARGB32;
        case OTPixelFormatI420:
            return OTC_VIDEO_FRAME_FORMAT_YUV420P;
    }
}

@implementation OTError

- (id)initWithErrorCode:(int32_t)errorCode
                 domain:(NSString*)domain
   localizedDescription:(NSString*)description
{
    NSDictionary* userInfo = [NSDictionary
                              dictionaryWithObjectsAndKeys:description,
                              NSLocalizedDescriptionKey,
                              nil];
    self = [super initWithDomain:domain code:errorCode userInfo:userInfo];
    return self;
}

@end

@implementation OTVideoFrame {
    otc_video_frame *_frame_copy;
}

@synthesize planes, timestamp, format, metadata;

- (id)init {
    if (self = [super init]) {
        [self setPlanes:[[NSPointerArray alloc]
                         initWithOptions:NSPointerFunctionsOpaqueMemory]];
        [self setFormat:nil];
    }
    return self;
}

- (id)initWithFormat:(OTVideoFormat*)videoFormat {
    if (self = [self init]) {
        [self setFormat:videoFormat];
    }
    return self;
}

- (void)dealloc {
    [self setPlanes:nil];
    [self setFormat:nil];
    //[self setMetadata:nil];
}

- (void)setPlanesWithPointers:(uint8_t*[])somePlanes
                    numPlanes:(int)numPlanes
{
    [self clearPlanes];
    for (int i = 0; i < numPlanes; i++) {
        [self.planes addPointer:somePlanes[i]];
    }
}

- (void)clearPlanes {
    while (self.planes.count > 0) {
        [self.planes removePointerAtIndex:self.planes.count - 1];
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


#pragma mark CVPixelBuffer <--> otc_video_frame conversion

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

 

/*- (void)setMetadata:(nonnull NSData *)data error:(out OTError* _Nullable*)error {
    if (data.length > OTC_VIDEO_FRAME_METADATA_MAX_SIZE) {
        if (error) {
            *error = [[OTError alloc] initWithErrorCode:1011
                                                  domain:OTK_MAC_PUBLISHER_ERROR_DOMAIN
                                    localizedDescription:nil];
        }
        return;
    }
    self.metadata = data;
}*/


@end
