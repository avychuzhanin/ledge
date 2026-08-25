import AppKit
import SwiftUI

/// Сборка картинки со штрихами — и для показа, и для сохранения.
enum MarkupRender {

    /// Крупные квадраты вместо содержимого: замазка должна быть необратимой,
    /// поэтому не размытие, а честная потеря пикселей.
    static func pixelated(_ cg: CGImage) -> CGImage? {
        let w = cg.width, h = cg.height
        let block = max(6, min(w, h) / 55)
        let sw = max(1, w / block), sh = max(1, h / block)

        guard let small = context(width: sw, height: sh) else { return nil }
        small.interpolationQuality = .medium
        small.draw(cg, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        guard let tiny = small.makeImage(), let big = context(width: w, height: h)
        else { return nil }
        big.interpolationQuality = .none
        big.draw(tiny, in: CGRect(x: 0, y: 0, width: w, height: h))
        return big.makeImage()
    }

    static func compose(base: CGImage, pixels: CGImage?, marks: [Stroke]) -> CGImage? {
        let w = base.width, h = base.height
        guard let ctx = context(width: w, height: h) else { return nil }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))

        // рисуем в координатах картинки: начало сверху слева, как на экране
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        let full = CGRect(x: 0, y: 0, width: w, height: h)

        for mark in marks {
            if mark.tool == .blur {
                guard let pixels else { continue }
                ctx.saveGState()
                ctx.clip(to: mark.rect)
                ctx.translateBy(x: 0, y: CGFloat(h))
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(pixels, in: full)
                ctx.restoreGState()
                continue
            }
            ctx.saveGState()
            ctx.setStrokeColor(mark.color.ns.usingColorSpace(.sRGB)?.cgColor
                               ?? mark.color.ns.cgColor)
            ctx.setLineWidth(mark.width)
            ctx.setLineCap(mark.tool == .box ? .square : .round)
            ctx.setLineJoin(.round)
            ctx.addPath(mark.path.cgPath)
            ctx.strokePath()
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Пишем строго 8 бит на канал — по той же причине, что и в Ingest.
    static func png(_ cg: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }
}
