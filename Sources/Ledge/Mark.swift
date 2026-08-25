import AppKit

/// Знак приложения — тот же силуэт полки с губой. Один знак везде:
/// меню-бар, пустая полка, иконка.
enum Mark {
    static func path(in rect: NSRect, lipRatio: CGFloat = 0.26) -> NSBezierPath {
        let w = rect.width, h = rect.height
        let bw = w * 0.82
        let lipH = h * lipRatio
        let r = min(w, h) * 0.12
        let p = NSBezierPath()
        p.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        p.line(to: NSPoint(x: rect.minX + bw - r, y: rect.maxY))
        p.appendArc(withCenter: NSPoint(x: rect.minX + bw - r, y: rect.maxY - r),
                    radius: r, startAngle: 90, endAngle: 0, clockwise: true)
        p.line(to: NSPoint(x: rect.minX + bw, y: rect.minY + lipH))
        p.line(to: NSPoint(x: rect.maxX - r, y: rect.minY + lipH))
        p.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.minY + lipH - r),
                    radius: r, startAngle: 90, endAngle: 0, clockwise: true)
        p.line(to: NSPoint(x: rect.maxX, y: rect.minY + r))
        p.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.minY + r),
                    radius: r, startAngle: 0, endAngle: -90, clockwise: true)
        p.line(to: NSPoint(x: rect.minX, y: rect.minY))
        p.close()
        return p
    }

    static func statusImage() -> NSImage {
        let size = NSSize(width: 15, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 0, dy: 2)
            NSColor.black.setFill()
            path(in: inset).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
