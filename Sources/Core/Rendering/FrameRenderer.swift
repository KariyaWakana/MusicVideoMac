import SwiftUI
import CoreImage

class FrameRenderer {
    
    static func extractAverageColor(from nsImage: NSImage) -> Color {
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let ciImage = CIImage(bitmapImageRep: bitmap) else {
            return Color(NSColor.darkGray)
        }
        
        let extentVector = CIVector(x: ciImage.extent.origin.x,
                                    y: ciImage.extent.origin.y,
                                    z: ciImage.extent.size.width,
                                    w: ciImage.extent.size.height)
        
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: extentVector]),
              let outputImage = filter.outputImage else {
            return Color(NSColor.darkGray)
        }
        
        var bitmapArray = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(outputImage, toBitmap: &bitmapArray, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        let r = CGFloat(bitmapArray[0]) / 255.0 * 0.5 // Darken for background
        let g = CGFloat(bitmapArray[1]) / 255.0 * 0.5
        let b = CGFloat(bitmapArray[2]) / 255.0 * 0.5
        
        return Color(red: r, green: g, blue: b)
    }
    
    static func generateFrames(meta: AlbumMetadata, coverImage: NSImage?, resolution: String = "1080p") -> [String] {
        var framePaths: [String] = []
        let bgColor = coverImage != nil ? extractAverageColor(from: coverImage!) : Color(NSColor.windowBackgroundColor)
        
        let is4K = resolution == "4K"
        let is480p = resolution == "480p"
        
        let width: CGFloat = is4K ? 3840 : (is480p ? 854 : 1920)
        let height: CGFloat = is4K ? 2160 : (is480p ? 480 : 1080)
        let scale: CGFloat = is4K ? 2.0 : (is480p ? (480.0 / 1080.0) : 1.0)
        
        for (index, _) in meta.tracks.enumerated() {
            let view = FrameView(meta: meta, coverImage: coverImage, currentTrackIndex: index, bgColor: bgColor, scale: scale)
                .frame(width: width, height: height)
            
            DispatchQueue.main.sync {
                autoreleasepool {
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 1.0
                    
                    if let nsImage = renderer.nsImage,
                       let tiffData = nsImage.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        
                        let filename = NSTemporaryDirectory().appending("frame_\(index).png")
                        try? pngData.write(to: URL(fileURLWithPath: filename))
                        framePaths.append(filename)
                    }
                }
            }
        }
        return framePaths
    }
}

// The SwiftUI View that represents a single frame of the video
struct FrameView: View {
    var meta: AlbumMetadata
    var coverImage: NSImage?
    var currentTrackIndex: Int
    var nextTrackIndex: Int? = nil
    var transitionProgress: Double = 0.0
    var bgColor: Color
    var scale: CGFloat
    
    @AppStorage("layoutMode") private var layoutMode: String = "Left"
    @AppStorage("verticalAlignment") private var verticalAlignment: String = "Center"
    @AppStorage("metadataPosition") private var metadataPosition: String = "Top"
    @AppStorage("isCompilation") private var isCompilation: Bool = false
    @AppStorage("trackNumberStyle") private var trackNumberStyle: Int = 0
    @AppStorage("coverScale") private var coverScale: Double = 1.0
    @AppStorage("fontFamily") private var fontFamily: String = "Lexend"
    @AppStorage("customFontName") private var customFontName: String = ""
    @AppStorage("titleFontSize") private var titleFontSize: Double = 60.0
    @AppStorage("subtitleFontSize") private var subtitleFontSize: Double = 40.0
    @AppStorage("trackFontSize") private var trackFontSize: Double = 35.0
    
    @AppStorage("useCustomColors") private var useCustomColors: Bool = false
    @AppStorage("customBgColorR") private var bgR: Double = 0.2
    @AppStorage("customBgColorG") private var bgG: Double = 0.2
    @AppStorage("customBgColorB") private var bgB: Double = 0.2
    
    @AppStorage("customTextColorR") private var textR: Double = 1.0
    @AppStorage("customTextColorG") private var textG: Double = 1.0
    @AppStorage("customTextColorB") private var textB: Double = 1.0
    
    var effectiveBgColor: Color {
        if useCustomColors {
            return Color(red: bgR, green: bgG, blue: bgB)
        }
        return bgColor
    }
    
    private var effectiveTextColor: Color {
        useCustomColors ? Color(red: textR, green: textG, blue: textB) : Color(NSColor.labelColor)
    }
    
