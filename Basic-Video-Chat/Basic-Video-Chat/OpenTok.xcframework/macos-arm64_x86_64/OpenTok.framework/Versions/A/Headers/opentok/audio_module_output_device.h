/** @file audio_module_output_device.h
    @brief Audio module output device.
*/
#ifndef AUDIO_MODULE_OUTPUT_DEVICE_H
#define AUDIO_MODULE_OUTPUT_DEVICE_H

#include <stdlib.h>

#include "config.h"
#include "base.h"

OTC_BEGIN_DECL

/**
   Represents an audio output device enumerator, listing the output devices detected by the
   default audio module.
*/
typedef struct otc_audio_module_output_device_enumerator
    otc_audio_module_output_device_enumerator;

/**
   Creates an audio output device enumerator, listing the output devices
   detected by the default audio module.
   @return The audio output device enumerator.
*/
OTC_DECL(otc_audio_module_output_device_enumerator*)
otc_audio_module_output_device_enumerator_new();

/**
   Gets the number of audio output devices in an audio output device enumerator.
   @param device_enumerator The audio output device enumerator.
   @return The number of audio output devices.
*/
OTC_DECL(int)
otc_audio_module_output_device_enumerator_size(
    otc_audio_module_output_device_enumerator* device_enumerator);

/**
   Gets the ID of the specified audio output device in an audio output device enumerator.
   @param device_enumerator The audio output device enumerator.
   @param device_index The index of the device in the enumeration.
   @return The ID of the device at selected index, or nullptr if the index is out of
   range.
*/
OTC_DECL(const char*)
otc_audio_module_output_device_enumerator_get_device_id(
    otc_audio_module_output_device_enumerator* device_enumerator,
    int device_index);

/**
   Gets the name of the specified audio output device in an audio output device enumerator.
   @param device_enumerator The audio output device enumerator.
   @param device_index The index of the device in the enumeration.
   @return The name of the device at selected index, or nullptr if the index is out
   of range.
*/
OTC_DECL(const char*)
otc_audio_module_output_device_enumerator_get_device_name(
    otc_audio_module_output_device_enumerator* device_enumerator,
    int device_index);

/**
   Deletes an audio output device enumerator.
   @param device_enumerator The audio output device enumerator.
   @return The result of the operation. 0 if success.
*/
OTC_DECL(otc_status)
otc_audio_module_output_device_enumerator_delete(
    otc_audio_module_output_device_enumerator* device_enumerator);

/**
   Selects an audio output device in the default audio module.
   @param device_id The ID of the audio output device.
   @return The result of the operation. 0 if success.
*/
OTC_DECL(otc_status)
otc_audio_module_output_device_select(const char* device_id);

OTC_END_DECL

#endif  // AUDIO_MODULE_OUTPUT_DEVICE_H
