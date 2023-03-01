//
//  OTVideoKit.h
//
//  Copyright (c) 2014 TokBox, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CMTime.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreGraphics/CoreGraphics.h>
#include <OpenTok/OpenTok.h>
@class OTError;

#define OTK_MAC_PUBLISHER_ERROR_DOMAIN @"OTKMacPublisherErrorDomain"
/**
 * Defines values for video orientations (up, down, left, right) for the
 * orieintation property of an <OTVideoFrame> object.
 */
typedef NS_ENUM(int32_t, OTVideoOrientation) {
    /** The video is oriented top up. No rotation is applies. */
    OTVideoOrientationUp = 1,
    /** The video is rotated 180 degrees. */
    OTVideoOrientationDown = 2,
   /** The video is rotated 90 degrees. */
    OTVideoOrientationLeft = 3,
   /** The video is rotated 270 degrees. */
    OTVideoOrientationRight = 4,
};

/**
 * Defines values for pixel format for the pixelFormat property of an
 * <OTVideoFrame> object.
 */
typedef NS_ENUM(int32_t, OTPixelFormat) {
    /** I420 format. */
    OTPixelFormatI420 = 'I420',
    /** ARGB format. */
    OTPixelFormatARGB = 'ARGB',
    /** NV12 format. */
    OTPixelFormatNV12 = 'NV12',
};

enum otk_video_orientation {
    OTK_VIDEO_ORIENTATION_LANDSCAPE_LEFT = 90,
    OTK_VIDEO_ORIENTATION_LANDSCAPE_RIGHT = 270,
    OTK_VIDEO_ORIENTATION_PORTRAIT = 0,
    OTK_VIDEO_ORIENTATION_PORTRAIT_UPSIDE_DOWN = 180
};


/**
 * Defines values for the <[OTSubscriber viewScaleBehavior]> and
 * <[OTPublisher viewScaleBehavior]> properties.
 */
typedef NS_ENUM(NSInteger, OTVideoViewScaleBehavior) {
    /**
     * The video shrinks, as needed, so that the entire video is visible
     * with pillarboxing.
     */
    OTVideoViewScaleBehaviorFit,
    /**
     * The video scales to fill the entire area of the renderer, with cropping
     * as needed.
     */
    OTVideoViewScaleBehaviorFill,
};

/**
 * Defines values for the <OTVideoCapture setVideoContentHint:> method.
 *
 * You can read more about these options in the
 * [W3C Working Draft](https://www.w3.org/TR/mst-content-hint/).
 * And [here](https://webrtc.github.io/samples/src/content/capture/video-contenthint/)
 * are some live examples.
 */
typedef NS_ENUM(NSInteger, OTVideoContentHint) {
    /**
     * No hint is provided (the default).
     */
        OTVideoContentHintNone,
    /**
     * The track should be treated as if it contains video where motion is important.
     */
        OTVideoContentHintMotion,
    /**
     * The track should be treated as if video details are extra important. For example,
     * you may use this setting for a stream that contains text content, painting, or line art.
     */
        OTVideoContentHintDetail,
    /**
     * The track should be treated as if video details are extra important, and that significant
     * sharp edges and areas of consistent color can occur frequently. For example, you may use this
     * settting for a stream that contains text content.
     */
        OTVideoContentHintText
};



/**
 * Defines the video format assigned to an instance of an <OTVideoFrame> object.
 */
@interface OTVideoFormat : NSObject

/**
 * The name you assign to the video format
 */
@property(nonatomic, copy) NSString* _Nonnull name;
/**
 * The pixel format. Valid values are defined in the <OTPixelFormat> enum.
 */
@property(nonatomic, assign) OTPixelFormat pixelFormat;
/**
 * The number of bytes per row of the video.
 */
@property(nonatomic, strong) NSMutableArray* _Nonnull bytesPerRow;
/**
 * The width of the video, in pixels.
 */
@property(nonatomic, assign) uint32_t imageWidth;
/**
 * The height of the video, in pixels.
 */
@property(nonatomic, assign) uint32_t imageHeight;
/**
 * The estimated number of frames per second in the video.
 */
@property(nonatomic, assign) double estimatedFramesPerSecond;
/**
 * The estimated capture delay, in milliseconds, of the video.
 */
@property(nonatomic, assign) double estimatedCaptureDelay;

+ (nonnull OTVideoFormat*)videoFormatI420WithWidth:(uint32_t)width
                                            height:(uint32_t)height;

+ (nonnull OTVideoFormat*)videoFormatNV12WithWidth:(uint32_t)width
                                            height:(uint32_t)height;

+ (nonnull OTVideoFormat*)videoFormatARGBWithWidth:(uint32_t)width
                                            height:(uint32_t)height;

@end

