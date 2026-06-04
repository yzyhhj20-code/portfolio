import SwiftUI
import PhotosUI

struct ContentView: View {
    var body: some View {
        CameraScreen()
    }
}

struct CameraScreen: View {
    @StateObject private var model = CameraViewModel()
    @State private var showingPicker = false
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            // 亮色极简背景
            Color(red: 0.97, green: 0.97, blue: 0.96).ignoresSafeArea()

            if let result = model.capturedImage {
                ResultView(image: result) {
                    model.resetToCamera()
                }
                .transition(.opacity)
            } else {
              GeometryReader { geo in
                // 按所选比例算出取景框精确尺寸（宽/高 = ratio.value）：
                // 在「满宽」与「留足上下栏空间」之间取最大可放下的框。
                let availW = geo.size.width - 32
                let maxH = max(160, geo.size.height - 380)
                let r = model.aspectRatio.value
                let boxW = min(availW, maxH * r)
                let boxH = boxW / r

                VStack(spacing: 0) {
                    TopBar(
                        presetName: model.preset.displayName,
                        onSettings: { model.showingSettings = true },
                        onFlip: { model.flipCamera() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    RatioSelector(selected: $model.aspectRatio)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    Spacer(minLength: 12)

                    // 取景框固定为所选比例（VStack 默认水平居中）；
                    // CameraView 用 overlay 贴合（UIImageView scaleAspectFill 铺满裁切）。
                    Color.black
                        .frame(width: boxW, height: boxH)
                        .overlay(
                            CameraView(
                                threshold: $model.threshold,
                                preset: $model.preset,
                                isRunning: $model.isRunning,
                                onPhoto: { cgImage in
                                    // 用拍照时的当前比例居中裁剪，保证成片与预览一致
                                    let out = cropToRatio(cgImage, ratio: model.aspectRatio.value) ?? cgImage
                                    model.capturedImage = UIImage(cgImage: out)
                                    model.isRunning = false
                                },
                                onPermissionDenied: {
                                    model.permissionDenied = true
                                },
                                flashOn: model.flashOn
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color(red: 0.90, green: 0.90, blue: 0.91), lineWidth: 1)
                        )

                    Spacer(minLength: 12)

                    ControlsPanel(
                        threshold: $model.threshold,
                        preset: $model.preset,
                        flashOn: model.flashOn,
                        onShutter: { model.capture() },
                        onPickLast: { showingPicker = true },
                        onToggleFlash: { model.flashOn.toggle() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
              }
            }

            if model.permissionDenied {
                PermissionDeniedView()
            }
        }
        .sheet(isPresented: $model.showingSettings) {
            SettingsView()
        }
        .photosPicker(isPresented: $showingPicker, selection: $pickedItem, matching: .images)
        .onChange(of: pickedItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data),
                   let cg = normalizeUpright(ui),
                   let processed = ImageProcessing.process(cgImage: cg, threshold: UInt8(model.threshold), preset: model.preset) {
                    let out = cropToRatio(processed, ratio: model.aspectRatio.value) ?? processed
                    await MainActor.run {
                        model.capturedImage = UIImage(cgImage: out)
                        model.isRunning = false
                    }
                }
                await MainActor.run { pickedItem = nil }
            }
        }
    }
}

private struct TopBar: View {
    let presetName: String
    let onSettings: () -> Void
    let onFlip: () -> Void

    var body: some View {
        HStack {
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text(presetName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
            Spacer()
            Button(action: onFlip) {
                Image(systemName: "camera.rotate")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
            }
        }
        .background(Color.clear)
    }
}

private struct ControlsPanel: View {
    @Binding var threshold: Double
    @Binding var preset: PixelPreset
    let flashOn: Bool
    let onShutter: () -> Void
    let onPickLast: () -> Void
    let onToggleFlash: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Threshold")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))

                Slider(value: $threshold, in: 0...255, step: 1)
                    .tint(Color.black)
            }