    private func intToRoman(_ number: Int) -> String {
        let romanValues = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
        ]
        var num = number
        var result = ""
        for (value, numeral) in romanValues {
            while num >= value {
                result += numeral
                num -= value
            }
        }
        return result
    }
    
    private func formattedTitle(for track: Track, index: Int) -> String {
        let baseTitle = track.title
        let trackIndex = index + 1
        var safeTitle = ""
        switch trackNumberStyle {
        case 1: safeTitle = String(format: "%02d. %@", trackIndex, baseTitle)
        case 2: safeTitle = "\(trackIndex). \(baseTitle)"
        case 3: safeTitle = "\(intToRoman(trackIndex)) \(baseTitle)"
        default: safeTitle = baseTitle
        }
        
        let maxLength = 80
        if safeTitle.count > maxLength {
            return String(safeTitle.prefix(maxLength)) + "..."
        }
        return safeTitle
    }
    
    private func formattedArtistSuffix(for track: Track) -> String {
        let shouldShowArtist = (isCompilation && track.artist != nil) || (!isCompilation && track.artist != nil && !(track.artist?.isEmpty ?? true) && track.artist != meta.artist)
        if shouldShowArtist, let artistStr = track.artist {
            return " - " + artistStr
        }
        return ""
    }
    
    private func effectiveFontFamilyName() -> String {
        fontFamily == "Custom" ? (customFontName.isEmpty ? "System" : customFontName) : fontFamily
    }
    
    private var cjkLanguageCode: String? {
        switch meta.cjkVariant {
        case "SC": return "zh-Hans"
        case "TC": return "zh-Hant"
        case "JP": return "ja"
        case "KR": return "ko"
        default: return nil
        }
    }
    
    private func dynamicNSFont(size: CGFloat, weight: Double) -> NSFont {
        let familyName = effectiveFontFamilyName()
        var attributes: [CFString: Any] = [:]
        
        if familyName != "System" && !familyName.isEmpty {
            attributes[kCTFontNameAttribute] = familyName as CFString
            attributes[kCTFontVariationAttribute] = [2003265652: weight]
        } else {
            let normalizedWeight = (weight - 400.0) / 300.0 * 0.4
            let nsWeight = NSFont.Weight(rawValue: normalizedWeight)
            let sysFont = NSFont.systemFont(ofSize: size, weight: nsWeight)
            attributes[kCTFontNameAttribute] = sysFont.fontName as CFString
        }
        
        if let langCode = cjkLanguageCode {
            attributes[kCTLanguageAttributeName] = langCode as CFString
        }
        
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }
    
    private func dynamicFont(size: CGFloat, weight: Double) -> Font {
        return Font(dynamicNSFont(size: size, weight: weight))
    }
    
    private func trackStyle(for index: Int) -> (scale: Double, opacity: Double, weight: Double) {
        let t = transitionProgress * transitionProgress * (3.0 - 2.0 * transitionProgress)
        var scaleMult = 1.0
        var opacity = 0.5
        var weight = 400.0 // Regular
        
        if let next = nextTrackIndex, transitionProgress > 0 {
            if index == currentTrackIndex {
                scaleMult = 1.2 - (0.2 * t)
                opacity = 1.0 - (0.5 * t)
                weight = 700.0 - (300.0 * t)
            } else if index == next {
                scaleMult = 1.0 + (0.2 * t)
                opacity = 0.5 + (0.5 * t)
                weight = 400.0 + (300.0 * t)
            }
        } else {
            if index == currentTrackIndex {
                scaleMult = 1.2
                opacity = 1.0
                weight = 700.0 // Bold
            }
        }
        return (scaleMult, opacity, weight)
    }
    
    var alignment: VerticalAlignment {
        switch verticalAlignment {
        case "Top": return .top
        case "Bottom": return .bottom
        default: return .center
        }
    }
    
    var body: some View {
        ZStack {
            effectiveBgColor.edgesIgnoringSafeArea(.all)
            
            if layoutMode == "Center" {
                HStack(alignment: .center, spacing: 40 * scale) {
                    
                    // Left Tracks (roughly 1/3 width)
                    trackListBlock(startIndex: 0, endIndex: -1, isCenter: true, forceLeft: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Center Cover + Meta (roughly 1/3 width)
                    VStack(spacing: 40 * scale) {
                        if metadataPosition == "Top" {
                            metadataBlock
                            Spacer()
                        }
                        
                        if let cover = coverImage {
                            Image(nsImage: cover)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 600 * scale * coverScale, height: 600 * scale * coverScale)
                                .shadow(color: .black.opacity(0.6), radius: 15 * scale, x: 0, y: 15 * scale)
                        } else {
                            Rectangle()
                                .fill(Color.gray)
                                .frame(width: 600 * scale * coverScale, height: 600 * scale * coverScale)
                                .shadow(color: .black.opacity(0.6), radius: 15 * scale, x: 0, y: 15 * scale)
                        }
                        
                        if metadataPosition != "Top" {
                            Spacer()
                            metadataBlock
                        }
                    }
                    .frame(width: 600 * scale * max(1.0, coverScale)) // stable center width based on cover size
                    
                    // Right Tracks (roughly 1/3 width)
                    trackListBlock(startIndex: 0, endIndex: -1, isCenter: true, forceRight: true)
                        .frame(maxWidth: .infinity, alignment: .leading) // User requested left-aligned text for right tracks too
                }
                .padding(.horizontal, 60 * scale)
                .padding(.vertical, 60 * scale)
            } else {
                HStack(alignment: alignment, spacing: 80 * scale) {
                    if layoutMode == "Right" {
                        textContent.frame(maxWidth: .infinity, alignment: .leading)
                        coverContent
                    } else {
                        // Default Left
                        coverContent
                        textContent.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 100 * scale)
                .padding(.vertical, 80 * scale)
            }
        }
        .frame(maxHeight: .infinity)
        .environment(\.locale, cjkLanguageCode != nil ? Locale(identifier: cjkLanguageCode!) : Locale.current)
    }
    
    @ViewBuilder
    var metadataBlock: some View {
        let isCenter = layoutMode == "Center"
        VStack(alignment: isCenter ? .center : .leading, spacing: 10 * scale) {
            Text(meta.title)
                .font(.custom(effectiveFontFamilyName(), size: CGFloat(titleFontSize) * scale).weight(.bold))
                .foregroundColor(effectiveTextColor)
                .lineLimit(2)
                .multilineTextAlignment(isCenter ? .center : .leading)
            
            let displayArtist = isCompilation ? "Various Artists" : meta.artist
            Text("\(displayArtist) • \(meta.year) • \(meta.genre)")
                .font(.custom(effectiveFontFamilyName(), size: CGFloat(subtitleFontSize) * scale).weight(.medium))
                .foregroundColor(effectiveTextColor.opacity(0.7))
        }
    }
    
    @ViewBuilder
    var coverContent: some View {
        if let cover = coverImage {
            Image(nsImage: cover)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 800 * scale * coverScale, height: 800 * scale * coverScale)
                .clipShape(RoundedRectangle(cornerRadius: 16 * scale))
                .overlay(
                    RoundedRectangle(cornerRadius: 16 * scale)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1 * scale)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16 * scale)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1 * scale)
                        .blendMode(.overlay)
                )
                // macOS native stacked shadow
                .shadow(color: .black.opacity(0.3), radius: 3 * scale, x: 0, y: 2 * scale)   // Contact shadow
                .shadow(color: .black.opacity(0.15), radius: 12 * scale, x: 0, y: 8 * scale)  // Mid shadow
                .shadow(color: .black.opacity(0.1), radius: 40 * scale, x: 0, y: 25 * scale) // Ambient deep shadow
        } else {
            Rectangle()
                .fill(Color.gray)
                .frame(width: 800 * scale * coverScale, height: 800 * scale * coverScale)
                .clipShape(RoundedRectangle(cornerRadius: 16 * scale))
                .shadow(color: .black.opacity(0.3), radius: 3 * scale, x: 0, y: 2 * scale)
                .shadow(color: .black.opacity(0.1), radius: 40 * scale, x: 0, y: 25 * scale)
        }
    }
    
    @ViewBuilder
    var textContent: some View {
        VStack(alignment: .leading, spacing: 30 * scale) {
            if metadataPosition == "Top" {
                metadataBlock
                trackListBlock(startIndex: 0, endIndex: -1, isCenter: false)
            } else if metadataPosition == "Bottom" {
                trackListBlock(startIndex: 0, endIndex: -1, isCenter: false)
                metadataBlock
            } else {
                metadataBlock
                Spacer()
                trackListBlock(startIndex: 0, endIndex: -1, isCenter: false)
            }
        }
    }
    
    @ViewBuilder
    private func trackListBlock(startIndex: Int, endIndex: Int, isCenter: Bool, forceLeft: Bool = false, forceRight: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            let maxTracks = isCenter ? 24 : 12 // 24 tracks per page (12 per side) in Triptych mode
            let currentPage = currentTrackIndex / maxTracks
            let nextPage = (nextTrackIndex ?? currentTrackIndex) / maxTracks
            
            // Current Page
            let start1 = currentPage * maxTracks
            let end1 = min(start1 + maxTracks, meta.tracks.count)
            
            renderTrackGroup(start: start1, end: end1, isCenter: isCenter, forceLeft: forceLeft, forceRight: forceRight)
                .opacity(currentPage != nextPage ? 1.0 - transitionProgress : 1.0)
            
            // Next Page (crossfade)
            if currentPage != nextPage {
                let start2 = nextPage * maxTracks
                let end2 = min(start2 + maxTracks, meta.tracks.count)
                
                renderTrackGroup(start: start2, end: end2, isCenter: isCenter, forceLeft: forceLeft, forceRight: forceRight)
                    .opacity(transitionProgress)
            }
        }
    }
    
    @ViewBuilder
    private func renderTrackGroup(start: Int, end: Int, isCenter: Bool, forceLeft: Bool, forceRight: Bool) -> some View {
        if isCenter {
            let total = end - start
            let leftCount = (total + 1) / 2
            let leftEnd = start + leftCount
            
            if forceLeft {
                VStack(alignment: .leading, spacing: 15 * scale) {
                    ForEach(start..<leftEnd, id: \.self) { i in
                        singleTrackRow(index: i, isCenter: isCenter)
                    }
                }
            } else if forceRight {
                VStack(alignment: .leading, spacing: 15 * scale) {
                    ForEach(leftEnd..<end, id: \.self) { i in
                        singleTrackRow(index: i, isCenter: isCenter)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 15 * scale) {
                ForEach(start..<end, id: \.self) { i in
                    singleTrackRow(index: i, isCenter: isCenter)
                }
            }
        }
    }
    
    @ViewBuilder
    private func singleTrackRow(index i: Int, isCenter: Bool) -> some View {
        let track = meta.tracks[i]
        let displayTitle = formattedTitle(for: track, index: i)
        let style = trackStyle(for: i)
        let rawProgress = (style.weight - 400.0) / 300.0
        let artistSuffix = formattedArtistSuffix(for: track)
        
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            KeynoteTransitionText(
                text: displayTitle,
                transitionProgress: rawProgress,
                regularFont: dynamicNSFont(size: CGFloat(trackFontSize * 1.2) * scale, weight: 400.0),
                boldFont: dynamicNSFont(size: CGFloat(trackFontSize * 1.2) * scale, weight: 700.0),
                color: effectiveTextColor.opacity(style.opacity)
            )
            
            if !artistSuffix.isEmpty {
                KeynoteTransitionText(
                    text: artistSuffix,
                    transitionProgress: rawProgress,
                    regularFont: dynamicNSFont(size: CGFloat(trackFontSize * 0.8) * scale, weight: 400.0),
                    boldFont: dynamicNSFont(size: CGFloat(trackFontSize * 0.8) * scale, weight: 700.0),
                    color: effectiveTextColor.opacity(style.opacity * 0.8)
                )
            }
        }
        .lineLimit(1)
        .drawingGroup()
        .scaleEffect(style.scale / 1.2, anchor: .leading)
    }
}

