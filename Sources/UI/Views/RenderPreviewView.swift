import SwiftUI

struct RenderPreviewView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
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
                    
                    GeometryReader { geometry in
                        let availableWidth = max(0, geometry.size.width - 40)
                        let availableHeight = max(0, geometry.size.height - 40)
                        let scaleByWidth = availableWidth / 1920.0
                        let scaleByHeight = availableHeight / 1080.0
                        let scale = min(scaleByWidth, scaleByHeight)
                        
                        FrameView(meta: viewModel.meta, coverImage: viewModel.coverImage, currentTrackIndex: 0, bgColor: Color(NSColor.controlBackgroundColor), scale: scale)
                            .frame(width: 1920 * scale, height: 1080 * scale)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 10)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
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
