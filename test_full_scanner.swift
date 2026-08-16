import Foundation
import AppKit

// Replicate the exact regex logic from AudioScanner.swift to see what it finds
let albumPath = NSHomeDirectory() + "/Downloads/Remember11 -the age of infinity- SOUND COLLECTION"
let fm = FileManager.default
var foundFiles: [String] = []
if let enumerator = fm.enumerator(at: URL(fileURLWithPath: albumPath), includingPropertiesForKeys: nil) {
    for case let fileURL as URL in enumerator {
        if ["mp3", "flac", "wav", "m4a"].contains(fileURL.pathExtension.lowercased()) {
            foundFiles.append(fileURL.path)
        }
    }
}
print("Found \(foundFiles.count) files")

for path in foundFiles.prefix(5) { // Just check first 5
    var embeddedDiscNumber: Int? = nil
    let relPath = (path as NSString).replacingOccurrences(of: albumPath + "/", with: "")
    let pathComponents = relPath.components(separatedBy: "/")
    if pathComponents.count > 1 {
        let parentFolder = pathComponents[0]
        if let regex = try? NSRegularExpression(pattern: "(?i)(?:cd|disc|disk)\\s*(\\d+)") {
            if let match = regex.firstMatch(in: parentFolder, range: NSRange(parentFolder.startIndex..., in: parentFolder)),
               let range = Range(match.range(at: 1), in: parentFolder) {
                embeddedDiscNumber = Int(parentFolder[range])
                print("Matched folder: \(parentFolder) -> Disc: \(embeddedDiscNumber ?? -1)")
            } else {
                print("Regex failed for folder: \(parentFolder)")
            }
        }
    }
}
