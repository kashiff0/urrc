import SwiftUI

struct TimeLapseView: View {

    @ObservedObject var manager: TimeLapseManager

    var body: some View {
        VStack(spacing: 12) {

            // Interval picker
            if !manager.isCapturing {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TimeLapseInterval.allCases) { interval in
                            Button {
                                manager.selectedInterval = interval
                            } label: {
                                Text(interval.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(manager.selectedInterval == interval ? .black : .white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(manager.selectedInterval == interval
                                                  ? Color.cyan : Color.white.opacity(0.15))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Status row
            HStack(spacing: 16) {
                if manager.isCapturing {
                    // Rolling thumbnail
                    if let thumb = manager.latestThumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Capturing every \(manager.selectedInterval.rawValue)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                        Text("\(manager.frameCount) frames")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.cyan)
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