            HStack(spacing: 10) {
                PresetPill(title: "Clean", isSelected: preset == .clean) { preset = .clean }
                PresetPill(title: "Grit", isSelected: preset == .grit) { preset = .grit }
                PresetPill(title: "Poster", isSelected: preset == .poster) { preset = .poster }
            }

            HStack {
                Button(action: onPickLast) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.93, green: 0.93, blue: 0.94))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(.black.opacity(0.8))
                        )
                }

                Spacer()

                ShutterButton(action: onShutter)

                Spacer()

                Button(action: onToggleFlash) {
                    Circle()
                        .fill(flashOn ? Color.black : Color.white)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(Color(red: 0.90, green: 0.90, blue: 0.91), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: flashOn ? "bolt.fill" : "bolt")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(flashOn ? .white : .black.opacity(0.8))
                        )
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.90, green: 0.90, blue: 0.91), lineWidth: 1)
        )
    }
}

private struct PresetPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.black)
                .frame(height: 32)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.black : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(isSelected ? 0 : 0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct ShutterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.15), lineWidth: 2)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(Color.black)
                    .frame(width: 58, height: 58)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ResultView: View {
    let image: UIImage
    let onBack: () -> Void

    @State private var showingShare = false
    @State private var showingSavedToast = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                }
                Spacer()
                Button(action: { showingShare = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer(minLength: 10)

            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .padding(.horizontal, 16)

            Spacer(minLength: 10)

            HStack(spacing: 12) {
                Button(action: saveToPhotos) {
                    Text("保存")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button(action: { showingShare = true }) {
                    Text("分享")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(red: 0.90, green: 0.90, blue: 0.91), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color(red: 0.97, green: 0.97, blue: 0.96).ignoresSafeArea())
        .overlay(alignment: .top) {
            if showingSavedToast {
                Text("已保存到相册")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingShare) {
            ShareSheet(activityItems: [image])
        }
    }

    private func saveToPhotos() {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeInOut(duration: 0.2)) { showingSavedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) { showingSavedToast = false }
        }
    }
}

private struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Export") {
                    LabeledContent("格式", value: "PNG（默认）")
                    LabeledContent("尺寸", value: "原图（MVP）")
                }
                Section("About") {
                    LabeledContent("版本", value: "0.1")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct PermissionDeniedView: View {
    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.96).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.black.opacity(0.55))
                Text("需要相机权限")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                Text("请在「设置」中允许 PixelCam 使用相机")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
                    .multilineTextAlignment(.center)
                Button(action: openSettings) {
                    Text("去设置")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .frame(height: 44)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.top, 4)
            }
            .padding(32)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

private struct RatioSelector: View {
    @Binding var selected: AspectRatioOption

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AspectRatioOption.allCases, id: \.self) { opt in
                Button { selected = opt } label: {
                    Text(opt.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected == opt ? Color.white : Color.black)
                        .frame(height: 30)
                        .frame(maxWidth: .infinity)
                        .background(selected == opt ? Color.black : Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.black.opacity(selected == opt ? 0 : 0.18), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 把带 EXIF 朝向的图片「正过来」，得到方向已烘焙进像素的 CGImage（相册导入用）
private func normalizeUpright(_ image: UIImage) -> CGImage? {
    if image.imageOrientation == .up, let cg = image.cgImage { return cg }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let r = UIGraphicsImageRenderer(size: image.size, format: format)
    return r.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }.cgImage
}

/// 把 CGImage 居中裁剪到目标 宽/高 比例
private func cropToRatio(_ image: CGImage, ratio: CGFloat) -> CGImage? {
    let w = CGFloat(image.width)
    let h = CGFloat(image.height)
    var cropW = w, cropH = h
    if w / h > ratio {
        cropW = h * ratio          // 太宽 → 裁宽
    } else {
        cropH = w / ratio          // 太高 → 裁高
    }
    let rect = CGRect(x: (w - cropW) / 2, y: (h - cropH) / 2, width: cropW, height: cropH)
    return image.cropping(to: rect)
}

#Preview {
    ContentView()
}
