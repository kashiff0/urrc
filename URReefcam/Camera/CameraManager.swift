import AVFoundation
import Photos
import SwiftUI

// Note: No @MainActor on the class — sessionQueue.async blocks access stored properties,
// which Swift 5.9 strict concurrency disallows if the class is @MainActor-isolated.
// All @Published updates are dispatched to DispatchQueue.main explicitly.
final class CameraManager: ObservableObject {

    // MARK: - Published state
    @Published var currentLens: LensOption = .main
    @Published var isSessionRunning = false
    @Published var lastThumbnail: UIImage?
    @Published var isProRAWAvailable = false

    /// Set when the camera prompt has been answered with "Don't Allow" — the UI
    /// uses it to explain the black screen instead of leaving the user guessing.
    @Published var isCameraDenied = false

    @Published var captureMode: CaptureMode = .photo {
        didSet {
            guard captureMode != oldValue else { return }
            if captureMode == .video {
                // Audio is attached lazily so the mic prompt only appears once
                // the user actually wants video.
                enableAudioInput()
            } else {
                // Back to the photo preset so stills capture at full
                // resolution rather than at the last video format's.
                setPresetForVideoFormatSelection(false)
            }
        }
    }

    // MARK: - Session
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.ureefcam.session", qos: .userInitiated)

    // MARK: - Inputs / Outputs
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    let photoOutput = AVCapturePhotoOutput()   // internal access for TimeLapseManager
    private var currentDevice: AVCaptureDevice?

    /// configureSession() must run exactly once; onAppear/onDisappear cycles
    /// would otherwise re-enter it every time the view comes back.
    private var isConfigured = false

    // MARK: - Callbacks
    var onDeviceReady: ((AVCaptureDevice) -> Void)?

    // MARK: - Photo delegate storage
    // Keyed by capture ID rather than a single slot: AVFoundation only holds a
    // weak reference to the delegate, so a second shutter press used to
    // deallocate the first capture's delegate before it had finished.
    private var photoCaptureDelegates: [Int64: PhotoCaptureDelegate] = [:]

    // MARK: - Session lifecycle

    func startSession() {
        // Gate on authorization first. Configuring the session before the user
        // has answered leaves it with no inputs and no way to recover until the
        // app is relaunched.
        Permissions.requestCamera { [weak self] granted in
            guard let self else { return }

            guard granted else {
                DispatchQueue.main.async {
                    self.isCameraDenied = true
                    self.isSessionRunning = false
                }
                return
            }
            DispatchQueue.main.async { self.isCameraDenied = false }

            self.sessionQueue.async {
                if !self.isConfigured {
                    self.configureSession()
                    self.isConfigured = true
                }
                if !self.session.isRunning { self.session.startRunning() }

                let running = self.session.isRunning
                let device = self.currentDevice
                DispatchQueue.main.async {
                    self.isSessionRunning = running
                    if let device { self.onDeviceReady?(device) }
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

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            applyMaxPhotoDimensions(for: device)
            let proRAW = photoOutput.isAppleProRAWSupported
            if proRAW { photoOutput.isAppleProRAWEnabled = true }
            DispatchQueue.main.async { self.isProRAWAvailable = proRAW }
        }

        configureFlash(device: device)
        session.commitConfiguration()
    }

    /// Picks the genuinely largest supported size. The array is not documented
    /// as sorted, so taking `.last` could quietly cap capture resolution, and
    /// the old zero-valued fallback was not a legal value to assign.
    private func applyMaxPhotoDimensions(for device: AVCaptureDevice) {
        let supported = device.activeFormat.supportedMaxPhotoDimensions
        guard let largest = supported.max(by: {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }) else { return }
        photoOutput.maxPhotoDimensions = largest
    }

    // MARK: - Audio

    /// Without an audio input every recording comes out silent, however good
    /// the video settings are.
    private func enableAudioInput() {
        guard audioDeviceInput == nil else { return }

        Permissions.requestMicrophone { [weak self] granted in
            guard let self, granted else { return }
            self.sessionQueue.async {
                guard self.audioDeviceInput == nil,
                      let device = AVCaptureDevice.default(for: .audio),
                      let input = try? AVCaptureDeviceInput(device: device) else { return }

                self.session.beginConfiguration()
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.audioDeviceInput = input
                }
                self.session.commitConfiguration()
            }
        }
    }

    // MARK: - Session preset

    /// Photo capture wants the `.photo` preset; video wants `.inputPriority`,
    /// which is the only preset under which an explicitly chosen
    /// `device.activeFormat` survives. Setting a named preset silently discards
    /// the format, which is why the video mode selector otherwise does nothing.
    func setPresetForVideoFormatSelection(_ enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let target: AVCaptureSession.Preset = enabled ? .inputPriority : .photo
            guard self.session.sessionPreset != target,
                  self.session.canSetSessionPreset(target) else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = target
            self.session.commitConfiguration()
        }
    }

