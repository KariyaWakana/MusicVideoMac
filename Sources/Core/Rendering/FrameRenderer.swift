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
            let view = FrameView(meta: meta, coverImage: coverImage, currentTrackIndex: index, bgColor: bgColor, scale: scale, config: FrameViewConfig())
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

struct FrameViewConfig {
    var layoutMode: String
    var verticalAlignment: String
    var metadataPosition: String
    var isCompilation: Bool
    var trackNumberStyle: Int
    var coverScale: Double
    var fontFamily: String
    var customFontName: String
    var titleFontSize: Double
    var subtitleFontSize: Double
    var trackFontSize: Double
    var useCustomColors: Bool
    var bgR: Double
    var bgG: Double
    var bgB: Double
    var textR: Double
    var textG: Double
    var textB: Double
    var discLabelPosition: String
    
    init(layoutMode: String, verticalAlignment: String, metadataPosition: String, isCompilation: Bool, trackNumberStyle: Int, coverScale: Double, fontFamily: String, customFontName: String, titleFontSize: Double, subtitleFontSize: Double, trackFontSize: Double, useCustomColors: Bool, bgR: Double, bgG: Double, bgB: Double, textR: Double, textG: Double, textB: Double, discLabelPosition: String) {
        self.layoutMode = layoutMode
        self.verticalAlignment = verticalAlignment
        self.metadataPosition = metadataPosition
        self.isCompilation = isCompilation
        self.trackNumberStyle = trackNumberStyle
        self.coverScale = coverScale
        self.fontFamily = fontFamily
        self.customFontName = customFontName
        self.titleFontSize = titleFontSize
        self.subtitleFontSize = subtitleFontSize
        self.trackFontSize = trackFontSize
        self.useCustomColors = useCustomColors
        self.bgR = bgR
        self.bgG = bgG
        self.bgB = bgB
        self.textR = textR
        self.textG = textG
        self.textB = textB
        self.discLabelPosition = discLabelPosition
    }
    
    init(defaults: UserDefaults = .standard) {
        layoutMode = defaults.string(forKey: "layoutMode") ?? "Left"
        verticalAlignment = defaults.string(forKey: "verticalAlignment") ?? "Center"
        metadataPosition = defaults.string(forKey: "metadataPosition") ?? "Top"
        isCompilation = defaults.bool(forKey: "isCompilation")
        trackNumberStyle = defaults.integer(forKey: "trackNumberStyle")
        coverScale = defaults.object(forKey: "coverScale") != nil ? defaults.double(forKey: "coverScale") : 1.0
        fontFamily = defaults.string(forKey: "fontFamily") ?? "Lexend"
        customFontName = defaults.string(forKey: "customFontName") ?? ""
        titleFontSize = defaults.object(forKey: "titleFontSize") != nil ? defaults.double(forKey: "titleFontSize") : 60.0
        subtitleFontSize = defaults.object(forKey: "subtitleFontSize") != nil ? defaults.double(forKey: "subtitleFontSize") : 40.0
        trackFontSize = defaults.object(forKey: "trackFontSize") != nil ? defaults.double(forKey: "trackFontSize") : 35.0
        useCustomColors = defaults.bool(forKey: "useCustomColors")
        bgR = defaults.object(forKey: "customBgColorR") != nil ? defaults.double(forKey: "customBgColorR") : 0.2
        bgG = defaults.object(forKey: "customBgColorG") != nil ? defaults.double(forKey: "customBgColorG") : 0.2
        bgB = defaults.object(forKey: "customBgColorB") != nil ? defaults.double(forKey: "customBgColorB") : 0.2
        textR = defaults.object(forKey: "customTextColorR") != nil ? defaults.double(forKey: "customTextColorR") : 1.0
        textG = defaults.object(forKey: "customTextColorG") != nil ? defaults.double(forKey: "customTextColorG") : 1.0
        textB = defaults.object(forKey: "customTextColorB") != nil ? defaults.double(forKey: "customTextColorB") : 1.0
        discLabelPosition = defaults.string(forKey: "discLabelPosition") ?? "Right of Title"
    }
}

