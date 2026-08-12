import re

with open('Sources/Core/Rendering/FrameRenderer.swift', 'r') as f:
    text = f.read()

parts = text.split('struct FrameView: View {')
if len(parts) == 2:
    header = parts[0]
    body = parts[1]
    
    # Remove @AppStorage
    body = re.sub(r'(\s+)@AppStorage\(\".*?\"\)\s+private\s+var\s+(\w+):\s+[A-Za-z]+\s+=\s+[^\n]*\n', '', body)
    
    # Add config variable
    body = re.sub(r'var scale: CGFloat\n', 'var scale: CGFloat\n    var config: FrameViewConfig\n', body)
    
    vars_to_replace = [
        'layoutMode', 'verticalAlignment', 'metadataPosition', 'isCompilation', 'trackNumberStyle',
        'coverScale', 'fontFamily', 'customFontName', 'titleFontSize', 'subtitleFontSize', 'trackFontSize',
        'useCustomColors', 'bgR', 'bgG', 'bgB', 'textR', 'textG', 'textB'
    ]
    
    for v in vars_to_replace:
        body = re.sub(rf'\b{v}\b', f'config.{v}', body)
        
    final_text = header + 'struct FrameView: View {' + body
    
    # Now we need to append LiveFrameView at the bottom
    live_frame_view = """
struct LiveFrameView: View {
    var meta: AlbumMetadata
    var coverImage: NSImage?
    var currentTrackIndex: Int
    var bgColor: Color
    var scale: CGFloat
    
    @AppStorage("layoutMode") private var dummy1 = ""
    @AppStorage("verticalAlignment") private var dummy2 = ""
    @AppStorage("metadataPosition") private var dummy3 = ""
    @AppStorage("isCompilation") private var dummy4 = false
    @AppStorage("trackNumberStyle") private var dummy5 = 0
    @AppStorage("coverScale") private var dummy6 = 1.0
    @AppStorage("fontFamily") private var dummy7 = ""
    @AppStorage("customFontName") private var dummy8 = ""
    @AppStorage("titleFontSize") private var dummy9 = 60.0
    @AppStorage("subtitleFontSize") private var dummy10 = 40.0
    @AppStorage("trackFontSize") private var dummy11 = 35.0
    @AppStorage("useCustomColors") private var dummy12 = false
    @AppStorage("customBgColorR") private var dummy13 = 0.0
    @AppStorage("customBgColorG") private var dummy14 = 0.0
    @AppStorage("customBgColorB") private var dummy15 = 0.0
    @AppStorage("customTextColorR") private var dummy16 = 0.0
    @AppStorage("customTextColorG") private var dummy17 = 0.0
    @AppStorage("customTextColorB") private var dummy18 = 0.0
    
    var body: some View {
        FrameView(
            meta: meta,
            coverImage: coverImage,
            currentTrackIndex: currentTrackIndex,
            bgColor: bgColor,
            scale: scale,
            config: FrameViewConfig(defaults: .standard)
        )
    }
}
"""
    final_text += live_frame_view
    
    # Fix the FrameView initialization in FrameRenderer.generateFrames
    final_text = final_text.replace(
        'FrameView(meta: meta, coverImage: coverImage, currentTrackIndex: index, bgColor: bgColor, scale: scale)',
        'FrameView(meta: meta, coverImage: coverImage, currentTrackIndex: index, bgColor: bgColor, scale: scale, config: FrameViewConfig())'
    )
    
    with open('Sources/Core/Rendering/FrameRenderer.swift', 'w') as f:
        f.write(final_text)
        print("Patched successfully")
else:
    print("Failed to split")
