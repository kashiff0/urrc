import SwiftUI

struct SettingsView: View {

    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var whiteBalanceManager: WhiteBalanceManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {

                Section("Camera") {
                    HStack {
                        Label("ProRAW", systemImage: "camera.aperture")
                        Spacer()
                        if cameraManager.isProRAWAvailable {
                            Text("Available").foregroundColor(.cyan).font(.caption)
                        } else {
                            Text("Not supported on this device").foregroundColor(.gray).font(.caption)
                        }
                    }

                    HStack {
                        Label("Flash", systemImage: "bolt.slash.fill")
                        Spacer()
                        Text("Always Off").foregroundColor(.gray).font(.caption)
                    }
                }

                Section("White Balance") {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text("\(Int(whiteBalanceManager.temperature))K")
                            .foregroundColor(.cyan).font(.caption.monospacedDigit())
                    }
                    HStack {
                        Text("Tint")
                        Spacer()
                        Text("\(whiteBalanceManager.tint > 0 ? "+" : "")\(Int(whiteBalanceManager.tint))")
                            .foregroundColor(.green).font(.caption.monospacedDigit())
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.gray)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundColor(.gray)
                    }
                    HStack {
                        Label("Designed for reef aquariums", systemImage: "drop.fill")
                            .foregroundColor(.cyan)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
