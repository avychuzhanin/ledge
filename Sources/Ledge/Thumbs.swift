import AppKit
import QuickLookThumbnailing

/// Настоящие превью файлов через QuickLook, с откатом на иконку системы.
final class Thumbs {
    static let shared = Thumbs()
    private var cache: [URL: NSImage] = [:]
    private var textCache: [String: NSImage] = [:]
    private let side: CGFloat = 72

    func cached(_ url: URL) -> NSImage? { cache[url] }

    /// Файл изменился — превью надо построить заново.
    func forget(_ url: URL) { cache[url] = nil }

    func icon(_ url: URL) -> NSImage {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: side, height: side)
        return img
    }

    /// Карточка текста: настоящие первые строки, а не абстрактный значок.
    func textCard(_ text: String) -> NSImage {
        if let hit = textCache[text] { return hit }
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let paper = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            NSColor(srgbRed: 0.98, green: 0.976, blue: 0.968, alpha: 1).setFill()
            paper.fill()
            NSColor(white: 0, alpha: 0.14).setStroke()
            paper.lineWidth = 1
            paper.stroke()

            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            style.lineSpacing = 1
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 6.5),
                .foregroundColor: NSColor(white: 0.18, alpha: 1),
                .paragraphStyle: style
            ]
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            String(body.prefix(220)).draw(in: rect.insetBy(dx: 6, dy: 5),
                                          withAttributes: attrs)
            return true
        }
        textCache[text] = img
        return img
    }

    func preview(_ url: URL) async -> NSImage {
        if let hit = cache[url] { return hit }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let req = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: scale,
            representationTypes: .thumbnail
        )
        req.iconMode = false
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) {
            let img = NSImage(cgImage: rep.cgImage, size: NSSize(width: side, height: side))
            cache[url] = img
            return img
        }
        let fallback = icon(url)
        cache[url] = fallback
        return fallback
    }
}

/// Крупное превью для карточки в ленте: та же QuickLook, только крупнее —
/// в ленте картинка должна читаться, а не намекать на себя.
extension Thumbs {
    private static var bigCache: [URL: NSImage] = [:]
    private static let bigSide: CGFloat = 320

    func cachedBig(_ url: URL) -> NSImage? { Thumbs.bigCache[url] }

    func forgetBig(_ url: URL) { Thumbs.bigCache[url] = nil }

    func big(_ url: URL) async -> NSImage? {
        if let hit = Thumbs.bigCache[url] { return hit }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let req = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: Thumbs.bigSide, height: Thumbs.bigSide),
            scale: scale,
            representationTypes: .thumbnail
        )
        req.iconMode = false
        guard let rep = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: req) else { return nil }
        let side = CGSize(width: CGFloat(rep.cgImage.width) / scale,
                          height: CGFloat(rep.cgImage.height) / scale)
        let img = NSImage(cgImage: rep.cgImage, size: side)
        Thumbs.bigCache[url] = img
        return img
    }
}
