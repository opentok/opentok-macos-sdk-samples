/** @file audio_data.h
    @brief Audio Data.

    This file includes the type definition for an audio data.
*/
#ifndef audio_data_h
#define audio_data_h

#include "config.h"

OTC_BEGIN_DECL

/**
    This struct represents subscriber PCM audio data, reported periodically
    by the {@link otc_subscriber_callbacks.on_audio_data} callback function.
  */
struct otc_audio_data {
    const void* sample_buffer; /**< The pointer to binary audio sample buffer. */
    const int bits_per_sample; /**< The number of bits per sample. */
    const int sample_rate; /**< The sample rate (number of times audio is sampled per second). */
    const size_t number_of_channels; /**< The number of channels. */
    const size_t number_of_samples; /**< The number of audio samples in the sample buffer. */
};

OTC_END_DECL

#endif /* audio_data_h */

