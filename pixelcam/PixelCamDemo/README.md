## PixelCamDemo（SwiftUI + 相机 + 1‑bit 黑白 + 保存/分享）

这是一个可运行的 iOS Demo 源码包（不含 .xcodeproj）。你只需要在 Xcode 里新建一个 SwiftUI App 工程，然后把本文件夹里的 `.swift` 文件拖进去即可运行。

### 运行环境
- iOS 16+（建议）
- Xcode 15+（建议）

### 集成步骤（最省事的方式）
1. 打开 Xcode → File → New → Project → iOS → **App**
2. Product Name 随便填（例如 `PixelCamDemoApp`），Interface 选 **SwiftUI**，Language 选 **Swift**
3. 把本文件夹内以下文件全部拖到 Xcode 工程中（勾选 “Copy items if needed”）：
   - `PixelCamDemoApp.swift`
   - `ContentView.swift`
   - `CameraView.swift`
   - `CameraViewController.swift`
   - `ImageProcessing.swift`
   - `ShareSheet.swift`
4. 在你的工程 `Info.plist` 增加权限文案（必加，否则会闪退/无权限）：
   - `NSCameraUsageDescription`：例如 “用于拍摄 1-bit 黑白点阵照片”
   - `NSPhotoLibraryAddUsageDescription`：例如 “用于保存作品到相册”
5. 真机运行（相机功能需要真机；模拟器无相机）

### Demo 功能
- 实时取景 1-bit 黑白预览（基于 AVCaptureVideoDataOutput）
- 3 个预设：Clean / Grit（有序抖动）/ Poster（像素块 + 阈值）
- Threshold（阈值）滑杆
- 拍照后进入结果页
- 保存到相册（PNG）
- 系统分享面板

### 下一步（你想继续做可上线版本时）
- 用 Metal/Compute 加速实时处理（省电、帧率更稳）
- 结果页增加裁切/旋转/导出尺寸
- 增加“导入照片处理”（相册导入）
- 上架所需：隐私说明、数据收集声明、崩溃与权限兜底

