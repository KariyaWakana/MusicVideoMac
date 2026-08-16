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
                        var embeddedDiscNumber: Int? = nil
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
                                                    else if (uKey == "TPOS" || uKey == "DISC" || uKey == "DISK" || uKey == "DISCNUMBER") && embeddedDiscNumber == nil {
                                                        if let num = val as? NSNumber { embeddedDiscNumber = num.intValue }
                                                        else if let str = val as? String { embeddedDiscNumber = Int(str.components(separatedBy: "/").first ?? str) }
                                                    }
                                                    else if (uKey == "COVERART" || uKey == "METADATA_BLOCK_PICTURE") && localArtwork == nil, let data = val as? Data { localArtwork = NSImage(data: data) }
                                                } else if let identifier = item.identifier {
                                                    if identifier == .iTunesMetadataDiscNumber && embeddedDiscNumber == nil {
                                                        if let data = val as? Data, data.count >= 6 {
                                                            // iTunes stores disc number as data, usually 4-byte or 8-byte ints.
                                                            // Offset 4 usually contains the disc number. Offset 6 for total.
                                                            let disc = Int(data[5])
                                                            if disc > 0 { embeddedDiscNumber = disc }
                                                        } else if let num = val as? NSNumber {
                                                            embeddedDiscNumber = num.intValue
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Fallback to folder name matching (e.g. "Disk 1", "CD 2") if metadata is missing
                            if embeddedDiscNumber == nil {
                                let relPath = (path as NSString).replacingOccurrences(of: (finalDir?.path ?? "") + "/", with: "")
                                let pathComponents = relPath.components(separatedBy: "/")
                                if pathComponents.count > 1 {
                                    let parentFolder = pathComponents[0]
                                    if let regex = try? NSRegularExpression(pattern: "(?i)(?:cd|disc|disk)\\s*(\\d+)") {
                                        if let match = regex.firstMatch(in: parentFolder, range: NSRange(parentFolder.startIndex..., in: parentFolder)),
                                           let range = Range(match.range(at: 1), in: parentFolder) {
                                            embeddedDiscNumber = Int(parentFolder[range])
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
                                    else if (uKey == "TPOS" || uKey == "DISC" || uKey == "DISK" || uKey == "DISCNUMBER") && embeddedDiscNumber == nil {
                                        if let num = item.numberValue { embeddedDiscNumber = num.intValue }
                                        else if let str = item.stringValue { embeddedDiscNumber = Int(str.components(separatedBy: "/").first ?? str) }
                                    }
                                    else if (uKey == "COVERART" || uKey == "METADATA_BLOCK_PICTURE") && localArtwork == nil, let data = item.dataValue { localArtwork = NSImage(data: data) }
                                } else if let identifier = item.identifier {
                                    if identifier == .iTunesMetadataDiscNumber && embeddedDiscNumber == nil {
                                        if let data = item.dataValue, data.count >= 6 {
                                            let disc = Int(data[5])
                                            if disc > 0 { embeddedDiscNumber = disc }
                                        } else if let num = item.numberValue {
                                            embeddedDiscNumber = num.intValue
                                        }
                                    }
                                }
                            }
                            
                            // Fallback to folder name matching for older macOS versions too
                            if embeddedDiscNumber == nil {
                                let relPath = (path as NSString).replacingOccurrences(of: (finalDir?.path ?? "") + "/", with: "")
                                let pathComponents = relPath.components(separatedBy: "/")
                                if pathComponents.count > 1 {
                                    let parentFolder = pathComponents[0]
                                    if let regex = try? NSRegularExpression(pattern: "(?i)(?:cd|disc|disk)\\s*(\\d+)") {
                                        if let match = regex.firstMatch(in: parentFolder, range: NSRange(parentFolder.startIndex..., in: parentFolder)),
                                           let range = Range(match.range(at: 1), in: parentFolder) {
                                            embeddedDiscNumber = Int(parentFolder[range])
                                        }
                                    }
                                }
                            }
                        }
                        
                        let rawTitle = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                        let clean = AudioScanner.cleanTrackTitle(rawTitle)
                        let finalTitle = (embeddedTitle != nil && !embeddedTitle!.isEmpty) ? embeddedTitle! : clean.title
                        let finalArtist = (embeddedArtist != nil && !embeddedArtist!.isEmpty) ? embeddedArtist! : clean.artist
                        
                        // Folder structure takes precedence over ID3 tags for disc numbers
                        let parentFolder = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
                        if let regex = try? NSRegularExpression(pattern: "(?i)(?:cd|disc|disk)\\s*(\\d+)"),
                           let match = regex.firstMatch(in: parentFolder, range: NSRange(location: 0, length: parentFolder.utf16.count)) {
                            let numStr = (parentFolder as NSString).substring(with: match.range(at: 1))
                            embeddedDiscNumber = Int(numStr)
                        }
                        
                        let track = Track(title: finalTitle, artist: finalArtist, filePath: path, discNumber: embeddedDiscNumber, duration: duration.isNaN ? 0 : duration, artwork: localArtwork)
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
            
            tracks.append(Track(title: raw.title, artist: raw.artist, filePath: audioURL.path, audioStartTime: raw.startTime, duration: max(0, duration)))
        }
        
        return (tracks, albumTitle, albumArtist)
    }
    
    // Parses a timestamped text (e.g., "00:00 Movement 1\n05:30 Movement 2") and generates Track objects
    static func parseVirtualTracks(from text: String, originalTrack: Track) -> [Track] {
        let lines = text.components(separatedBy: .newlines)
        
        struct ParsedTime {
            var time: Double
            var title: String
            var disc: Int?
        }
        
        // Regex to match MM:SS or HH:MM:SS
        guard let regex = try? NSRegularExpression(pattern: "^(?:(\\d{1,2}):)?(\\d{1,2}):(\\d{2})\\s+(.+)$") else { return [] }
        var parsedTimes: [ParsedTime] = []
        var currentDisc = originalTrack.discNumber
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Check for Disc header
            if let discRegex = try? NSRegularExpression(pattern: "(?i)^(?:cd|disc|disk)\\s*(\\d+)"),
               let match = discRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) {
                let numStr = (trimmed as NSString).substring(with: match.range(at: 1))
                currentDisc = Int(numStr)
                continue
            }
            
            if let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) {
                let nsString = trimmed as NSString
                
                var hours = 0.0
                var minutes = 0.0
                var seconds = 0.0
                
                let range1 = match.range(at: 1)
                let range2 = match.range(at: 2)
                let range3 = match.range(at: 3)
                let titleRange = match.range(at: 4)
                
                if range1.location != NSNotFound {
                    hours = Double(nsString.substring(with: range1)) ?? 0.0
                    minutes = Double(nsString.substring(with: range2)) ?? 0.0
                } else {
                    minutes = Double(nsString.substring(with: range2)) ?? 0.0
                }
                seconds = Double(nsString.substring(with: range3)) ?? 0.0
                
                let title = nsString.substring(with: titleRange).trimmingCharacters(in: .whitespaces)
                let totalSeconds = (hours * 3600) + (minutes * 60) + seconds
                
                var pt = ParsedTime(time: totalSeconds, title: title)
                pt.disc = currentDisc
                parsedTimes.append(pt)
            }
        }
        
        // Sort just in case user inputted them out of order
        parsedTimes.sort { $0.time < $1.time }
        
        var virtualTracks: [Track] = []
        for (i, pt) in parsedTimes.enumerated() {
            var duration: Double = 0
            if i < parsedTimes.count - 1 {
                duration = parsedTimes[i + 1].time - pt.time
            } else {
                duration = originalTrack.duration - pt.time
            }
            
            virtualTracks.append(Track(
                title: pt.title,
                artist: originalTrack.artist, // Inherit artist
                filePath: originalTrack.filePath, // Use the same audio file
                discNumber: pt.disc, // Inherited or parsed disc
                audioStartTime: pt.time,
                duration: max(0, duration)
            ))
        }
        
        return virtualTracks
    }
}
import Foundation
import AppKit

