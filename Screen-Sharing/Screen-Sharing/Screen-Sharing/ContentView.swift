//
//  ContentView.swift
//  Screen-Sharing
//
//  Created by Jerónimo Valli on 12/13/22.
//

import SwiftUI

struct ContentView: View {
    
    @State var userStopped = false
    @State var disableInput = false
    @State var isUnauthorized = false
    
    @StateObject var screenRecorder = ScreenRecorder()
    @ObservedObject var openTokController = OpenTokController()
    
    var body: some View {
        HSplitView {
            VStack {
                if (!openTokController.opentokIsConnected) {
                  Text("Connecting Opentok session")
                    .frame(width: 320, height: 80)
                }
                HStack {
                    Button {
                        Task { await screenRecorder.start() }
                        // Fades the paused screen out.
                        withAnimation(Animation.easeOut(duration: 0.25)) {
                            userStopped = false
                        }
                    } label: {
                        Text("Start Capture")
                    }
                    .disabled(screenRecorder.isRunning)
                    Button {
                        Task { await screenRecorder.stop() }
                        // Fades the paused screen in.
                        withAnimation(Animation.easeOut(duration: 0.25)) {
                            userStopped = true
                        }
                        
                    } label: {
                        Text("Stop Capture")
                    }
                    .disabled(!screenRecorder.isRunning)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
                if (openTokController.subscriberConnected) {
                  openTokController.subscriberView
                    .frame(width: 320, height: 240)
                    .clipShape(Rectangle())
                }
            }
            .background(MaterialView())
            .frame(minWidth: 280, maxWidth: 280, minHeight: 900.0)
            .disabled(disableInput)
            screenRecorder.capturePreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(screenRecorder.contentSize, contentMode: .fit)
                .padding(8)
                .overlay {
                    if userStopped {
                        Image(systemName: "nosign")
                            .font(.system(size: 250, weight: .bold))
                            .foregroundColor(Color(white: 0.3, opacity: 1.0))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(white: 0.0, opacity: 0.5))
                    }
                }
        }
        .overlay {
            if isUnauthorized {
                VStack() {
                    Spacer()
                    VStack {
                        Text("No screen recording permission.")
                            .font(.largeTitle)
                            .padding(.top)
                        Text("Open System Settings and go to Privacy & Security > Screen Recording to grant permission.")
                            .font(.title2)
                            .padding(.bottom)
                    }
                    .frame(maxWidth: .infinity)
                    .background(.red)
                    
                }
            }
        }
        .navigationTitle("Screen Capture Sample")
        .onAppear {
            Task {
                if await screenRecorder.canRecord {
                    await screenRecorder.start()
                } else {
                    isUnauthorized = true
                    disableInput = true
                }
            }
            screenRecorder.otController = openTokController
            openTokController.connect()
        }
    }
}

struct MaterialView: NSViewRepresentable {
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/*
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
*/
