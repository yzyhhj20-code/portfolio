import Foundation
import CoreVideo
import CoreGraphics

enum PixelPreset: String, CaseIterable, Equatable {
    case clean
    case grit
    case poster

    var displayName: String {
        switch self {
        case .clean: return "Clean"
        case .grit: return "Grit"
        case .poster: return "Poster"
        }
    }
}

/// 简化的帧处理器：实时预览走 pixelBuffer → 1-bit（CPU/vImage）
final class FrameProcessor {
    private var lumaBuffer: [UInt8] = []
    private var outBuffer: [UInt8] = []

    func process(pixelBuffer: CVPixelBuffer, threshold: UInt8, preset: PixelPreset) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // 预分配
        let pixelCount = width * height
        if lumaBuffer.count != pixelCount { lumaBuffer = Array(repeating: 0, count: pixelCount) }
        if outBuffer.count != pixelCount { outBuffer = Array(repeating: 0, count: pixelCount) }

        // 直接从 BGRA8888 计算灰度（避免 vImage API 在不同 Xcode/SDK 下的符号差异）
        let srcPtr = base.assumingMemoryBound(to: UInt8.self)
        lumaBuffer.withUnsafeMutableBufferPointer { lumaPtr in
            var i = 0
            for y in 0..<height {
                let rowStart = y * bytesPerRow
                for x in 0..<width {
                    let p = rowStart + x * 4
                    let b = srcPtr[p + 0]
                    let g = srcPtr[p + 1]
                    let r = srcPtr[p + 2]
                    // 近似 BT.601: Y = 0.299R + 0.587G + 0.114B
                    let yy = (77 * Int(r) + 150 * Int(g) + 29 * Int(b)) >> 8
                    lumaPtr[i] = UInt8(clamping: yy)
                    i += 1
                }
            }
        }

        // 降采样到目标长边再抖动：让黑白颗粒可见（全分辨率细点缩放后会糊成灰色）
        let ds = downscaleLuma(lumaBuffer, width: width, height: height, targetLong: kDitherTargetLong)
        var out = [UInt8](repeating: 0, count: ds.width * ds.height)
        applyDither(preset: preset, luma: ds.luma, out: &out, width: ds.width, height: ds.height, threshold: threshold)
        return makeGrayCGImage(bytes: out, width: ds.width, height: ds.height)
    }
}

enum ImageProcessing {
    /// 拍照成片：CGImage → 1-bit（CPU）
    static func process(cgImage: CGImage, threshold: UInt8, preset: PixelPreset) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height

        // 将 CGImage 画到 RGBA buffer
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var rgba = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let ctx = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 灰度
        var luma = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = rgba[i * 4 + 0]
            let g = rgba[i * 4 + 1]
            let b = rgba[i * 4 + 2]
            // 近似 BT.601
            let y = (77 * Int(r) + 150 * Int(g) + 29 * Int(b)) >> 8
            luma[i] = UInt8(clamping: y)
        }

        // 降采样到目标长边再抖动（与预览一致）
        let ds = downscaleLuma(luma, width: width, height: height, targetLong: kDitherTargetLong)
        var out = [UInt8](repeating: 0, count: ds.width * ds.height)
        applyDither(preset: preset, luma: ds.luma, out: &out, width: ds.width, height: ds.height, threshold: threshold)
        return makeGrayCGImage(bytes: out, width: ds.width, height: ds.height)
    }
}

// MARK: - Helpers (算法)

/// 抖动前降采样的目标长边（像素）。越小颗粒越粗、越像 BitCam；越大越细腻。
private let kDitherTargetLong = 360

/// 按目标长边把 luma 块平均降采样，返回新 luma 及尺寸（长边已 <= target 时原样返回）
private func downscaleLuma(_ luma: [UInt8], width: Int, height: Int, targetLong: Int) -> (luma: [UInt8], width: Int, height: Int) {
    let longSide = max(width, height)
    if longSide <= targetLong { return (luma, width, height) }
    let scale = Double(targetLong) / Double(longSide)
    let w = max(1, Int(Double(width) * scale))
    let h = max(1, Int(Double(height) * scale))
    var out = [UInt8](repeating: 0, count: w * h)
    luma.withUnsafeBufferPointer { src in
        for ny in 0..<h {
            let sy0 = ny * height / h
            let sy1 = max(sy0 + 1, (ny + 1) * height / h)
            for nx in 0..<w {
                let sx0 = nx * width / w
                let sx1 = max(sx0 + 1, (nx + 1) * width / w)
                var sum = 0, cnt = 0
                var yy = sy0
                while yy < sy1 {
                    let row = yy * width
                    var xx = sx0
                    while xx < sx1 { sum += Int(src[row + xx]); cnt += 1; xx += 1 }
                    yy += 1
                }
                out[ny * w + nx] = UInt8(clamping: sum / max(1, cnt))
            }
        }
    }
    return (out, w, h)
}

