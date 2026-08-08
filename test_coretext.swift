import Cocoa
import CoreText

func calculatePositions(text: String, font: NSFont) {
    let attrString = NSAttributedString(string: text, attributes: [.font: font])
    let line = CTLineCreateWithAttributedString(attrString)
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]
    
    let nsString = text as NSString
    
    for run in runs {
        let count = CTRunGetGlyphCount(run)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetPositions(run, CFRangeMake(0, count), &positions)
        
        var indices = [CFIndex](repeating: 0, count: count)
        CTRunGetStringIndices(run, CFRangeMake(0, count), &indices)
        
        for i in 0..<count {
            let index = indices[i]
            if i > 0 && indices[i] == indices[i-1] { continue }
            if index >= nsString.length { continue }
            
            let charRange = nsString.rangeOfComposedCharacterSequence(at: index)
            let character = nsString.substring(with: charRange)
            print("Char: '\(character)', X: \(positions[i].x)")
        }
    }
}

let font = NSFont.systemFont(ofSize: 20)
calculatePositions(text: "Hello World", font: font)
