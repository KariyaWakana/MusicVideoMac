import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppViewModel.self) var viewModel
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        
        NavigationStack {
            Group {
                if viewModel.meta.tracks.isEmpty {
                    // Empty State (macOS 14 native ContentUnavailableView)
                    ContentUnavailableView {
                        Label("No Album Loaded", systemImage: "music.note.list")
                    } description: {
                        Text("Drag and drop an audio folder here, or click to browse.")
                    } actions: {
                        VStack(spacing: 15) {
                            HStack(spacing: 15) {
                                Button("Select Folder") {
                                    viewModel.selectFolderWithNSOpenPanel()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                
                                Button("Scan Optical Drive") {
                                    viewModel.loadAlbum(from: nil)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                
                                if !viewModel.meta.tracks.isEmpty {
                                    Button("Edit Metadata") {
                                        openWindow(id: "EditInfo")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                }
                            }
                            
                            @Bindable var bindableViewModel = viewModel
                            Toggle("Multi-CD Album (Scan Subfolders)", isOn: $bindableViewModel.scanSubfolders)
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .disabled(viewModel.isProcessing)
                        .padding(.top, 10)
                        
                        if viewModel.isProcessing {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text(viewModel.statusMessage).foregroundColor(.secondary)
                            }
                            .padding(.top, 20)
                        }
                    }
                } else {
                    // Apple Music Style Album View
                    ScrollView {
                        VStack(alignment: .leading, spacing: 30) {
                            
                            // Header Section
                            HStack(alignment: .bottom, spacing: 30) {
                                // Cover Art
                                if let cover = viewModel.coverImage {
                                    Image(nsImage: cover)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 260, height: 260)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                                } else {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
                                        .frame(width: 260, height: 260)
                                        .overlay(Image(systemName: "music.quarternote.3").font(.system(size: 60)).foregroundStyle(.secondary))
                                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                                }
                                
                                // Metadata & Controls
                                VStack(alignment: .leading, spacing: 12) {
                                    @AppStorage("isCompilation") var isCompilation: Bool = false
                                    
                                    Text(viewModel.meta.title)
                                        .font(.system(size: 36, weight: .bold)) // Large Title
                                        .lineLimit(2)
                                    
                                    Text(isCompilation ? "Various Artists" : viewModel.meta.artist)
                                        .font(.title)
                                        .foregroundStyle(.secondary)
                                    
                                    Text("\(viewModel.meta.genre) • \(viewModel.meta.year)")
                                        .font(.title3)
                                        .foregroundStyle(.tertiary)
                                    
                                    Spacer().frame(height: 10)
                                    
                                    HStack(spacing: 15) {
                                        Button(action: { openWindow(id: "RenderPreview") }) {
                                            Label("Custom Render...", systemImage: "play.fill")
                                                .padding(.horizontal, 10)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.accentColor)
                                        .controlSize(.large)
                                        .disabled(viewModel.isProcessing)
                                        
                                        Button(action: { openWindow(id: "EditInfo") }) {
                                            Label("Edit Info", systemImage: "pencil")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.large)
                                        
                                        Button(action: viewModel.resetAll) {
                                            Image(systemName: "xmark")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.large)
                                    }
                                    
                                    if viewModel.isProcessing {
                                        HStack {
                                            if let progress = viewModel.renderProgress {
                                                ProgressView(value: progress).controlSize(.small).frame(width: 100)
                                            } else {
                                                ProgressView().controlSize(.small)
                                            }
                                            Text(viewModel.statusMessage)
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.top, 5)
                                    }
                                }
                            }
                            .padding(.horizontal, 40)
                            .padding(.top, 40)
                            
                            Divider().padding(.horizontal, 40)
                            
                            // Dynamic Tracklist Layout (Fixes Table height truncation)
                            VStack(spacing: 0) {
                                // Header Row
                                HStack {
                                    Text("#").frame(width: 30, alignment: .leading)
                                    Text("Title").frame(minWidth: 100, idealWidth: 200, maxWidth: .infinity, alignment: .leading)
                                    Text("Artist").frame(minWidth: 80, idealWidth: 150, maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                
                                Divider()
                                
                                // Track Rows
                                ForEach(Array(viewModel.meta.tracks.enumerated()), id: \.element.id) { index, track in
                                    HStack {
                                        Text(String(format: "%02d", index + 1))
                                            .frame(width: 30, alignment: .leading)
                                            .foregroundColor(.secondary)
                                        
                                        Text(track.title)
                                            .font(.system(size: 14))
                                            .frame(minWidth: 100, idealWidth: 200, maxWidth: .infinity, alignment: .leading)
                                        
                                        if let artist = track.artist, !artist.isEmpty, artist != viewModel.meta.artist {
                                            Text(artist)
                                                .font(.system(size: 13))
                                                .foregroundColor(.secondary)
                                                .frame(minWidth: 80, idealWidth: 150, maxWidth: .infinity, alignment: .leading)
                                        } else {
                                            Spacer().frame(minWidth: 80, idealWidth: 150, maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .background(index % 2 == 0 ? Color(NSColor.alternatingContentBackgroundColors[0]) : Color(NSColor.alternatingContentBackgroundColors[1]))
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                            .padding(.horizontal, 40)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationTitle(viewModel.meta.tracks.isEmpty ? "Music Video Generator" : viewModel.meta.title)
            .searchable(text: Bindable(viewModel).searchTerm, prompt: "Override iTunes Search...")
            .autocorrectionDisabled(true)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        openWindow(id: "RenderQueue")
                    }) {
                        Label("Render Queue", systemImage: "list.and.film")
                    }
                    .help("View active and queued rendering jobs")
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        viewModel.saveAlbumSettings()
                        viewModel.statusMessage = "Settings saved to album folder."
                    }) {
                        Label("Save Settings", systemImage: "square.and.arrow.down")
                    }
                    .help("Save current layout and metadata to album folder")
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(viewModel.meta.tracks.isEmpty)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: Bindable(viewModel).isHovering) { providers in
            viewModel.handleDrop(providers: providers)
            return true
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}
