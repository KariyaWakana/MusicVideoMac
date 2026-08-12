import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct MetadataEditorView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.undoManager) var undoManager
    @Environment(\.dismiss) var dismiss
    @AppStorage("isCompilation") private var isCompilation: Bool = false
    
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
                                        self.viewModel.coverImage = image
                                    }
                                }
                            }
                            return true
                        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                                if let data = data, let image = NSImage(data: data) {
                                    DispatchQueue.main.async {
                                        self.viewModel.coverImage = image
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
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.secondary)
                            .padding(.trailing, 4)
                            .help("Drag to reorder")
                        
                        let index = (viewModel.meta.tracks.firstIndex(where: { $0.id == track.id }) ?? 0) + 1
                        Text(String(format: "%02d.", index))
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
                    }
                    .padding(.vertical, 4)
                }
                .onMove { indices, newOffset in
                    viewModel.meta.tracks.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Save Changes") {
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
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let image = NSImage(contentsOf: url) {
                    let oldImage = viewModel.coverImage
                    viewModel.coverImage = image
                    viewModel.registerPropertyUndo(undoManager: undoManager, keyPath: \.coverImage, oldValue: oldImage, newValue: image)
                }
            }
        }
    }
}
