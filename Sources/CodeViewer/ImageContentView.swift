import AppKit
import SwiftUI

/// Full-pane preview for image documents. Large images scale down to fit and
/// small ones keep their natural size — never upscaled — while NSImage carries
/// the per-format work (EXIF orientation, SVG rendering), so no format
/// handling lives here. The opaque background covers the idle code pane
/// underneath, matching the status views.
struct ImageContentView: View {
    let document: ImageDocument

    var body: some View {
        ImageView(image: document.image)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// Wraps `NSImageView` instead of a SwiftUI `Image` so animated formats
/// (GIF/APNG) keep playing instead of freezing on their first frame.
private struct ImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyDown
        view.animates = true
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image {
            view.image = image
        }
    }
}

#if DEBUG
#Preview {
    ImageContentView(document: ImageDocument(
        image: {
            let image = NSImage(size: NSSize(width: 220, height: 140))
            image.lockFocus()
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 10, y: 10, width: 200, height: 120), xRadius: 12, yRadius: 12).fill()
            image.unlockFocus()
            return image
        }(),
        byteSize: 2_048,
        modificationDate: nil
    ))
    .frame(width: 560, height: 380)
}
#endif
