import Foundation
import AVFoundation
import CoreGraphics
import AppKit
import SwiftUI

enum AssemblerError: Error, LocalizedError {
    case writerInitializationFailed
    case videoInputFailed
    case audioInputFailed
    case trackNotFound
    case imageRendererFailed
    case pixelBufferPoolNil
    case cvPixelBufferCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .writerInitializationFailed: return "Failed to initialize AVAssetWriter."
        case .videoInputFailed: return "Failed to setup Video Input."
        case .audioInputFailed: return "Failed to setup Audio Input."
        case .trackNotFound: return "An audio track could not be read."
        case .imageRendererFailed: return "ImageRenderer failed to create CGImage."
        case .pixelBufferPoolNil: return "AVAssetWriter pixel buffer pool is nil."
        case .cvPixelBufferCreationFailed: return "CVPixelBufferPoolCreatePixelBuffer failed."
        }
    }
}

class NativeVideoAssembler {
    
    static func assemble(meta: AlbumMetadata, coverImage: NSImage?, resolution: String, outputURL: URL, progress: @escaping (String, Double?) -> Void, completion: @escaping (Bool) -> Void) {
        let width: CGFloat = resolution == "4K" ? 3840 : (resolution == "480p" ? 852 : 1920)
        let height: CGFloat = resolution == "4K" ? 2160 : (resolution == "480p" ? 480 : 1080)
        let renderSize = CGSize(width: width, height: height)
        let scale: CGFloat = resolution == "4K" ? 2.0 : (resolution == "480p" ? (480.0 / 1080.0) : 1.0)
        
        // Calculate total duration
        let totalDuration = meta.tracks.reduce(0.0) { $0 + $1.duration }
        guard totalDuration > 0 else {
            completion(false)
            return
        }
        
        Task.detached(priority: .userInitiated) {
            do {
                try await performAssembly(meta: meta, coverImage: coverImage, renderSize: renderSize, scale: scale, totalDuration: totalDuration, outputURL: outputURL, progress: progress)
                await MainActor.run { completion(true) }
            } catch {
                print("Native Assembly Error: \(error)")
                await MainActor.run {
                    progress("Error: \(error.localizedDescription)", nil)
                    completion(false)
                }
            }
        }
    }
    
    private static func performAssembly(meta: AlbumMetadata, coverImage: NSImage?, renderSize: CGSize, scale: CGFloat, totalDuration: Double, outputURL: URL, progress: @escaping (String, Double?) -> Void) async throws {
        
        // --- PHASE 1: VIDEO ONLY GENERATION ---
        await MainActor.run { progress("Rendering VFR Video Frames (No Audio)...", 0.1) }
        
        let tempVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_video.mp4")
        if FileManager.default.fileExists(atPath: tempVideoURL.path) {
            try FileManager.default.removeItem(at: tempVideoURL)
        }
        
        let writer = try AVAssetWriter(outputURL: tempVideoURL, fileType: .mp4)
        
        // Setup Video Input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height)
        ]
        
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(renderSize.width),
            kCVPixelBufferHeightKey as String: Int(renderSize.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: sourcePixelBufferAttributes)
        
        guard writer.canAdd(videoInput) else { throw AssemblerError.videoInputFailed }
        writer.add(videoInput)
        
        guard writer.startWriting() else { throw writer.error ?? AssemblerError.writerInitializationFailed }
        writer.startSession(atSourceTime: .zero)
        
        let fps: Double = 60.0
        let timeScale: Int32 = 600000
        
        var currentSeconds: Double = 0.0
        var lastAppendedSeconds: Double = -1.0
        
