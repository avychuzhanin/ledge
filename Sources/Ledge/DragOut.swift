import AppKit
import SwiftUI

/// Прозрачный слой поверх строки: тащит вещи наружу настоящей системной
/// сессией драга, ловит ховер и двойной клик. Файл уезжает файлом,
/// текст — текстом, поэтому вставляется прямо в поле ввода.
final class DragOutView: NSView, NSDraggingSource {
    var provider: () -> [ShelfItem] = { [] }
    var onSuccess: (NSDragOperation) -> Void = { _ in }
    var onHover: (Bool) -> Void = { _ in }
    var onDoubleClick: () -> Void = {}
    var onClick: () -> Void = {}
    var onDown: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onDragStateChange: (Bool) -> Void = { _ in }

    private var tracking: NSTrackingArea?
    private var inZone = false
    private var clickWork: DispatchWorkItem?
    private var dragged = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self)
        addTrackingArea(t)
        tracking = t
        syncHover()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setHover(false) }
    }

    /// Строка умеет уехать из-под неподвижного курсора — скролл, новая вещь
    /// сверху, полка ушла за грань. Тогда mouseExited не придёт, и ховер
    /// залипает. Поэтому сверяемся с тем, где мышь на самом деле.
    private func syncHover() {
        // Не трогаем состояние прямо посреди раскладки — только следующим тиком.
        DispatchQueue.main.async { [weak self] in self?.checkHover() }
    }

    private func checkHover() {
        guard let w = window, w.isVisible, !isHiddenOrHasHiddenAncestor else {
            setHover(false); return
        }
        let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        setHover(bounds.contains(p) && visibleRect.contains(p))
    }

    private func setHover(_ on: Bool) {
        guard on != inZone else { return }
        inZone = on
        onHover(on)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) { setHover(false) }

    override func mouseDown(with event: NSEvent) {
        dragged = false
        onDown(event.modifierFlags)
        if event.clickCount == 2 {
            clickWork?.cancel(); clickWork = nil
            onDoubleClick()
        }
    }

    /// Одиночный клик — быстрое превью. Ждём интервал двойного клика,
    /// чтобы не показать превью перед открытием файла.
    override func mouseUp(with event: NSEvent) {
        guard !dragged, event.clickCount == 1 else { return }
        let work = DispatchWorkItem { [weak self] in self?.onClick() }
        clickWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval,
                                      execute: work)
    }

    override func mouseDragged(with event: NSEvent) {
        dragged = true
        clickWork?.cancel(); clickWork = nil
        let shelf = provider()
        guard !shelf.isEmpty else { return }

        let side: CGFloat = 56
        let origin = convert(event.locationInWindow, from: nil)
        var items: [NSDraggingItem] = []
        for (i, thing) in shelf.enumerated() {
            let writer: NSPasteboardWriting
            let icon: NSImage
            if let text = thing.text {
                writer = text as NSString
                icon = Thumbs.shared.textCard(text)
            } else if let url = thing.url {
                writer = url as NSURL
                icon = Thumbs.shared.cached(url) ?? Thumbs.shared.icon(url)
            } else {
                continue
            }
            let item = NSDraggingItem(pasteboardWriter: writer)
            let frame = NSRect(x: origin.x - side / 2 + CGFloat(i) * 7,
                               y: origin.y - side / 2 - CGFloat(i) * 7,
                               width: side, height: side)
            item.setDraggingFrame(frame, contents: icon)
            items.append(item)
        }
        guard !items.isEmpty else { return }

        onDragStateChange(true)
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt point: NSPoint, operation: NSDragOperation) {
        onDragStateChange(false)
        setHover(false)
        if !operation.isEmpty && operation != .delete { onSuccess(operation) }
    }
}

struct DragOut: NSViewRepresentable {
    var items: () -> [ShelfItem]
    var onSuccess: (NSDragOperation) -> Void = { _ in }
    var onHover: (Bool) -> Void = { _ in }
    var onDoubleClick: () -> Void = {}
    var onClick: () -> Void = {}
    var onDown: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onDragStateChange: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> DragOutView { DragOutView() }

    func updateNSView(_ v: DragOutView, context: Context) {
        v.provider = items
        v.onSuccess = onSuccess
        v.onHover = onHover
        v.onDoubleClick = onDoubleClick
        v.onClick = onClick
        v.onDown = onDown
        v.onDragStateChange = onDragStateChange
    }
}