/**
 * Defines a frame of a video. See <[OTVideoRender renderVideoFrame:]> and
 * <[OTVideoCaptureConsumer consumeFrame:]>.
 */
@interface OTVideoFrame : NSObject

/** @name Properties of OTVideoFrame objects */

/**
 * An array of planes in the video frame.
 */
@property(nonatomic, strong) NSPointerArray* _Nullable planes;
/**
 * A timestap of the video frame.
 */
@property(nonatomic, assign) CMTime timestamp;
/**
 * The orientation of the video frame.
 */
@property(nonatomic, assign) OTVideoOrientation orientation;
/**
 * The format of the video frame.
 */
@property(nonatomic, strong) OTVideoFormat* _Nullable format;
/**
 * The metadata associated with this video frame, if any.
 */
@property(nonatomic, readonly) NSData* _Nullable metadata;

/** @name Instantiating OTVideoFrame objects */

/**
 * Initializes an OTVideoFrame object.
 */
- (nonnull id)init;

/**
 * Initializes an OTVideoFrame object with a specified format.
 *
 * @param videoFormat The video format used by the video frame.
 */
- (nonnull id)initWithFormat:(nonnull OTVideoFormat*)videoFormat;
/**
 * Sets planes for the video frame.
 *
 * @param planes The planes to assign.
 * @param numPlanes The number of planes to assign.
 */
- (void)setPlanesWithPointers:(uint8_t* _Nonnull[_Nonnull])planes numPlanes:(int)numPlanes;
/**
 * Cleans the planes in the video frame.
 */
- (void)clearPlanes;

/**
 * Sets the metadata associated with this video frame.
 *
 * @param data The metadata to assign.
 * @param error If the size of the metadata passed is bigger than 32 bytes
 * this value is set to an OTError object with the `code`  property set to
 * OTNullOrInvalidParameter.
 */
- (void)setMetadata:(nonnull NSData *)data error:(out OTError* _Nullable* _Nullable)error;
+ (struct otc_video_frame*_Nullable)convertPixelBufferToOTCFrame:(CVImageBufferRef _Nullable )frame;
@end

/**
 * Defines a the consumer of an OTVideoCapture object.
 */
@protocol OTVideoCaptureConsumer <NSObject>

/**
 * Consumes a frame.
 *
 * @param frame The frame to consume.
 */
- (void)consumeFrame:(nonnull OTVideoFrame*)frame;

/**
 * Consumes a CoreVideo image buffer.
 *
 * @param frame The CVImageBufferRef to consume. The frame's pixel type must be one of the following
 *             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
 *             kCVPixelFormatType_420YpCbCr8Planar, kCVPixelFormatType_420YpCbCr8PlanarFullRange,
 *             kCVPixelFormatType_32ARGB, kCVPixelFormatType_32BGRA, or kCVPixelFormatType_24RGB.
 * @param orientation The orientation of the frame.
 * @param ts The frame timestamp.
 * @param metadata The frame metadata.
 *
 * @return YES if the image buffer consumed successfully, or NO upon failure.
 */
- (BOOL)consumeImageBuffer:(nonnull CVImageBufferRef)frame orientation:(OTVideoOrientation)orientation
                 timestamp:(CMTime)ts metadata:(NSData* _Nullable)metadata;

@end

/**
 * Defines a video capturer to be used by an <OTPublisherKit> object.
 * See the `videoCapture` property of an <OTPublisherKit> object.
 */
@protocol OTVideoCapture <NSObject>

/**
 * The <OTVideoCaptureConsumer> object that consumes frames for the video
 * capturer.
 */
@property(atomic, weak) id<OTVideoCaptureConsumer> _Nullable videoCaptureConsumer;

/**
 * This property will get/set the video content hint to one of the values
 * given in the <OTVideoContentHint> enum. By default it is set to NONE.
*/
@property(nonatomic, readwrite) OTVideoContentHint videoContentHint;

/**
 * Initializes the video capturer.
 */
- (void)initCapture NS_SWIFT_NAME(initCapture());
/**
 * Releases the video capturer.
 */
- (void)releaseCapture NS_SWIFT_NAME(releaseCapture());
/**
 * Starts capturing video.
 */
- (int32_t)startCapture;
/**
 * Stops capturing video.
 */
- (int32_t)stopCapture;
/**
 * Whether video is being captured.
 */
- (BOOL)isCaptureStarted;
/**
 * The video format of the video capturer.
 * @param videoFormat The video format used.
 */
- (int32_t)captureSettings:(nonnull OTVideoFormat*)videoFormat;

@end

@interface OTError : NSError

- (id _Nullable)initWithErrorCode:(int32_t)errorCode
                              domain_Nullable:(NSString*_Nullable)domain
                localizedDescription_Nullable:(NSString*_Nullable)description;

@end
