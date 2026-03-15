import AVFoundation
import Photos
import SwiftUI

// MARK: - Capture Interval

enum TimeLapseInterval: String, CaseIterable, Identifiable {
    case s5  = "5s"
    case s10 = "10s"
    case s30 = "30s"
    case m1  = "1m"
    case m5  = "5m"
    case m15 = "15m"
    case h1  = "1h"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .s5:  return 5
        case .s10: return 10
        case .s30: return 30
        case .m1:  return 60
        case .m5:  return 300
        case .m15: return 900
        case .h1:  return 3600
        }
    }
}

// MARK: - TimeLapseManager

@MainActor
final class TimeLapseManager: ObservableObject {

    @Published var isCapturing = false
    @Published var selectedInterval: TimeLapseInterval = .s10
    @Published var frameCount = 0
    @Published var latestThumbnail: UIImage?

    private var captureTimer: Timer?
    private var frameURLs: [URL] = []
    private weak var photoOutput: AVCapturePhotoOutput?
    private var captureDelegate: TimeLapsePhotoDelegate?

    // MARK: - Configure

    func configure(photoOutput: AVCapturePhotoOutput) {
        self.photoOutput = photoOutput
    }

    // MARK: - Start / Stop

    func startCapture() {
        guard !isCapturing else { return }
        frameURLs = []
        frameCount = 0
        isCapturing = true
        scheduleNextCapture()
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil
        if !frameURLs.isEmpty {
            Task { await assembleVideo() }
        }
    }

    // MARK: - Frame capture

    private func scheduleNextCapture() {
        captureTimer = Timer.scheduledTimer(withTimeInterval: selectedInterval.seconds,
                                            repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.captureFrame()
            }
        }
    }

    private func captureFrame() {
        guard isCapturing, let photoOutput else { return }

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off

        let delegate = TimeLapsePhotoDelegate { [weak self] url, image in
            Task { @MainActor in
                guard let self else { return }
                if let url { self.frameURLs.append(url) }
                self.latestThumbnail = image
                self.frameCount += 1
                if self.isCapturing { self.scheduleNextCapture() }
            }
        }
        captureDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    // MARK: - Video assembly

    private func assembleVideo() async {
        guard !frameURLs.isEmpty else { return }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timelapse_\(Date().timeIntervalSince1970)")
            .appendingPathExtension("mov")

        guard let firstImage = UIImage(contentsOfFile: frameURLs[0].path),
              let cgImage = firstImage.cgImage else { return }

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let fps: Int32 = 30

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else { return }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for (index, url) in frameURLs.enumerated() {
            guard let image = UIImage(contentsOfFile: url.path),
                  let buffer = pixelBuffer(from: image, size: size) else { continue }
            let time = CMTimeMake(value: Int64(index), timescale: fps)

            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            adaptor.append(buffer, withPresentationTime: time)
            try? FileManager.default.removeItem(at: url)
        }

        input.markAsFinished()
        await writer.finishWriting()

        if writer.status == .completed {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
            }) { _, _ in
                try? FileManager.default.removeItem(at: outputURL)
            }
        }
    }

    // MARK: - Pixel buffer helper

    private func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        CVPixelBufferCreate(kCFAllocatorDefault,
                            Int(size.width), Int(size.height),
                            kCVPixelFormatType_32ARGB, attrs as CFDictionary,
                            &buffer)
        guard let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                            width: Int(size.width),
                            height: Int(size.height),
                            bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        ctx?.draw(image.cgImage!, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}

// MARK: - Time-lapse photo delegate

private final class TimeLapsePhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    private let completion: (URL?, UIImage?) -> Void

    init(completion: @escaping (URL?, UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            completion(nil, nil)
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try? data.write(to: url)
        let thumbnail = UIImage(data: data)
        completion(url, thumbnail)
    }
}
