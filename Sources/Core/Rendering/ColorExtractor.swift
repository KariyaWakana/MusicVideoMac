import Cocoa
import SwiftUI

struct ColorExtractor {
    
    struct QuantizedColor: Hashable {
        let r: UInt8
        let g: UInt8
        let b: UInt8
        
        var cgColor: CGColor {
            // Shift back to get the center of the bucket for more accurate representation
            CGColor(red: CGFloat(r | 0x08) / 255.0, green: CGFloat(g | 0x08) / 255.0, blue: CGFloat(b | 0x08) / 255.0, alpha: 1.0)
        }
    }
    
    /// Extracts colors that occupy at least a certain percentage of the image area
    static func extractDominantColors(from image: NSImage, threshold: Double = 0.05) -> [CGColor] {
        let size = CGSize(width: 64, height: 64)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * Int(size.width)
        let bitsPerComponent = 8
        
        var rawData = [UInt8](repeating: 0, count: Int(size.width * size.height) * bytesPerPixel)
        
        guard let context = CGContext(data: &rawData,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: bitsPerComponent,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            return []
        }
        
        // Draw the image into the small context to downsample
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        
        var frequencyMap: [QuantizedColor: Int] = [:]
        let totalPixels = Int(size.width * size.height)
        
        for i in 0..<totalPixels {
            let offset = i * bytesPerPixel
            let r = rawData[offset]
            let g = rawData[offset + 1]
            let b = rawData[offset + 2]
            let a = rawData[offset + 3]
            
            // Skip fully transparent pixels
            if a < 128 { continue }
            
            // Quantize: Drop the lower 4 bits to group visually similar colors
            let quantized = QuantizedColor(r: r & 0xF0, g: g & 0xF0, b: b & 0xF0)
            frequencyMap[quantized, default: 0] += 1
        }
        
        let minCount = Int(Double(totalPixels) * threshold)
        
        let dominantColors = frequencyMap
            .filter { $0.value >= minCount }
            .sorted { $0.value > $1.value }
            .map { $0.key.cgColor }
        
        if dominantColors.isEmpty {
            // Fallback to the most frequent color if none met the threshold
            if let maxColor = frequencyMap.max(by: { $0.value < $1.value })?.key.cgColor {
                return [maxColor]
            }
            return [CGColor.black]
        }
        
        return dominantColors
    }
    
    /// Generates a high-contrast complementary color for text, based on the given background
    static func complementaryTextColor(for bgCGColor: CGColor) -> CGColor {
        guard let nsColor = NSColor(cgColor: bgCGColor)?.usingColorSpace(.sRGB) else {
            return NSColor.white.cgColor
        }
        
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // Randomly shift hue by roughly 180 degrees (150~210 deg) for contrast
        let hueShift = CGFloat.random(in: 0.4...0.6)
        var newHue = hue + hueShift
        if newHue > 1.0 { newHue -= 1.0 }
        
        // Ensure contrast via brightness check
        var newBrightness: CGFloat
        if brightness > 0.5 {
            // If background is light, force text to be dark
            newBrightness = CGFloat.random(in: 0.1...0.3)
        } else {
            // If background is dark, force text to be bright
            newBrightness = CGFloat.random(in: 0.8...1.0)
        }
        
        // Retain some vibrancy, unless background is completely grayscale
        let newSaturation = saturation < 0.1 ? 0.0 : CGFloat.random(in: 0.5...1.0)
        
        return NSColor(hue: newHue, saturation: newSaturation, brightness: newBrightness, alpha: 1.0).cgColor
    }
}
