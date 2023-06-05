Basic Video Chat with Metal sample app
===========================

The Basic Video Chat with Metal app is a very simple application meant to get a new developer
started using the OpenTok MacOS SDK.

Adding the OpenTok library
==========================
In this example the OpenTok iOS SDK was not included as a dependency,
you can do it through Swift Package Manager or Cocoapods.


Swift Package Manager
---------------------
To add a package dependency to your Xcode project, you should select 
*File* > *Swift Packages* > *Add Package Dependency* and enter the repository URL:
`https://github.com/Vonage/client-sdk-video-macos.git`.


Cocoapods
---------
To use CocoaPods to add the OpenTok library and its dependencies into this sample app
simply open Terminal, navigate to the root directory of the project and run: `pod install`.

Steps to build & run
====================

1. Create a Vonage Video API Account
2. Get an APIKey, Session-ID, Token from Vonage video playground
3. Add these details to ViewController.m and run the sample
4. You can have a two-party video call with the video playground as the second participant.

Notes:
======
This sample assumes there are only 2 participants in the call. If more than 1 subscriber joins, the behaviour is unexpected.
