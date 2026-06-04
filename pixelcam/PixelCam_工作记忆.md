# PixelCam 工作记忆（1-bit 黑白点阵相机 iOS App）

> 对标 BitCam。SwiftUI + AVFoundation。最近更新：2026-06-03

## 工程结构
- **正式工程**：`像素相机/PixelCam/PixelCam.xcodeproj`，源码在 `PixelCam/PixelCam/`
- `PixelCamDemo/`：旧副本，**无 xcodeproj，忽略/可删**，别改错
- 6 个 swift 文件：
  - `PixelCamApp.swift` 入口
  - `ContentView.swift` 全部 UI（相机屏 + 结果页 + 控件 + 比例切换 + 权限页）
  - `CameraView.swift` representable 包装 + `CameraViewModel` + `AspectRatioOption` 枚举
  - `CameraViewController.swift` AVFoundation 采集/预览/拍照
  - `ImageProcessing.swift` 灰度+抖动算法（核心）
  - `ShareSheet.swift` 系统分享

## 🚨 踩过的大坑（按重要度）

### 1. 缺启动屏幕 → 整个 App 被 letterbox（最隐蔽，排查最久）
- 症状：四周黑边、圆角卡片、顶部大空白、`GeometryReader` 拿到的是**缩小的假尺寸**，导致所有布局计算全错，怎么调都不对
- 根因：Info.plist **没有 `UILaunchScreen`**
- 修复：Info.plist 加 `<key>UILaunchScreen</key><dict/>`
- **教训：iOS 布局怎么调都诡异时，先确认有没有启动屏幕（是否全屏运行）**
- 加完必须**真机删 App 重装**，不能只 Rebuild（系统缓存 letterbox 模式）

### 2. UIViewControllerRepresentable 尺寸协商不可靠
- `.aspectRatio(.fit)` 会把它缩成最小块；`maxHeight:.infinity` 不撑开 → 取景框忽大忽小（细条↔小块循环）
- 修复：用 `GeometryReader` 算**死像素尺寸**给一个 `Color`，相机作为 `.overlay` 贴合
- 当前取景框尺寸公式见 ContentView：`boxW = min(availW, maxH * ratio)`, `boxH = boxW / ratio`
- maxH 预留：`geo.size.height - 380`（留给 TopBar + 比例条 + 控制面板）

### 3. 相机帧默认横向（旋转 90°/细条）
- `VideoDataOutput` 的 `connection.videoRotationAngle` 在部分机型**不生效**
- 修复：预览帧交付时给 `UIImage(orientation:)` 打朝向：后置 `.right`，前置 `.leftMirrored`
- 拍照走 `PhotoOutput`（connection 旋转**可靠**，保留），再 `uprightCGImage` 把方向烘焙进像素
- Info.plist 另修：`armv7` → `arm64`（否则新机型装不上）

## 效果算法（ImageProcessing.swift，对标 BitCam 的关键）

### 三种模式
| 模式 | 算法 | 观感 |
|---|---|---|
| Clean | 纯阈值 thresholdToBinary | 高对比硬黑白 |
| **Grit** | **Floyd–Steinberg 误差扩散** | 丰富点阵，BitCam 灵魂 |
| Poster | Bayer 有序抖动 orderedDither | 规则网点/报纸印刷 |

### 🔑 关键认知
1. **必须先降采样再抖动**：全分辨率(3000px)抖动 → 点细到 1px → 存图/缩放被抗锯齿**糊成灰色**。BitCam 在 ~480px 上抖动，点 2-3px 可见。
   - 参数 `kDitherTargetLong`（当前 **360**）：越小颗粒越粗越像 BitCam
   - 预览 `previewView.layer.magnificationFilter = .nearest`（放大保持锐利方块）
   - 副作用：成片分辨率 ≈ 360px（复古相机常态）。要高清出图需单独提高拍照档目标长边
2. **抖动前加对比** `applyDither` 里 `k=1.4`：压黑暗部提亮亮部，避免发灰发白。越大越硬朗。
3. **Floyd–Steinberg 对"比较阈值"几乎免疫**（误差自动补偿密度）→ 改 threshold 取景框无变化。
   - 修复：FS 里把滑杆映射成**亮度偏置** `bias = 128 - threshold`，比较点固定 128。右=更暗，左=更亮。
4. 预览采集分辨率：`sessionPreset = .hd1280x720`（原 VGA）

## 其他已修
- 每帧写 `@Published previewImage` → 全量重渲染卡顿（已删，预览由 VC 内 UIImageView 直接画）
- 拍照全分辨率处理挪到 `processQueue` 后台
- 权限被拒：`onPermissionDenied` 回调 + `PermissionDeniedView`（带"去设置"）
- 保存反馈：顶部"已保存到相册"胶囊 toast + 成功震动
- 闪光灯：`flashOn` 链路（前置无硬件闪光自动忽略 `supportedFlashModes`）
- 相册导入：`.photosPicker`（PHPicker，**不需相册权限**）→ 当前预设+比例处理。需 iOS 16+

## 比例系统
- `AspectRatioOption`：9:16 / 3:4 / 1:1 / 4:3 / 16:9，value = 宽/高，默认 3:4
- 预览：`scaleAspectFill` 铺满所选比例框（裁切）
- 成片：`cropToRatio` 居中裁剪到同比例，与预览一致

## 验证习惯
- SourceKit 在无 Xcode 工程上下文时会报一堆 "Cannot find type UIImage/PixelPreset..."——**全是误报**，忽略
- 改完用 sandbox 跑 `grep -o "{"` 数大括号配平 + `plutil -lint` 验 Info.plist

## App 图标 / Logo (2026-06-03)
- 概念：**1-bit 像素画相机**（白机柔黑底，镜头是棋盘抖动玻璃 + 左上高光）——呼应 BitCam/像素感。曾误做成光滑渐变镜头被否，关键词是「突出像素感、像 BitCam」。
- 生成器：`make_logo_final.py`（PIL，NEAREST 放大保持硬边方块）。逻辑画布 `L=40`，相机用 `OX,OY` 偏移居中；`BG`柔黑、`BODY`米白。改完重跑即覆盖图标。
  - 调小相机→`OX,OY` 调大；换底色→`BG`；镜头格子→`r`。
- 其他脚本：`make_logo_pixel.py`(3 个像素变体对比)、`make_logo.py`/`make_logo2.py`(早期渐变/光滑方案，已弃)。
- **图标接线（重点，PixelCam 是旧式 pbxproj objectVersion 56，无文件夹同步）**：
  - 工程原本**没有 Assets.xcassets**。已手动创建 `PixelCam/PixelCam/Assets.xcassets/`(根 Contents.json + AppIcon.appiconset/Contents.json + AppIcon-1024.png 单图 1024 通用格式)。
  - 用 Python 脚本改 `project.pbxproj` 接好：加 PBXFileReference(folder.assetcatalog)+PBXBuildFile+组 children+Resources 阶段+两个 config 的 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`。改前备份 `project.pbxproj.bak`，改后 `plutil -lint` 通过。
  - 装新图标：Xcode 关掉重开 → Cmd+Shift+K → 真机**先删旧 App 再装**(图标有缓存)。
- 对比参考：BitCam 截图(IMG_1868)是满分辨率误差扩散；图标走低分辨率方块像素风。
