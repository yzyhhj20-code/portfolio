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

        // 预设处理（在 luma 上做）
        switch preset {
        case .clean:
            thresholdToBinary(luma: lumaBuffer, out: &outBuffer, width: width, height: height, threshold: threshold)
        case .grit:
            orderedDither(luma: lumaBuffer, out: &outBuffer, width: width, height: height, threshold: threshold, strength: 48)
        case .poster:
            pixelateThenThreshold(luma: lumaBuffer, out: &outBuffer, width: width, height: height, threshold: threshold, block: 6)
        }

        return makeGrayCGImage(bytes: outBuffer, width: width, height: height)
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

        var out = [UInt8](repeating: 0, count: width * height)
        switch preset {
        case .clean:
            thresholdToBinary(luma: luma, out: &out, width: width, height: height, threshold: threshold)
        case .grit:
            orderedDither(luma: luma, out: &out, width: width, height: height, threshold: threshold, strength: 48)
        case .poster:
            pixelateThenThreshold(luma: luma, out: &out, width: width, height: height, threshold: threshold, block: 8)
        }

        return makeGrayCGImage(bytes: out, width: width, height: height)
    }
}

// MARK: - Helpers (算法)

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

/// 像素块：先做块平均，再阈值（更“海报块面”）
private func pixelateThenThreshold(luma: [UInt8], out: inout [UInt8], width: Int, height: Int, threshold: UInt8, block: Int) {
    let b = max(2, block)
    let t = Int(threshold)

    out.withUnsafeMutableBufferPointer { outPtr in
        luma.withUnsafeBufferPointer { inPtr in
            var y = 0
            while y < height {
                var x = 0
                while x < width {
                    let xEnd = min(x + b, width)
                    let yEnd = min(y + b, height)

                    var sum = 0
                    var count = 0
                    for yy in y..<yEnd {
                        let row = yy * width
                        for xx in x..<xEnd {
                            sum += Int(inPtr[row + xx])
                            count += 1
                        }
                    }
                    let avg = sum / max(1, count)
                    let v: UInt8 = (avg < t) ? 0 : 255

                    for yy in y..<yEnd {
                        let row = yy * width
                        for xx in x..<xEnd {
                            outPtr[row + xx] = v
                        }
                    }

                    x += b
                }
                y += b
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