    private func configureFlash(device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFlashModeSupported(.off) { device.flashMode = .off }
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

            let previousInput = self.videoDeviceInput
            if let previousInput { self.session.removeInput(previousInput) }

            guard self.session.canAddInput(newInput) else {
                // Put the old lens back rather than committing a session with
                // no video input at all, which is an unrecoverable black frame.
                if let previousInput, self.session.canAddInput(previousInput) {
                    self.session.addInput(previousInput)
                }
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(newInput)
            self.videoDeviceInput = newInput
            self.currentDevice = device

            self.applyMaxPhotoDimensions(for: device)
            let proRAW = self.photoOutput.isAppleProRAWSupported
            if proRAW { self.photoOutput.isAppleProRAWEnabled = true }

            self.configureFlash(device: device)
            self.session.commitConfiguration()

            DispatchQueue.main.async {
                self.currentLens = lens
                self.isProRAWAvailable = proRAW
                self.onDeviceReady?(device)
            }
        }
    }

    private func bestDevice(for lens: LensOption) -> AVCaptureDevice? {
        switch lens {
        case .ultraWide:
            return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        case .main:
            return AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .telephoto:
            return AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
        }
    }

    // MARK: - Photo capture

    func capturePhoto() {
        let settings = buildPhotoSettings()
        let id = settings.uniqueID

        let delegate = PhotoCaptureDelegate { [weak self] image in
            DispatchQueue.main.async {
                guard let self else { return }
                if let image { self.lastThumbnail = image }
                self.photoCaptureDelegates.removeValue(forKey: id)
            }
        }
        photoCaptureDelegates[id] = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    private func buildPhotoSettings() -> AVCapturePhotoSettings {
        if isProRAWAvailable,
           let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
            let settings = AVCapturePhotoSettings(
                rawPixelFormatType: rawFormat,
                processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc]
            )
            settings.flashMode = .off
            return settings
        }
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        return settings
    }

    // MARK: - Zoom

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
    case main      = "1×"
    case telephoto = "4×"
    var id: String { rawValue }
}

// MARK: - Capture Mode

enum CaptureMode: String, CaseIterable {
    case photo     = "Photo"
    case video     = "Video"
    case timeLapse = "Time-lapse"
}

// MARK: - Photo Capture Delegate

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    private let completion: (UIImage?) -> Void

    /// A ProRAW capture delivers two callbacks — the RAW frame and the
    /// processed one. Saving from each produced two library assets for one
    /// shutter press, so both are collected here and written as a single asset
    /// with the RAW as an alternate resource, which is how Photos expects a
    /// RAW+JPEG pair to arrive.
    private var rawData: Data?
    private var processedData: Data?
    private var expectedCallbacks = 1
    private var receivedCallbacks = 0

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        // expectedPhotoCount is AVFoundation's own count of how many times
        // didFinishProcessingPhoto will fire for this capture.
        expectedCallbacks = max(1, resolvedSettings.expectedPhotoCount)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        receivedCallbacks += 1

        if error == nil, let data = photo.fileDataRepresentation() {
            if photo.isRawPhoto { rawData = data } else { processedData = data }
        }

        guard receivedCallbacks >= expectedCallbacks else { return }
        finish()
    }

    private func finish() {
        // Copied to locals so the save closure captures values rather than self.
        let processed = processedData
        let raw = rawData

        // Prefer the processed frame for both the library asset and the
        // thumbnail; UIImage cannot render a DNG.
        if let primary = processed ?? raw {
            Permissions.saveToPhotoLibrary({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: primary, options: nil)

                // Attach the RAW alongside the processed frame rather than as
                // its own asset — one shutter press, one item in Photos.
                if processed != nil, let raw {
                    request.addResource(with: .alternatePhoto, data: raw, options: nil)
                }
            })
        }

        completion(processed.flatMap(UIImage.init(data:)))
    }
}
