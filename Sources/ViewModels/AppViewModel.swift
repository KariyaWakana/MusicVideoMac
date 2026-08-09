import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
class AppViewModel {
    var meta = AlbumMetadata()
    var coverImage: NSImage? = nil
    var searchTerm: String = ""
    var statusMessage: String = "Ready to scan CDs or drop a folder."
    var isProcessing: Bool = false
    var renderProgress: Double? = nil
    var isHovering: Bool = false
    var showingFileImporter: Bool = false
    var scanSubfolders: Bool = false
    
    var activeSecurityScopedURL: URL? = nil
    var activeAlbumDirectory: URL? = nil
    
    // Using UserDefaults directly for @Observable integration, as @AppStorage is View-specific
    var videoResolution: String {
        get { UserDefaults.standard.string(forKey: "videoResolution") ?? "1080p" }
    }
    
    var outputFormat: String {
        get { UserDefaults.standard.string(forKey: "outputFormat") ?? "mp4" }
    }
    
    // MARK: - Text Overflow Calculation & Auto-Fit
    
    // The UI font sizes are relative to a normalized 1920x1080 coordinate system.
    // Therefore, the overflow calculation must always use 1920.0 as the base width,
    // regardless of the final export resolution (4K, 480p), because the font sizes
    // scale proportionally with the resolution during rendering.
    func availableTextWidth(layoutMode: String, coverScale: Double) -> CGFloat {
        let width: CGFloat = 1920.0
        if layoutMode == "Center" {
            return width - 120 // 60 padding on each side
        } else {
            // 100 horizontal padding * 2 = 200
            // spacing = 80
            // cover width = 800 * coverScale
            return width - 280.0 - CGFloat(800.0 * coverScale)
        }
    }
    
    func textWidth(for string: String, fontName: String, fontSize: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
        let actualFontName = fontName == "Custom" ? (UserDefaults.standard.string(forKey: "customFontName") ?? "System") : fontName
        var nsFont: NSFont
        if actualFontName == "System" || actualFontName.isEmpty {
            nsFont = NSFont.systemFont(ofSize: fontSize, weight: weight)
        } else {
            nsFont = NSFont(name: actualFontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: weight)
        }
        let attrString = NSAttributedString(string: string, attributes: [.font: nsFont])
        return attrString.size().width
    }
    
    func availableTextHeight(layoutMode: String, coverScale: Double) -> CGFloat {
        let height: CGFloat = 1080.0
        if layoutMode == "Center" {
            // VStack spacing is 60. Cover takes 600 * coverScale.
            return height - 120.0 - 60.0 - CGFloat(600.0 * coverScale)
        } else {
            // Left/Right has 80 vertical padding on top and bottom (160 total)
            return height - 160.0
        }
    }
    
    struct LayoutSimulationResult {
        var titleOverflow: Bool
        var subtitleOverflow: Bool
        var trackOverflow: Bool
    }
    
    func simulateLayout(titleSize: Double, subtitleSize: Double, trackSize: Double, fontFamily: String, layoutMode: String, trackNumberStyle: Int, isCompilation: Bool, coverScale: Double) -> LayoutSimulationResult {
        let availW = availableTextWidth(layoutMode: layoutMode, coverScale: coverScale)
        let availH = availableTextHeight(layoutMode: layoutMode, coverScale: coverScale)
        
        var tOverflow = false
        var sOverflow = false
        var trOverflow = false
        
        // 1. Simulate Title
        let titleText = meta.title
        var titleH: CGFloat = 0
        if !titleText.isEmpty {
            let w = textWidth(for: titleText, fontName: fontFamily, fontSize: CGFloat(titleSize), weight: .bold)
            let lines = w > availW ? 2 : 1
            if w > availW * 2 { tOverflow = true } // Even 2 lines overflow horizontally
            titleH = CGFloat(lines) * CGFloat(titleSize) * 1.2
        }
        
        // 2. Simulate Subtitle
        let subtitleText = "\(meta.artist) \(meta.year)"
        var subtitleH: CGFloat = 0
        if !subtitleText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            let w = textWidth(for: subtitleText, fontName: fontFamily, fontSize: CGFloat(subtitleSize), weight: .medium)
            if w > availW { sOverflow = true }
            subtitleH = CGFloat(subtitleSize) * 1.2
        }
        
