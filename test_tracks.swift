import Foundation

struct Track {
    var title: String
    var artist: String?
    var filePath: String
    var discNumber: Int?
    var audioStartTime: Double? = nil
    var duration: Double = 0
}

let home = NSHomeDirectory()
let albumPath = home + "/Downloads/Remember11 -the age of infinity- SOUND COLLECTION"

let fm = FileManager.default
var audioFiles: [URL] = []
if let enumerator = fm.enumerator(at: URL(fileURLWithPath: albumPath), includingPropertiesForKeys: nil) {
    for case let fileURL as URL in enumerator {
        if ["mp3", "flac", "wav", "m4a", "aac"].contains(fileURL.pathExtension.lowercased()) {
            audioFiles.append(fileURL)
        }
    }
}

var tracks = [Track]()
for fileURL in audioFiles {
    let relPath = fileURL.path.replacingOccurrences(of: albumPath + "/", with: "")
    let pathComponents = relPath.components(separatedBy: "/")
    var folderDisc: Int? = nil
    if pathComponents.count > 1 {
        let parentFolder = pathComponents[0]
        if let regex = try? NSRegularExpression(pattern: "(?i)(?:cd|disc|disk)\\s*(\\d+)") {
            if let match = regex.firstMatch(in: parentFolder, range: NSRange(parentFolder.startIndex..., in: parentFolder)),
               let range = Range(match.range(at: 1), in: parentFolder) {
                folderDisc = Int(parentFolder[range])
            }
        }
    }
    tracks.append(Track(title: fileURL.lastPathComponent, artist: nil, filePath: fileURL.path, discNumber: folderDisc))
}

let uniqueDiscs = Array(Set(tracks.compactMap { $0.discNumber })).sorted()
print("Total tracks: \(tracks.count)")
print("Unique discs array: \(uniqueDiscs)")
