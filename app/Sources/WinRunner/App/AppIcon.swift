import AppKit
import SwiftUI

/// The app's own icon, drawn in code so the build needs no image files. Temporary, like the name.
struct AppIconView: View {
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.22, green: 0.47, blue: 0.98), Color(red: 0.47, green: 0.30, blue: 0.94)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: side * 0.36, weight: .medium))
                .foregroundStyle(.white)
        }
        // Apple's icon grid leaves a transparent margin around the shape
        .frame(width: side * 0.805, height: side * 0.805)
        .frame(width: side, height: side)
    }
}

@MainActor
enum AppIconRenderer {
    /// Writes an .iconset folder; build-app.sh turns it into AppIcon.icns with iconutil.
    static func render(to iconset: URL) throws {
        try Paths.ensure(iconset)
        let sizes: [(String, CGFloat)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, side) in sizes {
            let renderer = ImageRenderer(content: AppIconView(side: side))
            renderer.scale = 1
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw AppError("icon \(name) did not render")
            }
            try png.write(to: iconset.appendingPathComponent("\(name).png"))
        }
    }
}