        // 3. Simulate Tracks
        var trackH: CGFloat = 0
        if !meta.tracks.isEmpty {
            let maxTracks = layoutMode == "Center" ? 8 : 12
            let trackCount = min(meta.tracks.count, maxTracks)
            
            for i in 0..<trackCount {
                let track = meta.tracks[i]
                var prefix = track.title
                if trackNumberStyle > 0 { prefix = "00. " + prefix }
                
                let w1 = textWidth(for: prefix, fontName: fontFamily, fontSize: CGFloat(trackSize * 1.2), weight: .bold)
                var w2: CGFloat = 0
                
                if isCompilation, let artist = track.artist {
                    w2 = textWidth(for: " - " + artist, fontName: fontFamily, fontSize: CGFloat(trackSize * 0.8), weight: .regular)
                } else if !isCompilation, let artist = track.artist, !artist.isEmpty, artist != meta.artist {
                    w2 = textWidth(for: " - " + artist, fontName: fontFamily, fontSize: CGFloat(trackSize * 0.8), weight: .regular)
                }
                
                if (w1 + w2) > availW { trOverflow = true }
            }
            trackH = CGFloat(trackCount) * CGFloat(trackSize * 1.2) * 1.2 + CGFloat(max(0, trackCount - 1)) * 15.0
        }
        
        // 4. Simulate Vertical Height
        var totalH: CGFloat = 0
        if titleH > 0 { totalH += titleH }
        if subtitleH > 0 {
            if titleH > 0 { totalH += 10 }
            totalH += subtitleH
        }
        if trackH > 0 {
            if titleH > 0 || subtitleH > 0 { totalH += 30 }
            totalH += trackH
        }
        
        if totalH > availH {
            // Vertical Overflow! Blame active components.
            if titleH > 0 { tOverflow = true }
            if subtitleH > 0 { sOverflow = true }
            if trackH > 0 { trOverflow = true }
        }
        
