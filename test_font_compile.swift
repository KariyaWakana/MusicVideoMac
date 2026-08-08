import Cocoa
import SwiftUI

func testDynamicFont(size: CGFloat, weight: Double) -> Font {
    let familyName = "Lexend"
    
    if familyName == "System" || familyName.isEmpty {
        let nsWeight = NSFont.Weight(rawValue: weight)
        let nsFont = NSFont.systemFont(ofSize: size, weight: nsWeight)
        return Font(nsFont)
    } else {
        let attributes: [CFString: Any] = [
            kCTFontNameAttribute: familyName,
            kCTFontVariationAttribute: [2003265652: weight]
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let ctFont = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        let nsFont = ctFont as NSFont
        return Font(nsFont)
    }
}
