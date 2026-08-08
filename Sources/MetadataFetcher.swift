import Foundation

class MetadataFetcher {
    static func fetchMetadata(for directory: URL?, searchTerm: String, completion: @escaping (AlbumMetadata?) -> Void) {
        var baseMeta = AlbumMetadata()
        var localCoverURL: URL? = nil
        
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
        }
        
        let query = searchTerm.isEmpty ? baseMeta.title : searchTerm
        
        guard let encodedTerm = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encodedTerm)&entity=album&limit=1") else {
            baseMeta.coverURL = localCoverURL
            completion(baseMeta)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   let firstResult = results.first {
                    
                    var meta = AlbumMetadata()
                    // Only override title/artist if we didn't extract them from the folder
                    meta.title = baseMeta.title.isEmpty ? (firstResult["collectionName"] as? String ?? baseMeta.title) : baseMeta.title
                    meta.artist = baseMeta.artist.isEmpty ? (firstResult["artistName"] as? String ?? baseMeta.artist) : baseMeta.artist
                    
                    if let releaseDate = firstResult["releaseDate"] as? String {
                        meta.year = String(releaseDate.prefix(4))
                    }
                    meta.genre = firstResult["primaryGenreName"] as? String ?? meta.genre
                    
                    if localCoverURL != nil {
                        meta.coverURL = localCoverURL // Local cover takes priority
                    } else if let artworkUrl100 = firstResult["artworkUrl100"] as? String {
                        let highResUrl = artworkUrl100.replacingOccurrences(of: "100x100bb", with: "1000x1000bb")
                        meta.coverURL = URL(string: highResUrl)
                    }
                    
                    DispatchQueue.main.async {
                        completion(meta)
                    }
                } else {
                    DispatchQueue.main.async {
                        baseMeta.coverURL = localCoverURL
                        completion(baseMeta)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    baseMeta.coverURL = localCoverURL
                    completion(baseMeta)
                }
            }
        }.resume()
    }
}
