import Cocoa

let family = "Lexend"
let size: CGFloat = 20.0

for weight in stride(from: 0.0, through: 0.4, by: 0.1) {
    let traits: [NSFontDescriptor.TraitKey: Any] = [.weight: weight]
    let attr: [NSFontDescriptor.AttributeName: Any] = [
        .name: family,
        .traits: traits
    ]
    let desc = NSFontDescriptor(fontAttributes: attr)
    if let font = NSFont(descriptor: desc, size: size) {
        print("Weight \(weight): width of 'A' is \(font.advancementForGlyph(font.glyph(withName: "A")).width)")
    } else {
        print("Failed to load \(family)")
    }
}
