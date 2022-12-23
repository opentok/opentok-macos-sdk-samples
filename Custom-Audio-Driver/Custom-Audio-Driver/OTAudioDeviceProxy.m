//
//  OTAudioDeviceProxy.m
//
//  Copyright (c) 2014 TokBox, Inc. All rights reserved.
//

#import "OTAudioDeviceProxy.h"

@implementation OTAudioDeviceProxy
{
    @public
    id<OTAudioDevice> audioDevice_;
    struct otc_audio_device_callbacks otc_audio_callbacks;
}

otc_bool otc_audio_proxy_get_render_settings(const otc_audio_device *audio_device,
                                           void *user_data,
                                           struct otc_audio_device_settings *settings)
{
    OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(user_data);
    OTAudioFormat* format = [audio_device_proxy->audioDevice_ renderFormat];
    settings->sampling_rate = format.sampleRate;
    settings->number_of_channels = format.numChannels;
     return true;
}

otc_bool otc_audio_proxy_get_capture_settings(const otc_audio_device *audio_device,
                                            void *user_data,
                                            struct otc_audio_device_settings *settings)
{
    OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(user_data);
    OTAudioFormat* format = [audio_device_proxy->audioDevice_ captureFormat];
    settings->sampling_rate = format.sampleRate;
    settings->number_of_channels = format.numChannels;
    return true;
}

otc_bool otc_audio_proxy_init_render(const otc_audio_device *audio_device, void *user_data)
{
    OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(user_data);
    BOOL ret = [audio_device_proxy->audioDevice_ initializeRendering];
    return ret;
}

otc_bool otc_audio_proxy_init_capture(const otc_audio_device *audio_device, void *user_data)
{
    OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(user_data);
    BOOL ret = [audio_device_proxy->audioDevice_ initializeCapture];
    return ret;
}

otc_bool otc_audio_proxy_start_render(const otc_audio_device *audio_device, void *user_data)
{
    OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(user_data);
    BOOL ret = [audio_device_proxy->audioDevice_ startRendering];
    return ret;
}

otc_bool otc_audio_proxy_stop_render(const otc_audio_device *audio_device, void *user_data)
{
    OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(user_data);
    BOOL ret = [audio_device_proxy->audioDevice_ stopRendering];
    return ret;
}

otc_bool otc_audio_proxy_start_capture(const otc_audio_device *audio_device, void *user_data)
{
    OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(user_data);
    BOOL ret = [audio_device_proxy->audioDevice_ startCapture];
    return ret;
}

otc_bool otc_audio_proxy_stop_capture(const otc_audio_device *audio_device, void *user_data)
{
    OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(user_data);
    BOOL ret = [audio_device_proxy->audioDevice_ stopCapture];
    return ret;
}

// Delay information and control
int otc_audio_proxy_playout_delay(const otc_audio_device *audio_device, void *user_data)
{
    OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(user_data);
    return [audio_device_proxy->audioDevice_ estimatedRenderDelay];
}

int otc_audio_proxy_recording_delay(const otc_audio_device *audio_device, void *user_data)
{
    OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(user_data);
    return [audio_device_proxy->audioDevice_ estimatedCaptureDelay];
}

otc_bool otc_audio_proxy_destroy_capture(const otc_audio_device *audio_device, void *user_data)
{
    // Sridhar : iOS autmoatically shuts down audio resources when last pub or sub disconnects.
    // Also, Apple recommends using one audiounit for both recording and playing, if we implement that
    // this callback can't be used.
    //struct otc_audio_device_callbacks *dev = (struct otc_audio_device_callbacks*) audio_device;
    //OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(dev->user_data);
    BOOL ret = true;/*[audio_device_proxy->audioDevice_ stopCapture]*/;
    return ret;
}

otc_bool otc_audio_proxy_destroy_render(const otc_audio_device *audio_device, void *user_data)
{
    // Sridhar : iOS autmoatically shuts down audio resources when last pub or sub disconnects.
    // Also, Apple recommends using one audiounit for both recording and playing, if we implement that
    // this callback can't be used.
    //struct otc_audio_device_callbacks *dev = (struct otc_audio_device_callbacks*) audio_device;
    //OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(dev->user_data);
    BOOL ret = true;/*[audio_device_proxy->audioDevice_ stopCapture]*/;
    return ret;
}

