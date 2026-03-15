import SwiftUI

struct VideoModeSelector: View {

    @ObservedObject var videoManager: VideoManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VideoMode.allCases) { mode in
                    Button {
                        videoManager.selectedMode = mode
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(videoManager.selectedMode == mode ? .black : .white)
                            Text(mode.subtitle)
                                .font(.system(size: 9))
                                .foregroundColor(videoManager.selectedMode == mode
                                                 ? .black.opacity(0.7) : .white.opacity(0.5))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(videoManager.selectedMode == mode ? Color.cyan : Color.white.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(videoManager.isRecording)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
