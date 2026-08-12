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

let json = """
{"layoutMode":"Right","metaGenre":"Post Hardcore","fontFamily":"Lexend","textR":0.8967775922391857,"textG":0.24660922509684458,"subtitleFontSize":20,"metaYear":"1999","trackFontSize":24,"cjkVariant":"Auto","metaArtist":"Hell Mach 4","useCustomColors":true,"verticalAlignment":"Split","isCompilation":false,"trackEdits":[{"title":"Beg","artist":"Hell Mach 4","filename":"01 Hell Mach 4 - Beg.m4a"},{"title":"Hedgeclipper","artist":"Hell Mach 4","filename":"02 Hell Mach 4 - Hedgeclipper.m4a"},{"title":"Ten Meter Resolution","artist":"Hell Mach 4","filename":"03 Hell Mach 4 - Ten Meter Resolution.m4a"},{"title":"Blues For Dave","artist":"Hell Mach 4","filename":"04 Hell Mach 4 - Blues For Dave.m4a"},{"title":"Human Cannon Ball","artist":"Hell Mach 4","filename":"05 Hell Mach 4 - Human Cannon Ball.m4a"},{"filename":"06 Hell Mach 4 - Cardinal.m4a","title":"Cardinal","artist":"Hell Mach 4"},{"filename":"07 Hell Mach 4 - Sistine Chapel.m4a","title":"Sistine Chapel","artist":"Hell Mach 4"},{"title":"Firestone","artist":"Hell Mach 4","filename":"08 Hell Mach 4 - Firestone.m4a"},{"title":"Beg 2","artist":"Hell Mach 4","filename":"09 Hell Mach 4 - Beg 2.m4a"},{"title":"Other Go To Heaven","artist":"Hell Mach 4","filename":"10 Hell Mach 4 - Other Go To Heaven.m4a"}],"coverScale":1,"titleFontSize":64,"trackNumberStyle":0,"metaTitle":"Ten Meter Resolution","textB":0.10717971345003428,"bgB":0.9319880604743958,"metadataPosition":"Top","customFontName":"","bgG":0.9300941824913025,"bgR":0.9469490647315979}
"""

do {
    let data = json.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(AlbumSettingsData.self, from: data)
    print("Success: \(decoded.metaTitle ?? "nil")")
} catch {
    print("Error: \(error)")
}
