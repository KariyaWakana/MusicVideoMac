import SwiftUI

struct SettingsView: View {
    @Environment(AppViewModel.self) var viewModel
    
    // Export Settings
    @AppStorage("videoResolution") private var videoResolution: String = "1080p"
    @AppStorage("videoFramerate") private var videoFramerate: Int = 30
    @AppStorage("outputFormat") private var outputFormat: String = "mp4"
    @AppStorage("hardwareAcceleration") private var hardwareAcceleration: Bool = true
    
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
    
    // Mock Data for Preview (Used if no album is loaded)
    private var mockMeta: AlbumMetadata = {
        var m = AlbumMetadata()
        m.title = "Preview Title"
        m.artist = "Artist"
        m.year = "2026"
        m.genre = "Electronic"
        m.tracks = [
            Track(title: "First Track", artist: "Aimer", filePath: "", duration: 180),
            Track(title: "Second Track", artist: "EGOIST", filePath: "", duration: 180),
            Track(title: "Third Track", artist: "ReoNa", filePath: "", duration: 180)
        ]
        return m
    }()
    
    var previewMeta: AlbumMetadata {
        viewModel.meta.tracks.isEmpty ? mockMeta : viewModel.meta
    }
    var previewCover: NSImage? {
        viewModel.meta.tracks.isEmpty ? nil : viewModel.coverImage
    }

    var body: some View {
        TabView {
            // Tab 1: Export Settings
            ScrollView {
                Form {
                    Section {
                        Picker("Resolution:", selection: $videoResolution) {
                            Text("480p (854x480)").tag("480p")
                            Text("1080p (1920x1080)").tag("1080p")
                            Text("4K (3840x2160)").tag("4K")
                        }
                        Picker("Framerate:", selection: $videoFramerate) {
                            Text("30 fps").tag(30)
                            Text("60 fps").tag(60)
                        }
                        Picker("Output Format:", selection: $outputFormat) {
                            Text("MP4 (.mp4)").tag("mp4")
                            Text("QuickTime (.mov)").tag("mov")
                        }
                    } header: { Text("Video Settings").font(.headline) }
                    
                    Section {
                        Toggle("Hardware Acceleration (VideoToolbox)", isOn: $hardwareAcceleration)
                        Text("Dramatically speeds up rendering on Apple Silicon/Intel. Disable only if you experience glitches.")
                            .font(.caption).foregroundColor(.secondary)
                    } header: { Text("Performance").font(.headline) }
                }
                .formStyle(.grouped)
                .padding(20)
            }
            .tabItem {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            
            // Tab 2: Appearance Settings
            VStack(spacing: 0) {
                // ANCHORED LIVE PREVIEW
                let scale: CGFloat = 0.22 // Slightly larger since it has its own space
                FrameView(meta: previewMeta, coverImage: previewCover, currentTrackIndex: 0, bgColor: Color(NSColor.controlBackgroundColor), scale: scale)
                    .frame(width: 1920 * scale, height: 1080 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                    .background(Color(NSColor.windowBackgroundColor).shadow(radius: 2))
                    .zIndex(1)
                
                Divider()
                
                // SCROLLABLE SETTINGS BELOW
                ScrollView {
                    LayoutSettingsForm()
                        .padding(20)
                }
            }
            .tabItem {
                Label("Appearance", systemImage: "paintbrush")
            }
        }
        .frame(width: 550, height: 750)
    }
}