otc_bool otc_audio_proxy_render_is_initialized(const otc_audio_device *audio_device, void *user_data)
{
    OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(user_data);
    return [audio_device_proxy->audioDevice_ renderingIsInitialized];
}

otc_bool otc_audio_proxy_capture_is_initialized(const otc_audio_device *audio_device, void *user_data)
{
    OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(user_data);
    return [audio_device_proxy->audioDevice_ captureIsInitialized];
}

otc_bool otc_audio_proxy_is_rendering(const otc_audio_device *audio_device, void *user_data)
{
    OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(user_data);
    return [audio_device_proxy->audioDevice_ isRendering];
}

otc_bool otc_audio_proxy_is_capturing(const otc_audio_device *audio_device, void *user_data)
{
    OTAudioDeviceProxy *audio_device_proxy = (__bridge OTAudioDeviceProxy *)(user_data);
    return [audio_device_proxy->audioDevice_ isCapturing];
}

-(id)initWithAudioDevice:(id<OTAudioDevice>)device {
    self = [super init];
    if (self) {
        otc_audio_callbacks.init_renderer = otc_audio_proxy_init_render;
        otc_audio_callbacks.destroy_renderer = otc_audio_proxy_destroy_render;
        otc_audio_callbacks.start_renderer = otc_audio_proxy_start_render;
        otc_audio_callbacks.stop_renderer = otc_audio_proxy_stop_render;
        otc_audio_callbacks.get_render_settings = otc_audio_proxy_get_render_settings;
        otc_audio_callbacks.get_estimated_render_delay = otc_audio_proxy_playout_delay;
        otc_audio_callbacks.is_renderer_initialized = otc_audio_proxy_render_is_initialized;
        otc_audio_callbacks.is_renderer_started = otc_audio_proxy_is_rendering;

        otc_audio_callbacks.init_capturer = otc_audio_proxy_init_capture;
        otc_audio_callbacks.destroy_capturer = otc_audio_proxy_destroy_capture;
        otc_audio_callbacks.start_capturer = otc_audio_proxy_start_capture;
        otc_audio_callbacks.stop_capturer = otc_audio_proxy_stop_capture;
        otc_audio_callbacks.get_capture_settings = otc_audio_proxy_get_capture_settings;
        otc_audio_callbacks.get_estimated_capture_delay = otc_audio_proxy_recording_delay;
        otc_audio_callbacks.is_capturer_initialized = otc_audio_proxy_capture_is_initialized;
        otc_audio_callbacks.is_capturer_started = otc_audio_proxy_is_capturing;

        otc_audio_callbacks.user_data = (__bridge void *)(self);
        otc_set_audio_device(&otc_audio_callbacks);
        
        [self setAudioDevice:device];
    }
    return self;
}

-(void) setAudioDevice:(id<OTAudioDevice>) device
{
    audioDevice_ = device;
    
    if (nil != device) {
        // TODO: Handle this error plz.
        [audioDevice_ setAudioBus:self];
    }
}

-(id<OTAudioDevice>) audioDevice
{
    return audioDevice_;
}

- (void) writeCaptureData:(void*) data numberOfSamples:(uint32_t) count
{
    otc_audio_device_write_capture_data(data,count);
}

- (uint32_t) readRenderData:(void*) data numberOfSamples:(uint32_t) count
{
    //Data flows out of this function. We push samples into on_play.
    return (uint32_t)otc_audio_device_read_render_data(data, count);
}

-(struct otc_audio_device_cb*) cAudioDevice
{
    return (nil != audioDevice_) ? (struct otc_audio_device_cb*)&otc_audio_callbacks : NULL;
}

@end

@implementation OTAudioFormat

@dynamic sampleRate, numChannels;

- (void)setSampleRate:(uint16_t) samplingRate
{
    format_.sampling_rate = samplingRate;
}

- (uint16_t)sampleRate {
    return format_.sampling_rate;
}

- (void)setNumChannels:(uint8_t)numChannels
{
    format_.number_of_channels = numChannels;
}

- (uint8_t)numChannels {
    return format_.number_of_channels;
}

@end

