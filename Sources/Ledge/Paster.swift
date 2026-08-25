import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Отдать вещь обратно в работу: положить в буфер и нажать ⌘V за пользователя
/// в той программе, которая была впереди до того, как открылась лента.
enum Paster {
    /// Нажимать ⌘V за пользователя macOS разрешает только с доступом
    /// к «Универсальному доступу». Без него мы просто кладём в буфер.
    static var trusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func askTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Кладём в буфер. Простым текстом — когда нужно без оформления и без файла.
    static func copy(_ items: [ShelfItem], plain: Bool = false) {
        guard !items.isEmpty else { return }
        let pb = NSPasteboard.general
        ClipWatcher.skipNext = true
        pb.clearContents()

        let texts = items.compactMap { item -> String? in
            if let t = item.text { return t }
            if plain, let link = item.linkAddress { return link }
            if plain, let u = item.url { return u.path }
            return nil
        }
        if plain || items.allSatisfy(\.isText) {
            pb.setString(texts.joined(separator: "\n"), forType: .string)
            return
        }

        var writers: [NSPasteboardWriting] = []
        for item in items {
            if let t = item.text { writers.append(t as NSString) }
            else if let u = item.url { writers.append(u as NSURL) }
        }
        pb.writeObjects(writers)
    }

    /// Скопировать и вставить туда, откуда пришли.
    static func paste(_ items: [ShelfItem], into app: NSRunningApplication?, plain: Bool = false) {
        copy(items, plain: plain)
        guard trusted else { askTrust(); return }
        app?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { press() }
    }

    /// Само нажатие ⌘V.
    private static func press() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
