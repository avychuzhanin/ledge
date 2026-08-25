import AppKit
import SwiftUI

/// Полоска-хваталка: за неё полку можно перетащить куда угодно.
final class MoveHandleView: NSView {
    var onBegin: () -> Void = {}
    var onMove: (NSPoint) -> Void = { _ in }
    var onEnd: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }

    private var grabScreen: NSPoint = .zero
    private var grabFrame: NSRect = .zero
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        onHover(true)
        NSCursor.openHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        onHover(false)
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        grabScreen = NSEvent.mouseLocation
        grabFrame = window?.frame ?? .zero
        NSCursor.closedHand.set()
        onBegin()
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        onMove(NSPoint(x: grabFrame.origin.x + (now.x - grabScreen.x),
                       y: grabFrame.origin.y + (now.y - grabScreen.y)))
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.openHand.set()
        onEnd()
    }
}

struct MoveHandle: NSViewRepresentable {
    var onBegin: () -> Void
    var onMove: (NSPoint) -> Void
    var onEnd: () -> Void
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> MoveHandleView { MoveHandleView() }

    func updateNSView(_ v: MoveHandleView, context: Context) {
        v.onBegin = onBegin
        v.onMove = onMove
        v.onEnd = onEnd
        v.onHover = onHover
    }
}
