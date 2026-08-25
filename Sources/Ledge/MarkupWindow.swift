import AppKit
import SwiftUI

/// Окно разметки: одно на всё приложение, открывается карандашом с полки.
final class MarkupWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: MarkupModel?
    private var keys: Any?

    var onSaved: () -> Void = {}
    var isOpen: Bool { window?.isVisible == true }

    func open(_ item: ShelfItem) {
        guard let model = MarkupModel(item: item) else { return NSSound.beep() }
        self.model = model
        close()

        let frame = fitting(model.size)
        let w = NSWindow(contentRect: frame,
                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        // за фон окно не двигаем — иначе штрих превращается в перетаскивание
        w.isMovableByWindowBackground = false
        w.title = item.name
        w.delegate = self
        w.contentView = NSHostingView(rootView: MarkupView(
            model: model,
            onCopy: { _ = model.copyToClipboard() },
            onSave: { [weak self] in self?.save() },
            onClose: { [weak self] in self?.close() }))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
        listen()
    }

    func close() {
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
        window?.delegate = nil
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
        window = nil
        model = nil
    }

    private func save() {
        guard let model, model.saveOverFile() else { return NSSound.beep() }
        onSaved()
    }

    /// Окно у нас без строки меню, поэтому сочетания ловим сами.
    private func listen() {
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let model = self.model,
                  self.window?.isKeyWindow == true else { return e }
            let cmd = e.modifierFlags.contains(.command)
            switch (e.charactersIgnoringModifiers?.lowercased() ?? "", cmd) {
            case ("z", true): model.undo(); return nil
            case ("s", true): self.save(); return nil
            case ("c", true): _ = model.copyToClipboard(); return nil
            case ("w", true): self.close(); return nil
            case ("1", false): model.tool = .arrow; return nil
            case ("2", false): model.tool = .box; return nil
            case ("3", false): model.tool = .pen; return nil
            case ("4", false): model.tool = .blur; return nil
            default: break
            }
            if e.keyCode == 53 { self.close(); return nil }       // Esc
            return e
        }
    }

    private func fitting(_ size: CGSize) -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let box = CGSize(width: screen.width * 0.82, height: screen.height * 0.82)
        let k = min(box.width / size.width, box.height / size.height, 1)
        return NSRect(x: 0, y: 0,
                      width: max(680, size.width * k + 48),
                      height: max(500, size.height * k + 108))
    }
}