class CDRipManager {
    static let shared = CDRipManager()
    
    // Rips the CD at `sourceURL` (e.g. /Volumes/Audio CD) to a user-selected directory.
    // Progress callback returns 0.0 to 1.0
    func ripAudioCD(from sourceURL: URL, progress: @escaping (String, Double) -> Void, completion: @escaping (URL?) -> Void) {
        
        let fileManager = FileManager.default
        let extensions = ["aiff", "aif", "wav"]
        var audioFiles: [URL] = []
        
        do {
            let files = try fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
            audioFiles = files.filter { extensions.contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        if audioFiles.isEmpty {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        // Let the user choose destination via NSOpenPanel
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.message = "Choose a destination folder to save the ripped CD tracks."
            panel.prompt = "Save Rips Here"
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.canChooseFiles = false
            
            // Suggest ~/Music/MusicVideoMacApp/Rips/
            let musicDir = fileManager.urls(for: .musicDirectory, in: .userDomainMask).first!
            let appMusicDir = musicDir.appendingPathComponent("MusicVideoMacApp").appendingPathComponent("Rips")
            
            try? fileManager.createDirectory(at: appMusicDir, withIntermediateDirectories: true, attributes: nil)
            panel.directoryURL = appMusicDir
            
            let handler: (NSApplication.ModalResponse) -> Void = { response in
                if response == .OK, let destinationURL = panel.url {
                    Task.detached(priority: .userInitiated) {
                        await self.performRip(files: audioFiles, to: destinationURL, progress: progress) { finalURL in
                            DispatchQueue.main.async { completion(finalURL) }
                        }
                    }
                } else {
                    completion(nil) // User cancelled
                }
            }
            
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window, completionHandler: handler)
            } else {
                NSApp.activate(ignoringOtherApps: true)
                panel.begin(completionHandler: handler)
            }
        }
    }
    
