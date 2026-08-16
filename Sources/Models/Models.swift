import Foundation
import AppKit

struct Track: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var artist: String?
    let filePath: String
    var discNumber: Int?
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
    var discTitle: String? = nil
    var itunesTrackCountsPerDisc: [Int: Int]? = nil
    var tracks: [Track] = []
    
    // Rendering Overrides
    var overrideBgColor: [Double]? = nil
    var overrideTextColor: [Double]? = nil
    var overrideDiscLabelPosition: String? = nil
    
    // Per-Disc Color Mappings for multi-disc continuous rendering
    var discBgColors: [String: [Double]]? = nil
    var discTextColors: [String: [Double]]? = nil
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
        var discNumber: Int?
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
    
    // Per-Disc Color Storage (String keys like "1", "2" mapping to [R, G, B])
    var discBgColors: [String: [Double]]?
    var discTextColors: [String: [Double]]?
    var discLabelPosition: String? // "Hidden", "Right of Title", "Left of Title", "Subtitle", "Above Tracks"
    
    var useCustomColors: Bool?
    
    // Custom Colors
    var bgR: Double?
    var bgG: Double?
    var bgB: Double?
    var textR: Double?
    var textG: Double?
    var textB: Double?
}