// The SwiftUI View that represents a single frame of the video
struct FrameView: View {
    var meta: AlbumMetadata
    var coverImage: NSImage?
    var currentTrackIndex: Int
    var nextTrackIndex: Int? = nil
    var transitionProgress: Double = 0.0
    var isDiscTransition: Bool = false
    var bgColor: Color
    var scale: CGFloat
    var config: FrameViewConfig
    
    func colorForDisc(_ disc: Int?) -> Color {
        guard let disc = disc else { return config.useCustomColors ? Color(red: config.bgR, green: config.bgG, blue: config.bgB) : bgColor }
        let dKey = String(disc)
        if config.useCustomColors, let overrideBg = meta.discBgColors?[dKey], overrideBg.count >= 3 {
            return Color(red: overrideBg[0], green: overrideBg[1], blue: overrideBg[2])
        }
        return config.useCustomColors ? Color(red: config.bgR, green: config.bgG, blue: config.bgB) : bgColor
    }
    
    var effectiveBgColor: Color {
        if let overrideBg = meta.overrideBgColor, overrideBg.count >= 3 {
            return Color(red: overrideBg[0], green: overrideBg[1], blue: overrideBg[2])
        }
        let discNum = (currentTrackIndex >= 0 && currentTrackIndex < meta.tracks.count) ? meta.tracks[currentTrackIndex].discNumber : nil
        return colorForDisc(discNum)
    }
    
    private func colorForTextDisc(_ disc: Int?) -> Color {
        guard let disc = disc else { return config.useCustomColors ? Color(red: config.textR, green: config.textG, blue: config.textB) : Color(NSColor.labelColor) }
        let dKey = String(disc)
        if config.useCustomColors, let overrideText = meta.discTextColors?[dKey], overrideText.count >= 3 {
            return Color(red: overrideText[0], green: overrideText[1], blue: overrideText[2])
        }
        return config.useCustomColors ? Color(red: config.textR, green: config.textG, blue: config.textB) : Color(NSColor.labelColor)
    }
    
    private func blendColors(_ c1: Color, _ c2: Color, progress: Double) -> Color {
        let ns1 = NSColor(c1)
        let ns2 = NSColor(c2)
        let r = ns1.redComponent * (1 - progress) + ns2.redComponent * progress
        let g = ns1.greenComponent * (1 - progress) + ns2.greenComponent * progress
        let b = ns1.blueComponent * (1 - progress) + ns2.blueComponent * progress
        let a = ns1.alphaComponent * (1 - progress) + ns2.alphaComponent * progress
        return Color(red: r, green: g, blue: b, opacity: a)
    }
    
    private var effectiveTextColor: Color {
        if let overrideText = meta.overrideTextColor, overrideText.count >= 3 {
            return Color(red: overrideText[0], green: overrideText[1], blue: overrideText[2])
        }
        
        let track = (currentTrackIndex >= 0 && currentTrackIndex < meta.tracks.count) ? meta.tracks[currentTrackIndex] : nil
        let c1 = colorForTextDisc(track?.discNumber ?? 1)
        
        if isDiscTransition {
            let nextTrack = (nextTrackIndex != nil && nextTrackIndex! >= 0 && nextTrackIndex! < meta.tracks.count) ? meta.tracks[nextTrackIndex!] : nil
            let c2 = colorForTextDisc(nextTrack?.discNumber ?? 1)
            return blendColors(c1, c2, progress: transitionProgress)
        }
        
        return c1
    }
    
    private var transitionOpacity: Double {
        if !isDiscTransition { return 1.0 }
        if transitionProgress < 0.33 {
            return 1.0 - (transitionProgress * 3.0)
        } else if transitionProgress > 0.66 {
            return (transitionProgress - 0.66) * 3.0
        } else {
            return 0.0
        }
    }
    
