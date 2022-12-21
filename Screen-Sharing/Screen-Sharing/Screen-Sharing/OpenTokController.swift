//
//  OpenTokController.swift
//  Screen-Sharing
//
//  Created by Jerónimo Valli on 11/21/22.
//  Copyright (c) 2022 Vonage. All rights reserved.
//

import Foundation

class OpenTokController: NSObject, ObservableObject {
  
    var openTokWrapper: OpenTokWrapper?
  var publisherView = OpenTokView(.publisher)
  var subscriberView = OpenTokView(.subscriber)
  
  @Published var opentokIsConnected = false
  @Published var publisherConnected = false
  @Published var subscriberConnected = false
  @Published var shouldProvideCustomCapturedFrame = false
  
  public override init() {
    super.init()
      openTokWrapper = OpenTokWrapper(delegate: self)
  }
  
  public func connect() {
    openTokWrapper?.connect()
  }
  
  public func publish() {
    openTokWrapper?.publish()
  }
    
  public func consumeBuffer(_ sampleBuffer: CMSampleBuffer?) {
      if let sampleBuffer = sampleBuffer {
          openTokWrapper?.consumeFrame(sampleBuffer)
      }
  }
}

extension OpenTokController: OpenTokWrapperDelegate {
  
  func onSessionConnected(_ sessionId: String!) {
    DispatchQueue.main.async { [weak self] in
      self?.opentokIsConnected = true
      self?.publish()
    }
  }
  
  func onSessionDisconnected(_ sessionId: String!) {
    print("onSessionDisconnected")
  }
    
    func onSessionError(_ error: String!) {
        print("onSessionError: \(error)")
    }
  
  func onPublisherRenderFrame(_ frame: OpaquePointer!) {
    DispatchQueue.main.async { [weak self] in
        self?.publisherConnected = true
    }
      if publisherView.customVideoCapturer == nil {
          publisherView.videoView.view.drawFrame(frame)
      }
  }
  
  func onSubscriberConnected() {
    DispatchQueue.main.async { [weak self] in
        self?.subscriberConnected = true
    }
  }
  
  func onSubscriberRenderFrame(_ frame: OpaquePointer!) {
    if subscriberConnected {
      subscriberView.videoView.view.drawFrame(frame)
    }
  }
  
  func onSubscriberDisconnected() {
    DispatchQueue.main.async { [weak self] in
        self?.subscriberConnected = false
    }
  }
    
    func onSubscriberError(_ error: String!) {
        print("onSubscriberError: \(error)")
    }
    
    func onVideoCapturerDestroy(_ video_capturer: OpaquePointer!) {
        publisherView.customVideoCapturer = nil
        shouldProvideCustomCapturedFrame = false
    }
    
    func onVideoCapturerStart(_ video_capturer: OpaquePointer!) {
        publisherView.customVideoCapturer = video_capturer
        shouldProvideCustomCapturedFrame = true
    }
}
