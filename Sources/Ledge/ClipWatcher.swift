import AppKit
import Combine

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
    /// Что легло на полку от последнего копирования. Убрали его с полки —
    /// то же самое, скопированное заново, снова должно туда попасть.
    private var lastItem: UUID?
    private var watch: AnyCancellable?
    /// Сколько раз уже заглядывали в одно и то же копирование.
    private var tries = 0
    private static let maxTries = 8   // ≈ 3,5 секунды

    var isOn: Bool { UserDefaults.standard.bool(forKey: Self.key) }

    init(store: ShelfStore) {
        self.store = store
        UserDefaults.standard.register(defaults: [Self.key: true])
        lastChange = NSPasteboard.general.changeCount
        watch = store.$items.sink { [weak self] items in
            guard let self, self.lastPrint != nil else { return }
            let gone = self.lastItem.map { id in !items.contains { $0.id == id } } ?? false
            if items.isEmpty || gone { self.lastPrint = nil; self.lastItem = nil }
        }
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
        let count = pb.changeCount
        guard count != lastChange else { return }
        if Self.skipNext {
            Self.skipNext = false
            lastChange = count; tries = 0
            lastPrint = fingerprint(pb); lastItem = nil
            return
        }
        guard !Ingest.isSecret(pb) else { lastChange = count; tries = 0; return }

        // Chrome сперва очищает буфер, а картинку дописывает чуть позже —
        // номер копирования при этом не меняется. Заглянули слишком рано и
        // ничего не нашли — не закрываем копирование, смотрим ещё раз.
        var items: [ShelfItem] = []
        let print = fingerprint(pb)
        if Ingest.canAccept(pb) {
            guard print != lastPrint else { lastChange = count; tries = 0; return }
            items = Ingest.items(from: pb, store: store, source: .clip)
        }
        if items.isEmpty, tries < Self.maxTries { tries += 1; return }
        lastChange = count; tries = 0
        guard !items.isEmpty else { return }
        let from = Apps.frontmostID
        for i in items.indices { items[i].appID = from }
        lastPrint = print
        lastItem = items.first?.id
        store.add(items)
    }

    /// Чтобы одно и то же копирование не плодило файлы.
    private func fingerprint(_ pb: NSPasteboard) -> Int {
        var h = Hasher()
        if let s = pb.string(forType: .fileURL) { h.combine(s) }
        if let s = pb.string(forType: .string) { h.combine(s) }
        // Картинку сверяем целиком: по размеру и началу файла две разные
        // картинки одного размера с одинаковым краем выглядели как одна,
        // и вторую полка молча пропускала.
        if let d = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            d.withUnsafeBytes { h.combine(bytes: $0) }
        }
        if let d = pb.data(forType: Ingest.svgType) { h.combine(d.count) }
        return h.finalize()
    }
}
