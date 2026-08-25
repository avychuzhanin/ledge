import AppKit

/// Следит за системным драгом. Отличает настоящий drag-and-drop от
/// обычного протаскивания мышью: смотрит на счётчик drag-пастборда.
final class DragWatcher {
    private var monitors: [Any] = []
    private var baseline = 0
    private(set) var isDragging = false

    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}

    func start() {
        add(.leftMouseDown) { [weak self] _ in
            self?.baseline = NSPasteboard(name: .drag).changeCount
        }
        add(.leftMouseDragged) { [weak self] _ in
            guard let self, !self.isDragging else { return }
            let pb = NSPasteboard(name: .drag)
            guard pb.changeCount != self.baseline, Ingest.canAccept(pb) else { return }
            self.isDragging = true
            self.onBegin()
        }
        add(.leftMouseUp) { [weak self] _ in
            guard let self, self.isDragging else { return }
            self.isDragging = false
            self.onEnd()
        }
    }

    private func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { e in
            handler(e); return e
        }) { monitors.append(l) }
    }

    deinit { monitors.forEach(NSEvent.removeMonitor) }
}