        return LayoutSimulationResult(titleOverflow: tOverflow, subtitleOverflow: sOverflow, trackOverflow: trOverflow)
    }
    
    func isTitleOverflowing(titleFontSize: Double, subtitleFontSize: Double, trackFontSize: Double, fontFamily: String, layoutMode: String, trackNumberStyle: Int, isCompilation: Bool, coverScale: Double) -> Bool {
        return simulateLayout(titleSize: titleFontSize, subtitleSize: subtitleFontSize, trackSize: trackFontSize, fontFamily: fontFamily, layoutMode: layoutMode, trackNumberStyle: trackNumberStyle, isCompilation: isCompilation, coverScale: coverScale).titleOverflow
    }
    
    func isSubtitleOverflowing(titleFontSize: Double, subtitleFontSize: Double, trackFontSize: Double, fontFamily: String, layoutMode: String, trackNumberStyle: Int, isCompilation: Bool, coverScale: Double) -> Bool {
        return simulateLayout(titleSize: titleFontSize, subtitleSize: subtitleFontSize, trackSize: trackFontSize, fontFamily: fontFamily, layoutMode: layoutMode, trackNumberStyle: trackNumberStyle, isCompilation: isCompilation, coverScale: coverScale).subtitleOverflow
    }
    
    func isTrackOverflowing(titleFontSize: Double, subtitleFontSize: Double, trackFontSize: Double, fontFamily: String, layoutMode: String, trackNumberStyle: Int, isCompilation: Bool, coverScale: Double) -> Bool {
        return simulateLayout(titleSize: titleFontSize, subtitleSize: subtitleFontSize, trackSize: trackFontSize, fontFamily: fontFamily, layoutMode: layoutMode, trackNumberStyle: trackNumberStyle, isCompilation: isCompilation, coverScale: coverScale).trackOverflow
    }
    
    func autoFitTitle(currentSize: Double, subtitleFontSize: Double, trackFontSize: Double, fontFamily: String, layoutMode: String, trackNumberStyle: Int, isCompilation: Bool, coverScale: Double) -> Double {
        var size = currentSize
        while size > 10 {
            let sim = simulateLayout(titleSize: size, subtitleSize: subtitleFontSize, trackSize: trackFontSize, fontFamily: fontFamily, layoutMode: layoutMode, trackNumberStyle: trackNumberStyle, isCompilation: isCompilation, coverScale: coverScale)
            if !sim.titleOverflow { return size }
            size -= 2
        }
        return size
    }
    
    func autoFitSubtitle(currentSize: Double, titleFontSize: Double, trackFontSize: Double, fontFamily: String, layoutMode: String, trackNumberStyle: Int, isCompilation: Bool, coverScale: Double) -> Double {
        var size = currentSize
        while size > 10 {
            let sim = simulateLayout(titleSize: titleFontSize, subtitleSize: size, trackSize: trackFontSize, fontFamily: fontFamily, layoutMode: layoutMode, trackNumberStyle: trackNumberStyle, isCompilation: isCompilation, coverScale: coverScale)
            if !sim.subtitleOverflow { return size }
            size -= 2
        }
        return size
    }
    
    func autoFitTracks(currentSize: Double, titleFontSize: Double, subtitleFontSize: Double, fontFamily: String, layoutMode: String, trackNumberStyle: Int, isCompilation: Bool, coverScale: Double) -> Double {
        var size = currentSize
        while size > 10 {
            let sim = simulateLayout(titleSize: titleFontSize, subtitleSize: subtitleFontSize, trackSize: size, fontFamily: fontFamily, layoutMode: layoutMode, trackNumberStyle: trackNumberStyle, isCompilation: isCompilation, coverScale: coverScale)
            if !sim.trackOverflow { return size }
            size -= 2
        }
        return size
    }
    
    func resetAll() {
        meta = AlbumMetadata()
        coverImage = nil
        searchTerm = ""
        statusMessage = "Ready to scan CDs or drop a folder."
        isProcessing = false
        activeAlbumDirectory = nil
    }
    
    func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let url = item as? URL {
                Task { @MainActor in
                    self.loadAlbum(from: url)
                }
            } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                Task { @MainActor in
                    self.loadAlbum(from: url)
                }
            }
        }
    }
    
    func selectFolderWithNSOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { @MainActor in
                    self.loadAlbum(from: url)
                }
            }
        }
    }
    
    func loadAlbum(from url: URL?) {
        // Release any previous sandbox access
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        
        isProcessing = true
        statusMessage = url != nil ? "Scanning folder..." : "Scanning /Volumes for Audio CDs..."
        let includeSubfolders = self.scanSubfolders
        
        if let targetURL = url, targetURL.startAccessingSecurityScopedResource() {
            activeSecurityScopedURL = targetURL
        } else {
            activeSecurityScopedURL = nil
        }
        
        Task.detached {
            let result = await AudioScanner.scanForAudio(at: url, includeSubfolders: includeSubfolders)
            
            await MainActor.run {
                if result.tracks.isEmpty {
                    self.statusMessage = "No audio files found."
                    self.isProcessing = false
                    return
                }
                
                self.meta.tracks = result.tracks
                self.activeAlbumDirectory = result.directory
                if let parsedTitle = result.albumTitle { self.meta.title = parsedTitle }
                if let parsedArtist = result.albumArtist { self.meta.artist = parsedArtist }
                
                // Prioritize embedded artwork if found!
                if let embedded = result.embeddedArtwork {
                    self.coverImage = embedded
                    self.statusMessage = "Loaded embedded artwork."
                }
                
                self.statusMessage = "Found \(result.tracks.count) tracks. Fetching metadata..."
                
                MetadataFetcher.fetchMetadata(for: result.directory, searchTerm: self.searchTerm) { fetchedMeta in
                    if let fetchedMeta = fetchedMeta {
                        // Prefer embedded metadata, fallback to fetched metadata (which falls back to folder parsing)
                        self.meta.title = result.albumTitle ?? fetchedMeta.title
                        self.meta.artist = result.albumArtist ?? fetchedMeta.artist
                        self.meta.year = result.year ?? fetchedMeta.year
                        self.meta.genre = result.genre ?? fetchedMeta.genre
                        
                        self.loadAlbumSettings()
                        
                        
                        if let coverURL = fetchedMeta.coverURL, self.coverImage == nil {
                            self.statusMessage = "Loading cover art..."
                            if coverURL.isFileURL {
                                if let img = NSImage(contentsOf: coverURL) {
                                    self.coverImage = img
                                    self.statusMessage = "Preview ready."
                                    self.isProcessing = false
                                } else {
                                    self.statusMessage = "Failed to load local cover image."
                                    self.isProcessing = false
                                }
                            } else {
                                URLSession.shared.dataTask(with: coverURL) { data, _, _ in
                                    if let data = data, let img = NSImage(data: data) {
                                        Task { @MainActor in
                                            self.coverImage = img
                                            self.statusMessage = "Preview ready."
                                            self.isProcessing = false
                                        }
                                    } else {
                                        Task { @MainActor in
                                            self.statusMessage = "Failed to download cover."
                                            self.isProcessing = false
                                        }
                                    }
                                }.resume()
                            }
                        } else {
                            if self.coverImage == nil {
                                self.statusMessage = "Preview ready (No cover found)."
                                self.isProcessing = false
                            } else {
                                self.statusMessage = "Preview ready (Using embedded cover)."
                                self.isProcessing = false
                            }
                        }
                    } else {
                        self.statusMessage = "Preview ready (Metadata search failed)."
                        self.isProcessing = false
                    }
                }
            }
        }
    }
    
    func renderVideo() {
        let panel = NSSavePanel()
        let safeTitle = self.meta.title.replacingOccurrences(of: "/", with: "_")
        let format = outputFormat
        panel.nameFieldStringValue = "\(safeTitle).\(format)"
        panel.allowedContentTypes = [UTType(filenameExtension: format) ?? .mpeg4Movie]
        
        panel.begin { response in
            if response == .OK, let outputURL = panel.url {
                Task { @MainActor in
                    self.saveAlbumSettings()
                    self.isProcessing = true
                    self.statusMessage = "Rendering layout frames..."
                }
                
                Task.detached {
                    await MainActor.run {
                        self.statusMessage = "Assembling video with Native VFR Engine... (Extremely Fast!)"
                    }
                    
                    NativeVideoAssembler.assemble(meta: await self.meta, coverImage: await self.coverImage, resolution: await self.videoResolution, outputURL: outputURL, progress: { msg, percent in
                        Task { @MainActor in
                            self.statusMessage = msg
                            self.renderProgress = percent
                        }
                    }) { success in
                        Task { @MainActor in
                            self.isProcessing = false
                            self.renderProgress = nil
                            if success {
                                self.statusMessage = "Success! Saved to \(outputURL.lastPathComponent)."
                                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                            } else {
                                self.statusMessage = "Failed to render video."
                            }
                        }
                    }
                }
            }
        }
    }
    
    func loadAlbumSettings() {
        guard let dir = activeAlbumDirectory else { return }
        let settingsURL = dir.appendingPathComponent(".mv_settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(AlbumSettingsData.self, from: data) else {
            return
        }
        
        // Apply Metadata
        if let title = settings.metaTitle { self.meta.title = title }
        if let artist = settings.metaArtist { self.meta.artist = artist }
        if let year = settings.metaYear { self.meta.year = year }
        if let genre = settings.metaGenre { self.meta.genre = genre }
        if let cjkVariant = settings.cjkVariant { self.meta.cjkVariant = cjkVariant }
        
        if let trackEdits = settings.trackEdits {
            var newTracks = [Track]()
            var remainingTracks = self.meta.tracks
            
            for edit in trackEdits {
                if let index = remainingTracks.firstIndex(where: { ($0.filePath as NSString).lastPathComponent == edit.filename }) {
                    var track = remainingTracks.remove(at: index)
                    if let newTitle = edit.title { track.title = newTitle }
                    if let newArtist = edit.artist { track.artist = newArtist }
                    newTracks.append(track)
                }
            }
            // Append any tracks that were in the folder but not in the saved settings
            newTracks.append(contentsOf: remainingTracks)
            self.meta.tracks = newTracks
        }
        
        // Apply Layout Settings
        let defaults = UserDefaults.standard
        if let v = settings.layoutMode { defaults.set(v, forKey: "layoutMode") }
        if let v = settings.verticalAlignment { defaults.set(v, forKey: "verticalAlignment") }
        if let v = settings.metadataPosition { defaults.set(v, forKey: "metadataPosition") }
        if let v = settings.isCompilation { defaults.set(v, forKey: "isCompilation") }
        if let v = settings.trackNumberStyle { defaults.set(v, forKey: "trackNumberStyle") }
        if let v = settings.coverScale { defaults.set(v, forKey: "coverScale") }
        if let v = settings.fontFamily { defaults.set(v, forKey: "fontFamily") }
        if let v = settings.customFontName { defaults.set(v, forKey: "customFontName") }
        if let v = settings.titleFontSize { defaults.set(v, forKey: "titleFontSize") }
        if let v = settings.subtitleFontSize { defaults.set(v, forKey: "subtitleFontSize") }
        if let v = settings.trackFontSize { defaults.set(v, forKey: "trackFontSize") }
        if let v = settings.useCustomColors { defaults.set(v, forKey: "useCustomColors") }
        if let v = settings.bgR { defaults.set(v, forKey: "customBgColorR") }
        if let v = settings.bgG { defaults.set(v, forKey: "customBgColorG") }
        if let v = settings.bgB { defaults.set(v, forKey: "customBgColorB") }
        if let v = settings.textR { defaults.set(v, forKey: "customTextColorR") }
        if let v = settings.textG { defaults.set(v, forKey: "customTextColorG") }
        if let v = settings.textB { defaults.set(v, forKey: "customTextColorB") }
        
        print("Loaded settings from \(settingsURL)")
    }
    
    func saveAlbumSettings() {
        guard let dir = activeAlbumDirectory else { return }
        
        var settings = AlbumSettingsData()
        settings.metaTitle = self.meta.title
        settings.metaArtist = self.meta.artist
        settings.metaYear = self.meta.year
        settings.metaGenre = self.meta.genre
        settings.cjkVariant = self.meta.cjkVariant
        
        settings.trackEdits = self.meta.tracks.map { track in
            AlbumSettingsData.TrackEdit(
                filename: (track.filePath as NSString).lastPathComponent,
                title: track.title,
                artist: track.artist
            )
        }
        
        let defaults = UserDefaults.standard
        settings.layoutMode = defaults.string(forKey: "layoutMode")
        settings.verticalAlignment = defaults.string(forKey: "verticalAlignment")
        settings.metadataPosition = defaults.string(forKey: "metadataPosition")
        settings.isCompilation = defaults.bool(forKey: "isCompilation")
        settings.trackNumberStyle = defaults.integer(forKey: "trackNumberStyle")
        settings.coverScale = defaults.double(forKey: "coverScale")
        settings.fontFamily = defaults.string(forKey: "fontFamily")
        settings.customFontName = defaults.string(forKey: "customFontName")
        settings.titleFontSize = defaults.double(forKey: "titleFontSize")
        settings.subtitleFontSize = defaults.double(forKey: "subtitleFontSize")
        settings.trackFontSize = defaults.double(forKey: "trackFontSize")
        settings.useCustomColors = defaults.bool(forKey: "useCustomColors")
        settings.bgR = defaults.double(forKey: "customBgColorR")
        settings.bgG = defaults.double(forKey: "customBgColorG")
        settings.bgB = defaults.double(forKey: "customBgColorB")
        settings.textR = defaults.double(forKey: "customTextColorR")
        settings.textG = defaults.double(forKey: "customTextColorG")
        settings.textB = defaults.double(forKey: "customTextColorB")
        
        let settingsURL = dir.appendingPathComponent(".mv_settings.json")
        
        let hasAccess = activeSecurityScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if hasAccess { activeSecurityScopedURL?.stopAccessingSecurityScopedResource() }
        }
        
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL, options: .atomic)
            print("Successfully saved settings to \(settingsURL)")
        } catch {
            print("Failed to save album settings: \(error)")
        }
    }
    
    // MARK: - UndoManager Support
    
    func registerSliderUndo(undoManager: UndoManager?, key: String, oldValue: Double, newValue: Double) {
        guard let undoManager = undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            UserDefaults.standard.set(oldValue, forKey: key)
            // Re-register for Redo
            target.registerSliderUndo(undoManager: undoManager, key: key, oldValue: newValue, newValue: oldValue)
        }
    }
}
