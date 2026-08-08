import Foundation

class MetadataFetcher {
    
    static let userAgent = "MusicVideoMacApp/1.0 ( https://github.com/cgga )"
    
    static func fetchMetadata(for directory: URL?, searchTerm: String, completion: @escaping (AlbumMetadata?) -> Void) {
        // Step 0: Find the first supported audio file to extract embedded tags
        var firstAudioFile: URL? = nil
        if let dir = directory, searchTerm.isEmpty {
            let fm = FileManager.default
            if let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) {
                for case let file as URL in enumerator {
                    let ext = file.pathExtension.lowercased()
                    if ["mp3", "flac", "m4a", "alac", "wav", "aiff", "ogg"].contains(ext) {
                        firstAudioFile = file
                        break
                    }
                }
            }
        }
        
        if let audioFile = firstAudioFile {
            AudioTagReader.readTags(from: audioFile) { tags in
                self.processHeuristicsAndFetch(directory: directory, searchTerm: searchTerm, embeddedTags: tags, completion: completion)
            }
        } else {
            self.processHeuristicsAndFetch(directory: directory, searchTerm: searchTerm, embeddedTags: nil, completion: completion)
        }
    }
    
    private static func processHeuristicsAndFetch(directory: URL?, searchTerm: String, embeddedTags: ExtractedTags?, completion: @escaping (AlbumMetadata?) -> Void) {
        var baseMeta = AlbumMetadata()
        var localCoverURL: URL? = embeddedTags?.artworkURL // Embedded artwork has highest priority!
        
        // 1. Try to extract from folder or parent folder
        if let dir = directory, searchTerm.isEmpty {
            let folderName = dir.lastPathComponent
            let parentFolderName = dir.deletingLastPathComponent().lastPathComponent
            
            func extractFrom(name: String) -> Bool {
                let components = name.components(separatedBy: " - ")
                if components.count >= 2 {
                    baseMeta.artist = components[0].trimmingCharacters(in: .whitespaces)
                    baseMeta.title = components[1...].joined(separator: " - ").trimmingCharacters(in: .whitespaces)
                    return true
                }
                return false
            }
            
            if !extractFrom(name: folderName) {
                if !extractFrom(name: parentFolderName) {
                    baseMeta.title = folderName
                }
            }
            
            // Look for local cover.jpg / cover.png
            let possibleCovers = ["cover.jpg", "cover.png", "folder.jpg", "Artwork.jpg", "Artwork.png"]
            for coverName in possibleCovers {
                let coverPath = dir.appendingPathComponent(coverName)
                if FileManager.default.fileExists(atPath: coverPath.path) {
                    localCoverURL = coverPath
                    break
                }
            }
            // If embedded tags gave us a title, it overwrites the folder guess.
            if let embeddedTitle = embeddedTags?.album ?? embeddedTags?.title, !embeddedTitle.isEmpty {
                baseMeta.title = embeddedTitle
            }
            if let embeddedArtist = embeddedTags?.artist, !embeddedArtist.isEmpty {
                baseMeta.artist = embeddedArtist
            }
            if let embeddedYear = embeddedTags?.year {
                baseMeta.year = embeddedYear
            }
            if let embeddedGenre = embeddedTags?.genre {
                baseMeta.genre = embeddedGenre
            }
        }
        
        // If we have a searchTerm from the UI, it takes absolute precedence over everything
        let query = searchTerm.isEmpty ? baseMeta.title : searchTerm
        if query.isEmpty {
            baseMeta.coverURL = localCoverURL
            completion(baseMeta)
            return
        }
        
        // 2. Try MusicBrainz first
        fetchFromMusicBrainz(query: query, baseMeta: baseMeta, localCoverURL: localCoverURL) { mbMeta in
            if let mbMeta = mbMeta {
                completion(mbMeta)
            } else {
                // 3. Fallback to iTunes
                fetchFromITunes(query: query, baseMeta: baseMeta, localCoverURL: localCoverURL, completion: completion)
            }
        }
    }
    
    private static func fetchFromMusicBrainz(query: String, baseMeta: AlbumMetadata, localCoverURL: URL?, completion: @escaping (AlbumMetadata?) -> Void) {
        guard let encodedTerm = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://musicbrainz.org/ws/2/release/?query=release:\(encodedTerm)&fmt=json") else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let releases = json["releases"] as? [[String: Any]],
                   let firstRelease = releases.first,
                   let mbid = firstRelease["id"] as? String {
                    
                    var meta = AlbumMetadata()
                    meta.title = baseMeta.title.isEmpty ? (firstRelease["title"] as? String ?? baseMeta.title) : baseMeta.title
                    
                    if let artistCredit = firstRelease["artist-credit"] as? [[String: Any]],
                       let firstArtist = artistCredit.first?["name"] as? String {
                        meta.artist = baseMeta.artist.isEmpty ? firstArtist : baseMeta.artist
                    } else {
                        meta.artist = baseMeta.artist
                    }
                    
                    if let date = firstRelease["date"] as? String {
                        meta.year = String(date.prefix(4))
                    }
                    
                    // Fetch Cover Art
                    if localCoverURL != nil {
                        meta.coverURL = localCoverURL
                        DispatchQueue.main.async { completion(meta) }
                    } else {
                        fetchCoverArtArchive(mbid: mbid) { coverURL in
                            if let coverURL = coverURL {
                                meta.coverURL = coverURL
                                DispatchQueue.main.async { completion(meta) }
                            } else {
                                // If MusicBrainz has the text data but no cover, we fail the MB search
                                // and fallback to iTunes which might have the cover.
                                completion(nil)
                            }
                        }
                    }
                } else {
                    completion(nil) // No MB results
                }
            } catch {
                completion(nil)
            }
        }.resume()
    }
    
    private static func fetchCoverArtArchive(mbid: String, completion: @escaping (URL?) -> Void) {
        guard let url = URL(string: "https://coverartarchive.org/release/\(mbid)") else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let images = json["images"] as? [[String: Any]],
                   let frontImage = images.first(where: { ($0["front"] as? Bool) == true }) ?? images.first,
                   let imageUrlString = frontImage["image"] as? String,
                   let imageUrl = URL(string: imageUrlString) {
                    completion(imageUrl)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }.resume()
    }
    
    private static func fetchFromITunes(query: String, baseMeta: AlbumMetadata, localCoverURL: URL?, completion: @escaping (AlbumMetadata?) -> Void) {
        guard let encodedTerm = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encodedTerm)&entity=album&limit=1") else {
            var meta = baseMeta
            meta.coverURL = localCoverURL
            DispatchQueue.main.async { completion(meta) }
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                var meta = baseMeta
                meta.coverURL = localCoverURL
                DispatchQueue.main.async { completion(meta) }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   let firstResult = results.first {
                    
                    var meta = AlbumMetadata()
                    meta.title = baseMeta.title.isEmpty ? (firstResult["collectionName"] as? String ?? baseMeta.title) : baseMeta.title
                    meta.artist = baseMeta.artist.isEmpty ? (firstResult["artistName"] as? String ?? baseMeta.artist) : baseMeta.artist
                    
                    if let releaseDate = firstResult["releaseDate"] as? String {
                        meta.year = String(releaseDate.prefix(4))
                    }
                    meta.genre = firstResult["primaryGenreName"] as? String ?? meta.genre
                    
                    if localCoverURL != nil {
                        meta.coverURL = localCoverURL
                    } else if let artworkUrl100 = firstResult["artworkUrl100"] as? String {
                        let highResUrl = artworkUrl100.replacingOccurrences(of: "100x100bb", with: "1000x1000bb")
                        meta.coverURL = URL(string: highResUrl)
                    }
                    
                    DispatchQueue.main.async {
                        completion(meta)
                    }
                } else {
                    DispatchQueue.main.async {
                        var meta = baseMeta
                        meta.coverURL = localCoverURL
                        completion(meta)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    var meta = baseMeta
                    meta.coverURL = localCoverURL
                    completion(meta)
                }
            }
        }.resume()
    }
}
