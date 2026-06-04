import SwiftUI
import AVFoundation

/// SwiftUI 包装层：把 UIKit 的 CameraViewController 放进来
struct CameraView: UIViewControllerRepresentable {
    @Binding var threshold: Double
    @Binding var preset: PixelPreset
    @Binding var isRunning: Bool

    let onPhoto: (CGImage) -> Void
    var onPermissionDenied: (() -> Void)? = nil
    var flashOn: Bool = false

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onPhoto = onPhoto
        vc.onPermissionDenied = onPermissionDenied
        vc.threshold = UInt8(threshold)
        vc.preset = preset
        vc.flashOn = flashOn
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.threshold = UInt8(threshold)
        uiViewController.preset = preset
        uiViewController.flashOn = flashOn

        if isRunning {
            uiViewController.startIfNeeded()
        } else {
            uiViewController.stopIfNeeded()
        }
    }
}

final class CameraViewModel: ObservableObject {
    @Published var threshold: Double = 128
    @Published var preset: PixelPreset = .clean
    @Published var capturedImage: UIImage?
    @Published var showingSettings: Bool = false
    @Published var isRunning: Bool = true
    @Published var permissionDenied: Bool = false
    @Published var aspectRatio: AspectRatioOption = .r3_4
    @Published var flashOn: Bool = false

    func capture() {
        NotificationCenter.default.post(name: .pixelCamCapture, object: nil)
    }

    func resetToCamera() {
        capturedImage = nil
        isRunning = true
    }

    func flipCamera() {
        NotificationCenter.default.post(name: .pixelCamFlipCamera, object: nil)
    }
}

extension Notification.Name {
    static let pixelCamCapture = Notification.Name("pixelCamCapture")
    static let pixelCamFlipCamera = Notification.Name("pixelCamFlipCamera")
}

/// 取景框比例（值 = 宽 / 高）
enum AspectRatioOption: String, CaseIterable, Equatable {
    case r9_16 = "9:16"
    case r3_4  = "3:4"
    case r1_1  = "1:1"
    case r4_3  = "4:3"
    case r16_9 = "16:9"

    var value: CGFloat {
        switch self {
        case .r9_16: return 9.0 / 16.0
        case .r3_4:  return 3.0 / 4.0
        case .r1_1:  return 1.0
        case .r4_3:  return 4.0 / 3.0
        case .r16_9: return 16.0 / 9.0
        }
    }
}

