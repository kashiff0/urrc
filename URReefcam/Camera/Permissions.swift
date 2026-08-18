import AVFoundation
import Photos

/// Authorization gates for the three things the app touches.
///
/// These matter more than they look. AVFoundation will happily configure a
/// capture session before the user has answered the camera prompt — the inputs
/// just silently fail to attach, leaving a black preview that only fixes itself
/// on the next launch. So every path into the session goes through here first.
enum Permissions {

    // MARK: - Camera

    static var cameraStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Calls back on an arbitrary queue — hop to main yourself if you touch UI.
    static func requestCamera(_ completion: @escaping (Bool) -> Void) {
        switch cameraStatus {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
        default:
            // Denied or restricted — only Settings can change this now.
            completion(false)
        }
    }

    // MARK: - Microphone

    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// Deliberately not requested at launch: a reef camera is photo-first, and
    /// prompting for the mic before the user has touched video mode reads as
    /// suspicious. Called when video mode is first selected instead.
    static func requestMicrophone(_ completion: @escaping (Bool) -> Void) {
        switch microphoneStatus {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        default:
            completion(false)
        }
    }

    // MARK: - Photo library

    /// Add-only: the app saves captures but never reads the user's library, so
    /// it asks for the narrower permission that matches NSPhotoLibraryAddUsageDescription.
    static func requestPhotoLibraryAdd(_ completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { new in
                completion(new == .authorized || new == .limited)
            }
        default:
            completion(false)
        }
    }

    /// Wraps a save so it can never silently no-op against a missing grant.
    static func saveToPhotoLibrary(
        _ changes: @escaping () -> Void,
        completion: ((Bool, Error?) -> Void)? = nil
    ) {
        requestPhotoLibraryAdd { granted in
            guard granted else {
                completion?(false, nil)
                return
            }
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                completion?(success, error)
            }
        }
    }
}
