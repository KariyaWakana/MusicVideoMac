import SwiftUI

struct LayoutSettingsForm: View {
    @Environment(AppViewModel.self) var viewModel
    
    // Appearance Settings
    @AppStorage("layoutMode") private var layoutMode: String = "Left"
    @AppStorage("verticalAlignment") private var verticalAlignment: String = "Center"
    @AppStorage("metadataPosition") private var metadataPosition: String = "Top"
    @AppStorage("isCompilation") private var isCompilation: Bool = false
    @AppStorage("trackNumberStyle") private var trackNumberStyle: Int = 0
    @AppStorage("coverScale") private var coverScale: Double = 1.0
    
    @AppStorage("fontFamily") private var fontFamily: String = "Lexend"
    @AppStorage("customFontName") private var customFontName: String = ""
    @AppStorage("titleFontSize") private var titleFontSize: Double = 64.0
    @AppStorage("subtitleFontSize") private var subtitleFontSize: Double = 20.0
    @AppStorage("trackFontSize") private var trackFontSize: Double = 32.0
    
    @AppStorage("useCustomColors") private var useCustomColors: Bool = false
    @AppStorage("customBgColorR") private var bgR: Double = 0.2
    @AppStorage("customBgColorG") private var bgG: Double = 0.2
    @AppStorage("customBgColorB") private var bgB: Double = 0.2
    
    @AppStorage("customTextColorR") private var textR: Double = 1.0
    @AppStorage("customTextColorG") private var textG: Double = 1.0
    @AppStorage("customTextColorB") private var textB: Double = 1.0
    
    @State private var fontPickerDelegate = FontPickerDelegate()
    
    enum FocusField { case form }
    @FocusState private var focusedField: FocusField?
    
