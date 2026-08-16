import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct MetadataEditorView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.undoManager) var undoManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.openWindow) private var openWindow
    @AppStorage("isCompilation") private var isCompilation: Bool = false
    
    @State private var showingVirtualTrackPopover: UUID? = nil
    @State private var virtualTrackText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Edit Metadata")
                .font(.title2)
                .bold()
                .padding()
            
            HStack(spacing: 20) {
                // Cover Image Picker
                VStack(spacing: 10) {
                    Group {
                        if let image = viewModel.coverImage {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 140, height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 2)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 140, height: 140)
                                .overlay(
                                    VStack {
                                        Image(systemName: "photo")
                                            .font(.largeTitle)
                                        Text("No Cover")
                                            .font(.caption)
                                            .padding(.top, 4)
                                    }
                                    .foregroundColor(.secondary)
                                )
                        }
                    }
                    .help("Right-click to Scan Document with iPhone")
                    .importsItemProviders([.image, .pdf]) { providers in
                        guard let provider = providers.first else { return false }
                        
                        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                            provider.loadDataRepresentation(forTypeIdentifier: UTType.pdf.identifier) { data, _ in
                                if let data = data, let pdf = PDFDocument(data: data), let page = pdf.page(at: 0) {
                                    let imgRect = page.bounds(for: .mediaBox)
                                    let image = page.thumbnail(of: imgRect.size, for: .mediaBox)
                                    DispatchQueue.main.async {
                                        self.openCropper(with: image)
                                    }
                                }
                            }
                            return true
                        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                                if let data = data, let image = NSImage(data: data) {
                                    DispatchQueue.main.async {
                                        self.openCropper(with: image)
                                    }
                                }
                            }
                            return true
                        }
                        return false
                    }
                    
                    Button("Select Cover...") {
                        selectCoverImage()
                    }
                    .controlSize(.small)
                    
                    if viewModel.coverImage != nil {
                        Button("Save Cover...") {
                            exportCoverImage()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.leading, 10)
                
                Form {
                    Section("Album Information") {
                        TextField("Album Title", text: $viewModel.meta.title, axis: .vertical)
                            .lineLimit(1...3)
                            .disableAutocorrection(true)
                        TextField("Album Artist", text: $viewModel.meta.artist, axis: .vertical)
                            .lineLimit(1...2)
                            .disabled(isCompilation)
                            .disableAutocorrection(true)
                        TextField("Year", text: $viewModel.meta.year)
                            .disableAutocorrection(true)
                        TextField("Genre", text: $viewModel.meta.genre)
                            .disableAutocorrection(true)
                        
                        Picker("Album Language (CJK Variant)", selection: $viewModel.meta.cjkVariant) {
                            Text("Auto (System Default)").tag("Auto")
                            Text("Simplified Chinese").tag("SC")
                            Text("Traditional Chinese").tag("TC")
                            Text("Japanese").tag("JP")
                            Text("Korean").tag("KR")
                        }
                        
                        Toggle("Compilation Album (Various Artists)", isOn: $isCompilation)
                    }
                }
            }
            .padding()
            .frame(height: 240)
            
            Divider()
            
            List {
                ForEach($viewModel.meta.tracks) { $track in
                    VStack(alignment: .leading, spacing: 0) {
                        let indexInArray = viewModel.meta.tracks.firstIndex(where: { $0.id == track.id }) ?? 0
                        let currentDisc = track.discNumber ?? 1
                        let previousDisc = indexInArray > 0 ? (viewModel.meta.tracks[indexInArray - 1].discNumber ?? 1) : -1
                        
                        if currentDisc != previousDisc {
                            Text("Disc \(currentDisc)")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                                .padding(.top, indexInArray == 0 ? 0 : 16)
                                .padding(.bottom, 8)
                        }
                        
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                                .padding(.trailing, 4)
                                .help("Drag to reorder")
                            
                            let trackIndexInDisc = viewModel.meta.tracks.prefix(upTo: indexInArray).filter { ($0.discNumber ?? 1) == currentDisc }.count + 1
                            Text(String(format: "%02d.", trackIndexInDisc))
                                .foregroundColor(.secondary)
                                .frame(width: 30, alignment: .leading)
                            
                            TextField("Track Title", text: $track.title, axis: .vertical)
                                .lineLimit(1...4)
                                .disableAutocorrection(true)
                        
                            TextField("Track Artist (Optional)", text: Binding(
                                get: { track.artist ?? "" },
                                set: { track.artist = $0.isEmpty ? nil : $0 }
                            ), axis: .vertical)
                            .lineLimit(1...2)
                            .disableAutocorrection(true)
                            
                            VStack(spacing: 2) {
                                Text("Disc").font(.system(size: 9)).foregroundColor(.secondary)
                                TextField("", value: Binding(
                                    get: { track.discNumber ?? 1 },
                                    set: { track.discNumber = $0 }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 35)
                                .multilineTextAlignment(.center)
                            }
                            
                            Button(action: {
                            virtualTrackText = ""
                            showingVirtualTrackPopover = track.id
                        }) {
                            Image(systemName: "scissors")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Virtual Split with Timestamps")
                        .popover(isPresented: Binding(
                            get: { showingVirtualTrackPopover == track.id },
                            set: { if !$0 { showingVirtualTrackPopover = nil } }
                        ), arrowEdge: .trailing) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Virtual Tracks (Timestamps)")
                                    .font(.headline)
                                Text("Enter one timestamp and title per line.\\nExample:\\n00:00 Movement 1\\n05:30 Movement 2")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                TextEditor(text: $virtualTrackText)
                                    .frame(width: 250, height: 150)
                                    .font(.system(.body, design: .monospaced))
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
                                
                                HStack {
                                    Spacer()
                                    Button("Cancel") { showingVirtualTrackPopover = nil }
                                    Button("Apply Split") {
                                        if let index = viewModel.meta.tracks.firstIndex(where: { $0.id == track.id }) {
                                            let virtualTracks = AudioScanner.parseVirtualTracks(from: virtualTrackText, originalTrack: track)
                                            if !virtualTracks.isEmpty {
                                                viewModel.meta.tracks.remove(at: index)
                                                viewModel.meta.tracks.insert(contentsOf: virtualTracks, at: index)
                                            }
                                        }
                                        showingVirtualTrackPopover = nil
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding()
                        }
                    } // HStack
                    .padding(.vertical, 4)
                } // VStack
                } // ForEach
                .onMove { indices, newOffset in
                    viewModel.meta.tracks.move(fromOffsets: indices, toOffset: newOffset)
                    // Auto-fix disc numbers based on surrounding tracks if it was moved across disc boundaries
                    if newOffset > 0 && newOffset <= viewModel.meta.tracks.count {
                        let prevDisc = viewModel.meta.tracks[newOffset - 1].discNumber ?? 1
                        for index in indices {
                            let mappedIndex = index < newOffset ? newOffset - 1 : newOffset
                            if mappedIndex >= 0 && mappedIndex < viewModel.meta.tracks.count {
                                viewModel.meta.tracks[mappedIndex].discNumber = prevDisc
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Save to Album folder") {
                    viewModel.saveAlbumSettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .frame(width: 600, height: 620) // Slightly wider to accommodate the image
        .onChange(of: viewModel.meta) { oldMeta, newMeta in
            if oldMeta != newMeta {
                viewModel.registerPropertyUndo(undoManager: undoManager, keyPath: \.meta, oldValue: oldMeta, newValue: newMeta)
            }
        }
        .onChange(of: isCompilation) { oldVal, newVal in
            if oldVal != newVal {
                viewModel.registerAppStorageUndo(undoManager: undoManager, key: "isCompilation", oldValue: oldVal, newValue: newVal)
            }
        }
    }
    
    private func selectCoverImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url {
                if let image = NSImage(contentsOf: url) {
                    openCropper(with: image)
                }
            }
        }
        
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            panel.begin(completionHandler: handler)
        }
    }
    
    private func openCropper(with image: NSImage) {
        viewModel.imageToCrop = image
        openWindow(id: "ImageCropper")
    }
    
    private func exportCoverImage() {
        guard let image = viewModel.coverImage,
              let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "cover.png"
        
        // Default directory to active album directory if available
        if let defaultURL = viewModel.activeAlbumDirectory {
            panel.directoryURL = defaultURL
        }
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try pngData.write(to: url)
                } catch {
                    print("Error saving cover image: \(error.localizedDescription)")
                }
            }
        }
    }
}

extension NSImage {
    func squareCropped() -> NSImage {
        let size = self.size
        let side = min(size.width, size.height)
        let xOffset = (size.width - side) / 2.0
        let yOffset = (size.height - side) / 2.0
        
        let croppedRect = NSRect(x: xOffset, y: yOffset, width: side, height: side)
        let newImage = NSImage(size: NSSize(width: side, height: side))
        
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: NSSize(width: side, height: side)),
                  from: croppedRect,
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
}
