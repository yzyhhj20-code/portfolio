import SwiftUI

struct ContentView: View {
    var body: some View {
        CameraScreen()
    }
}

struct CameraScreen: View {
    @StateObject private var model = CameraViewModel()

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
                VStack(spacing: 0) {
                    TopBar(
                        presetName: model.preset.displayName,
                        onSettings: { model.showingSettings = true },
                        onFlip: { model.flipCamera() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    CameraView(
                        threshold: $model.threshold,
                        preset: $model.preset,
                        isRunning: $model.isRunning,
                        onFrame: { cgImage in
                            model.previewImage = cgImage
                        },
                        onPhoto: { cgImage in
                            model.capturedImage = UIImage(cgImage: cgImage)
                            model.isRunning = false
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3.0/4.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(red: 0.90, green: 0.90, blue: 0.91), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    ControlsPanel(
                        threshold: $model.threshold,
                        preset: $model.preset,
                        onShutter: { model.capture() },
                        onPickLast: { /* MVP：不做独立图库，留空 */ }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .sheet(isPresented: $model.showingSettings) {
            SettingsView()
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
    let onShutter: () -> Void
    let onPickLast: () -> Void

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

                Button(action: { /* MVP：留空（闪光灯/镜像）*/ }) {
                    Circle()
                        .stroke(Color(red: 0.90, green: 0.90, blue: 0.91), lineWidth: 1)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "bolt")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(.black.opacity(0.8))
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
                Text(showingSavedToast ? "Saved" : "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.50))
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
                .rotationEffect(image.size.width > image.size.height ? .degrees(90) : .degrees(0))
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
        .sheet(isPresented: $showingShare) {
            ShareSheet(activityItems: [image])
        }
    }

    private func saveToPhotos() {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        withAnimation(.easeInOut(duration: 0.2)) { showingSavedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
                    LabeledContent("版本", value: "0.1 Demo")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ContentView()
}