    private func performRip(files: [URL], to destination: URL, progress: @escaping (String, Double) -> Void, completion: @escaping (URL?) -> Void) async {
        let fileManager = FileManager.default
        
        // Create an album folder inside the destination
        // If it's just "Audio CD", try to get a better name or just use a timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let albumFolderName = "Audio_CD_Rip_\(dateFormatter.string(from: Date()))"
        let targetDir = destination.appendingPathComponent(albumFolderName)
        
        do {
            try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            completion(nil)
            return
        }
        
        let totalFiles = files.count
        
        for (index, file) in files.enumerated() {
            let fileName = file.lastPathComponent
            let targetURL = targetDir.appendingPathComponent(fileName)
            
            let trackProgress = Double(index) / Double(totalFiles)
            await MainActor.run {
                progress("Ripping \(fileName)...", trackProgress)
            }
            
            do {
                // Audio CDs are slow to read, so we read chunks and write chunks to show real progress
                // However, standard FileManager.copyItem is usually fine for a 50MB aiff file (takes 1-3 seconds).
                // To keep it robust and not freeze the UI, we use FileHandle copying.
                try await copyFileWithProgress(from: file, to: targetURL) { fraction in
                    let overallProgress = trackProgress + (fraction / Double(totalFiles))
                    progress("Ripping \(fileName)...", overallProgress)
                }
            } catch {
                print("Failed to rip file: \(file.path) - \(error.localizedDescription)")
                // Continue to next file
            }
        }
        await MainActor.run {
            progress("CD Rip Complete! Ejecting disc...", 1.0)
        }
        
        // Eject the CD to prevent slot-loading drives from getting stuck
        // We use NSWorkspace unmountAndEjectDevice
        if let volumeURL = files.first?.deletingLastPathComponent() {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volumeURL)
            } catch {
                print("Failed to eject CD: \(error)")
            }
        }
        
        completion(targetDir)
    }
    
    private func copyFileWithProgress(from source: URL, to destination: URL, progressHandler: @escaping (Double) -> Void) async throws {
        let chunkSize = 1024 * 1024 * 4 // 4 MB chunks
        let sourceHandle = try FileHandle(forReadingFrom: source)
        
        // Create empty destination file
        FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: nil)
        let destinationHandle = try FileHandle(forWritingTo: destination)
        
        defer {
            try? sourceHandle.close()
            try? destinationHandle.close()
        }
        
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let fileSize = fileAttributes[.size] as? UInt64 ?? 0
        
        var bytesRead: UInt64 = 0
        
        while true {
            guard let data = try sourceHandle.read(upToCount: chunkSize), !data.isEmpty else {
                break
            }
            
            try destinationHandle.write(contentsOf: data)
            bytesRead += UInt64(data.count)
            
            if fileSize > 0 {
                let fraction = Double(bytesRead) / Double(fileSize)
                await MainActor.run { progressHandler(fraction) }
            }
            
            // Yield to avoid blocking the cooperative thread pool
            await Task.yield()
        }
    }
}