    private var effectiveDiscStr: String? {
        if let explicit = meta.discTitle { return explicit }
        let uniqueDiscs = Array(Set(meta.tracks.compactMap { $0.discNumber }))
        if uniqueDiscs.count > 1 {
            let displayIndex = (isDiscTransition && transitionProgress > 0.5 && nextTrackIndex != nil) ? nextTrackIndex! : currentTrackIndex
            let track = (displayIndex >= 0 && displayIndex < meta.tracks.count) ? meta.tracks[displayIndex] : nil
            return "Disc \(track?.discNumber ?? 1)"
        }
        return nil
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
        switch config.trackNumberStyle {
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
        let shouldShowArtist = (config.isCompilation && track.artist != nil) || (!config.isCompilation && track.artist != nil && !(track.artist?.isEmpty ?? true) && track.artist != meta.artist)
        if shouldShowArtist, let artistStr = track.artist {
            return " - " + artistStr
        }
        return ""
    }
    
    private func effectiveFontFamilyName() -> String {
        config.fontFamily == "Custom" ? (config.customFontName.isEmpty ? "System" : config.customFontName) : config.fontFamily
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
        switch config.verticalAlignment {
        case "Top": return .top
        case "Bottom": return .bottom
        case "Center", "Split": return .center
        default: return .center
        }
    }
    
    var body: some View {
        let isCenter = config.layoutMode == "Center"
        let track = (currentTrackIndex >= 0 && currentTrackIndex < meta.tracks.count) ? meta.tracks[currentTrackIndex] : nil
        let nextTrack = (nextTrackIndex != nil && nextTrackIndex! >= 0 && nextTrackIndex! < meta.tracks.count) ? meta.tracks[nextTrackIndex!] : nil
        
        ZStack {
            if isDiscTransition, let t1 = track, let t2 = nextTrack {
                // Background color linearly crossfades over the entire transition
                ZStack {
                    colorForDisc(t1.discNumber).opacity(1.0 - transitionProgress)
                    colorForDisc(t2.discNumber).opacity(transitionProgress)
                }.edgesIgnoringSafeArea(.all)
            } else {
                effectiveBgColor.edgesIgnoringSafeArea(.all)
            }
            
            // Text opacity: Always 1.0, elements crossfade their opacities natively
            let textOpacity = 1.0
            Group {
                if isCenter {
                    VStack(spacing: 0) {
                        if config.verticalAlignment == "Bottom" || config.verticalAlignment == "Center" { Spacer() }
                        
                        HStack(alignment: .center, spacing: 40 * scale) {
                            
                            VStack(alignment: .leading, spacing: 20 * scale) {
                                let labelPos = meta.overrideDiscLabelPosition ?? config.discLabelPosition
                                let showDiscText = (effectiveDiscStr != nil && labelPos == "Above Tracks")
                                if showDiscText {
                                    Text(effectiveDiscStr ?? "")
                                        .font(.custom(effectiveFontFamilyName(), size: CGFloat(config.trackFontSize * 1.0) * scale).weight(.bold))
                                        .foregroundColor(effectiveTextColor)
                                        .padding(.bottom, -15 * scale)
                                        .opacity(transitionOpacity)
                                }
                                
                                trackListBlock(startIndex: 0, endIndex: -1, isCenter: true, forceLeft: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            
                            VStack(spacing: 40 * scale) {
                                if config.metadataPosition == "Top" {
                                    metadataBlock
                                }
                                
                                if let cover = coverImage {
                                    Image(nsImage: cover)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 600 * scale * config.coverScale, height: 600 * scale * config.coverScale)
                                        .shadow(color: .black.opacity(0.6), radius: 15 * scale, x: 0, y: 15 * scale)
                                } else {
                                    Rectangle()
                                        .fill(Color.gray)
                                        .frame(width: 600 * scale * config.coverScale, height: 600 * scale * config.coverScale)
                                        .shadow(color: .black.opacity(0.6), radius: 15 * scale, x: 0, y: 15 * scale)
                                }
                                
                                if config.metadataPosition != "Top" {
                                    metadataBlock
                                }
                            }
                            .frame(width: 600 * scale * max(1.0, config.coverScale))
                            
                            VStack(alignment: .leading, spacing: 20 * scale) {
                                let labelPos = meta.overrideDiscLabelPosition ?? config.discLabelPosition
                                let showDiscText = (effectiveDiscStr != nil && labelPos == "Above Tracks")
                                if showDiscText {
                                    Text(effectiveDiscStr ?? "")
                                        .font(.custom(effectiveFontFamilyName(), size: CGFloat(config.trackFontSize * 1.0) * scale).weight(.bold))
                                        .foregroundColor(effectiveTextColor)
                                        .padding(.bottom, -15 * scale)
                                        .opacity(transitionOpacity)
                                }
                                
                                trackListBlock(startIndex: 0, endIndex: -1, isCenter: true, forceRight: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 60 * scale)
                        
                        if config.verticalAlignment == "Top" || config.verticalAlignment == "Center" { Spacer() }
                    }
                    .padding(.vertical, 60 * scale)
                } else {
                    HStack(alignment: alignment, spacing: 80 * scale) {
                        if config.layoutMode == "Right" {
                            textContent.frame(maxWidth: .infinity, alignment: .leading)
                            coverContent
                        } else {
                            coverContent
                            textContent.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 100 * scale)
                    .padding(.vertical, 80 * scale)
                }
            }
            .opacity(textOpacity)
        }
        .frame(maxHeight: .infinity)
        .environment(\.locale, cjkLanguageCode != nil ? Locale(identifier: cjkLanguageCode!) : Locale.current)
    }
    
    @ViewBuilder
    var metadataBlock: some View {
        let isCenter = config.layoutMode == "Center"
        ZStack(alignment: isCenter ? .center : .leading) {
            metadataBlockForTrack(currentTrackIndex)
                .opacity(isDiscTransition ? 1.0 - transitionProgress : 1.0)
            
            if isDiscTransition {
                metadataBlockForTrack(nextTrackIndex ?? currentTrackIndex)
                    .opacity(transitionProgress)
            }
        }
    }
    
    @ViewBuilder
    func metadataBlockForTrack(_ trackIndex: Int) -> some View {
        let isCenter = config.layoutMode == "Center"
        VStack(alignment: isCenter ? .center : .leading, spacing: 10 * scale) {
            let labelPos = meta.overrideDiscLabelPosition ?? config.discLabelPosition
            let uniqueDiscs = Array(Set(meta.tracks.compactMap { $0.discNumber }))
            
            let track = (trackIndex >= 0 && trackIndex < meta.tracks.count) ? meta.tracks[trackIndex] : nil
            let autoDiscStr = "Disc \(track?.discNumber ?? 1)"
            
            let discStr = meta.discTitle ?? (uniqueDiscs.count > 1 ? autoDiscStr : "")
            let showDiscText = (labelPos != "Hidden" && (meta.discTitle != nil || uniqueDiscs.count > 1))
            
            let displayTitle = (showDiscText && labelPos == "Right of Title") ? "\(meta.title) (\(discStr))" :
                               (showDiscText && labelPos == "Left of Title") ? "(\(discStr)) \(meta.title)" :
                               meta.title
            
            Text(displayTitle)
                .font(.custom(effectiveFontFamilyName(), size: CGFloat(config.titleFontSize) * scale).weight(.bold))
                .foregroundColor(effectiveTextColor)
                .lineLimit(2)
                .multilineTextAlignment(isCenter ? .center : .leading)
            
            let displayArtist = config.isCompilation ? "Various Artists" : meta.artist
            let subtitleBase = "\(displayArtist) • \(meta.year) • \(meta.genre)"
            let displaySubtitle = (showDiscText && labelPos == "Subtitle") ? "\(discStr) • \(subtitleBase)" : subtitleBase
            
            Text(displaySubtitle)
                .font(.custom(effectiveFontFamilyName(), size: CGFloat(config.subtitleFontSize) * scale).weight(.medium))
                .foregroundColor(effectiveTextColor.opacity(0.7))
        }
    }
    
    @ViewBuilder
    var coverContent: some View {
        if let cover = coverImage {
            Image(nsImage: cover)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 800 * scale * config.coverScale, height: 800 * scale * config.coverScale)
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
                .shadow(color: .black.opacity(0.3), radius: 3 * scale, x: 0, y: 2 * scale)
                .shadow(color: .black.opacity(0.15), radius: 12 * scale, x: 0, y: 8 * scale)
                .shadow(color: .black.opacity(0.1), radius: 40 * scale, x: 0, y: 25 * scale)
        } else {
            Rectangle()
                .fill(Color.gray)
                .frame(width: 800 * scale * config.coverScale, height: 800 * scale * config.coverScale)
                .clipShape(RoundedRectangle(cornerRadius: 16 * scale))
                .shadow(color: .black.opacity(0.3), radius: 3 * scale, x: 0, y: 2 * scale)
                .shadow(color: .black.opacity(0.1), radius: 40 * scale, x: 0, y: 25 * scale)
        }
    }
    
    @ViewBuilder
    var textContent: some View {
        let labelPos = meta.overrideDiscLabelPosition ?? config.discLabelPosition
        let showDiscText = (effectiveDiscStr != nil && labelPos == "Above Tracks")
        
        VStack(alignment: .leading, spacing: 30 * scale) {
            if config.metadataPosition == "Top" {
                metadataBlock
                if config.verticalAlignment == "Split" { Spacer() }
                if showDiscText {
                    Text(effectiveDiscStr ?? "")
                        .font(.custom(effectiveFontFamilyName(), size: CGFloat(config.trackFontSize * 1.0) * scale).weight(.bold))
                        .foregroundColor(effectiveTextColor)
                        .padding(.bottom, -15 * scale)
                        .opacity(transitionOpacity)
                }
                trackListBlock(startIndex: 0, endIndex: -1, isCenter: false)
            } else {
                if showDiscText {
                    Text(effectiveDiscStr ?? "")
                        .font(.custom(effectiveFontFamilyName(), size: CGFloat(config.trackFontSize * 1.0) * scale).weight(.bold))
                        .foregroundColor(effectiveTextColor)
                        .padding(.bottom, -15 * scale)
                        .opacity(transitionOpacity)
                }
                trackListBlock(startIndex: 0, endIndex: -1, isCenter: false)
                if config.verticalAlignment == "Split" { Spacer() }
                metadataBlock
            }
        }
    }
    
    private func indicesForDisc(_ discNumber: Int) -> [Int] {
        return meta.tracks.enumerated().filter { ($0.element.discNumber ?? 1) == discNumber }.map { $0.offset }
    }
    
    @ViewBuilder
    private func trackListBlock(startIndex: Int, endIndex: Int, isCenter: Bool, forceLeft: Bool = false, forceRight: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            let maxTracks = isCenter ? 24 : 12
            
            let displayIndex = (isDiscTransition && transitionProgress > 0.5 && nextTrackIndex != nil) ? nextTrackIndex! : currentTrackIndex
            let displayDisc = (displayIndex >= 0 && displayIndex < meta.tracks.count) ? (meta.tracks[displayIndex].discNumber ?? 1) : 1
            
            let indices = indicesForDisc(displayDisc)
            
            let currentPageIndex = indices.firstIndex(of: currentTrackIndex) ?? 0
            let nextPageIndex = indices.firstIndex(of: nextTrackIndex ?? currentTrackIndex) ?? currentPageIndex
            
            let currentPage = currentPageIndex / maxTracks
            let nextPage = nextPageIndex / maxTracks
            
            let isPageTurn = (!isDiscTransition && currentPage != nextPage)
            
            let start1 = currentPage * maxTracks
            let end1 = min(start1 + maxTracks, indices.count)
            let pageIndices1 = Array(indices[start1..<end1])
            
            renderTrackGroup(indices: pageIndices1, isCenter: isCenter, forceLeft: forceLeft, forceRight: forceRight)
                .opacity(isDiscTransition ? transitionOpacity : (isPageTurn ? 1.0 - transitionProgress : 1.0))
            
            if isPageTurn {
                let start2 = nextPage * maxTracks
                let end2 = min(start2 + maxTracks, indices.count)
                let pageIndices2 = Array(indices[start2..<end2])
                
                renderTrackGroup(indices: pageIndices2, isCenter: isCenter, forceLeft: forceLeft, forceRight: forceRight)
                    .opacity(transitionProgress)
            }
        }
    }
    
    @ViewBuilder
    private func renderTrackGroup(indices: [Int], isCenter: Bool, forceLeft: Bool, forceRight: Bool) -> some View {
        if isCenter {
            let total = indices.count
            let leftCount = (total + 1) / 2
            let leftIndices = Array(indices[0..<leftCount])
            let rightIndices = Array(indices[leftCount..<total])
            
            if forceLeft {
                VStack(alignment: .leading, spacing: 15 * scale) {
                    ForEach(leftIndices, id: \.self) { i in
                        singleTrackRow(index: i, isCenter: isCenter)
                    }
                }
            } else if forceRight {
                VStack(alignment: .leading, spacing: 15 * scale) {
                    ForEach(rightIndices, id: \.self) { i in
                        singleTrackRow(index: i, isCenter: isCenter)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 15 * scale) {
                ForEach(indices, id: \.self) { i in
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
                regularFont: dynamicNSFont(size: CGFloat(config.trackFontSize * 1.2) * scale, weight: 400.0),
                boldFont: dynamicNSFont(size: CGFloat(config.trackFontSize * 1.2) * scale, weight: 700.0),
                color: effectiveTextColor.opacity(style.opacity)
            )
            
            if !artistSuffix.isEmpty {
                KeynoteTransitionText(
                    text: artistSuffix,
                    transitionProgress: rawProgress,
                    regularFont: dynamicNSFont(size: CGFloat(config.trackFontSize * 0.8) * scale, weight: 400.0),
                    boldFont: dynamicNSFont(size: CGFloat(config.trackFontSize * 0.8) * scale, weight: 700.0),
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
            .opacity(0.0)
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

struct LiveFrameView: View {
    var meta: AlbumMetadata
    var coverImage: NSImage?
    var currentTrackIndex: Int
    var nextTrackIndex: Int? = nil
    var transitionProgress: Double = 0.0
    var isDiscTransition: Bool = false
    var bgColor: Color
    var scale: CGFloat
    
    @AppStorage("layoutMode") private var layoutMode = "Left"
    @AppStorage("verticalAlignment") private var verticalAlignment = "Center"
    @AppStorage("metadataPosition") private var metadataPosition = "Top"
    @AppStorage("isCompilation") private var isCompilation = false
    @AppStorage("trackNumberStyle") private var trackNumberStyle = 1
    @AppStorage("coverScale") private var coverScale: Double = 1.0
    @AppStorage("fontFamily") private var fontFamily = "Lexend"
    @AppStorage("customFontName") private var customFontName = ""
    @AppStorage("titleFontSize") private var titleFontSize: Double = 60.0
    @AppStorage("subtitleFontSize") private var subtitleFontSize: Double = 40.0
    @AppStorage("trackFontSize") private var trackFontSize: Double = 35.0
    @AppStorage("useCustomColors") private var useCustomColors = false
    @AppStorage("customBgColorR") private var customBgColorR = 0.2
    @AppStorage("customBgColorG") private var customBgColorG = 0.2
    @AppStorage("customBgColorB") private var customBgColorB = 0.2
    @AppStorage("customTextColorR") private var customTextColorR = 1.0
    @AppStorage("customTextColorG") private var customTextColorG = 1.0
    @AppStorage("customTextColorB") private var customTextColorB = 1.0
    @AppStorage("discLabelPosition") private var discLabelPosition = "Right of Title"
    
    var body: some View {
        let config = FrameViewConfig(
            layoutMode: layoutMode,
            verticalAlignment: verticalAlignment,
            metadataPosition: metadataPosition,
            isCompilation: isCompilation,
            trackNumberStyle: trackNumberStyle,
            coverScale: coverScale,
            fontFamily: fontFamily,
            customFontName: customFontName,
            titleFontSize: titleFontSize,
            subtitleFontSize: subtitleFontSize,
            trackFontSize: trackFontSize,
            useCustomColors: useCustomColors,
            bgR: customBgColorR, bgG: customBgColorG, bgB: customBgColorB,
            textR: customTextColorR, textG: customTextColorG, textB: customTextColorB,
            discLabelPosition: discLabelPosition
        )
        
        FrameView(
            meta: meta,
            coverImage: coverImage,
            currentTrackIndex: currentTrackIndex,
            nextTrackIndex: nextTrackIndex,
            transitionProgress: transitionProgress,
            isDiscTransition: isDiscTransition,
            bgColor: bgColor,
            scale: scale,
            config: config
        )
    }
}