/// 统一抖动入口（预览与拍照共用，保证观感一致）
private func applyDither(preset: PixelPreset, luma: [UInt8], out: inout [UInt8], width: Int, height: Int, threshold: UInt8) {
    // 先提升对比：压黑暗部、提亮亮部，避免误差扩散结果发灰发白（更接近 BitCam 的硬朗黑白）
    var lu = luma
    let k = 1.4
    for i in 0..<lu.count {
        lu[i] = UInt8(clamping: Int((Double(lu[i]) - 128.0) * k + 128.0))
    }
    switch preset {
    case .clean:  thresholdToBinary(luma: lu, out: &out, width: width, height: height, threshold: threshold)
    case .grit:   floydSteinberg(luma: lu, out: &out, width: width, height: height, threshold: threshold)
    case .poster: orderedDither(luma: lu, out: &out, width: width, height: height, threshold: threshold, strength: 48)
    }
}

/// 纯阈值：< threshold → 黑(0)；>= threshold → 白(255)
private func thresholdToBinary(luma: [UInt8], out: inout [UInt8], width: Int, height: Int, threshold: UInt8) {
    let t = Int(threshold)
    let count = width * height
    out.withUnsafeMutableBufferPointer { outPtr in
        luma.withUnsafeBufferPointer { inPtr in
            for i in 0..<count {
                outPtr[i] = (Int(inPtr[i]) < t) ? 0 : 255
            }
        }
    }
}

/// 有序抖动（Bayer 8x8）：强度越大，颗粒越明显
private func orderedDither(luma: [UInt8], out: inout [UInt8], width: Int, height: Int, threshold: UInt8, strength: Int) {
    // 经典 Bayer 8x8，值域 0..63
    let bayer8: [Int] = [
        0, 48, 12, 60, 3, 51, 15, 63,
        32, 16, 44, 28, 35, 19, 47, 31,
        8, 56, 4, 52, 11, 59, 7, 55,
        40, 24, 36, 20, 43, 27, 39, 23,
        2, 50, 14, 62, 1, 49, 13, 61,
        34, 18, 46, 30, 33, 17, 45, 29,
        10, 58, 6, 54, 9, 57, 5, 53,
        42, 26, 38, 22, 41, 25, 37, 21
    ]

    let baseT = Int(threshold)
    let s = max(0, min(strength, 128))
    let count = width * height

    out.withUnsafeMutableBufferPointer { outPtr in
        luma.withUnsafeBufferPointer { inPtr in
            for i in 0..<count {
                let x = i % width
                let y = i / width
                let b = bayer8[(y & 7) * 8 + (x & 7)] // 0..63
                // 将 bayer 偏移映射到 [-s/2, +s/2]
                let offset = ((b - 31) * s) / 64
                let t = baseT + offset
                outPtr[i] = (Int(inPtr[i]) < t) ? 0 : 255
            }
        }
    }
}

/// Floyd–Steinberg 误差扩散抖动：全分辨率，用黑白点疏密表现灰阶层次（BitCam 经典 1-bit 观感）
private func floydSteinberg(luma: [UInt8], out: inout [UInt8], width: Int, height: Int, threshold: UInt8) {
    // 误差扩散对“比较阈值”几乎免疫（误差会自动补偿密度），
    // 因此把滑杆映射成亮度偏置：高阈值=更暗、低阈值=更亮，比较点固定 128。
    let bias = 128 - Int(threshold)
    var buf = [Int](repeating: 0, count: width * height)
    for i in 0..<(width * height) { buf[i] = Int(luma[i]) + bias }

    buf.withUnsafeMutableBufferPointer { b in
        out.withUnsafeMutableBufferPointer { o in
            for y in 0..<height {
                let row = y * width
                for x in 0..<width {
                    let i = row + x
                    let old = b[i]
                    let new = old < 128 ? 0 : 255
                    o[i] = UInt8(new)
                    let err = old - new
                    if err != 0 {
                        if x + 1 < width { b[i + 1] += err * 7 / 16 }
                        if y + 1 < height {
                            let down = i + width
                            if x > 0 { b[down - 1] += err * 3 / 16 }
                            b[down] += err * 5 / 16
                            if x + 1 < width { b[down + 1] += err * 1 / 16 }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - CGImage

private func makeGrayCGImage(bytes: [UInt8], width: Int, height: Int) -> CGImage? {
    let cfData = Data(bytes).withUnsafeBytes { ptr -> CFData in
        CFDataCreate(kCFAllocatorDefault, ptr.bindMemory(to: UInt8.self).baseAddress!, bytes.count)
    }
    guard let provider = CGDataProvider(data: cfData) else { return nil }

    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: 0),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}
