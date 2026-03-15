import SwiftUI

struct ShutterButton: View {

    let captureMode: CaptureMode
    let isRecording: Bool
    let thumbnail: UIImage?
    let onShutter: () -> Void

    var body: some View {
        Button(action: onShutter) {
            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(isRecording ? Color.red : Color.white, lineWidth: 3)
                    .frame(width: 72, height: 72)

                // Inner fill
                switch captureMode {
                case .photo:
                    Circle()
                        .fill(Color.white)
                        .frame(width: 60, height: 60)

                case .video:
                    RoundedRectangle(cornerRadius: isRecording ? 8 : 30)
                        .fill(isRecording ? Color.red : Color.red)
                        .frame(width: isRecording ? 28 : 56,
                               height: isRecording ? 28 : 56)
                        .animation(.easeInOut(duration: 0.2), value: isRecording)

                case .timeLapse:
                    Image(systemName: isRecording ? "stop.fill" : "timer")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(isRecording ? .red : .white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Thumbnail Badge

struct ThumbnailBadge: View {

    let image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.15))
                .frame(width: 52, height: 52)

            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }
}
