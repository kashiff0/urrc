import SwiftUI

struct LensSelector: View {

    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        HStack(spacing: 6) {
            ForEach(LensOption.allCases) { lens in
                Button {
                    cameraManager.switchLens(to: lens)
                } label: {
                    Text(lens.rawValue)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(cameraManager.currentLens == lens ? .black : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(cameraManager.currentLens == lens
                                      ? Color.cyan
                                      : Color.white.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
