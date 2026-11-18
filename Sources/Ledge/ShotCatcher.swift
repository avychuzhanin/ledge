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

    /// Настройки читаем и пишем напрямую через CFPreferences, а не через
    /// `defaults`: у приложения нет локали, и `defaults read` печатал
    /// «Снимки» как `\u0421\u043d…`. Сторож считал настройку сбитой,
    /// чинил её каждые 20 секунд и вместе с этим ронял очередь снимков.
    private static let domain = "com.apple.screencapture" as CFString

    private func pref(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, Self.domain)
    }

    private func setPref(_ key: String, _ value: CFPropertyList?) {
        CFPreferencesSetAppValue(key as CFString, value, Self.domain)
        CFPreferencesAppSynchronize(Self.domain)
    }

    private func enable() {
        try? FileManager.default.createDirectory(at: Self.folder,
                                                 withIntermediateDirectories: true)
        let d = UserDefaults.standard
        if d.string(forKey: Self.savedKey) == nil {
            d.set(currentLocation() ?? "", forKey: Self.savedKey)
        }
        if !locationIsOurs { setLocation(Self.folder.path) }
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
        let shown = thumbnailShown
        if d.string(forKey: Self.savedThumbKey) == nil {
            d.set(shown ? "1" : "0", forKey: Self.savedThumbKey)
        }
        guard shown else { return }
        setPref("show-thumbnail", kCFBooleanFalse)
        restartMenuBar()
    }

    private func restoreThumbnail() {
        let was = UserDefaults.standard.string(forKey: Self.savedThumbKey) ?? "1"
        setPref("show-thumbnail", was == "0" ? kCFBooleanFalse : kCFBooleanTrue)
        restartMenuBar()
        UserDefaults.standard.removeObject(forKey: Self.savedThumbKey)
    }

    /// Нет настройки — превьюшка включена, так у macOS по умолчанию.
    private var thumbnailShown: Bool {
        guard let v = pref("show-thumbnail") else { return true }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        return true
    }

    private func currentLocation() -> String? {
        guard let s = pref("location") as? String, !s.isEmpty else { return nil }
        return s
    }

    /// Сравниваем пути как пути: тильда, хвостовой слеш и форма юникода
    /// не должны считаться «другой папкой».
    private var locationIsOurs: Bool {
        guard let s = currentLocation() else { return false }
        let path = (s as NSString).expandingTildeInPath
        return URL(fileURLWithPath: path).standardizedFileURL.path
            == Self.folder.standardizedFileURL.path
    }

    private func setLocation(_ path: String?) {
        setPref("location", path.map { $0 as CFString })
        restartMenuBar()
    }

    /// Старый снимочный конвейер перечитывал настройку только после перезапуска.
    private func restartMenuBar() {
        run("/usr/bin/killall", ["SystemUIServer"])
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
        src.setEventHandler { [weak self, weak src] in
            guard let self else { return }
            // Папку могли снести — тогда снимки перестают сохраняться вообще,
            // потому что система пишет их по несуществующему пути.
            guard self.folderAlive() else { return self.repair() }
            // Папку снесли и тут же создали заново: путь жив, а дескриптор
            // смотрит в старую, мёртвую папку. Переподключаемся.
            if let flags = src?.data, !flags.intersection([.delete, .rename]).isEmpty {
                return self.rewatch()
            }
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
    /// Слежку перезапускаем только если папка пропадала: иначе сбросим
    /// очередь снимков, которые ещё не успели осесть, и они пропадут с полки.
    private func repair() {
        let wasAlive = folderAlive()
        if !wasAlive {
            try? FileManager.default.createDirectory(at: Self.folder,
                                                     withIntermediateDirectories: true)
            guard folderAlive() else { return }
        }
        if !locationIsOurs { setLocation(Self.folder.path) }
        if !wasAlive || source == nil { rewatch() }
    }

    private func rewatch() {
        known = Set(listing())
        watch()
    }

    /// Раз в двадцать секунд проверяем, что папка на месте и система пишет
    /// снимки именно в неё. Дешёвая страховка от тихой поломки скриншотов.
    private func startGuard() {
        guardTimer?.invalidate()
        guardTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self, self.isOn else { return }
            if !self.folderAlive() || !self.locationIsOurs { self.repair() }
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
