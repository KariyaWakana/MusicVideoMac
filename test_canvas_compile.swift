import SwiftUI
import CoreText
import Cocoa

struct KeynoteTransitionText: View {
    let text: String
    let transitionProgress: Double
    let regularFont: NSFont
    let boldFont: NSFont
    let color: Color
    
    struct CharLayout {
        let id: Int
        let char: String
        let regX: CGFloat
        let boldX: CGFloat
    }
    
    var layouts: [CharLayout] {
        let regPos = calculatePositions(text: text, font: regularFont)
        let boldPos = calculatePositions(text: text, font: boldFont)
        
        var result: [CharLayout] = []
        let count = min(regPos.count, boldPos.count)
        for i in 0..<count {
            result.append(CharLayout(id: i, char: regPos[i].char, regX: regPos[i].xOffset, boldX: boldPos[i].xOffset))
        }
        return result
    }
    
    var body: some View {
        let items = layouts
        let nsColor = NSColor(color)
        let baseAlpha = nsColor.alphaComponent
        let regAlpha = baseAlpha * (1.0 - transitionProgress)
        let boldAlpha = baseAlpha * transitionProgress
        
        Text(text)
            .font(Font(boldFont))
            .opacity(0.0) // Hidden Placeholder
            .overlay(
                Canvas { context, size in
                    context.withCGContext { cgContext in
                        cgContext.setAllowsFontSubpixelPositioning(true)
                        cgContext.setShouldSubpixelPositionFonts(true)
                        cgContext.setAllowsFontSubpixelQuantization(false)
                        cgContext.setShouldSubpixelQuantizeFonts(false)
                        
                        cgContext.translateBy(x: 0, y: size.height)
                        cgContext.scaleBy(x: 1.0, y: -1.0)
                        
                        let baselineY = -boldFont.descender
                        
                        for item in items {
                            let currentX = item.regX * (1.0 - transitionProgress) + item.boldX * transitionProgress
                            
                            let regAttrs: [NSAttributedString.Key: Any] = [
                                .font: regularFont,
                                .foregroundColor: nsColor.withAlphaComponent(regAlpha)
                            ]
                            let regAttrString = NSAttributedString(string: item.char, attributes: regAttrs)
                            let regLine = CTLineCreateWithAttributedString(regAttrString)
                            cgContext.textPosition = CGPoint(x: currentX, y: baselineY)
                            CTLineDraw(regLine, cgContext)
                            
                            let boldAttrs: [NSAttributedString.Key: Any] = [
                                .font: boldFont,
                                .foregroundColor: nsColor.withAlphaComponent(boldAlpha)
                            ]
                            let boldAttrString = NSAttributedString(string: item.char, attributes: boldAttrs)
                            let boldLine = CTLineCreateWithAttributedString(boldAttrString)
                            cgContext.textPosition = CGPoint(x: currentX, y: baselineY)
                            CTLineDraw(boldLine, cgContext)
                        }
                    }
                }
            )
    }
    
    private func calculatePositions(text: String, font: NSFont) -> [(char: String, xOffset: CGFloat)] {
        let attrString = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attrString)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        
        var result: [(char: String, xOffset: CGFloat)] = []
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
                result.append((char: character, xOffset: positions[i].x))
            }
        }
        return result
    }
}
