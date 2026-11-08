import AppKit

public enum BrandMark {
    public static func image(side: CGFloat, template: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let inset = side * 0.02
            let box = rect.insetBy(dx: inset, dy: inset)
            let path = NSBezierPath(roundedRect: box, xRadius: box.width * 0.28, yRadius: box.width * 0.28)
            if template {
                NSColor.black.setFill()
                path.fill()
                guard let context = NSGraphicsContext.current?.cgContext else { return true }
                context.saveGState()
                context.setBlendMode(.destinationOut)
                drawLetters(in: box, color: .black)
                context.restoreGState()
            } else {
                let gradient = NSGradient(colors: [
                    NSColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1),
                    NSColor(red: 0.90, green: 0.85, blue: 0.76, alpha: 1),
                ])
                gradient?.draw(in: path, angle: -90)
                drawLetters(in: box, color: NSColor(red: 0.16, green: 0.13, blue: 0.10, alpha: 1))
            }
            return true
        }
        image.isTemplate = template
        return image
    }

    public static func writePNG(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else { return }
        try data.write(to: url)
    }

    private static func drawLetters(in box: NSRect, color: NSColor) {
        let font = NSFont.systemFont(ofSize: box.width * 0.34, weight: .semibold)
        let text = NSAttributedString(string: "KB", attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        let bounds = text.boundingRect(
            with: NSSize(width: box.width, height: box.height),
            options: [.usesLineFragmentOrigin]
        )
        let origin = NSPoint(
            x: box.midX - bounds.width / 2,
            y: box.midY - bounds.height / 2 - box.height * 0.02
        )
        text.draw(at: origin)
    }
}
