import AppKit
import Combine

/// Список вещей на полке + запись на диск, чтобы переживало перезапуск.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("Ledge", isDirectory: true)
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("blobs"),
                                                 withIntermediateDirectories: true)
        return base
    }()
    private var indexURL: URL { Self.root.appendingPathComponent("items.json") }
    private var blobs: URL { Self.root.appendingPathComponent("blobs", isDirectory: true) }

    init() { load() }

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.byteSize } }

    /// Чем отличаем одну вещь от другой: файл — путём, текст — содержимым.
    private static func key(_ i: ShelfItem) -> String {
        if let u = i.url { return u.standardizedFileURL.path }
        return "текст:" + (i.text ?? "")
    }

    // MARK: изменения

    func add(_ new: [ShelfItem]) {
        guard !new.isEmpty else { return }
        let known = Set(items.map(Self.key))
        let fresh = new.filter { !known.contains(Self.key($0)) }
        guard !fresh.isEmpty else { return }
        items.insert(contentsOf: fresh, at: 0)
        trimClipboard()
        save()
    }

    /// История буфера не должна выдавливать то, что притащили руками,
    /// и то, что разложено по стопкам: стопка держит вещь, пока сам не уберёшь.
    private func trimClipboard() {
        let clips = items.filter { $0.source == .clip && $0.board == nil }
        let limit = Wide.historyLimit
        guard clips.count > limit else { return }
        let doomed = Set(clips.dropFirst(limit).map(\.id))
        for item in items where doomed.contains(item.id) && item.owned {
            if let u = item.url { try? FileManager.default.removeItem(at: u) }
        }
        items.removeAll { doomed.contains($0.id) }
    }

    func remove(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: i)
        if item.owned, let u = item.url { try? FileManager.default.removeItem(at: u) }
        save()
    }

    func remove(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let doomed = Set(ids)
        for item in items where doomed.contains(item.id) && item.owned {
            if let u = item.url { try? FileManager.default.removeItem(at: u) }
        }
        items.removeAll { doomed.contains($0.id) }
        save()
    }

    func removeAll() {
        for item in items where item.owned {
            if let u = item.url { try? FileManager.default.removeItem(at: u) }
        }
        items.removeAll()
        save()
    }

    /// Убрать только историю буфера, оставив принесённое руками и стопки.
    func removeHistory() {
        let doomed = items.filter { $0.source == .clip && $0.board == nil }.map(\.id)
        remove(doomed)
    }

    // MARK: стопки

    func setBoard(_ ids: [UUID], to board: UUID?) {
        let touched = Set(ids)
        guard !touched.isEmpty else { return }
        for i in items.indices where touched.contains(items[i].id) {
            items[i].board = board
        }
        save()
    }

    /// Стопку убрали — вещи из неё возвращаются в общий список.
    func forgetBoard(_ board: UUID) {
        for i in items.indices where items[i].board == board { items[i].board = nil }
        save()
    }

    func items(in board: UUID?) -> [ShelfItem] {
        guard let board else { return items }
        return items.filter { $0.board == board }
    }

    func count(in board: UUID) -> Int {
        items.reduce(0) { $1.board == board ? $0 + 1 : $0 }
    }

    /// Файл переписали — пересобираем вещь, чтобы обновились превью и размер.
    /// Стопка и программа-источник при этом остаются при вещи.
    func reload(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }),
              let url = items[i].url else { return }
        var fresh = ShelfItem(url: url, owned: items[i].owned, source: items[i].source)
        fresh.board = items[i].board
        fresh.appID = items[i].appID
        items[i] = fresh
        save()
    }

    func dropMissing() {
        let alive = items.filter(\.exists)
        if alive.count != items.count { items = alive; save() }
    }

    // MARK: диск

    /// Папку могли снести из-под нас — восстанавливаем перед записью.
    private func ensureRoot() {
        try? FileManager.default.createDirectory(
            at: Self.root.appendingPathComponent("blobs"), withIntermediateDirectories: true)
    }

    private func save() {
        ensureRoot()
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        try? e.encode(items).write(to: indexURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        items = ((try? d.decode([ShelfItem].self, from: data)) ?? []).filter(\.exists)
    }

    // MARK: материализация не-файлов

    func blobURL(name: String, ext: String) -> URL {
        ensureRoot()
        var base = name.replacingOccurrences(of: "/", with: "-")
        if base.count > 48 { base = String(base.prefix(48)) }
        if base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { base = "Без имени" }
        var candidate = blobs.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = blobs.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
