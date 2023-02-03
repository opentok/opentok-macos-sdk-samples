//
//  OpenTokController.swift
//  Basic-Video-Chat
//
//  Created by Jerónimo Valli on 11/21/22.
//  Copyright (c) 2022 Vonage. All rights reserved.
//

import Foundation
import AVFoundation

class OpenTokController: NSObject, ObservableObject {
  
  var openTokWrapper = OpenTokWrapper()
  var publisherView = OpenTokView(.publisher)
  var subscriberView = OpenTokView(.subscriber)
  let engine = AVAudioEngine()
  
  @Published var opentokIsConnected = false
  @Published var publisherConnected = false
  @Published var subscriberConnected = false
  
  public override init() {
    super.init()
    openTokWrapper.delegate = self
      
      addListenerBlock(listenerBlock: audioObjectPropertyListenerBlock,
               onAudioObjectID: AudioObjectID(bitPattern: kAudioObjectSystemObject),
               forPropertyAddress: AudioObjectPropertyAddress(
                  mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                  mScope: kAudioObjectPropertyScopeGlobal,
                  mElement: kAudioObjectPropertyElementMain))
  }
  
  public func connect() {
    openTokWrapper.connect()
  }
  
  public func publish() {
    openTokWrapper.publish()
  }
    
    // Utility function to simplify adding listener blocks:
    func addListenerBlock( listenerBlock: @escaping AudioObjectPropertyListenerBlock, onAudioObjectID: AudioObjectID, forPropertyAddress: AudioObjectPropertyAddress) {
        var copyPropertyAddress = forPropertyAddress
        if (kAudioHardwareNoError != AudioObjectAddPropertyListenerBlock(onAudioObjectID, &copyPropertyAddress, nil, listenerBlock)) {
            print("Error calling: AudioObjectAddPropertyListenerBlock")
        }
    }
    
    func audioObjectPropertyListenerBlock (numberAddresses: UInt32, addresses: UnsafePointer<AudioObjectPropertyAddress>) {
        var index: UInt32 = 0
        while index < numberAddresses {
            let address: AudioObjectPropertyAddress = addresses[0]
            switch address.mSelector {
            case kAudioHardwarePropertyDefaultOutputDevice:
                
                guard let device = AudioDevice.getDefaultAudioOutputDevice() else { return }
                //let allAudioDevices = AudioDevice.getAll()
                //let firstDevice = allAudioDevices
                //        .first(where: {$0.hasOutputStreams && $0.isBuiltIn })!
                //print("kAudioHardwarePropertyDefaultOutputDevice: \(firstDevice.id): \(firstDevice.uid)")
                var deviceID = device.id
                print("kAudioHardwarePropertyDefaultOutputDevice: \(deviceID): \(device.uid)")
                let engine = AVAudioEngine()
                if let outputAudioUnit = engine.outputNode.audioUnit {
                    
                    let error = AudioUnitSetProperty(outputAudioUnit,
                                                     kAudioOutputUnitProperty_CurrentDevice,
                                                     kAudioUnitScope_Global,
                                                     0,
                                                     &deviceID,
                                                     UInt32(MemoryLayout.size(ofValue: deviceID)))
                    print("Error AudioUnitSetProperty: \(error)")
                }
            default:
                
                print("We didn't expect this!")
                
            }
            index += 1
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
  
  func onPublisherRenderFrame(_ frame: OpaquePointer!) {
    DispatchQueue.main.async { [weak self] in
        self?.publisherConnected = true
    }
    publisherView.videoView.view.drawFrame(frame)
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
}

struct AudioDevice {
    let id: AudioDeviceID
    
    static func getAll() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        // Get size of buffer for list
        var devicesBufferSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                       &propertyAddress,
                                       0,
                                       nil,
                                       &devicesBufferSize)
        let devicesCount = Int(devicesBufferSize) / MemoryLayout<AudioDeviceID>.stride

        // Get list
        let devices = Array<AudioDeviceID>(unsafeUninitializedCapacity: devicesCount) { buffer, initializedCount in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                       &propertyAddress,
                                       0,
                                       nil,
                                       &devicesBufferSize,
                                       buffer.baseAddress!)
            initializedCount = devicesCount
        }

        return devices.map(Self.init)
    }
    
    static func getDefaultAudioOutputDevice() -> AudioDevice? {
        var devicePropertyAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                               mScope: kAudioObjectPropertyScopeGlobal,
                                                               mElement: kAudioObjectPropertyElementMain)
        /*
        var deviceID: AudioObjectID = kAudioDeviceUnknown
        var dataSize = UInt32(MemoryLayout.size(ofValue: deviceID))
        let systemObjectID = AudioObjectID(bitPattern: kAudioObjectSystemObject)
        if (kAudioHardwareNoError != AudioObjectGetPropertyData(systemObjectID,
                                                                &devicePropertyAddress,
                                                                0,
                                                                nil,
                                                                &dataSize,
                                                                &deviceID)) {
            return 0
        }
         */
        var devicesBufferSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                       &devicePropertyAddress,
                                       0,
                                       nil,
                                       &devicesBufferSize)
        let devicesCount = 1
        let devices = Array<AudioDeviceID>(unsafeUninitializedCapacity: devicesCount) { buffer, initializedCount in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                       &devicePropertyAddress,
                                       0,
                                       nil,
                                       &devicesBufferSize,
                                       buffer.baseAddress!)
            initializedCount = devicesCount
        }
        return devices.map(Self.init).first
    }

    var hasOutputStreams: Bool {
        var propertySize: UInt32 = 256

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)

        AudioObjectGetPropertyDataSize(id, &propertyAddress, 0, nil, &propertySize)

        return propertySize > 0
    }

    var isBuiltIn: Bool {
        transportType == kAudioDeviceTransportTypeBuiltIn
    }

    var transportType: AudioDevicePropertyID {
        var deviceTransportType = AudioDevicePropertyID()
        var propertySize = UInt32(MemoryLayout<AudioDevicePropertyID>.size)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        AudioObjectGetPropertyData(id, &propertyAddress,
                                   0, nil, &propertySize,
                                   &deviceTransportType)
        return deviceTransportType
    }

    var uid: String {
        var propertySize = UInt32(MemoryLayout<CFString>.size)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var result: CFString = "" as CFString
        AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &propertySize, &result)
        return result as String
    }
}
