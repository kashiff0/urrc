import AVFoundation
import Photos
import SwiftUI

@MainActor
final class CameraManager: ObservableObject {

    // MARK: - Published state
    @Published var currentLens: LensOption = .main
    @Published var isSessionRunning = false
    @Published var lastThumbnail: UIImage?
    @Published var captureMode: CaptureMode = .photo
    @Published var isProRAWAvailable = false

    // MARK: - Session
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.ureefcam.session", qos: .userInitiated)

    // MARK: - Inputs / Outputs
    private var videoDeviceInput: AVCaptureDeviceInput?
    let photoOutput = AVCapturePhotoOutput()   // internal access for TimeLapseManager
    private var currentDevice: AVCaptureDevice?

    // MARK: - Callbacks
    var onDeviceReady: ((AVCaptureDevice) -> Void)?

    // MARK: - Photo delegate storage
    private var photoCaptureDelegate: PhotoCaptureDelegate?

    // MARK: - Session lifecycle

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSession()
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
                if let device = self.currentDevice {
                    self.onDeviceReady?(device)
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async { self?.isSessionRunning = false }
        }
    }

    // MARK: - Session configuration

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Add video input for the main lens
        guard let device = bestDevice(for: .main),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        if session.canAddInput(input) {
            session.addInput(input)
            videoDeviceInput = input
            currentDevice = device
        }

        // Photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoDimensions = device.activeFormat.supportedMaxPhotoDimensions.last ?? .zero
            isProRAWAvailable = photoOutput.isAppleProRAWSupported
            if isProRAWAvailable {
                photoOutput.isAppleProRAWEnabled = true
            }
        }

        // Lock flash off
        configureFlash(device: device)

        session.commitConfiguration()
    }

    private func configureFlash(device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFlashModeSupported(.off) {
                device.flashMode = .off
            }
            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: - Lens switching

    func switchLens(to lens: LensOption) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.bestDevice(for: lens),
                  let newInput = try? AVCaptureDeviceInput(device: device) else { return }

            self.session.beginConfiguration()

            if let old = self.videoDeviceInput {
                self.session.removeInput(old)
            }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoDeviceInput = newInput
                self.currentDevice = device
            }

            // Re-apply photo output settings
            self.photoOutput.maxPhotoDimensions = device.activeFormat.supportedMaxPhotoDimensions.last ?? .zero
            let proRAWAvailable = self.photoOutput.isAppleProRAWSupported
            if proRAWAvailable { self.photoOutput.isAppleProRAWEnabled = true }

            self.configureFlash(device: device)
            self.session.commitConfiguration()

            DispatchQueue.main.async {
                self.currentLens = lens
                self.isProRAWAvailable = proRAWAvailable
                self.onDeviceReady?(device)
            }
        }
    }

    private func bestDevice(for lens: LensOption) -> AVCaptureDevice? {
        switch lens {
        case .ultraWide:
            return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        case .main:
            // Prefer triple camera system for best lens access
            return AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .telephoto:
            return AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
        }
    }

    // MARK: - Photo capture

    func capturePhoto(whiteBalanceManager: WhiteBalanceManager) {
        let settings = buildPhotoSettings()
        let delegate = PhotoCaptureDelegate { [weak self] image in
            DispatchQueue.main.async {
                self?.lastThumbnail = image
            }
        }
        photoCaptureDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    private func buildPhotoSettings() -> AVCapturePhotoSettings {
        if isProRAWAvailable,
           let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
            let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat,
                                                  processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc])
            settings.flashMode = .off
            return settings
        } else {
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            return settings
        }
    }

    // MARK: - Zoom (for telephoto fine control)

    func setZoomFactor(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                let clamped = min(max(factor, device.minAvailableVideoZoomFactor),
                                  device.maxAvailableVideoZoomFactor)
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {}
        }
    }
}

// MARK: - Lens Option

enum LensOption: String, CaseIterable, Identifiable {
    case ultraWide = "0.5×"
    case main = "1×"
    case telephoto = "4×"
    var id: String { rawValue }
}

// MARK: - Capture Mode

enum CaptureMode: String, CaseIterable {
    case photo = "Photo"
    case video = "Video"
    case timeLapse = "Time-lapse"
}

// MARK: - Photo Capture Delegate

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil else {
            completion(nil)
            return
        }

        // Save to Photos library
        PHPhotoLibrary.shared().performChanges({
            let creationRequest = PHAssetCreationRequest.forAsset()
            if let fileData = photo.fileDataRepresentation() {
                creationRequest.addResource(with: .photo, data: fileData, options: nil)
            }
        })

        // Thumbnail for shutter button
        if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            completion(image)
        } else {
            completion(nil)
        }
    }
}
