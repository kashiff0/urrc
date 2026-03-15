import SwiftUI

struct CameraControlBar: View {

    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var timeLapseManager: TimeLapseManager
    @ObservedObject var whiteBalanceManager: WhiteBalanceManager

    @Binding var showSettings: Bool
    @Binding var showSchedules: Bool

    var body: some View {
        VStack(spacing: 8) {

            // Mode-specific controls above the shutter row
            switch cameraManager.captureMode {
            case .video:
                VideoModeSelector(videoManager: videoManager)
                    .padding(.bottom, 4)
                if videoManager.isRecording {
                    Text(videoManager.formattedDuration)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.red)
                }
            case .timeLapse:
                TimeLapseView(manager: timeLapseManager)
                    .padding(.bottom, 4)
            case .photo:
                EmptyView()
            }

            // Main shutter row
            HStack {
                // Left: settings + schedule
                HStack(spacing: 12) {
                    Button {
                        showSchedules = true
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Center: shutter
                ShutterButton(
                    captureMode: cameraManager.captureMode,
                    isRecording: videoManager.isRecording || timeLapseManager.isCapturing,
                    thumbnail: nil,
                    onShutter: handleShutter
                )

                // Right: thumbnail + mode picker
                HStack(spacing: 12) {
                    ThumbnailBadge(image: cameraManager.lastThumbnail)

                    CaptureModeWheel(selected: $cameraManager.captureMode)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Shutter action

    private func handleShutter() {
        switch cameraManager.captureMode {
        case .photo:
            cameraManager.capturePhoto(whiteBalanceManager: whiteBalanceManager)

        case .video:
            if videoManager.isRecording {
                videoManager.stopRecording()
            } else {
                videoManager.startRecording()
            }

        case .timeLapse:
            if timeLapseManager.isCapturing {
                timeLapseManager.stopCapture()
            } else {
                timeLapseManager.startCapture()
            }
        }
    }
}

// MARK: - Capture mode wheel (vertical scroll picker)

private struct CaptureModeWheel: View {

    @Binding var selected: CaptureMode

    var body: some View {
        VStack(spacing: 4) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selected = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 11, weight: selected == mode ? .bold : .regular))
                        .foregroundColor(selected == mode ? .yellow : .white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
