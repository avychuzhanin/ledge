import AppKit
import SwiftUI

/// Окно разметки: одно на всё приложение, открывается карандашом с полки.
final class MarkupWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: MarkupModel?
    private var keys: Any?
    /// Кому отдать фокус, когда окно закроется.
    private var backTo: NSRunningApplication?

    var onSaved: () -> Void = {}
    var isOpen: Bool { window?.isVisible == true }

    func open(_ item: ShelfItem) {
        guard let model = MarkupModel(item: item) else { return NSSound.beep() }
        let front = NSWorkspace.shared.frontmostApplication
        close(giveBack: false)
        self.model = model
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { backTo = front }

        let frame = fitting(model.size)
        let w = NSWindow(contentRect: frame,
                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        // AppKit сам освобождает закрытое окно, и вместе с нашей ссылкой это
        // двойное освобождение — процесс падал на анимации закрытия.
        w.isReleasedWhenClosed = false
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

    func close(giveBack: Bool = true) {
        let w = window
        window = nil
        cleanup()
        w?.close()
        if giveBack { returnFocus() }
    }

    func windowWillClose(_ notification: Notification) {
        guard window != nil else { return }   // закрыли через close(), фокус уже отдан
        window = nil
        cleanup()
        returnFocus()
    }

    /// Окно сделало Ledge активной программой. Без окон он таким и остаётся,
    /// а глобальный монитор мыши чужие для активной программы события не
    /// видит — грань экрана переставала вызывать полку, пока не кликнешь
    /// куда-нибудь. Поэтому фокус возвращаем той программе, что была до нас.
    private func returnFocus() {
        defer { backTo = nil }
        if let backTo, !backTo.isTerminated {
            backTo.activate()
        } else {
            NSApp.deactivate()
        }
    }

    /// Монитор клавиш и картинка живут ровно столько, сколько окно.
    private func cleanup() {
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
        model = nil
    }

    private func save() {
        guard let model, model.saveOverFile() else { return NSSound.beep() }
        onSaved()
    }

    /// Окно у нас без строки меню, поэтому сочетания ловим сами.
    /// Команды сверяем по коду клавиши: на русской раскладке ⌘W приходит
    /// буквой «ц», и сравнение по букве их не ловило. Цифры одинаковы везде.
    private func listen() {
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let model = self.model,
                  self.window?.isKeyWindow == true else { return e }
            if e.modifierFlags.contains(.command) {
                switch e.keyCode {
                case Key.z: model.undo(); return nil
                case Key.s: self.save(); return nil
                case Key.c: _ = model.copyToClipboard(); return nil
                case Key.w: self.close(); return nil
                default: return e
                }
            }
            switch e.charactersIgnoringModifiers {
            case "1": model.tool = .arrow; return nil
            case "2": model.tool = .box; return nil
            case "3": model.tool = .pen; return nil
            case "4": model.tool = .blur; return nil
            default: break
            }
            if e.keyCode == Key.esc { self.close(); return nil }
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

/// Коды клавиш: буква на колпачке зависит от раскладки, код — нет.
private enum Key {
    static let s: UInt16 = 1
    static let z: UInt16 = 6
    static let c: UInt16 = 8
    static let w: UInt16 = 13
    static let esc: UInt16 = 53
}
