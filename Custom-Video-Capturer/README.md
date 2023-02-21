Custom Video Capturer sample app
===========================

This sample provides a captuer that captures from the Mac camera and publish.
We use the custom capture interface provided by the SDK to achieve this.

Steps to build & run:

1. Create a Vonage Video API Account
2. Get an APIKey, Session-ID, Token from Vonage video playground
3. Add these details to ViewController.m and run the sample
4. You can have a two-party video call with the video playground as the second participant.

Notes:

This sample assumes there are only 2 participants in the call. If more than 1 subscriber joins, the behaviour is unexpected.
