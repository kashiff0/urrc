import AVFoundation
import Photos
import SwiftUI

// MARK: - Video Mode

enum VideoMode: String, CaseIterable, Identifiable {
    // ProRes RAW is not available to third-party apps on iOS at all — only
    // Apple's own Camera app can produce it, and never through
    // AVCaptureMovieFileOutput. ProRes 422 HQ is the real equivalent, and is
    // limited to iPhone 15 Pro and later.
    case proRes         = "ProRes 422 HQ"
    case dolbyVision    = "Dolby Vision 4K"
    case highFPS        = "4K 120fps"
    case slowMo         = "Slo-Mo 4K"
    case action         = "Action 2.8K"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .proRes:      return "4K · 30fps · ProRes 422 HQ"
        case .dolbyVision: return "4K · 60fps · HEVC HDR"
        case .highFPS:     return "4K · 120fps · HEVC"
        case .slowMo:      return "4K · 120fps → 30fps"
        case .action:      return "2.8K · 60fps · HEVC"
        }
    }

    var targetFrameRate: Double {
        switch self {
        case .proRes:      return 30
        case .dolbyVision: return 60
        case .highFPS:     return 120
        case .slowMo:      return 120
        case .action:      return 60
        }
    }
}

// MARK: - VideoManager

final class VideoManager: ObservableObject {

    @Published var selectedMode: VideoMode = .dolbyVision
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

    /// Set when the chosen mode isn't supported by the current hardware, so the
    /// UI can say so instead of quietly recording something else.
    @Published var unsupportedModeNotice: String?

    private let movieOutput = AVCaptureMovieFileOutput()
    private weak var session: AVCaptureSession?
    private weak var device: AVCaptureDevice?
    private var recordingDelegate: MovieRecordingDelegate?
    private var durationTimer: Timer?
    private var outputURL: URL?

    /// Changing `activeFormat` resets the device's white balance to continuous
    /// auto, undoing the manual gains that are the whole point of the app.
    /// ContentView wires this up to re-apply them.
    var onFormatChanged: (() -> Void)?


    private let sessionQueue = DispatchQueue(label: "com.ureefcam.video", qos: .userInitiated)

    // MARK: - Configuration

    func configure(session: AVCaptureSession, device: AVCaptureDevice) {
        self.session = session
        self.device = device

        sessionQueue.async { [weak self] in
            guard let self, let session = self.session else { return }
            session.beginConfiguration()
            if session.canAddOutput(self.movieOutput) {
                session.addOutput(self.movieOutput)
            }
            session.commitConfiguration()
        }
    }

    // MARK: - Start / Stop recording

    func startRecording() {
        guard !isRecording, session != nil else { return }

        // Flip the UI immediately, but wait for the format to land before
        // opening the file — the previous version started recording while
        // reconfiguration was still in flight on another queue.
        isRecording = true
        recordingDuration = 0

        applyVideoFormat { [weak self] in
            guard let self else { return }
            guard self.isRecording else { return }  // stopped while configuring
            self.beginFileOutput()
        }
    }

    private func beginFileOutput() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        outputURL = url