        for (index, track) in meta.tracks.enumerated() {
            let isLastTrack = (index == meta.tracks.count - 1)
            
            let actualCrossfadeDuration = min(1.0, track.duration / 2.0)
            let crossfadeFrames = isLastTrack ? 0 : Int(actualCrossfadeDuration * fps)
            let staticDuration = track.duration - (isLastTrack ? 0 : actualCrossfadeDuration)
            
            let staticImage = try await generateCGImage(for: index, meta: meta, coverImage: coverImage, size: renderSize, scale: scale)
            let staticBuffer = try createPixelBuffer(for: staticImage, adaptor: adaptor, renderSize: renderSize)
            
            // Adaptive VFR: 1 FPS for static portions (prevents encoder bottleneck while keeping scrubbing buttery smooth)
            var remainingStatic = staticDuration
            while remainingStatic > 0 {
                let step = min(1.0, remainingStatic)
                let pts = CMTime(seconds: currentSeconds, preferredTimescale: timeScale)
                let lastPts = CMTime(seconds: lastAppendedSeconds, preferredTimescale: timeScale)
                
                if CMTimeCompare(pts, lastPts) > 0 {
                    try await appendPixelBuffer(staticBuffer, at: pts, adaptor: adaptor, input: videoInput)
                    lastAppendedSeconds = currentSeconds
                }
                currentSeconds += step
                remainingStatic -= step
            }
            
            if !isLastTrack && crossfadeFrames > 0 {
                let nextIndex = index + 1
                for f in 0..<crossfadeFrames {
                    // Yield to the main runloop and allow autorelease pools to drain, preventing memory bloat
                    await Task.yield()
                    
                    // Temporal Anti-Aliasing (Motion Blur): Render 2 subframes at 120fps and blend to 60fps
                    let t1 = (Double(f) + 0.0) / Double(crossfadeFrames)
                    let t2 = (Double(f) + 0.5) / Double(crossfadeFrames)
                    
                    let morphedCG1 = try await generateCGImage(for: index, nextTrackIndex: nextIndex, transitionProgress: t1, meta: meta, coverImage: coverImage, size: renderSize, scale: scale)
                    let morphedCG2 = try await generateCGImage(for: index, nextTrackIndex: nextIndex, transitionProgress: t2, meta: meta, coverImage: coverImage, size: renderSize, scale: scale)
                    
                    let blendedBuffer = try createBlendedPixelBuffer(cgImage1: morphedCG1, cgImage2: morphedCG2, adaptor: adaptor, renderSize: renderSize)
                    
                    let pts = CMTime(seconds: currentSeconds, preferredTimescale: timeScale)
                    let lastPts = CMTime(seconds: lastAppendedSeconds, preferredTimescale: timeScale)
                    
                    if CMTimeCompare(pts, lastPts) > 0 {
                        try await appendPixelBuffer(blendedBuffer, at: pts, adaptor: adaptor, input: videoInput)
                        lastAppendedSeconds = currentSeconds
                    }
                    currentSeconds += 1.0 / fps
                }
            }
            
            await MainActor.run {
                progress("Rendering Adaptive VFR Frames...", 0.1 + 0.6 * (Double(index) / Double(meta.tracks.count)))
            }
        }
        
