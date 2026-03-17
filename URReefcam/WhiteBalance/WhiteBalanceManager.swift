import AVFoundation
import SwiftUI

final class WhiteBalanceManager: ObservableObject {

    // MARK: - Published
    @Published var temperature: Float = 8500 { didSet { applyToDevice() } }
    @Published var tint: Float = 45          { didSet { applyToDevice() } }
    @Published var selectedPreset: WBPreset? = WBPreset.builtIn.first

    // MARK: - Private
    private weak var device: AVCaptureDevice?
    private let sessionQueue = DispatchQueue(label: "com.ureefcam.wb", qos: .userInitiated)

    // MARK: - Ranges (matching dev brief)
    static let temperatureRange: ClosedRange<Float> = 1000...10000
    static let tintRange: ClosedRange<Float> = -150...150

    // MARK: - Configuration

    func configure(device: AVCaptureDevice) {
        self.device = device
        applyToDevice()
    }

    // MARK: - Apply gains to device

    func applyToDevice() {
        guard let device else { return }
        let tempTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
            temperature: temperature,
            tint: tint
        )

        sessionQueue.async { [weak self, weak device] in
            guard let self, let device else { return }
            guard device.isWhiteBalanceModeSupported(.locked) else { return }

            var gains = device.deviceWhiteBalanceGains(for: tempTint)

            // CRITICAL: clamp to [1.0, maxGain] — prevents NSRangeException crash
            let maxGain = device.maxWhiteBalanceGain
            gains.redGain   = min(max(gains.redGain,   1.0), maxGain)
            gains.greenGain = min(max(gains.greenGain, 1.0), maxGain)
            gains.blueGain  = min(max(gains.blueGain,  1.0), maxGain)

            do {
                try device.lockForConfiguration()
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                print("WB lock failed: \(error)")
            }
        }
    }

    // MARK: - Apply preset

    func apply(preset: WBPreset) {
        selectedPreset = preset
        temperature = preset.temperature
        tint = preset.tint
    }

    // MARK: - Restore auto WB (for switching away from manual)

    func restoreAutoWB() {
        guard let device else { return }
        sessionQueue.async { [weak device] in
            guard let device else { return }
            guard device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) else { return }
            do {
                try device.lockForConfiguration()
                device.whiteBalanceMode = .continuousAutoWhiteBalance
                device.unlockForConfiguration()
            } catch {}
        }
    }
}
