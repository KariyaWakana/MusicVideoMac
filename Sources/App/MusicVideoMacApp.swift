import SwiftUI

@main
struct MusicVideoMacApp: App {
    @Environment(\.undoManager) var undoManager
    @State private var viewModel = AppViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .onAppear {
                    viewModel.undoManager = undoManager
                }
        }
        .windowStyle(.hiddenTitleBar)
        
        Window("Render Settings", id: "RenderPreview") {
            RenderPreviewView(viewModel: viewModel)
                .environment(viewModel)
        }
        
        Window("Edit Album Info", id: "EditInfo") {
            MetadataEditorView(viewModel: viewModel)
                .environment(viewModel)
        }
        
        Window("Export Wizard", id: "ExportWizard") {
            ExportSettingsWizard()
                .environment(viewModel)
        }
        
        Settings {
            SettingsView()
                .environment(viewModel)
        }
    }
}
