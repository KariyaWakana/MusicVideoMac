import Foundation

// Simulate the logic in AppViewModel / ContentView
struct Track {
    var title: String
    var discNumber: Int?
}

var tracks = [
    Track(title: "Track 1", discNumber: 1),
    Track(title: "Track 2", discNumber: 1),
    Track(title: "Track 3", discNumber: 2)
]

let uniqueDiscs = Array(Set(tracks.compactMap { $0.discNumber })).sorted()
print(uniqueDiscs)
