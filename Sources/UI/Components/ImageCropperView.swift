import SwiftUI

struct ImageCropperView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.undoManager) var undoManager
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    
    // Gestures state
    @GestureState private var magnifyBy: CGFloat = 1.0
    @GestureState private var dragOffset: CGSize = .zero
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Adjust Cover Crop")
                .font(.headline)
                .padding()
            
            Text("Scroll or pinch to zoom. Drag to reposition.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
            
            if let image = viewModel.imageToCrop {
                GeometryReader { geometry in
                    let size = min(geometry.size.width, geometry.size.height)
                    let displayScale = calculateInitialScale(imageSize: image.size, frameSize: size)
                    
                    ZStack {
                        // Checkerboard background for transparency
                        Color.black.opacity(0.1)
                        
                        // The Image
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: image.size.width * displayScale, height: image.size.height * displayScale)
                            .scaleEffect(scale * magnifyBy)
                            .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
                            .gesture(
                                DragGesture()
                                    .updating($dragOffset) { value, state, _ in
                                        state = value.translation
                                    }
                                    .onEnded { value in
                                        offset.width += value.translation.width
                                        offset.height += value.translation.height
                                    }
                            )
                            .gesture(
                                MagnificationGesture()
                                    .updating($magnifyBy) { value, state, _ in
                                        state = value
                                    }
                                    .onEnded { value in
                                        scale *= value
                                        // Prevent zooming out too much
                                        if scale < 0.5 { scale = 0.5 }
                                    }
                            )
                        
                        // The Cropping Mask (Square)
                        Rectangle()
                            .fill(Color.black.opacity(0.6))
                            .reverseMask {
                                Rectangle()
                                    .frame(width: size, height: size)
                            }
                            .allowsHitTesting(false)
                        
                        // Crop Border
                        Rectangle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: size, height: size)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
                .frame(width: 400, height: 400) // Fixed UI size for the cropper
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                Text("No image selected")
                    .frame(width: 400, height: 400)
            }
            
            Divider()
            
            HStack {
                Button("Cancel") {
                    viewModel.imageToCrop = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Apply Crop") {
                    if let img = viewModel.imageToCrop {
                        applyCrop(to: img)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
    }
    
    private func calculateInitialScale(imageSize: NSSize, frameSize: CGFloat) -> CGFloat {
        // We want the shortest side of the image to perfectly fill the frame (aspectFill)
        let scaleX = frameSize / imageSize.width
        let scaleY = frameSize / imageSize.height
        return max(scaleX, scaleY)
    }
    
    private func applyCrop(to originalImage: NSImage) {
        // The crop frame size in UI points is 400x400
        let frameSize: CGFloat = 400.0
        let initialDisplayScale = calculateInitialScale(imageSize: originalImage.size, frameSize: frameSize)
        
        let totalScale = initialDisplayScale * scale
        
        // Target image size is the width/height corresponding to the 400x400 crop box, un-scaled
        let outputSize = frameSize / totalScale
        
        // Calculate the offset in the original image's coordinates
        let normalizedOffsetX = -offset.width / totalScale
        let normalizedOffsetY = offset.height / totalScale // Y is flipped in AppKit coordinate system
        
        let originX = (originalImage.size.width - outputSize) / 2.0 + normalizedOffsetX
        let originY = (originalImage.size.height - outputSize) / 2.0 + normalizedOffsetY
        
        let cropRect = NSRect(x: originX, y: originY, width: outputSize, height: outputSize)
        
        let newImage = NSImage(size: NSSize(width: outputSize, height: outputSize))
        newImage.lockFocus()
        originalImage.draw(in: NSRect(origin: .zero, size: NSSize(width: outputSize, height: outputSize)),
                           from: cropRect,
                           operation: .copy,
                           fraction: 1.0)
        newImage.unlockFocus()
        
        let oldCover = viewModel.coverImage
        viewModel.coverImage = newImage
        viewModel.registerPropertyUndo(undoManager: undoManager, keyPath: \.coverImage, oldValue: oldCover, newValue: newImage)
        
        viewModel.imageToCrop = nil
        dismiss()
    }
}

// Helper for masking out the center
extension View {
    func reverseMask<Mask: View>(
        alignment: Alignment = .center,
        @ViewBuilder _ mask: () -> Mask
    ) -> some View {
        self.mask(
            ZStack {
                Rectangle()
                mask()
                    .blendMode(.destinationOut)
            }
        )
    }
}
