Video Transformers
======================

The Video Transformers app is a very simple application created on top of Basic Video Chat meant to get a new developer
started using Media Processor APIs on OpenTok Mac SDK. For a full description, see the [Video Transformers tutorial at the
OpenTok developer center](https://tokbox.com/developer/guides/vonage-media-processor/mac/).

You can use pre-built transformers in the Vonage Media Processor library or create your own custom video transformer to apply to published video.

You can use the otc_publisher_set_video_transformers() and otc_publisher_set_audio_transformers() functions to apply audio and video transformers to a published stream.

Important:

The audio and video transformer API is a beta feature.
Currently, only Apple silicon Macs are supported.
For video, you can apply the background blur video transformer included in the Vonage Media Library.

You can also create your own custom audio and video transformers.

<div class="important">
  <p>
  <b>Important:</b>
  </p>
  <p>
  <ul>
    <li>The audio and video transformer API is a beta feature.</li>
    <li>Currently, only Apple silicon Macs are supported.</li>
  </ul>
  </p>
</div>

For video, you can apply the background blur video transformer included in the Vonage Media Library.

You can also create your own custom audio and video transformers.

## Applying a video transformer from the Vonage Media Library

Use the <a href="/developer/sdks/mac/reference/media__transformer_8h.html#a5f56924c9915d85d186117061177bdf5"><code>otc_video_transformer_create()</code></a>
function to create a video transformer that uses a named transformer from the Vonage Media Library.

Currently, only one Vonage Media Library transformer is supported: background blur. For this transformer:

* Set the `type` parameter to `OTC_MEDIA_TRANSFORMER_TYPE_VONAGE` (defined in the SDK).
  This indicates that you are using a transformer from the Vonage Media Library.
* Set the `name` parameter to `"BackgroundBlur"`.
* Set the `properties` parameter to a JSON string defining properties for the transformer.
  For the background blur transformer, this JSON includes one property -- `radius` -- which can be set
  to `"High"`, `"Low"`, or `"None"`. An example of the JSON string is ` "{\"radius\":\"High\"}",`.
* Set the `callback` parameter to `NULL`. (This parameter is used for custom video transformers.)
* Set the `userData` parameter to `NULL`. (This parameter is used for custom video transformers.)

```c
otc_video_transformer *backgroundBlur = otc_video_transformer_create(
  OTC_MEDIA_TRANSFORMER_TYPE_VONAGE,
  "BackgroundBlur",
  "{\"radius\":\"High\"}",
  NULL,
  NULL
);
```

After you create the transformer, you can apply it to a publisher using the
<a href="developer/sdks/mac/reference/publisher_8h.html#a06dec21cf056dbbe1ddadd83c8e3488f"><code>otc_publisher_set_video_transformers()</code></a>
function:

```c
// Array of video transformers
otc_video_transformer *video_transformers[] = {
  background_blur
};

otc_publisher_set_video_transformers(publisher, video_transformers, 1);
```

The last parameter of `otc_publisher_set_video_transformers()` is the size of the `transformers` array.
In this example we are applying one video transformer to the publisher. You can apply multiple transformers
by adding multiple otc_video_transformer objects to the `transformers` array passed into
`otc_publisher_set_video_transformers()`.

## Creating a custom video transformer

Use the <a href="/developer/sdks/mac/reference/media__transformer_8h.html#a5f56924c9915d85d186117061177bdf5"><code>otc_video_transformer_create()</code></a>
function to create a video transformer.

* Set the `type` parameter to `OTC_MEDIA_TRANSFORMER_TYPE_CUSTOM` (defined in the SDK).
  This indicates that you are creating a custom transformer.
* Set the `name` parameter to a unique name for your transformer.
* Set the `properties` parameter `NULL`. (This parameter is used when using a transformer from
  the Vonage Media Library.)
* Set the `callback` parameter to a callback function. This function is an instance of
  the `video_transform_callback` type, defined in the SDK. This function has two parameters:
  `user_data` -- see the next parameter -- and `frame` -- an instance of type
  of type `otc_video_frame` (defined in the SDK) passed into the callback function when
  there is video frame data available. Transform the video frame data in the callback function.
* Set the `userData` parameter (optional) to user data to be passed in the callback function.

Here is a basic example:

```c
void on_transform_logo(void* user_data, struct otc_video_frame* frame)
{
    // implement transformer on the otc_video_frame data
}

otc_video_transformer *logo = otc_video_transformer_create(
  OTC_MEDIA_TRANSFORMER_TYPE_CUSTOM,
  "blacknwhite",
  NULL,
  on_transform_logo,
  NULL
);
```

After you create the transformer, you can apply it to a publisher using the
<a href="developer/sdks/mac/reference/publisher_8h.html#a06dec21cf056dbbe1ddadd83c8e3488f"><code>otc_publisher_set_video_transformers()</code></a>
function:

```c
// Array of video transformers
otc_video_transformer *video_transformers[] = {
  logo
};

otc_publisher_set_video_transformers(publisher, video_transformers, 1);
```

## Creating a custom audio transformer

Use the <a href="/developer/sdks/mac/reference/media__transformer_8h.html#a15c109155502af31df8f61be5174f202"><code>otc_audio_transformer_create()</code></a>
function to create an audio transformer.

* Set the `type` parameter to `OTC_MEDIA_TRANSFORMER_TYPE_CUSTOM` (defined in the SDK).
  This indicates that you are creating a custom transformer. (In this beta version, no
  predefined audio transformers from the Vonage Media Library are supported.)
* Set the `name` parameter to a unique name for your transformer.
* Set the `properties` parameter `NULL`. (This parameter is used when using a transformer from
  the Vonage Media Library.)
* Set the `callback` parameter to a callback function. This function is an instance of
  the `audio_transform_callback` type, defined in the SDK. This function has two parameters:
  `user_data` -- see the next parameter -- and `frame` -- an instance of type
  of type `otc_audio_data` (defined in the SDK) passed into the callback function when
  there is audio data available. Transform the audio data in the callback function.
* Set the `userData` parameter (optional) to user data to be passed in the callback function.

Here is a basic example:

```c
void on_transform_audio(void* user_data, struct otc_video_frame* frame)
{
    // implement transformer on the otc_audio_data audio data
}
