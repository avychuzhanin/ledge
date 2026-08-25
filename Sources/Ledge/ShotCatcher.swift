import AppKit

/// Уводит скриншоты и записи экрана с рабочего стола прямо на полку.
/// Меняет системную папку скриншотов на свою и следит за ней.
final class ShotCatcher {
    static let key = "catchShots"
    private static let savedKey = "previousShotLocation"
    private static let savedThumbKey = "previousShotThumbnail"
    static let folder: URL = ShelfStore.root
        .appendingPathComponent("Снимки", isDirectory: true)

    private static let extensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "tiff", "pdf", "mov", "mp4", "gif"
    ]

    private let store: ShelfStore
    private var source: DispatchSourceFileSystemObject?
    private var fd: CInt = -1
    private var known: Set<String> = []
    private var pending: [String: Int64] = [:]
    private var settle: Timer?
    private var guardTimer: Timer?

    var onCatch: () -> Void = {}

    var isOn: Bool { UserDefaults.standard.bool(forKey: Self.key) }

    init(store: ShelfStore) {
        self.store = store
        UserDefaults.standard.register(defaults: [Self.key: true])
    }

    func apply() { isOn ? enable() : disable() }

    func toggle() {
        UserDefaults.standard.set(!isOn, forKey: Self.key)
        apply()
    }

    // MARK: системная настройка

    private func enable() {
        try? FileManager.default.createDirectory(at: Self.folder,
                                                 withIntermediateDirectories: true)
        let d = UserDefaults.standard
        if d.string(forKey: Self.savedKey) == nil {
            d.set(currentLocation() ?? "", forKey: Self.savedKey)
        }
        setLocation(Self.folder.path)
        hideThumbnail()
        known = Set(listing())
        watch()
        startGuard()
    }

    private func disable() {
        guardTimer?.invalidate(); guardTimer = nil
        stopWatching()
        let previous = UserDefaults.standard.string(forKey: Self.savedKey) ?? ""
        setLocation(previous.isEmpty ? nil : previous)
        restoreThumbnail()
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
    }

    /// Плавающая превьюшка справа снизу держит файл у себя несколько секунд —
    /// из-за неё снимок попадал на полку с задержкой. Выключаем.
    private func hideThumbnail() {
        let d = UserDefaults.standard
        if d.string(forKey: Self.savedThumbKey) == nil {
            let was = run("/usr/bin/defaults",
                          ["read", "com.apple.screencapture", "show-thumbnail"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            d.set(was.isEmpty ? "1" : was, forKey: Self.savedThumbKey)
        }
        _ = run("/usr/bin/defaults",
                ["write", "com.apple.screencapture", "show-thumbnail", "-bool", "false"])
        _ = run("/usr/bin/killall", ["SystemUIServer"])
    }

    private func restoreThumbnail() {
        let was = UserDefaults.standard.string(forKey: Self.savedThumbKey) ?? "1"
        _ = run("/usr/bin/defaults",
                ["write", "com.apple.screencapture", "show-thumbnail", "-bool",
                 was == "0" ? "false" : "true"])
        _ = run("/usr/bin/killall", ["SystemUIServer"])
        UserDefaults.standard.removeObject(forKey: Self.savedThumbKey)
    }

    private func currentLocation() -> String? {
        let out = run("/usr/bin/defaults", ["read", "com.apple.screencapture", "location"])
        let s = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func setLocation(_ path: String?) {
        if let path {
            _ = run("/usr/bin/defaults",
                    ["write", "com.apple.screencapture", "location", "-string", path])
        } else {
            _ = run("/usr/bin/defaults", ["delete", "com.apple.screencapture", "location"])
        }
        _ = run("/usr/bin/killall", ["SystemUIServer"])
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: слежка за папкой

    private func listing() -> [String] {
        let all = (try? FileManager.default.contentsOfDirectory(atPath: Self.folder.path)) ?? []
        return all.filter {
            !$0.hasPrefix(".") && Self.extensions.contains(($0 as NSString).pathExtension.lowercased())
        }
    }

    private func watch() {
        stopWatching()
        fd = open(Self.folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            // Папку могли снести — тогда снимки перестают сохраняться вообще,
            // потому что система пишет их по несуществующему пути.
            guard self.folderAlive() else { return self.repair() }
            self.scan()
        }
        let handle = fd
        src.setCancelHandler { close(handle) }
        src.resume()
        source = src
    }

    private func folderAlive() -> Bool {
        var dir: ObjCBool = false
        let ok = FileManager.default.fileExists(atPath: Self.folder.path, isDirectory: &dir)
        return ok && dir.boolValue
    }

    /// Возвращаем папку и системную настройку на место.
    private func repair() {
        try? FileManager.default.createDirectory(at: Self.folder,
                                                 withIntermediateDirectories: true)
        guard folderAlive() else { return }
        if currentLocation() != Self.folder.path { setLocation(Self.folder.path) }
        known = Set(listing())
        watch()
    }

    /// Раз в двадцать секунд проверяем, что папка на месте и система пишет
    /// снимки именно в неё. Дешёвая страховка от тихой поломки скриншотов.
    private func startGuard() {
        guardTimer?.invalidate()
        guardTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self, self.isOn else { return }
            if !self.folderAlive() || self.currentLocation() != Self.folder.path {
                self.repair()
            }
        }
    }

    private func stopWatching() {
        source?.cancel(); source = nil; fd = -1
        settle?.invalidate(); settle = nil
        pending.removeAll()
    }

    private func scan() {
        for name in listing() where !known.contains(name) {
            if pending[name] == nil {
                let url = Self.folder.appendingPathComponent(name)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                pending[name] = Int64(size)
            }
        }
        guard !pending.isEmpty, settle == nil else { return }
        settle = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: true) { [weak self] t in
            self?.checkSettled(t)
        }
    }

    /// Запись экрана пишется постепенно — ждём, пока размер перестанет расти.
    private func checkSettled(_ timer: Timer) {
        var landed: [URL] = []
        for (name, lastSize) in pending {
            let url = Self.folder.appendingPathComponent(name)
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
                pending.removeValue(forKey: name)
                continue
            }
            if Int64(size) == lastSize && size > 0 {
                pending.removeValue(forKey: name)
                known.insert(name)
                landed.append(url)
            } else {
                pending[name] = Int64(size)
            }
        }
        if !landed.isEmpty {
            store.add(landed.map { ShelfItem(url: $0, owned: false, source: .shot) })
            onCatch()
        }
        if pending.isEmpty { timer.invalidate(); settle = nil }
    }
}
