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
    
    static func assemble(meta: AlbumMetadata, coverImage: NSImage?, resolution: String, outputURL: URL, defaultsSuite: String, progress: @escaping (String, Double?) -> Void, completion: @escaping (Bool) -> Void) {
        
        Task.detached {
            do {
                let is4K = resolution == "4K"
                let is480p = resolution == "480p"
                
                let width: CGFloat = is4K ? 3840 : (is480p ? 854 : 1920)
                let height: CGFloat = is4K ? 2160 : (is480p ? 480 : 1080)
                let scale: CGFloat = is4K ? 2.0 : (is480p ? (480.0 / 1080.0) : 1.0)
                let renderSize = CGSize(width: width, height: height)
                
                let totalDuration = meta.tracks.reduce(0.0) { $0 + $1.duration }
                
                try await performAssembly(meta: meta, coverImage: coverImage, renderSize: renderSize, scale: scale, totalDuration: totalDuration, outputURL: outputURL, defaultsSuite: defaultsSuite, progress: progress)
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
    
    private static func performAssembly(meta: AlbumMetadata, coverImage: NSImage?, renderSize: CGSize, scale: CGFloat, totalDuration: Double, outputURL: URL, defaultsSuite: String, progress: @escaping (String, Double?) -> Void) async throws {
        
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
        let defaults = UserDefaults(suiteName: defaultsSuite) ?? UserDefaults.standard
        let useSegmentAssembly = defaults.object(forKey: "useSegmentAssembly") == nil ? false : defaults.bool(forKey: "useSegmentAssembly")
        let useCFR = defaults.object(forKey: "useConstantFrameRate") == nil ? true : defaults.bool(forKey: "useConstantFrameRate")
        
        if useSegmentAssembly && useCFR {
            try await assembleWithSegments(meta: meta, coverImage: coverImage, destinationURL: outputURL, renderSize: renderSize, scale: scale, fps: fps, defaultsSuite: defaultsSuite, progress: progress)
            return
        }
        
        let timeScale: CMTimeScale = 600000
        
        let discTransitionDuration = defaults.double(forKey: "discTransitionDuration")
        
        var currentSeconds: Double = 0.0
        var lastAppendedSeconds: Double = -1.0
        
        for (index, track) in meta.tracks.enumerated() {
            let isLastTrack = (index == meta.tracks.count - 1)
            let nextTrack = isLastTrack ? nil : meta.tracks[index + 1]
            let isDiscTransition = !isLastTrack && track.discNumber != nextTrack?.discNumber
            
            let actualCrossfadeDuration = min(1.0, track.duration / 2.0)
            let crossfadeFrames = (isLastTrack || isDiscTransition) ? 0 : Int(actualCrossfadeDuration * fps)
            let staticDuration = track.duration - ((isLastTrack || isDiscTransition) ? 0 : actualCrossfadeDuration)
            
            let staticImage = try await generateCGImage(for: index, meta: meta, coverImage: coverImage, size: renderSize, scale: scale, defaultsSuite: defaultsSuite)
            let staticBuffer = try createPixelBuffer(for: staticImage, adaptor: adaptor, renderSize: renderSize)
            
            let useCFR = defaults.object(forKey: "useConstantFrameRate") == nil ? true : defaults.bool(forKey: "useConstantFrameRate")
            let vfrBaselineFPS = defaults.object(forKey: "vfrBaselineFPS") == nil ? 1.0 : defaults.double(forKey: "vfrBaselineFPS")
            
            if useCFR {
                // Constant Frame Rate (CFR): 60 FPS for static portions.
                // Fast approach: We reuse the EXACT SAME static pixel buffer in memory.
                // This skips all rendering/drawing CPU cost and pushes frames straight to the hardware encoder.
                let endStaticSeconds = currentSeconds + staticDuration
                while currentSeconds < endStaticSeconds {
                    let pts = CMTime(seconds: currentSeconds, preferredTimescale: timeScale)
                    let lastPts = CMTime(seconds: lastAppendedSeconds, preferredTimescale: timeScale)
                    
                    if CMTimeCompare(pts, lastPts) > 0 {
                        // INLINE append logic to bypass async/await context switching overhead on the hot path
                        while !videoInput.isReadyForMoreMediaData {
                            try await Task.sleep(nanoseconds: 1_000_000)
                        }
                        adaptor.append(staticBuffer, withPresentationTime: pts)
                        lastAppendedSeconds = currentSeconds
                    }
                    
                    let nextSeconds = currentSeconds + (1.0 / fps)
                    if nextSeconds > endStaticSeconds {
                        // Sync up the exact time boundary for audio perfect sync
                        currentSeconds = endStaticSeconds
                    } else {
                        currentSeconds = nextSeconds
                    }
                }
            } else {
                // Adaptive VFR with baseline FPS to trick platforms into keeping 60fps transitions
                var remainingStatic = staticDuration
                let frameStep = 1.0 / max(1.0, vfrBaselineFPS)
                while remainingStatic > 0 {
                    let step = min(frameStep, remainingStatic)
                    let pts = CMTime(seconds: currentSeconds, preferredTimescale: timeScale)
                    let lastPts = CMTime(seconds: lastAppendedSeconds, preferredTimescale: timeScale)
                    
                    if CMTimeCompare(pts, lastPts) > 0 {
                        // INLINE append logic to bypass async/await context switching overhead
                        while !videoInput.isReadyForMoreMediaData {
                            try await Task.sleep(nanoseconds: 1_000_000)
                        }
                        adaptor.append(staticBuffer, withPresentationTime: pts)
                        lastAppendedSeconds = currentSeconds
                    }
                    currentSeconds += step
                    remainingStatic -= step
                }
            }
            
            if !isLastTrack {
                let nextIndex = index + 1
                if isDiscTransition {
                    let transitionSeconds = discTransitionDuration > 0 ? discTransitionDuration : 3.0
                    let transitionFrames = Int(transitionSeconds * fps)
                    
                    if transitionFrames > 0 {
                        for f in 0..<transitionFrames {
                            await Task.yield()
                            
                            let t = Double(f) / Double(transitionFrames)
                            let morphedCG = try await generateCGImage(for: index, nextTrackIndex: nextIndex, transitionProgress: t, isDiscTransition: true, meta: meta, coverImage: coverImage, size: renderSize, scale: scale, defaultsSuite: defaultsSuite)
                            let buffer = try createPixelBuffer(for: morphedCG, adaptor: adaptor, renderSize: renderSize)
                            
                            let pts = CMTime(seconds: currentSeconds, preferredTimescale: timeScale)
                            let lastPts = CMTime(seconds: lastAppendedSeconds, preferredTimescale: timeScale)
                            if CMTimeCompare(pts, lastPts) > 0 {
                                try await appendPixelBuffer(buffer, at: pts, adaptor: adaptor, input: videoInput)
                                lastAppendedSeconds = currentSeconds
                            }
                            currentSeconds += 1.0 / fps
                        }
                    }
                } else if crossfadeFrames > 0 {
                    for f in 0..<crossfadeFrames {
                        // Yield to the main runloop and allow autorelease pools to drain, preventing memory bloat
                        await Task.yield()
                        
                        // Temporal Anti-Aliasing (Motion Blur): Render 2 subframes at 120fps and blend to 60fps
                        let t1 = (Double(f) + 0.0) / Double(crossfadeFrames)
                        let t2 = (Double(f) + 0.5) / Double(crossfadeFrames)
                        
                        let morphedCG1 = try await generateCGImage(for: index, nextTrackIndex: nextIndex, transitionProgress: t1, meta: meta, coverImage: coverImage, size: renderSize, scale: scale, defaultsSuite: defaultsSuite)
                        let morphedCG2 = try await generateCGImage(for: index, nextTrackIndex: nextIndex, transitionProgress: t2, meta: meta, coverImage: coverImage, size: renderSize, scale: scale, defaultsSuite: defaultsSuite)
                        
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
        
        for (index, track) in meta.tracks.enumerated() {
            let audioAsset = AVURLAsset(url: URL(fileURLWithPath: track.filePath))
            if let audioAssetTrack = try await audioAsset.loadTracks(withMediaType: .audio).first {
                let start = CMTime(seconds: track.audioStartTime, preferredTimescale: 600)
                let duration = CMTime(seconds: track.duration, preferredTimescale: 600)
                try compAudioTrack.insertTimeRange(CMTimeRange(start: start, duration: duration), of: audioAssetTrack, at: currentAudioTime)
                currentAudioTime = CMTimeAdd(currentAudioTime, duration)
                
                // Add silence gap if there's a disc transition
                let isLastTrack = (index == meta.tracks.count - 1)
                if !isLastTrack {
                    let nextTrack = meta.tracks[index + 1]
                    if track.discNumber != nextTrack.discNumber {
                        let transitionSeconds = discTransitionDuration > 0 ? discTransitionDuration : 3.0
                        let silenceDuration = CMTime(seconds: transitionSeconds, preferredTimescale: 600)
                        currentAudioTime = CMTimeAdd(currentAudioTime, silenceDuration)
                    }
                }
            }
        }
        
        // --- PHASE 3: EXPORT ---
        await MainActor.run { progress("Exporting Final Video Container...", 0.85) }
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        
        let audioQuality = defaults.string(forKey: "audioQuality") ?? "AAC"
        let preset = (audioQuality == "Lossless") ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw AssemblerError.writerInitializationFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputURL.pathExtension.lowercased() == "mov" ? AVFileType.mov : AVFileType.mp4
        // Network optimization is not compatible with Passthrough mode sometimes, so conditionally set it
        exportSession.shouldOptimizeForNetworkUse = (audioQuality != "Lossless")
        
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
    private static func generateCGImage(for trackIndex: Int, nextTrackIndex: Int? = nil, transitionProgress: Double = 0.0, isDiscTransition: Bool = false, meta: AlbumMetadata, coverImage: NSImage?, size: CGSize, scale: CGFloat, defaultsSuite: String) throws -> CGImage {
        return try autoreleasepool {
            let defaults = UserDefaults(suiteName: defaultsSuite) ?? UserDefaults.standard
            
            // Read background color setting (bgColor is passed into FrameView)
            let useCustomColors = defaults.bool(forKey: "useCustomColors")
            
            var bgColor = Color(NSColor.windowBackgroundColor)
            if useCustomColors {
                let r = defaults.double(forKey: "customBgColorR")
                let g = defaults.double(forKey: "customBgColorG")
                let b = defaults.double(forKey: "customBgColorB")
                bgColor = Color(red: r, green: g, blue: b)
            }
            
            let view = FrameView(meta: meta, coverImage: coverImage, currentTrackIndex: trackIndex, nextTrackIndex: nextTrackIndex, transitionProgress: transitionProgress, isDiscTransition: isDiscTransition, bgColor: bgColor, scale: scale, config: FrameViewConfig(defaults: defaults))
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
import Foundation
import AVFoundation
import AppKit
import CoreImage

extension NativeVideoAssembler {
    
    static func assembleWithSegments(
        meta: AlbumMetadata,
        coverImage: NSImage?,
        destinationURL: URL,
        renderSize: CGSize,
        scale: CGFloat,
        fps: Double,
        defaultsSuite: String,
        progress: @escaping @MainActor (String, Double) -> Void
    ) async throws {
        
        let timeScale: CMTimeScale = 600
        
        // 1. Setup temporary directory for segments
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        await MainActor.run { progress("Generating Video Segments (CFR Fast Assembly)...", 0.0) }
        
        let defaults = UserDefaults(suiteName: defaultsSuite) ?? UserDefaults.standard
        let discTransitionDuration = defaults.object(forKey: "discTransitionDuration") == nil ? 3.0 : defaults.double(forKey: "discTransitionDuration")
        
        var generatedStaticBlocks: [Int: URL] = [:]
        var generatedTrackTransitions: [Int: URL] = [:]
        var generatedDiscTransitions: [Int: URL] = [:]
        
        // Render segments
        for (index, _) in meta.tracks.enumerated() {
            let nextIndex = index + 1
            let hasNextTrack = nextIndex < meta.tracks.count
            
            // Generate Static Block (1 second)
            if generatedStaticBlocks[index] == nil {
                let staticURL = tempDir.appendingPathComponent("static_\(index).mp4")
                try await renderSegment(to: staticURL, renderSize: renderSize, fps: fps, framesCount: Int(fps)) { t in
                    return try await generateCGImage(for: index, nextTrackIndex: nextIndex, transitionProgress: 0.0, isDiscTransition: false, meta: meta, coverImage: coverImage, size: renderSize, scale: scale, defaultsSuite: defaultsSuite)
                }
                generatedStaticBlocks[index] = staticURL
            }
            
            await MainActor.run { progress("Rendering Segments...", Double(index) / Double(meta.tracks.count) * 0.5) }
            
            if hasNextTrack {
                let isDiscTransition = meta.tracks[index].discNumber != meta.tracks[nextIndex].discNumber
                
                if isDiscTransition {
                    let transSecs = discTransitionDuration > 0 ? discTransitionDuration : 3.0
                    let transFrames = Int(transSecs * fps)
                    if transFrames > 0 {
                        let url = tempDir.appendingPathComponent("disc_trans_\(index).mp4")
                        try await renderSegment(to: url, renderSize: renderSize, fps: fps, framesCount: transFrames) { f in
                            let t = Double(f) / Double(transFrames)
                            return try await generateCGImage(for: index, nextTrackIndex: nextIndex, transitionProgress: t, isDiscTransition: true, meta: meta, coverImage: coverImage, size: renderSize, scale: scale, defaultsSuite: defaultsSuite)
                        }
                        generatedDiscTransitions[index] = url
                    }
                } else {
                    let crossfadeFrames = Int(1.0 * fps) // Standard track transition
                    if crossfadeFrames > 0 {
                        let url = tempDir.appendingPathComponent("track_trans_\(index).mp4")
                        try await renderSegment(to: url, renderSize: renderSize, fps: fps, framesCount: crossfadeFrames) { f in
                            // Temporal anti-aliasing logic from original
                            let t1 = (Double(f) + 0.0) / Double(crossfadeFrames)
                            return try await generateCGImage(for: index, nextTrackIndex: nextIndex, transitionProgress: t1, meta: meta, coverImage: coverImage, size: renderSize, scale: scale, defaultsSuite: defaultsSuite)
                        }
                        generatedTrackTransitions[index] = url
                    }
                }
            }
        }
        
        // 2. Assemble Composition
        await MainActor.run { progress("Assembling Segments Losslessly...", 0.6) }
        
        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AssemblerError.writerInitializationFailed
        }
        
        var currentVideoTime = CMTime.zero
        var currentAudioTime = CMTime.zero
        
        let oneSecond = CMTime(seconds: 1.0, preferredTimescale: timeScale)
        
        for (index, track) in meta.tracks.enumerated() {
            let nextIndex = index + 1
            let hasNextTrack = nextIndex < meta.tracks.count
            let isDiscTransition = hasNextTrack && (track.discNumber != meta.tracks[nextIndex].discNumber)
            
            var staticDuration = track.duration
            if hasNextTrack {
                staticDuration -= isDiscTransition ? discTransitionDuration : 1.0
            }
            staticDuration = max(0, staticDuration)
            
            // Insert Static Segments
            if let staticURL = generatedStaticBlocks[index] {
                let asset = AVURLAsset(url: staticURL)
                if let vTrack = try await asset.loadTracks(withMediaType: .video).first {
                    let fullSeconds = Int(floor(staticDuration))
                    let remainder = staticDuration - Double(fullSeconds)
                    
                    // Loop the 1-second segment
                    for _ in 0..<fullSeconds {
                        try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: oneSecond), of: vTrack, at: currentVideoTime)
                        currentVideoTime = CMTimeAdd(currentVideoTime, oneSecond)
                    }
                    
                    // Remainder slice
                    if remainder > 0 {
                        let remainderTime = CMTime(seconds: remainder, preferredTimescale: timeScale)
                        try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: remainderTime), of: vTrack, at: currentVideoTime)
                        currentVideoTime = CMTimeAdd(currentVideoTime, remainderTime)
                    }
                }
            }
            
            // Insert Transition
            if hasNextTrack {
                if isDiscTransition, let transURL = generatedDiscTransitions[index] {
                    let asset = AVURLAsset(url: transURL)
                    if let vTrack = try await asset.loadTracks(withMediaType: .video).first {
                        let tDur = try await asset.load(.duration)
                        try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: tDur), of: vTrack, at: currentVideoTime)
                        currentVideoTime = CMTimeAdd(currentVideoTime, tDur)
                    }
                } else if !isDiscTransition, let transURL = generatedTrackTransitions[index] {
                    let asset = AVURLAsset(url: transURL)
                    if let vTrack = try await asset.loadTracks(withMediaType: .video).first {
                        let tDur = try await asset.load(.duration)
                        try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: tDur), of: vTrack, at: currentVideoTime)
                        currentVideoTime = CMTimeAdd(currentVideoTime, tDur)
                    }
                }
            }
            
            // Insert Audio
            let audioAsset = AVURLAsset(url: URL(fileURLWithPath: track.filePath))
            if let audioAssetTrack = try await audioAsset.loadTracks(withMediaType: .audio).first {
                let start = CMTime(seconds: track.audioStartTime, preferredTimescale: timeScale)
                let duration = CMTime(seconds: track.duration, preferredTimescale: timeScale)
                try compAudioTrack.insertTimeRange(CMTimeRange(start: start, duration: duration), of: audioAssetTrack, at: currentAudioTime)
                currentAudioTime = CMTimeAdd(currentAudioTime, duration)
            }
            
            if isDiscTransition {
                currentAudioTime = CMTimeAdd(currentAudioTime, CMTime(seconds: discTransitionDuration, preferredTimescale: timeScale))
            }
        }
        
        // 3. Export
        await MainActor.run { progress("Exporting Passthrough Video...", 0.8) }
        
        try? FileManager.default.removeItem(at: destinationURL)
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw AssemblerError.writerInitializationFailed
        }
        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mp4
        
        await exportSession.export()
        
        if exportSession.status == .failed {
            throw exportSession.error ?? AssemblerError.writerInitializationFailed
        }
        
        await MainActor.run { progress("Done!", 1.0) }
    }
    
    private static func renderSegment(
        to url: URL,
        renderSize: CGSize,
        fps: Double,
        framesCount: Int,
        frameGenerator: (Int) async throws -> CGImage
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        
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
            kCVPixelBufferHeightKey as String: Int(renderSize.height)
        ]
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )
        
        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        
        guard writer.startWriting() else {
            throw AssemblerError.writerInitializationFailed
        }
        writer.startSession(atSourceTime: .zero)
        
        var currentSeconds = 0.0
        
        for f in 0..<framesCount {
            await Task.yield()
            
            let cgImage = try await frameGenerator(f)
            let buffer = try createPixelBuffer(for: cgImage, adaptor: adaptor, renderSize: renderSize)
            
            let pts = CMTime(seconds: currentSeconds, preferredTimescale: 600)
            
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            adaptor.append(buffer, withPresentationTime: pts)
            
            currentSeconds += 1.0 / fps
        }
        
        videoInput.markAsFinished()
        await writer.finishWriting()
    }
}
