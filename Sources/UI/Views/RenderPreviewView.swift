import SwiftUI

struct RenderPreviewView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.openWindow) private var openWindow
    
    @AppStorage("useCustomColors") private var useCustomColors: Bool = false
    @AppStorage("separateDiscColors") private var separateDiscColors: Bool = false
    
    var previewMeta: AlbumMetadata {
        if viewModel.meta.tracks.isEmpty { return viewModel.meta }
        var meta = viewModel.meta
        
        let targetDisc = viewModel.previewDisc ?? viewModel.activeDisc
        if let disc = targetDisc {
            meta.tracks = meta.tracks.filter { ($0.discNumber ?? 1) == disc }
            let uniqueDiscs = Array(Set(viewModel.meta.tracks.compactMap { $0.discNumber }))
            if uniqueDiscs.count > 1 {
                meta.discTitle = "Disc \(disc)"
            }
            
            if useCustomColors && separateDiscColors {
                let dKey = String(disc)
                if let bg = viewModel.discBgColors[dKey] {
                    meta.overrideBgColor = bg
                }
                if let tc = viewModel.discTextColors[dKey] {
                    meta.overrideTextColor = tc
                }
            }
        }
        
        // Mock a long track list for preview
        if meta.tracks.isEmpty {
            meta.tracks = (1...12).map { i in
                Track(title: "Preview Track \(i)", artist: meta.artist.isEmpty ? "Artist" : meta.artist, filePath: "", discNumber: targetDisc, duration: 200)
            }
        }
        return meta
    }
    
    var body: some View {
        // Explicitly read observable dictionaries in body to force dependency tracking
        let _ = viewModel.discBgColors
        let _ = viewModel.discTextColors
        
        VStack(spacing: 0) {
            // Header
            Text("Custom Render Options")
                .font(.title2)
                .bold()
                .padding(.top, 20)
                .padding(.bottom, 10)
            
            Divider()
            
            // Interactive Preview Workspace
            HSplitView {
                // Left Side: Live Preview
                VStack {
                    Text("Live Preview")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.top, 10)
                    
                    let uniqueDiscs = Array(Set(viewModel.meta.tracks.compactMap { $0.discNumber })).sorted()
                    if uniqueDiscs.count > 1 && viewModel.activeDisc == nil {
                        HStack(spacing: 16) {
                            Button(action: {
                                let current = viewModel.previewDisc ?? uniqueDiscs.first ?? 1
                                if let idx = uniqueDiscs.firstIndex(of: current), idx > 0 {
                                    viewModel.previewDisc = uniqueDiscs[idx - 1]
                                }
                            }) {
                                Image(systemName: "chevron.left").font(.body.bold())
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            
                            Text("Previewing Disc \(viewModel.previewDisc ?? uniqueDiscs.first ?? 1)")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                                .frame(width: 140, alignment: .center)
                                
                            Button(action: {
                                let current = viewModel.previewDisc ?? uniqueDiscs.first ?? 1
                                if let idx = uniqueDiscs.firstIndex(of: current), idx < uniqueDiscs.count - 1 {
                                    viewModel.previewDisc = uniqueDiscs[idx + 1]
                                }
                            }) {
                                Image(systemName: "chevron.right").font(.body.bold())
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                        .padding(.top, 5)
                        .onAppear {
                            if viewModel.previewDisc == nil {
                                viewModel.previewDisc = uniqueDiscs.first
                            }
                        }
                    }
                    
                    GeometryReader { geometry in
                        let availableWidth = max(0, geometry.size.width - 40)
                        let availableHeight = max(0, geometry.size.height - 40)
                        let scaleByWidth = availableWidth / 1920.0
                        let scaleByHeight = availableHeight / 1080.0
                        let scale = min(scaleByWidth, scaleByHeight)
                        
                        LiveFrameView(meta: previewMeta, coverImage: viewModel.coverImage, currentTrackIndex: 0, bgColor: Color(NSColor.controlBackgroundColor), scale: scale)
                            .frame(width: 1920 * scale, height: 1080 * scale)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 10)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 10)
                }
                .frame(minWidth: 500, maxWidth: .infinity)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
                
                // Right Side: Settings Form
                ScrollView {
                    LayoutSettingsForm()
                        .padding(20)
                }
                .frame(minWidth: 350, idealWidth: 400, maxWidth: 500)
                .background(Color(NSColor.controlBackgroundColor))
            }
            
            Divider()
            
            // Footer Action Bar
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
                
                Spacer()
                
                Button("Next...") {
                    openWindow(id: "ExportWizard")
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 1000, minHeight: 700)
    }
}
