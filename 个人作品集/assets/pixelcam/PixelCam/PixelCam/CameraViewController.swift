import UIKit
import AVFoundation

final class CameraViewController: UIViewController {
    // MARK: - Public
    var onPhoto: ((CGImage) -> Void)?
    var onPermissionDenied: (() -> Void)?

    var threshold: UInt8 = 128
    var preset: PixelPreset = .clean
    var flashOn: Bool = false

    // MARK: - Capture
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()

    private let captureQueue = DispatchQueue(label: "pixelcam.capture.queue")
    private let processQueue = DispatchQueue(label: "pixelcam.process.queue", qos: .userInitiated)

    private var currentInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back

    private let processor = FrameProcessor()
    private var isConfigured = false
    private var isSessionRunning = false

    private let previewView = UIImageView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        previewView.contentMode = .scaleAspectFill
        previewView.clipsToBounds = true
        previewView.backgroundColor = .black
        previewView.layer.magnificationFilter = .nearest
        view.addSubview(previewView)

        previewView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(handleCapture), name: .pixelCamCapture, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFlip), name: .pixelCamFlipCamera, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopIfNeeded()
    }

    func startIfNeeded() {
        guard !isSessionRunning else { return }
        checkPermissionAndStart()
    }

    func stopIfNeeded() {
        guard isSessionRunning else { return }
        captureQueue.async {
            self.session.stopRunning()
            self.isSessionRunning = false
        }
    }

    // MARK: - Permission
    private func checkPermissionAndStart() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.configureAndStart()
                } else {
                    DispatchQueue.main.async { self.onPermissionDenied?() }
                }
            }
        default:
            // 权限被拒绝：通知上层显示「去设置」引导
            DispatchQueue.main.async { self.onPermissionDenied?() }
        }
    }

    // MARK: - Configure
    private func configureAndStart() {
        captureQueue.async {
            if !self.isConfigured {
                self.configureSession()
                self.isConfigured = true
            }
            guard !self.isSessionRunning else { return }
            self.session.startRunning()
            self.isSessionRunning = true
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        // Input
        if let input = makeDeviceInput(position: currentPosition) {
            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
            }
        }

        // Video output
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: processQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        // Photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        // 朝向：VideoDataOutput 的 connection 旋转在部分机型不生效，
        // 预览帧的朝向改为在交付时给 UIImage 打 orientation（见下方 delegate）。
        // 拍照走 PhotoOutput，connection 旋转可靠，这里保留。
        if let conn = photoOutput.connection(with: .video) {
            if #available(iOS 17.0, *), conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            } else if conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
        }

        session.commitConfiguration()
    }

    private func makeDeviceInput(position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        guard let device = discovery.devices.first else { return nil }
        return try? AVCaptureDeviceInput(device: device)
    }

    // MARK: - Actions
    @objc private func handleCapture() {
        captureQueue.async {
            // 前置拍照镜像，与预览保持一致
            if let conn = self.photoOutput.connection(with: .video),
               conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = (self.currentPosition == .front)
            }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = (self.flashOn && self.photoOutput.supportedFlashModes.contains(.on)) ? .on : .off
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    @objc private func handleFlip() {
        captureQueue.async {
            self.session.beginConfiguration()
            if let input = self.currentInput {
                self.session.removeInput(input)
            }
            self.currentPosition = (self.currentPosition == .back) ? .front : .back
            if let newInput = self.makeDeviceInput(position: self.currentPosition),
               self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.currentInput = newInput
            }
            self.session.commitConfiguration()
        }
    }
}

// MARK: - Video frames
extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output === videoOutput else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let th = threshold
        let pr = preset
        if let cgImage = processor.process(pixelBuffer: pixelBuffer, threshold: th, preset: pr) {
            // 预览帧是相机传感器的横向画面，按机位打 orientation 转成竖屏：
            // 后置 .right（顺时针90°）；前置 .leftMirrored（竖屏+镜像，自拍效果）
            let orient: UIImage.Orientation = (currentPosition == .front) ? .leftMirrored : .right
            let img = UIImage(cgImage: cgImage, scale: 1, orientation: orient)
            DispatchQueue.main.async {
                self.previewView.image = img
            }
        }
    }
}

// MARK: - Photo capture
extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else { return }
        guard let data = photo.fileDataRepresentation(),
              let uiImage = UIImage(data: data),
              let cg = Self.uprightCGImage(from: uiImage) else { return }

        let th = threshold
        let pr = preset
        // 全分辨率逐像素处理较重，放到后台队列，避免阻塞拍照回调
        processQueue.async {
            if let processed = ImageProcessing.process(cgImage: cg, threshold: th, preset: pr) {
                DispatchQueue.main.async {
                    self.onPhoto?(processed)
                }
            }
        }
    }

    /// 把带 EXIF 朝向的照片「正过来」，得到方向已烘焙进像素的 CGImage，
    /// 后续处理与保存都不再需要额外旋转。
    private static func uprightCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let normalized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return normalized.cgImage
    }
}
