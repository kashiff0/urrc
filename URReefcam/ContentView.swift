import SwiftUI

// MARK: - Camera access denied

private struct CameraAccessDeniedView: View {

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 44))
                .foregroundColor(.cyan)

            Text("Camera access is off")
                .font(.headline)
                .foregroundColor(.white)

            Text("URReefcam needs the camera to photograph your reef. Turn it on in Settings → Privacy & Security → Camera.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.cyan))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
        .ignoresSafeArea()
    }
}

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

            // Without this the denied-permission case is just a black screen
            // with working buttons, which reads as a broken app.
            if cameraManager.isCameraDenied {
                CameraAccessDeniedView()
            }

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
            // Callbacks are wired before the session starts — startSession()
            // now waits on the permission prompt, so onDeviceReady can fire at
            // any point after this.
            cameraManager.onDeviceReady = { device in
                whiteBalanceManager.configure(device: device)
                videoManager.configure(session: cameraManager.session,
                                       device: device)
                timeLapseManager.configure(photoOutput: cameraManager.photoOutput)
            }

            // Selecting a video format resets the device to auto white
            // balance, so the manual gains have to be pushed back down.
            videoManager.onFormatChanged = {
                whiteBalanceManager.applyToDevice()
            }

            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }
}
