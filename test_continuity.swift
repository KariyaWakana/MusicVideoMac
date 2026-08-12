import AppKit

class CameraReceiver: NSView {
    var onImageReceived: ((NSImage) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType, returnType: NSPasteboard.PasteboardType?) -> Any? {
        if let returnType = returnType, returnType == .tiff || returnType == .png {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }
    
    override func readSelectionFromPasteboard(_ pboard: NSPasteboard) -> Bool {
        guard let items = pboard.pasteboardItems else { return false }
        for item in items {
            if let data = item.data(forType: .tiff) ?? item.data(forType: .png),
               let image = NSImage(data: data) {
                onImageReceived?(image)
                return true
            }
        }
        return false
    }
    
    @objc func triggerScan() {
        if let menu = NSMenu.init(title: "Import") as NSMenu? {
            // macOS 10.14+ Continuity Camera
            // We can just send the importDocument: action
            NSApp.sendAction(#selector(NSText.importDocument(_:)), to: nil, from: self)
        }
    }
}
print("Compile check passed.")
