import AppKit

func ledgePath(in rect: NSRect) -> NSBezierPath {
    let w = rect.width, h = rect.height
    let bw = w * 0.64
    let lipH = h * 0.24
    let r = min(w, h) * 0.11
    let lr = r * 0.7
    let p = NSBezierPath()
    p.move(to: NSPoint(x: rect.minX, y: rect.maxY))
    p.line(to: NSPoint(x: rect.minX + bw - r, y: rect.maxY))
    p.appendArc(withCenter: NSPoint(x: rect.minX + bw - r, y: rect.maxY - r),
                radius: r, startAngle: 90, endAngle: 0, clockwise: true)
    p.line(to: NSPoint(x: rect.minX + bw, y: rect.minY + lipH + lr))
    p.appendArc(withCenter: NSPoint(x: rect.minX + bw + lr, y: rect.minY + lipH + lr),
                radius: lr, startAngle: 180, endAngle: 270, clockwise: false)
    p.line(to: NSPoint(x: rect.maxX - lr, y: rect.minY + lipH))
    p.appendArc(withCenter: NSPoint(x: rect.maxX - lr, y: rect.minY + lipH - lr),
                radius: lr, startAngle: 90, endAngle: 0, clockwise: true)
    p.line(to: NSPoint(x: rect.maxX, y: rect.minY + lr))
    p.appendArc(withCenter: NSPoint(x: rect.maxX - lr, y: rect.minY + lr),
                radius: lr, startAngle: 0, endAngle: -90, clockwise: true)
    p.line(to: NSPoint(x: rect.minX, y: rect.minY))
    p.close()
    return p
}

func render(_ side: Int) -> Data {
    let s = CGFloat(side)
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        let full = NSRect(x: 0, y: 0, width: s, height: s)
        let plate = NSBezierPath(roundedRect: full,
                                 xRadius: s * 0.2237, yRadius: s * 0.2237)
        plate.addClip()
        NSGradient(colors: [NSColor(srgbRed: 0.145, green: 0.129, blue: 0.118, alpha: 1),
                            NSColor(srgbRed: 0.055, green: 0.047, blue: 0.043, alpha: 1)])?
            .draw(in: full, angle: -90)

        // направленный свет сверху-справа, не симметричное гало
        NSGradient(colors: [NSColor(white: 1, alpha: 0.11),
                            NSColor(white: 1, alpha: 0.0)])?
            .draw(in: full, angle: -68)

        let mark = NSRect(x: s * 0.215, y: s * 0.255, width: s * 0.57, height: s * 0.49)
        let path = ledgePath(in: mark)

        NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45).setFill()
        let sh = NSShadow()
        sh.shadowColor = NSColor(white: 0, alpha: 0.5)
        sh.shadowOffset = NSSize(width: s * 0.012, height: -s * 0.012)
        sh.shadowBlurRadius = s * 0.045
        NSGraphicsContext.saveGraphicsState()
        sh.set()
        NSColor(srgbRed: 0.929, green: 0.913, blue: 0.890, alpha: 1).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(colors: [NSColor(srgbRed: 0.949, green: 0.937, blue: 0.917, alpha: 1),
                            NSColor(srgbRed: 0.847, green: 0.824, blue: 0.788, alpha: 1)])?
            .draw(in: mark, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // сигнальная риска на губе
        let bar = NSRect(x: mark.minX + mark.width * 0.665,
                         y: mark.minY + mark.height * 0.093,
                         width: mark.width * 0.235, height: max(1, s * 0.021))
        NSColor(srgbRed: 0.831, green: 0.376, blue: 0.212, alpha: 1).setFill()
        NSBezierPath(roundedRect: bar, xRadius: s * 0.011, yRadius: s * 0.011).fill()
        return true
    }
    let rep = NSBitmapImageRep(cgImage: img.cgImage(forProposedRect: nil,
                                                    context: nil, hints: nil)!)
    rep.size = NSSize(width: side, height: side)
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, side) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32),
                     ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                     ("icon_256x256", 256), ("icon_256x256@2x", 512),
                     ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! render(side).write(to: out.appendingPathComponent("\(name).png"))
}
print("iconset ready")
