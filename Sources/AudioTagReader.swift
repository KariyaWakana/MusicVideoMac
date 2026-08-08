import Foundation
import AVFoundation

struct ExtractedTags {
    var title: String?
    var artist: String?
    var album: String?
    var year: String?
    var genre: String?
    var artworkURL: URL?
}

class AudioTagReader {
    
    /// Reads ID3/Vorbis/MP4 tags and extracts artwork to a temporary file if present.
    static func readTags(from fileURL: URL, completion: @escaping (ExtractedTags) -> Void) {
        Task {
            var tags = ExtractedTags()
            let asset = AVAsset(url: fileURL)
            
            do {
                // Async load common metadata to prevent blocking
                let metadata = try await asset.load(.commonMetadata)
                
                for item in metadata {
                    guard let key = item.commonKey else { continue }
                    
                    switch key {
                    case .commonKeyTitle:
                        tags.title = try? await item.load(.stringValue)
                    case .commonKeyArtist:
                        tags.artist = try? await item.load(.stringValue)
                    case .commonKeyAlbumName:
                        tags.album = try? await item.load(.stringValue)
                    case .commonKeyCreationDate:
                        if let dateString = try? await item.load(.stringValue) {
                            tags.year = String(dateString.prefix(4))
                        }
                    case .commonKeyType:
                        tags.genre = try? await item.load(.stringValue)
                    case .commonKeyArtwork:
                        if let data = try? await item.load(.dataValue) {
                            let tempDir = FileManager.default.temporaryDirectory
                            let tempFileURL = tempDir.appendingPathComponent("extracted_cover_\(UUID().uuidString)").appendingPathExtension("jpg")
                            try? data.write(to: tempFileURL)
                            tags.artworkURL = tempFileURL
                        }
                    default:
                        break
                    }
                }
            } catch {
                print("AudioTagReader: Failed to load metadata from \(fileURL.lastPathComponent)")
            }
            
            DispatchQueue.main.async {
                completion(tags)
            }
        }
    }
}
