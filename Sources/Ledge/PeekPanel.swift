import AppKit
import Quartz
import SwiftUI

/// Быстрое превью файла по клику — как пробел в Finder, только рядом с полкой.
final class PeekPanel {
    private let panel: NSPanel
    private var hosting: NSHostingView<AnyView>
    private(set) var current: UUID?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none

        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    func toggle(_ item: ShelfItem, card: NSRect) {
        if isVisible, current == item.id { hide() } else { show(item, card: card) }
    }

    func show(_ item: ShelfItem, card: NSRect) {
        current = item.id
        hosting.rootView = AnyView(PeekView(item: item))
        let w = M.peekW + M.gutter * 2
        let h = M.peekH + M.gutter * 2
        let screen = NSScreen.screens.first { $0.frame.intersects(card) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? card

        var x = card.maxX + M.peekGap - M.gutter
        if card.maxX + M.peekGap + M.peekW > vf.maxX {
            x = card.minX - M.peekGap - M.peekW - M.gutter
        }
        var y = card.midY - h / 2
        y = min(max(y, vf.minY - M.gutter), vf.maxY - h + M.gutter)

        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        current = nil
        panel.orderOut(nil)
    }
}

private struct PeekView: View {
    let item: ShelfItem

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: M.radius, style: .continuous)
        return body(for: item)
            .id(item.id)
            .frame(width: M.peekW, height: M.peekH)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.primary.opacity(0.13), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.17), radius: 24, y: 12)
            .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
            .padding(M.gutter)
    }

    @ViewBuilder private func body(for item: ShelfItem) -> some View {
        if let text = item.text {
            ScrollView {
                Text(text)
                    .font(.system(size: 12.5))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
        } else if let url = item.url {
            QLView(url: url)
        } else {
            Color.clear
        }
    }
}

/// Настоящее превью файла системными силами.
struct QLView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        v.autostarts = true
        v.shouldCloseWithWindow = false
        v.previewItem = url as NSURL
        return v
    }

    func updateNSView(_ v: QLPreviewView, context: Context) {
        v.previewItem = url as NSURL
    }
}
