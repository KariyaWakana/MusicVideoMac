import Foundation

struct AlbumSettingsData: Codable {
    var metaTitle: String?
    var metaArtist: String?
    var metaYear: String?
    var metaGenre: String?
    
    struct TrackEdit: Codable {
        var filename: String
        var title: String?
        var artist: String?
    }
    var trackEdits: [TrackEdit]?
}

let url = URL(fileURLWithPath: "/Users/cgga/Downloads/Hell Mach 4 - Ten Meter Resolution/.mv_settings.json")
do {
    let data = try Data(contentsOf: url)
    let decoded = try JSONDecoder().decode(AlbumSettingsData.self, from: data)
    print("Success: \(decoded.metaTitle ?? "nil")")
    if let edits = decoded.trackEdits {
        for edit in edits {
            print("- \(edit.filename): \(edit.title ?? "nil") - \(edit.artist ?? "nil")")
        }
    }
} catch {
    print("Error: \(error)")
}
