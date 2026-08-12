import SwiftUI
import Observation
import Combine

enum RenderJobStatus: Equatable {
    case queued
    case rendering
    case completed
    case failed(String)
}

@Observable
class RenderJob: Identifiable {
    let id = UUID()
    let albumTitle: String
    let meta: AlbumMetadata
    let coverImage: NSImage?
    let resolution: String
    let outputURL: URL
    let defaultsSuite: String
    
    var status: RenderJobStatus = .queued
    var progress: Double = 0.0
    var message: String = "Waiting in queue..."
    
    init(meta: AlbumMetadata, coverImage: NSImage?, resolution: String, outputURL: URL) {
        self.albumTitle = meta.title
        self.meta = meta
        self.coverImage = coverImage
        self.resolution = resolution
        self.outputURL = outputURL
        
        let uuidStr = self.id.uuidString
        self.defaultsSuite = "RenderJob-\(uuidStr)"
        
        if let customDefaults = UserDefaults(suiteName: self.defaultsSuite) {
            let standardDict = UserDefaults.standard.dictionaryRepresentation()
            for (key, value) in standardDict {
                customDefaults.set(value, forKey: key)
            }
        }
    }
}

@Observable
class RenderQueueManager {
    static let shared = RenderQueueManager()
    
    var jobs: [RenderJob] = []
    private var isRendering = false
    
    private init() {}
    
    func enqueue(meta: AlbumMetadata, coverImage: NSImage?, resolution: String, outputURL: URL) {
        let job = RenderJob(meta: meta, coverImage: coverImage, resolution: resolution, outputURL: outputURL)
        DispatchQueue.main.async {
            self.jobs.append(job)
            self.processNext()
        }
    }
    
    func clearCompleted() {
        jobs.removeAll { $0.status == .completed }
    }
    
    private func processNext() {
        guard !isRendering else { return }
        guard let nextJob = jobs.first(where: { $0.status == .queued }) else { return }
        
        isRendering = true
        nextJob.status = .rendering
        nextJob.message = "Assembling video with Native VFR Engine..."
        
        NativeVideoAssembler.assemble(meta: nextJob.meta, coverImage: nextJob.coverImage, resolution: nextJob.resolution, outputURL: nextJob.outputURL, defaultsSuite: nextJob.defaultsSuite) { msg, percent in
            DispatchQueue.main.async {
                nextJob.message = msg
                if let percent = percent {
                    nextJob.progress = percent
                }
            }
        } completion: { success in
            DispatchQueue.main.async {
                if success {
                    nextJob.status = .completed
                    nextJob.message = "Success! Saved to \(nextJob.outputURL.lastPathComponent)."
                    nextJob.progress = 1.0
                    // Optionally open Finder
                    NSWorkspace.shared.activateFileViewerSelecting([nextJob.outputURL])
                } else {
                    nextJob.status = .failed("Failed to render video.")
                }
                
                // Cleanup snapshot defaults
                UserDefaults().removePersistentDomain(forName: nextJob.defaultsSuite)
                
                self.isRendering = false
                self.processNext()
            }
        }
    }
}