        let delegate = MovieRecordingDelegate { [weak self] savedURL, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRecording = false
                self.durationTimer?.invalidate()
                self.durationTimer = nil
                self.recordingDuration = 0
                if let error { print("Recording failed: \(error)") }
                if let savedURL { self.saveVideoToPhotos(url: savedURL) }
            }
        }
        recordingDelegate = delegate
        movieOutput.startRecording(to: url, recordingDelegate: delegate)

        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.recordingDuration += 1
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        if movieOutput.isRecording {
            movieOutput.stopRecording()   // delegate clears the rest of the state
        } else {
            // Stopped during format configuration, before the file was opened.
            isRecording = false
            durationTimer?.invalidate()
            durationTimer = nil
            recordingDuration = 0
        }
    }

    // MARK: - Format application

    /// Applies the selected mode's capture format, then reports back so white
    /// balance can be restored.
    ///
    /// The session must be on `.inputPriority` before `activeFormat` is set —
    /// any named preset (`.photo`, `.hd4K3840x2160`, …) makes the session pick
    /// its own format and silently discard ours. That single line is why mode
    /// selection previously had no observable effect.
    private func applyVideoFormat(completion: @escaping () -> Void) {
        guard let device, let session else { completion(); return }

        // Read the mode on the caller's thread — it is @Published and mutated
        // on main, so it must not be touched from the session queue.
        let mode = selectedMode

        sessionQueue.async { [weak self, weak device, weak session] in
            guard let self, let device, let session else {
                DispatchQueue.main.async { completion() }
                return
            }

            guard let format = self.bestFormat(for: mode, device: device) else {
                DispatchQueue.main.async { completion() }
                return
            }

            session.beginConfiguration()
            if session.canSetSessionPreset(.inputPriority) {
                session.sessionPreset = .inputPriority
            }

            do {
                try device.lockForConfiguration()
                device.activeFormat = format

                // Clamp the target rate to what this format actually offers —
                // asking for 120fps on a 60fps format throws.
                if let range = self.frameRateRange(for: mode, format: format) {
                    let fps = min(max(mode.targetFrameRate, range.minFrameRate), range.maxFrameRate)
                    let duration = CMTimeMake(value: 1, timescale: Int32(fps.rounded()))
                    device.activeVideoMinFrameDuration = duration
                    device.activeVideoMaxFrameDuration = duration
                }

                device.unlockForConfiguration()
            } catch {
                print("Format apply failed: \(error)")
            }
            session.commitConfiguration()

            self.applyCodec(for: mode)

            DispatchQueue.main.async {
                // activeFormat has just reset white balance to auto.
                self.onFormatChanged?()
                completion()
            }
        }
    }

    /// ProRes is selected on the output connection, not the device format, and
    /// only exists on iPhone 15 Pro and later.
    private func applyCodec(for mode: VideoMode) {
        guard let connection = movieOutput.connection(with: .video) else { return }

        let available = movieOutput.availableVideoCodecTypes
        let desired: AVVideoCodecType = mode == .proRes ? .proRes422HQ : .hevc

        guard available.contains(desired) else {
            if mode == .proRes {
                DispatchQueue.main.async {
                    self.unsupportedModeNotice =
                        "ProRes needs iPhone 15 Pro or later — recording HEVC instead."
                }
            }
            if available.contains(.hevc) {
                movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
            }
            return
        }

        DispatchQueue.main.async { self.unsupportedModeNotice = nil }
        movieOutput.setOutputSettings([AVVideoCodecKey: desired], for: connection)
    }

    private func bestFormat(for mode: VideoMode, device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = device.formats.filter { $0.mediaType == .video }
        guard !formats.isEmpty else { return nil }

        func matches(_ predicate: (AVCaptureDevice.Format, CMVideoDimensions) -> Bool) -> AVCaptureDevice.Format? {
            formats.first { predicate($0, CMVideoFormatDescriptionGetDimensions($0.formatDescription)) }
        }

        let match: AVCaptureDevice.Format?
        switch mode {
        case .proRes:
            // The ProRes codec is chosen on the output connection; the device
            // format just needs to be 4K at 30fps or better.
            match = matches { format, dims in
                dims.width >= 3840 &&
                    format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
            }

        case .dolbyVision:
            match = matches { format, dims in
                dims.width >= 3840 && format.isVideoHDRSupported &&
                    format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 60 }
            }

        case .highFPS, .slowMo:
            match = matches { format, dims in
                dims.width >= 3840 &&
                    format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 120 }
            }

        case .action:
            match = matches { format, dims in
                dims.width >= 2800 && dims.width < 3840 &&
                    format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 60 }
            }
        }

        // Falling back to the highest-resolution format beats the previous
        // `formats.last`, which is ordered by the driver and can be anything.
        return match ?? formats.max { a, b in
            let left = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let right = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            return Int(left.width) * Int(left.height) < Int(right.width) * Int(right.height)
        }
    }

    private func frameRateRange(for mode: VideoMode,
                                format: AVCaptureDevice.Format) -> AVFrameRateRange? {
        let ranges = format.videoSupportedFrameRateRanges
        return ranges.first { $0.maxFrameRate >= mode.targetFrameRate }
            ?? ranges.max { $0.maxFrameRate < $1.maxFrameRate }
    }

    // MARK: - Save to Photos

    private func saveVideoToPhotos(url: URL) {
        Permissions.saveToPhotoLibrary({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }, completion: { success, error in
            if let error { print("Video save failed: \(error)") }
            // Keep the file if it never made it to the library, so a denied
            // permission doesn't silently destroy the recording.
            if success { try? FileManager.default.removeItem(at: url) }
        })
    }

    // MARK: - Duration formatting

    var formattedDuration: String {
        let mins = Int(recordingDuration) / 60
        let secs = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Recording delegate

private final class MovieRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {

    private let completion: (URL?, Error?) -> Void

    init(completion: @escaping (URL?, Error?) -> Void) {
        self.completion = completion
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        completion(error == nil ? outputFileURL : nil, error)
    }
}
