import AVFoundation
import Photos
import SwiftUI

// MARK: - Video Mode

enum VideoMode: String, CaseIterable, Identifiable {
    case proResRAW      = "ProRes RAW"
    case dolbyVision    = "Dolby Vision 4K"
    case highFPS        = "4K 120fps"
    case slowMo         = "Slo-Mo 4K"
    case action         = "Action 2.8K"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .proResRAW:   return "4K · 30fps · ProRes RAW"
        case .dolbyVision: return "4K · 60fps · HEVC HDR"
        case .highFPS:     return "4K · 120fps · HEVC"
        case .slowMo:      return "4K · 120fps → 30fps"
        case .action:      return "2.8K · 60fps · HEVC"
        }
    }
}

// MARK: - VideoManager

@MainActor
final class VideoManager: ObservableObject {

    @Published var selectedMode: VideoMode = .dolbyVision
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

    private let movieOutput = AVCaptureMovieFileOutput()
    private weak var session: AVCaptureSession?
    private weak var device: AVCaptureDevice?
    private var recordingDelegate: MovieRecordingDelegate?
    private var durationTimer: Timer?
    private var outputURL: URL?

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
        guard !isRecording, let session else { return }
        applyVideoFormat()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        outputURL = url

        let delegate = MovieRecordingDelegate { [weak self] savedURL, error in
            DispatchQueue.main.async {
                self?.isRecording = false
                self?.durationTimer?.invalidate()
                self?.recordingDuration = 0
                if let savedURL { self?.saveVideoToPhotos(url: savedURL) }
            }
        }
        recordingDelegate = delegate
        movieOutput.startRecording(to: url, recordingDelegate: delegate)

        isRecording = true
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.recordingDuration += 1
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
    }

    // MARK: - Format application

    private func applyVideoFormat() {
        guard let device else { return }
        sessionQueue.async { [weak self, weak device] in
            guard let self, let device else { return }
            guard let format = self.bestFormat(for: self.selectedMode, device: device) else { return }
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                let range = self.frameRateRange(for: self.selectedMode, format: format)
                device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(range.maxFrameRate))
                device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(range.minFrameRate))
                device.unlockForConfiguration()
            } catch {
                print("Format apply failed: \(error)")
            }
        }
    }

    private func bestFormat(for mode: VideoMode, device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = device.formats.filter { $0.mediaType == .video }

        switch mode {
        case .proResRAW:
            // ProRes RAW: look for Apple ProRes RAW format at 4K
            return formats.first { format in
                let desc = format.formatDescription
                let dims = CMVideoFormatDescriptionGetDimensions(desc)
                let codec = CMFormatDescriptionGetMediaSubType(desc)
                return dims.width >= 3840 && codec == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            } ?? formats.last

        case .dolbyVision:
            return formats.first { format in
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dims.width >= 3840 && format.isVideoHDRSupported &&
                    format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 60 }
            } ?? formats.last

        case .highFPS, .slowMo:
            return formats.first { format in
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dims.width >= 3840 &&
                    format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 120 }
            } ?? formats.last

        case .action:
            return formats.first { format in
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dims.width >= 2800 && dims.width < 3840 &&
                    format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 60 }
            } ?? formats.last
        }
    }

    private func frameRateRange(for mode: VideoMode,
                                 format: AVCaptureDevice.Format) -> AVFrameRateRange {
        let targetFPS: Double
        switch mode {
        case .proResRAW:   targetFPS = 30
        case .dolbyVision: targetFPS = 60
        case .highFPS:     targetFPS = 120
        case .slowMo:      targetFPS = 120
        case .action:      targetFPS = 60
        }
        return format.videoSupportedFrameRateRanges
            .first { $0.maxFrameRate >= targetFPS }
            ?? format.videoSupportedFrameRateRanges.first!
    }

    // MARK: - Save to Photos

    private func saveVideoToPhotos(url: URL) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { _, error in
            if let error { print("Video save failed: \(error)") }
            try? FileManager.default.removeItem(at: url)
        }
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