        videoInput.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw writer.error ?? AssemblerError.writerInitializationFailed
        }
        
        // --- PHASE 2: COMPOSITION ---
        await MainActor.run { progress("Multiplexing Native Audio...", 0.75) }
        
        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AssemblerError.writerInitializationFailed
        }
        
        // Load the generated temp video
        let videoAsset = AVURLAsset(url: tempVideoURL)
        if let videoAssetTrack = try await videoAsset.loadTracks(withMediaType: .video).first {
            let vDuration = try await videoAsset.load(.duration)
            try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: vDuration), of: videoAssetTrack, at: .zero)
        }
        
        // Sequentially insert all original audio tracks
        var currentAudioTime = CMTime.zero
        for track in meta.tracks {
            let audioAsset = AVURLAsset(url: URL(fileURLWithPath: track.filePath))
            if let audioAssetTrack = try await audioAsset.loadTracks(withMediaType: .audio).first {
                let aDuration = try await audioAsset.load(.duration)
                try compAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: aDuration), of: audioAssetTrack, at: currentAudioTime)
                currentAudioTime = CMTimeAdd(currentAudioTime, aDuration)
            }
        }
        
        // --- PHASE 3: EXPORT ---
        await MainActor.run { progress("Exporting Final MP4 Container...", 0.85) }
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // Use Highest Quality preset to ensure maximum compatibility and fidelity
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw AssemblerError.writerInitializationFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputURL.pathExtension.lowercased() == "mov" ? .mov : .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        await exportSession.export()
        
        // Cleanup temp file
        try? FileManager.default.removeItem(at: tempVideoURL)
        
        if exportSession.status == .failed {
            throw exportSession.error ?? AssemblerError.writerInitializationFailed
        }
    }
    
    // MARK: - Pixel Buffer Helpers

    private static func createPixelBuffer(for cgImage: CGImage, adaptor: AVAssetWriterInputPixelBufferAdaptor, renderSize: CGSize) throws -> CVPixelBuffer {
        return try autoreleasepool {
            guard let pixelBufferPool = adaptor.pixelBufferPool else { 
                throw AssemblerError.pixelBufferPoolNil 
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
            
            guard let buffer = pixelBuffer else { 
                throw AssemblerError.cvPixelBufferCreationFailed 
            }
            
            CVPixelBufferLockBaseAddress(buffer, [])
            let data = CVPixelBufferGetBaseAddress(buffer)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            
            if let context = CGContext(data: data, width: Int(renderSize.width), height: Int(renderSize.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace, bitmapInfo: bitmapInfo) {
                let rect = CGRect(origin: .zero, size: renderSize)
                context.clear(rect)
                context.draw(cgImage, in: rect)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            
            return buffer
        }
    }

    private static func createBlendedPixelBuffer(cgImage1: CGImage, cgImage2: CGImage, adaptor: AVAssetWriterInputPixelBufferAdaptor, renderSize: CGSize) throws -> CVPixelBuffer {
        return try autoreleasepool {
            guard let pixelBufferPool = adaptor.pixelBufferPool else { 
                throw AssemblerError.pixelBufferPoolNil 
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
            
            guard let buffer = pixelBuffer else { 
                throw AssemblerError.cvPixelBufferCreationFailed 
            }
            
            CVPixelBufferLockBaseAddress(buffer, [])
            let data = CVPixelBufferGetBaseAddress(buffer)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            
            if let context = CGContext(data: data, width: Int(renderSize.width), height: Int(renderSize.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace, bitmapInfo: bitmapInfo) {
                let rect = CGRect(origin: .zero, size: renderSize)
                context.clear(rect)
                
                // Draw first frame at 100% opacity
                context.draw(cgImage1, in: rect)
                
                // Draw second frame at 50% opacity to create motion blur / temporal AA
                context.setAlpha(0.5)
                context.draw(cgImage2, in: rect)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            
            return buffer
        }
    }

    private static func appendPixelBuffer(_ buffer: CVPixelBuffer, at time: CMTime, adaptor: AVAssetWriterInputPixelBufferAdaptor, input: AVAssetWriterInput) async throws {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        adaptor.append(buffer, withPresentationTime: time)
    }
    
    @MainActor
    private static func generateCGImage(for trackIndex: Int, nextTrackIndex: Int? = nil, transitionProgress: Double = 0.0, meta: AlbumMetadata, coverImage: NSImage?, size: CGSize, scale: CGFloat) throws -> CGImage {
        return try autoreleasepool {
            // We reuse the existing FrameRenderer logic but return a CGImage instead of saving to disk
            
            // Read background color setting (bgColor is passed into FrameView)
            let useCustomColors = UserDefaults.standard.bool(forKey: "useCustomColors")
            
            var bgColor = Color(NSColor.windowBackgroundColor)
            if useCustomColors {
                let r = UserDefaults.standard.double(forKey: "customBgColorR")
                let g = UserDefaults.standard.double(forKey: "customBgColorG")
                let b = UserDefaults.standard.double(forKey: "customBgColorB")
                bgColor = Color(red: r, green: g, blue: b)
            }
            
            let view = FrameView(meta: meta, coverImage: coverImage, currentTrackIndex: trackIndex, nextTrackIndex: nextTrackIndex, transitionProgress: transitionProgress, bgColor: bgColor, scale: scale)
                .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.0 // Real pixel size
            
            guard let cgImage = renderer.cgImage else {
                throw AssemblerError.imageRendererFailed
            }
            return cgImage
        }
    }
}
