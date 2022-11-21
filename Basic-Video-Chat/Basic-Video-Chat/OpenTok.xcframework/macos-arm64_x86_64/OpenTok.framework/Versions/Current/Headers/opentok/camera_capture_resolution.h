/** @file camera_capture_resolution.h
    @brief OpenTok Camera Capture Resolution on default video capturers.

    This file includes the type definition for camera capture resolutions on default video capturers.
*/

#ifndef CAMERA_CAPTURE_RESOLUTION_H
#define CAMERA_CAPTURE_RESOLUTION_H

/** Publisher default camera capture resolution type enumeration.

    This enumeration represents the different camera capture resolution types supported.
    Note: For important considerations in using 1080p video, see this
    <a href="https://tokbox.com/developer/guides/1080p">developer guide</a>.  Additionally,
    1080p resolution is only recommended for relayed sessions.
 */
enum otc_camera_capture_resolution {
  OTC_CAMERA_CAPTURE_RESOLUTION_LOW = 0, /** The lowest resolution (320x240) */
  OTC_CAMERA_CAPTURE_RESOLUTION_MEDIUM = 1, /** VGA resolution (640x480) */
  OTC_CAMERA_CAPTURE_RESOLUTION_HIGH = 2, /** HD resolution (1280x720) */
  OTC_CAMERA_CAPTURE_RESOLUTION_1080P = 3 /** 1080p resolution (1920x1080) */
};

#endif /* camera_capture_resolution_h */
