//
//  ContentView.swift
//  Media-Transformers
//
//  Created by Jerónimo Valli on 11/16/22.
//  Copyright (c) 2022 Vonage. All rights reserved.
//

import SwiftUI

struct ContentView: View {
  
  @ObservedObject var openTokController = OpenTokController()
  
  var body: some View {
    VStack {
      if (!openTokController.opentokIsConnected) {
        Text("Connecting Opentok session")
          .frame(width: 640, height: 80)
      } else {
        if (openTokController.publisherConnected) {
          openTokController.publisherView
            .frame(width: 640, height: 480)
            .clipShape(Rectangle())
        }
        if (openTokController.subscriberConnected) {
          openTokController.subscriberView
            .frame(width: 640, height: 480)
            .clipShape(Rectangle())
        }
      }
    }.onAppear {
      self.openTokController.connect()
    }
  }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
