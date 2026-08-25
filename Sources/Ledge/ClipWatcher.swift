import AppKit

/// Всё скопированное — текст, картинки, SVG, файлы, ссылки — кладём на полку.
/// Содержимое, помеченное менеджерами паролей, пропускаем.
final class ClipWatcher {
    /// Мы сами что-то положили в буфер — подбирать это обратно не надо.
    static var skipNext = false

    static let key = "catchClipboard"

    private let store: ShelfStore
    private var timer: Timer?
    private var lastChange = 0
    private var lastPrint: Int?

    var isOn: Bool { UserDefaults.standard.bool(forKey: Self.key) }

    init(store: ShelfStore) {
        self.store = store
        UserDefaults.standard.register(defaults: [Self.key: true])
        lastChange = NSPasteboard.general.changeCount
    }

    func apply() { isOn ? start() : stop() }

    func toggle() {
        UserDefaults.standard.set(!isOn, forKey: Self.key)
        apply()
    }

    private func start() {
        stop()
        lastChange = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        if Self.skipNext { Self.skipNext = false; lastPrint = fingerprint(pb); return }
        guard !Ingest.isSecret(pb), Ingest.canAccept(pb) else { return }

        let print = fingerprint(pb)
        guard print != lastPrint else { return }

        var items = Ingest.items(from: pb, store: store, source: .clip)
        guard !items.isEmpty else { return }
        let from = Apps.frontmostID
        for i in items.indices { items[i].appID = from }
        lastPrint = print
        store.add(items)
    }

    /// Чтобы одно и то же копирование не плодило файлы.
    private func fingerprint(_ pb: NSPasteboard) -> Int {
        var h = Hasher()
        if let s = pb.string(forType: .fileURL) { h.combine(s) }
        if let s = pb.string(forType: .string) { h.combine(s) }
        if let d = pb.data(forType: .tiff) { h.combine(d.count); h.combine(d.prefix(1024)) }
        if let d = pb.data(forType: Ingest.svgType) { h.combine(d.count) }
        return h.finalize()
    }
}
