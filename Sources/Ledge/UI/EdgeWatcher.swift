import AppKit

/// Следит за курсором: полка просыпается от касания грани экрана.
/// Работает и при обычном движении мыши, и во время перетаскивания.
final class EdgeWatcher {
    private var monitors: [Any] = []
    var onMove: (CGPoint) -> Void = { _ in }

    func start() {
        add(.mouseMoved)
        add(.leftMouseDragged)
    }

    private func add(_ mask: NSEvent.EventTypeMask) {
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.onMove(NSEvent.mouseLocation)
        }) { monitors.append(g) }
    }

    deinit { monitors.forEach(NSEvent.removeMonitor) }
}
