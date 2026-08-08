import Foundation
import AVFoundation
import AppKit

class AudioScanner {
    static func scanForAudio(at url: URL? = nil, includeSubfolders: Bool = false) async -> (tracks: [Track], directory: URL?, albumTitle: String?, albumArtist: String?, year: String?, genre: String?, embeddedArtwork: NSImage?) {
        let fileManager = FileManager.default
        let extensions = ["aiff", "aif", "wav", "flac", "mp3", "m4a", "alac", "aac", "ogg"]
        var foundFiles: [String] = []
        var finalDir: URL? = nil
        var cueFileURL: URL? = nil
        
        if let specificURL = url {
            finalDir = specificURL
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: specificURL.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    let options: FileManager.DirectoryEnumerationOptions = includeSubfolders 
                        ? [.skipsHiddenFiles, .skipsPackageDescendants] 
                        : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
                    
                    if let enumerator = fileManager.enumerator(at: specificURL, includingPropertiesForKeys: [.isRegularFileKey], options: options) {
                        while let fileURL = enumerator.nextObject() as? URL {
                            let ext = fileURL.pathExtension.lowercased()
                            if ext == "cue" {
                                cueFileURL = fileURL
                            } else if extensions.contains(ext) {
                                foundFiles.append(fileURL.path)
                            }
                        }
                    }
                    foundFiles.sort()
                } else {
                    // It's a single file
                    let ext = specificURL.pathExtension.lowercased()
                    if extensions.contains(ext) {
                        foundFiles = [specificURL.path]
                        finalDir = specificURL.deletingLastPathComponent()
                    }
                }
            }
        } else {
            // Auto-detect /Volumes
            let volumesPath = "/Volumes"
            if let volumes = try? fileManager.contentsOfDirectory(atPath: volumesPath) {
                var dirsToScan = ["/Volumes/Audio CD"]
                for vol in volumes {
                    let path = "/Volumes/\(vol)"
                    if vol != "Macintosh HD" && vol != "Audio CD" {
                        dirsToScan.append(path)
                    }
                }
                
                for dir in dirsToScan {
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue {
                        if let files = try? fileManager.contentsOfDirectory(atPath: dir) {
                            let audio = files.filter { ext in
                                extensions.contains { $0 == (ext as NSString).pathExtension.lowercased() }
                            }
                            if !audio.isEmpty {
                                foundFiles = audio.map { "\(dir)/\($0)" }.sorted()
                                finalDir = URL(fileURLWithPath: dir)
                                print("Auto-detected audio files in: \(dir)")
                                break
                            }
                        }
                    }
                }
            }
        }
        
        if let cueURL = cueFileURL {
            let parsed = await parseCueFile(at: cueURL)
            if !parsed.tracks.isEmpty {
                return (parsed.tracks, finalDir, parsed.albumTitle, parsed.albumArtist, nil, nil, nil)
            }
        }
        
        if !foundFiles.isEmpty {
            var extractedArtwork: NSImage? = nil
            var extractedAlbum: String? = nil
            var extractedAlbumArtist: String? = nil
            var extractedYear: String? = nil
            var extractedGenre: String? = nil
            
            typealias TrackResult = (track: Track, album: String?, albumArtist: String?, year: String?, genre: String?)
            
            let tracks = await withTaskGroup(of: TrackResult?.self) { group in
                for path in foundFiles {
                    if (path as NSString).lastPathComponent.hasPrefix(".") { continue }
                    group.addTask {
                        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
                        var duration: Double = 0
                        var embeddedTitle: String? = nil
                        var embeddedArtist: String? = nil
                        var embeddedAlbum: String? = nil
                        var embeddedAlbumArtist: String? = nil
                        var embeddedYear: String? = nil
                        var embeddedGenre: String? = nil
                        var localArtwork: NSImage? = nil
                        
                        if #available(macOS 13.0, *) {
                            if let cmDuration = try? await asset.load(.duration) {
                                duration = CMTimeGetSeconds(cmDuration)
                            }
                            if let formats = try? await asset.load(.availableMetadataFormats) {
                                for format in formats {
                                    if let items = try? await asset.loadMetadata(for: format) {
                                        for item in items {
                                            if let val = try? await item.load(.value) {
                                                if let commonKey = item.commonKey {
                                                    if commonKey == .commonKeyTitle && embeddedTitle == nil { embeddedTitle = val as? String }
                                                    else if commonKey == .commonKeyArtist && embeddedArtist == nil { embeddedArtist = val as? String }
                                                    else if commonKey == .commonKeyAlbumName && embeddedAlbum == nil { embeddedAlbum = val as? String }
                                                    else if commonKey == .commonKeyCreationDate && embeddedYear == nil { embeddedYear = val as? String }
                                                    else if commonKey == .commonKeyType && embeddedGenre == nil { embeddedGenre = val as? String }
                                                    else if commonKey == .commonKeyArtwork && localArtwork == nil, let data = val as? Data { localArtwork = NSImage(data: data) }
                                                } else if let stringKey = item.key as? String {
                                                    let uKey = stringKey.uppercased()
                                                    if uKey == "TITLE" && embeddedTitle == nil { embeddedTitle = val as? String }
                                                    else if uKey == "ARTIST" && embeddedArtist == nil { embeddedArtist = val as? String }
                                                    else if uKey == "ALBUM" && embeddedAlbum == nil { embeddedAlbum = val as? String }
                                                    else if uKey == "ALBUMARTIST" && embeddedAlbumArtist == nil { embeddedAlbumArtist = val as? String }
                                                    else if (uKey == "DATE" || uKey == "YEAR") && embeddedYear == nil { embeddedYear = val as? String }
                                                    else if uKey == "GENRE" && embeddedGenre == nil { embeddedGenre = val as? String }
                                                    else if (uKey == "COVERART" || uKey == "METADATA_BLOCK_PICTURE") && localArtwork == nil, let data = val as? Data { localArtwork = NSImage(data: data) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            duration = CMTimeGetSeconds(asset.duration)
                            for item in asset.metadata {
                                if let commonKey = item.commonKey {
                                    if commonKey == .commonKeyTitle && embeddedTitle == nil { embeddedTitle = item.stringValue }
                                    else if commonKey == .commonKeyArtist && embeddedArtist == nil { embeddedArtist = item.stringValue }
                                    else if commonKey == .commonKeyAlbumName && embeddedAlbum == nil { embeddedAlbum = item.stringValue }
                                    else if commonKey == .commonKeyCreationDate && embeddedYear == nil { embeddedYear = item.stringValue }
                                    else if commonKey == .commonKeyType && embeddedGenre == nil { embeddedGenre = item.stringValue }
                                    else if commonKey == .commonKeyArtwork && localArtwork == nil, let data = item.dataValue { localArtwork = NSImage(data: data) }
                                } else if let stringKey = item.key as? String {
                                    let uKey = stringKey.uppercased()
                                    if uKey == "TITLE" && embeddedTitle == nil { embeddedTitle = item.stringValue }
                                    else if uKey == "ARTIST" && embeddedArtist == nil { embeddedArtist = item.stringValue }
                                    else if uKey == "ALBUM" && embeddedAlbum == nil { embeddedAlbum = item.stringValue }
                                    else if uKey == "ALBUMARTIST" && embeddedAlbumArtist == nil { embeddedAlbumArtist = item.stringValue }
                                    else if (uKey == "DATE" || uKey == "YEAR") && embeddedYear == nil { embeddedYear = item.stringValue }
                                    else if uKey == "GENRE" && embeddedGenre == nil { embeddedGenre = item.stringValue }
                                    else if (uKey == "COVERART" || uKey == "METADATA_BLOCK_PICTURE") && localArtwork == nil, let data = item.dataValue { localArtwork = NSImage(data: data) }
                                }
                            }
                        }
                        
                        let rawTitle = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                        let clean = AudioScanner.cleanTrackTitle(rawTitle)
                        let finalTitle = (embeddedTitle != nil && !embeddedTitle!.isEmpty) ? embeddedTitle! : clean.title
                        let finalArtist = (embeddedArtist != nil && !embeddedArtist!.isEmpty) ? embeddedArtist! : clean.artist
                        
                        let track = Track(title: finalTitle, artist: finalArtist, filePath: path, duration: duration.isNaN ? 0 : duration, artwork: localArtwork)
                        return (track, embeddedAlbum, embeddedAlbumArtist, embeddedYear, embeddedGenre)
                    }
                }
                var results: [Track] = []
                for await result in group {
                    if let res = result { 
                        results.append(res.track)
                        if extractedArtwork == nil { extractedArtwork = res.track.artwork }
                        if extractedAlbum == nil { extractedAlbum = res.album }
                        if extractedAlbumArtist == nil { extractedAlbumArtist = res.albumArtist }
                        if extractedYear == nil { extractedYear = res.year }
                        if extractedGenre == nil { extractedGenre = res.genre }
                    }
                }
                return results.sorted { $0.filePath < $1.filePath }
            }
            return (tracks, finalDir, extractedAlbum, extractedAlbumArtist, extractedYear, extractedGenre, extractedArtwork)
        }
        
        return ([], finalDir, nil, nil, nil, nil, nil)
    }
    
    static func cleanTrackTitle(_ rawTitle: String) -> (title: String, artist: String?) {
        var title = rawTitle
        var artist: String? = nil
        
        // Remove leading track numbers like "01 - ", "01 ", "1.", "01."
        if let regex = try? NSRegularExpression(pattern: "^\\d+[\\s\\.\\-]*") {
            title = regex.stringByReplacingMatches(in: title, range: NSRange(location: 0, length: title.utf16.count), withTemplate: "")
        }
        
        // Extract artist if "Artist - Title" format exists
        let components = title.components(separatedBy: " - ")
        if components.count >= 2 {
            // Assume the first part is artist, and the LAST part is the title.
            // This discards any album names that might be in the middle (e.g. Artist - Album - Title)
            let potentialArtist = components.first!.trimmingCharacters(in: .whitespacesAndNewlines)
            if potentialArtist.rangeOfCharacter(from: .letters) != nil {
                artist = potentialArtist
                title = components.last!.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return (title.trimmingCharacters(in: .whitespacesAndNewlines), artist)
    }
    
    static func parseCueFile(at cueURL: URL) async -> (tracks: [Track], albumTitle: String?, albumArtist: String?) {
        guard let content = try? String(contentsOf: cueURL, encoding: .utf8) else { return ([], nil, nil) }
        let lines = content.components(separatedBy: .newlines)
        
        var albumTitle: String?
        var albumArtist: String?
        var currentAudioFile: String?
        
        struct RawTrack {
            var title: String = ""
            var artist: String? = nil
            var startTime: Double = 0
            var file: String = ""
        }
        
        var rawTracks: [RawTrack] = []
        var currentTrack: RawTrack?
        var inTrack = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            if trimmed.hasPrefix("FILE") {
                let parts = trimmed.components(separatedBy: "\"")
                if parts.count >= 3 {
                    currentAudioFile = parts[1]
                }
            } else if trimmed.hasPrefix("TRACK") {
                if let t = currentTrack { rawTracks.append(t) }
                currentTrack = RawTrack(file: currentAudioFile ?? "")
                inTrack = true
            } else if trimmed.hasPrefix("TITLE") {
                let parts = trimmed.components(separatedBy: "\"")
                let title = parts.count >= 3 ? parts[1] : trimmed.replacingOccurrences(of: "TITLE ", with: "")
                if inTrack {
                    currentTrack?.title = title
                } else {
                    albumTitle = title
                }
            } else if trimmed.hasPrefix("PERFORMER") {
                let parts = trimmed.components(separatedBy: "\"")
                let artist = parts.count >= 3 ? parts[1] : trimmed.replacingOccurrences(of: "PERFORMER ", with: "")
                if inTrack {
                    currentTrack?.artist = artist
                } else {
                    albumArtist = artist
                }
            } else if trimmed.hasPrefix("INDEX 01") {
                let parts = trimmed.components(separatedBy: " ")
                if parts.count >= 3 {
                    let timeStr = parts[2]
                    let timeParts = timeStr.components(separatedBy: ":")
                    if timeParts.count == 3, let m = Double(timeParts[0]), let s = Double(timeParts[1]), let f = Double(timeParts[2]) {
                        currentTrack?.startTime = m * 60 + s + (f / 75.0)
                    }
                }
            }
        }
        if let t = currentTrack { rawTracks.append(t) }
        
        var tracks: [Track] = []
        let directory = cueURL.deletingLastPathComponent()
        
        for (i, raw) in rawTracks.enumerated() {
            let audioURL = directory.appendingPathComponent(raw.file)
            var duration: Double = 0
            
            if i < rawTracks.count - 1 {
                duration = rawTracks[i + 1].startTime - raw.startTime
            } else {
                let asset = AVURLAsset(url: audioURL)
                var totalDuration: Double = 0
                if #available(macOS 13.0, *) {
                    if let cmDuration = try? await asset.load(.duration) {
                        totalDuration = CMTimeGetSeconds(cmDuration)
                    }
                } else {
                    totalDuration = CMTimeGetSeconds(asset.duration)
                }
                duration = totalDuration - raw.startTime
            }
            
            tracks.append(Track(title: raw.title, artist: raw.artist, filePath: audioURL.path, duration: max(0, duration)))
        }
        
        return (tracks, albumTitle, albumArtist)
    }
}
