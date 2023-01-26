//
//  OTAudioDeviceProxy.h
//  Basic-Sample-Mac-C
//
//  Created by Rajkiran Talusani on 6/10/22.
//

#import <Foundation/Foundation.h>
#import "OTAudioKit.h"
#import <OpenTok/opentok.h>

struct otc_audio_device;
typedef struct otc_audio_device otc_audio_device;
//struct otc_audio_device_settings;

@interface OTAudioDeviceProxy : NSObject <OTAudioBus>

@property (nonatomic, strong) id<OTAudioDevice> audioDevice;

-(id)initWithAudioDevice:(id<OTAudioDevice>) device;
-(struct otc_audio_device_cb*) cAudioDevice;
@end

@interface OTAudioDeviceManager ()
+ (void)initializeDefaultDevice;
+ (void)setDefaultAudioDeviceClass:(Class)aClass;

@end

@interface OTAudioFormat ()
{
    @public
    struct otc_audio_device_settings format_;
}

@end
