import Foundation

// Copying necessary structs and logic from the app to test AudioScanner regex
let home = NSHomeDirectory()
let albumPath = home + "/Downloads/Remember11 -the age of infinity- SOUND COLLECTION"
print("Checking album path: \(albumPath)")

let fm = FileManager.default
do {
    let subdirs = try fm.contentsOfDirectory(atPath: albumPath)
    for subdir in subdirs {
        print("Found: \(subdir)")
    }
} catch {
    print("Error reading directory: \(error)")
}
