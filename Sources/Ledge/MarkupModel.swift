import AppKit
import SwiftUI

/// Состояние разметки одной картинки.
final class MarkupModel: ObservableObject {
    let item: ShelfItem
    let base: CGImage
    let pixels: CGImage?
    let size: CGSize

    @Published var marks: [Stroke] = []
    @Published var draft: Stroke?
    @Published var tool: MarkTool = .arrow
    @Published var color: MarkColor = .red
    @Published var weight: MarkWidth = .medium
    @Published var note = ""

    init?(item: ShelfItem) {
        guard let url = item.url,
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        self.item = item
        self.base = cg
        self.pixels = MarkupRender.pixelated(cg)
        self.size = CGSize(width: cg.width, height: cg.height)
    }

    var strokeWidth: CGFloat { weight.points(for: size) }
    var canUndo: Bool { !marks.isEmpty }

    func undo() {
        guard !marks.isEmpty else { return }
        marks.removeLast()
        note = ""
    }

    func clear() {
        marks.removeAll()
        note = ""
    }

    func begin(at p: CGPoint) {
        draft = Stroke(tool: tool, color: color, width: strokeWidth, from: clamp(p))
    }

    func extend(to p: CGPoint) {
        guard var d = draft else { return }
        let q = clamp(p)
        if d.tool == .pen {
            if let last = d.points.last, hypot(q.x - last.x, q.y - last.y) < strokeWidth * 0.4 {
                return
            }
            d.points.append(q)
        } else {
            d.points[1] = q
        }
        draft = d
    }

    func finish() {
        if let d = draft, d.meaningful { marks.append(d) }
        draft = nil
        note = ""
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), size.width), y: min(max(p.y, 0), size.height))
    }

    // MARK: наружу

    func composed() -> CGImage? {
        MarkupRender.compose(base: base, pixels: pixels, marks: marks)
    }

    /// Кладём в буфер и просим полку не подбирать своё же — иначе на ней
    /// тут же появится копия только что размеченной картинки.
    func copyToClipboard() -> Bool {
        guard let cg = composed(), let data = MarkupRender.png(cg) else { return false }
        ClipWatcher.skipNext = true
        let pb = NSPasteboard.general
        pb.clearContents()
        let image = NSImage(cgImage: cg, size: size)
        pb.writeObjects([image])
        pb.setData(data, forType: .png)
        note = "Скопировано"
        return true
    }

    func saveOverFile() -> Bool {
        guard let url = item.url, let cg = composed(),
              let data = MarkupRender.png(cg) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            Thumbs.shared.forget(url)
            note = "Сохранено"
            return true
        } catch { return false }
    }
}