    var body: some View {
        Form {
            Section {
                Picker("Cover Position:", selection: $layoutMode) {
                    Text("Cover Left").tag("Left")
                    Text("Cover Center (Triptych)").tag("Center")
                    Text("Cover Right").tag("Right")
                }
                
                Picker("Vertical Alignment:", selection: $verticalAlignment) {
                    Text("Top").tag("Top")
                    Text("Center").tag("Center")
                    Text("Bottom").tag("Bottom")
                    if layoutMode != "Center" {
                        Text("Split (Space Between)").tag("Split")
                    }
                }
                .onChange(of: layoutMode) { _, newMode in
                    if newMode == "Center" && verticalAlignment == "Split" {
                        verticalAlignment = "Center" // Fallback if Center mode hides Split
                    }
                }
                
                Picker("Title Position:", selection: $metadataPosition) {
                    Text(layoutMode == "Center" ? "Title Above Cover" : "Title Above Tracks").tag("Top")
                    Text(layoutMode == "Center" ? "Title Below Cover" : "Title Below Tracks").tag("Bottom")
                }
                Toggle("Compilation Album (Show Track Artists)", isOn: $isCompilation)
                
                Picker("Track Numbers:", selection: $trackNumberStyle) {
                    Text("None").tag(0)
                    Text("01 02 03").tag(1)
                    Text("1. 2. 3.").tag(2)
                    Text("I II III").tag(3)
                }
                
                HStack {
                    Label("Cover Scale", systemImage: "photo")
                    Slider(value: $coverScale, in: 0.5...1.5, step: 0.1)
                    Text(String(format: "%.1fx", coverScale)).frame(width: 40)
                }
            } header: { Text("Layout & Alignment").font(.headline) }
            
            Section {
                Picker("Font Family:", selection: $fontFamily) {
                    Text("Lexend").tag("Lexend")
                    Text("System (San Francisco)").tag("System")
                    Text("Helvetica").tag("Helvetica")
                    Text("PingFang SC").tag("PingFang SC")
                    Text("Toppan Bunkyu Gothic").tag("ToppanBunkyuGothic-Regular")
                    Text("Custom...").tag("Custom")
                }
                
                if fontFamily == "Custom" {
                    HStack {
                        Text(customFontName.isEmpty ? "No Font Selected" : customFontName)
                            .foregroundColor(customFontName.isEmpty ? .secondary : .primary)
                        Spacer()
                        Button("Choose Font...") {
                            openFontPanel()
                        }
                    }
                }
                
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        NumericSlider(title: "Title Size", systemImage: "textformat.size.larger", value: $titleFontSize, range: 20...120, appStorageKey: "titleFontSize", defaultValue: 64.0, viewModel: viewModel)
                        if viewModel.isTitleOverflowing(titleFontSize: titleFontSize, subtitleFontSize: subtitleFontSize, trackFontSize: trackFontSize, fontFamily: fontFamily, layoutMode: layoutMode, trackNumberStyle: trackNumberStyle, isCompilation: isCompilation, coverScale: coverScale) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                                Text("Title may be truncated").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Button("Auto Fit") {
                                    titleFontSize = viewModel.autoFitTitle(currentSize: titleFontSize, subtitleFontSize: subtitleFontSize, trackFontSize: trackFontSize, fontFamily: fontFamily, layoutMode: layoutMode, trackNumberStyle: trackNumberStyle, isCompilation: isCompilation, coverScale: coverScale)
                                }.font(.caption).buttonStyle(.plain).foregroundColor(.accentColor)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        NumericSlider(title: "Artist Size", systemImage: "textformat.size", value: $subtitleFontSize, range: 20...80, appStorageKey: "subtitleFontSize", defaultValue: 20.0, viewModel: viewModel)
                        if viewModel.isSubtitleOverflowing(titleFontSize: titleFontSize, subtitleFontSize: subtitleFontSize, trackFontSize: trackFontSize, fontFamily: fontFamily, layoutMode: layoutMode, trackNumberStyle: trackNumberStyle, isCompilation: isCompilation, coverScale: coverScale) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                                Text("Artist/Date may be truncated").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Button("Auto Fit") {
                                    subtitleFontSize = viewModel.autoFitSubtitle(currentSize: subtitleFontSize, titleFontSize: titleFontSize, trackFontSize: trackFontSize, fontFamily: fontFamily, layoutMode: layoutMode, trackNumberStyle: trackNumberStyle, isCompilation: isCompilation, coverScale: coverScale)
                                }.font(.caption).buttonStyle(.plain).foregroundColor(.accentColor)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        NumericSlider(title: "Track Size", systemImage: "textformat.size.smaller", value: $trackFontSize, range: 15...60, appStorageKey: "trackFontSize", defaultValue: 32.0, viewModel: viewModel)
                        if viewModel.isTrackOverflowing(titleFontSize: titleFontSize, subtitleFontSize: subtitleFontSize, trackFontSize: trackFontSize, fontFamily: fontFamily, layoutMode: layoutMode, trackNumberStyle: trackNumberStyle, isCompilation: isCompilation, coverScale: coverScale) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                                Text("Some tracks may be truncated").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Button("Auto Fit") {
                                    trackFontSize = viewModel.autoFitTracks(currentSize: trackFontSize, titleFontSize: titleFontSize, subtitleFontSize: subtitleFontSize, fontFamily: fontFamily, layoutMode: layoutMode, trackNumberStyle: trackNumberStyle, isCompilation: isCompilation, coverScale: coverScale)
                                }.font(.caption).buttonStyle(.plain).foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            } header: { Text("Typography").font(.headline) }
            
            Section {
                Toggle("Override Auto Colors", isOn: $useCustomColors)
                
                if useCustomColors {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Background Color")
                            Spacer()
                            MacColorPicker(selection: Binding(get: {
                                NSColor(red: bgR, green: bgG, blue: bgB, alpha: 1.0)
                            }, set: { newColor in
                                if let nsColor = newColor.usingColorSpace(.sRGB) {
                                    bgR = Double(nsColor.redComponent)
                                    bgG = Double(nsColor.greenComponent)
                                    bgB = Double(nsColor.blueComponent)
                                }
                            }))
                            .frame(width: 50, height: 25)
                        }
                        
                        Button(action: swapColors) {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        
                        HStack {
                            Text("Text Color")
                            Spacer()
                            MacColorPicker(selection: Binding(get: {
                                NSColor(red: textR, green: textG, blue: textB, alpha: 1.0)
                            }, set: { newColor in
                                if let nsColor = newColor.usingColorSpace(.sRGB) {
                                    textR = Double(nsColor.redComponent)
                                    textG = Double(nsColor.greenComponent)
                                    textB = Double(nsColor.blueComponent)
                                }
                            }))
                            .frame(width: 50, height: 25)
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.top, 5)
                    
                    if let cover = viewModel.coverImage {
                        Button("Extract Recommended Colors from Cover") {
                            extractColors(from: cover)
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 5)
                    }
                }
            } header: { Text("Colors").font(.headline) }
            
            Section {
                HStack(spacing: 15) {
                    Button("Save Current as Default") {
                        saveAsDefault()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Restore Default") {
                        restoreUserDefault()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 5)
                
                Button("Factory Reset") {
                    restoreFactoryDefaults()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .center)
            } header: { Text("Presets").font(.headline) }
        }
        .formStyle(.grouped)
        .focusable()
        .focusEffectDisabled()
        .focused($focusedField, equals: .form)
        .defaultFocus($focusedField, .form)
        .onAppear {
            migrateLegacySettings()
        }
    }
    
    private func migrateLegacySettings() {
        if metadataPosition == "Split" {
            verticalAlignment = "Split"
            metadataPosition = "Top"
        }
    }
    
    private func openFontPanel() {
        fontPickerDelegate.onFontSelected = { fontName in
            customFontName = fontName
        }
        NSFontManager.shared.target = fontPickerDelegate
        NSFontManager.shared.orderFrontFontPanel(nil)
    }
    
    private func swapColors() {
        let tempR = bgR, tempG = bgG, tempB = bgB
        bgR = textR; bgG = textG; bgB = textB
        textR = tempR; textG = tempG; textB = tempB
    }
    
    private func extractColors(from image: NSImage) {
        // 1. Extract dominant colors (>5% area)
        let dominantColors = ColorExtractor.extractDominantColors(from: image, threshold: 0.05)
        
        // 2. Randomly select one as background
        guard let bgCGColor = dominantColors.randomElement() else { return }
        
        // 3. Generate high contrast text color
        let textCGColor = ColorExtractor.complementaryTextColor(for: bgCGColor)
        
        // 4. Update UI state
        if let bgNSColor = NSColor(cgColor: bgCGColor)?.usingColorSpace(.sRGB),
           let textNSColor = NSColor(cgColor: textCGColor)?.usingColorSpace(.sRGB) {
            bgR = Double(bgNSColor.redComponent)
            bgG = Double(bgNSColor.greenComponent)
            bgB = Double(bgNSColor.blueComponent)
            
            textR = Double(textNSColor.redComponent)
            textG = Double(textNSColor.greenComponent)
            textB = Double(textNSColor.blueComponent)
            
            // Automatically turn on custom colors
            useCustomColors = true
        }
    }
    
    
    private let presetKeys = ["layoutMode", "verticalAlignment", "metadataPosition", "isCompilation", "trackNumberStyle", "coverScale", "fontFamily", "customFontName", "titleFontSize", "subtitleFontSize", "trackFontSize", "useCustomColors", "customBgColorR", "customBgColorG", "customBgColorB", "customTextColorR", "customTextColorG", "customTextColorB"]
    
    private func saveAsDefault() {
        let defaults = UserDefaults.standard
        for key in presetKeys {
            defaults.set(defaults.object(forKey: key), forKey: "preset_\(key)")
        }
    }
    
    private func restoreUserDefault() {
        let defaults = UserDefaults.standard
        for key in presetKeys {
            if let val = defaults.object(forKey: "preset_\(key)") {
                defaults.set(val, forKey: key)
            }
        }
    }
    
    private func restoreFactoryDefaults() {
        layoutMode = "Left"
        verticalAlignment = "Center"
        metadataPosition = "Top"
        isCompilation = false
        trackNumberStyle = 0
        coverScale = 1.0
        fontFamily = "Lexend"
        customFontName = ""
        titleFontSize = 64.0
        subtitleFontSize = 20.0
        trackFontSize = 32.0
        useCustomColors = false
    }
}

class FontPickerDelegate: NSObject {
    var onFontSelected: ((String) -> Void)?
    
    @objc func changeFont(_ sender: NSFontManager) {
        let newFont = sender.convert(NSFont.systemFont(ofSize: 12))
        // We use fontName (PostScript name) since SwiftUI's Font.custom prefers it.
        onFontSelected?(newFont.fontName)
    }
}

struct MacColorPicker: NSViewRepresentable {
    @Binding var selection: NSColor
    
    func makeNSView(context: Context) -> NSColorWell {
        print("🌈 [MacColorPicker] makeNSView: Creating NSColorWell instance")
        let colorWell = NSColorWell()
        colorWell.target = context.coordinator
        colorWell.action = #selector(Coordinator.colorChanged(_:))
        return colorWell
    }
    
    func updateNSView(_ nsView: NSColorWell, context: Context) {
        // print("🌈 [MacColorPicker] updateNSView: Updating color to \(selection)")
        nsView.color = selection
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: MacColorPicker
        init(_ parent: MacColorPicker) {
            self.parent = parent
        }
        @objc func colorChanged(_ sender: NSColorWell) {
            print("🌈 [MacColorPicker] colorChanged: User selected new color -> \(sender.color)")
            parent.selection = sender.color
        }
    }
}
