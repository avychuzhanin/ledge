import AppKit

/// Контент-вью окна: принимает всё, что на неё бросают.
/// Реагирует только внутри силуэта полки — поле под тень остаётся глухим.
final class DropCatcherView: NSView {
    var hotRect: NSRect = .zero
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    var onDrop: (NSPasteboard) -> Bool = { _ in false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(Ingest.acceptedTypes)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func inside(_ info: NSDraggingInfo) -> Bool {
        let p = convert(info.draggingLocation, from: nil)
        return hotRect.isEmpty || hotRect.contains(p)
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        guard Ingest.canAccept(info.draggingPasteboard) else { return [] }
        if inside(info) { onEnter(); return .copy }
        return []
    }

    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        guard Ingest.canAccept(info.draggingPasteboard) else { return [] }
        if inside(info) { onEnter(); return .copy }
        onExit()
        return []
    }

    override func draggingExited(_ info: NSDraggingInfo?) { onExit() }
    override func prepareForDragOperation(_ info: NSDraggingInfo) -> Bool { inside(info) }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        defer { onExit() }
        return onDrop(info.draggingPasteboard)
    }
}
