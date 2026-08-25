import AppKit
import SwiftUI

/// Место, которое принимает перетаскивание и при этом само кликается:
/// корешок стопки в ленте работает и как кнопка, и как приёмник.
final class DropSpotView: NSView {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    var onDrop: (NSPasteboard) -> Bool = { _ in false }
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(Ingest.acceptedTypes)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        onClick == nil ? nil : super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        guard Ingest.canAccept(info.draggingPasteboard) else { return [] }
        onEnter()
        return .copy
    }

    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        Ingest.canAccept(info.draggingPasteboard) ? .copy : []
    }

    override func draggingExited(_ info: NSDraggingInfo?) { onExit() }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        defer { onExit() }
        return onDrop(info.draggingPasteboard)
    }
}

struct DropSpot: NSViewRepresentable {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    var onDrop: (NSPasteboard) -> Bool
    var onClick: (() -> Void)?

    func makeNSView(context: Context) -> DropSpotView { DropSpotView() }

    func updateNSView(_ v: DropSpotView, context: Context) {
        v.onEnter = onEnter
        v.onExit = onExit
        v.onDrop = onDrop
        v.onClick = onClick
    }
}
