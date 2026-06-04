import SwiftUI
import AVFoundation

/// SwiftUI 包装层：把 UIKit 的 CameraViewController 放进来
struct CameraView: UIViewControllerRepresentable {
    @Binding var threshold: Double
    @Binding var preset: PixelPreset
    @Binding var isRunning: Bool

    let onFrame: (CGImage) -> Void
    let onPhoto: (CGImage) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onFrame = onFrame
        vc.onPhoto = onPhoto
        vc.threshold = UInt8(threshold)
        vc.preset = preset
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.threshold = UInt8(threshold)
        uiViewController.preset = preset

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
    @Published var previewImage: CGImage?
    @Published var showingSettings: Bool = false
    @Published var isRunning: Bool = true

    private weak var controller: CameraViewController?

    func attach(controller: CameraViewController) {
        self.controller = controller
    }

    func capture() {
        // 由 CameraViewController 执行拍照；这里通过通知触发最简单
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

