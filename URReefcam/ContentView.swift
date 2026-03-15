import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var whiteBalanceManager = WhiteBalanceManager()
    @StateObject private var videoManager = VideoManager()
    @StateObject private var timeLapseManager = TimeLapseManager()
    @StateObject private var scheduleManager = ScheduleManager.shared

    @State private var showSettings = false
    @State private var showSchedules = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: lens selector + WB preset picker
                HStack {
                    LensSelector(cameraManager: cameraManager)
                    Spacer()
                    WBPresetPicker(whiteBalanceManager: whiteBalanceManager,
                                   cameraManager: cameraManager)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // White balance sliders
                WBControlView(whiteBalanceManager: whiteBalanceManager,
                              cameraManager: cameraManager)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                // Bottom control bar
                CameraControlBar(
                    cameraManager: cameraManager,
                    videoManager: videoManager,
                    timeLapseManager: timeLapseManager,
                    whiteBalanceManager: whiteBalanceManager,
                    showSettings: $showSettings,
                    showSchedules: $showSchedules
                )
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(cameraManager: cameraManager,
                         whiteBalanceManager: whiteBalanceManager)
        }
        .sheet(isPresented: $showSchedules) {
            ScheduleView(manager: scheduleManager)
        }
        .onAppear {
            cameraManager.startSession()
            cameraManager.onDeviceReady = { device in
                whiteBalanceManager.configure(device: device)
                videoManager.configure(session: cameraManager.session,
                                       device: device)
                timeLapseManager.configure(photoOutput: cameraManager.photoOutput)
            }
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }
}
