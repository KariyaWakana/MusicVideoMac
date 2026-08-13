import Foundation
import AppKit

struct Track: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var artist: String?
    let filePath: String
    var audioStartTime: Double = 0.0
    var duration: Double
    var artwork: NSImage? = nil
}

struct AlbumMetadata: Equatable {
    var title: String = "Unknown Album"
    var artist: String = "Unknown Artist"
    var year: String = "Unknown Year"
    var genre: String = "Unknown Genre"
    var coverURL: URL? = nil
    var localCoverPath: String? = nil
    var cjkVariant: String = "Auto"
    var tracks: [Track] = []
}

struct AlbumSettingsData: Codable {
    var metaTitle: String?
    var metaArtist: String?
    var metaYear: String?
    var metaGenre: String?
    
    struct TrackEdit: Codable {
        var filename: String
        var title: String?
        var artist: String?
        var audioStartTime: Double?
        var duration: Double?
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
