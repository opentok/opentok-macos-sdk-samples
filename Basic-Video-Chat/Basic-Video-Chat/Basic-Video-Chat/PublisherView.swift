//
//  PublisherView.swift
//  Basic-Video-Chat
//
//  Created by Jerónimo Valli on 11/18/22.
//  Copyright (c) 2022 Vonage. All rights reserved.
//

import SwiftUI
import AppKit

enum OpenTokViewRole {
  case publisher
  case subscriber
}

struct OpenTokView: View {
  
  let viewRole: OpenTokViewRole
  let videoView: VideoRenderViewRepresentable

  init(_ viewRole: OpenTokViewRole) {
    self.viewRole = viewRole
    self.videoView = VideoRenderViewRepresentable()
  }

  var body: some View {
    VStack {
      videoView
        .frame(width: 640, height: 480)
    }
  }
}

struct PublisherView_Previews: PreviewProvider {
  static var previews: some View {
    OpenTokView(.publisher)
  }
}

struct VideoRenderViewRepresentable: NSViewRepresentable {

    var view = VideoRenderView()
    
    func makeNSView(context: Context) -> NSView {
        DispatchQueue.main.async {
            view.awakeFromNib()
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
    }

}
