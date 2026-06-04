import UIKit
import AVFoundation

final class CameraViewController: UIViewController {
    // MARK: - Public
    var onFrame: ((CGImage) -> Void)?
    var onPhoto: ((CGImage) -> Void)?

    var threshold: UInt8 = 128
    var preset: PixelPreset = .clean

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
                }
            }
        default:
            // MVP：权限被拒绝时不弹复杂提示，留给上层做引导
            break
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
        session.sessionPreset = .vga640x480

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

        // Orientation
        if let conn = videoOutput.connection(with: .video), conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }
        if let conn = photoOutput.connection(with: .video), conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
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
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        photoOutput.capturePhoto(with: settings, delegate: self)
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

        // 实时预览用：尽量轻量
        let th = threshold
        let pr = preset
        if let cgImage = processor.process(pixelBuffer: pixelBuffer, threshold: th, preset: pr) {
            DispatchQueue.main.async {
                self.previewView.image = UIImage(cgImage: cgImage)
                self.onFrame?(cgImage)
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
              let cg = uiImage.cgImage else { return }

        // 拍照成片：用同一套处理，但输入是 CGImage
        let th = threshold
        let pr = preset
        if let processed = ImageProcessing.process(cgImage: cg, threshold: th, preset: pr) {
            DispatchQueue.main.async {
                self.onPhoto?(processed)
            }
        }
    }
}

