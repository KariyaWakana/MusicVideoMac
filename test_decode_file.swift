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
    
    // Layout Settings
    var layoutMode: String?
    var verticalAlignment: String?
    var metadataPosition: String?
    var isCompilation: Bool?
    var trackNumberStyle: Int?
    var coverScale: Double?
    var fontFamily: String?
    var customFontName: String?
    var cjkVariant: String?
    var titleFontSize: Double?
    var subtitleFontSize: Double?
    var trackFontSize: Double?
    var useCustomColors: Bool?
    
    // Custom Colors
    var bgR: Double?
    var bgG: Double?
    var bgB: Double?
    var textR: Double?
    var textG: Double?
    var textB: Double?
}

let url = URL(fileURLWithPath: "/Users/cgga/Downloads/Hell Mach 4 - Ten Meter Resolution/.mv_settings.json")
do {
    let data = try Data(contentsOf: url)
    let decoded = try JSONDecoder().decode(AlbumSettingsData.self, from: data)
    print("Success: \(decoded.metaTitle ?? "nil")")
} catch {
    print("Error: \(error)")
}