// MARK: - Keynote "Magic Move" Text Component
struct KeynoteTransitionText: View {
    let text: String
    let transitionProgress: Double // 0.0 (Regular) to 1.0 (Bold)
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
            .opacity(0.0) // Hidden Placeholder locks the frame size
            .overlay(
                Canvas { context, size in
                    context.withCGContext { cgContext in
                        // --- 1. OVERRIDE SWIFTUI PIXEL SNAPPING ---
                        cgContext.setAllowsFontSubpixelPositioning(true)
                        cgContext.setShouldSubpixelPositionFonts(true)
                        cgContext.setAllowsFontSubpixelQuantization(false)
                        cgContext.setShouldSubpixelQuantizeFonts(false)
                        
                        // --- 2. FIX COORDINATE SYSTEM ---
                        cgContext.translateBy(x: 0, y: size.height)
                        cgContext.scaleBy(x: 1.0, y: -1.0)
                        
                        let baselineY = -boldFont.descender
                        
                        // --- 3. DRAW GLYPHS MANUALLY ---
                        for item in items {
                            let currentX = item.regX * (1.0 - transitionProgress) + item.boldX * transitionProgress
                            
                            // Draw Regular fading out
                            let regAttrs: [NSAttributedString.Key: Any] = [
                                .font: regularFont,
                                .foregroundColor: nsColor.withAlphaComponent(regAlpha)
                            ]
                            let regAttrString = NSAttributedString(string: item.char, attributes: regAttrs)
                            let regLine = CTLineCreateWithAttributedString(regAttrString)
                            cgContext.textPosition = CGPoint(x: currentX, y: baselineY)
                            CTLineDraw(regLine, cgContext)
                            
                            // Draw Bold fading in
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
