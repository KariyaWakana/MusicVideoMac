import SwiftUI

struct ExportSettingsWizard: View {
    @Environment(AppViewModel.self) var viewModel
    @Environment(\.dismiss) var dismiss
    
    // Export Settings
    @AppStorage("videoResolution") private var videoResolution: String = "1080p"
    @AppStorage("videoFramerate") private var videoFramerate: Int = 30
    @AppStorage("outputFormat") private var outputFormat: String = "mp4"
    @AppStorage("audioQuality") private var audioQuality: String = "AAC"
    @AppStorage("hardwareAcceleration") private var hardwareAcceleration: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Export Settings")
                .font(.title2)
                .bold()
                .padding(.top, 20)
                .padding(.bottom, 10)
            
            Divider()
            
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
                    .onChange(of: outputFormat) { _, newFormat in
                        if newFormat == "mp4" && audioQuality == "Lossless" {
                            audioQuality = "AAC"
                        }
                    }
                } header: { Text("Video Profile").font(.headline) }
                
                Section {
                    Picker("Audio Quality:", selection: $audioQuality) {
                        Text("Standard (AAC)").tag("AAC")
                        Text("Lossless (Passthrough)").tag("Lossless")
                    }
                    .onChange(of: audioQuality) { _, newQuality in
                        if newQuality == "Lossless" {
                            outputFormat = "mov"
                        }
                    }
                    if audioQuality == "Lossless" {
                        Text("Lossless requires .mov format. Original audio bitstream will be copied directly.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } header: { Text("Audio Profile").font(.headline) }
                
                Section {
                    Toggle("Hardware Acceleration (VideoToolbox)", isOn: $hardwareAcceleration)
                    Text("Dramatically speeds up rendering on Apple Silicon/Intel. Disable only if you experience glitches.")
                        .font(.caption).foregroundColor(.secondary)
                } header: { Text("Performance").font(.headline) }
            }
            .formStyle(.grouped)
            .padding(20)
            
            Divider()
            
            HStack(spacing: 15) {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save Video...") {
                    dismiss()
                    
                    viewModel.renderVideo()
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 500, height: 420)
    }
}
