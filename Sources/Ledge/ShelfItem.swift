import AppKit
import Foundation
import UniformTypeIdentifiers

/// Одна вещь на полке. Файлы держим ссылкой на оригинал, картинки и векторы
/// материализуем в свою папку (owned == true), а простой текст живёт прямо
/// в списке — без файла, чтобы вытаскиваться обратно текстом.
enum ShelfSource: String, Codable {
    case drop   // притащили мышкой
    case shot   // снимок экрана
    case clip   // скопировали в буфер
}

/// Чем вещь является на вид — этим и различаются карточки в ленте.
enum ShelfKind {
    case text, image, link, folder, file
}

struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL?
    let text: String?
    let name: String
    let owned: Bool
    let addedAt: Date
    let source: ShelfSource
    /// В какой стопке лежит. Вещи из стопок история буфера не выдавливает.
    var board: UUID?
    /// Откуда скопировали — bundle id программы, которая была впереди.
    var appID: String?

    init(url: URL, owned: Bool, source: ShelfSource = .drop, appID: String? = nil) {
        self.id = UUID()
        self.url = url
        self.text = nil
        self.name = url.lastPathComponent
        self.owned = owned
        self.addedAt = Date()
        self.source = source
        self.board = nil
        self.appID = appID
    }

    init(text: String, source: ShelfSource = .drop, appID: String? = nil) {
        self.id = UUID()
        self.url = nil
        self.text = text
        self.name = Self.title(for: text)
        self.owned = false
        self.addedAt = Date()
        self.source = source
        self.board = nil
        self.appID = appID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        url = try? c.decode(URL.self, forKey: .url)
        text = try? c.decode(String.self, forKey: .text)
        name = (try? c.decode(String.self, forKey: .name))
            ?? url?.lastPathComponent ?? "Текст"
        owned = (try? c.decode(Bool.self, forKey: .owned)) ?? false
        addedAt = (try? c.decode(Date.self, forKey: .addedAt)) ?? Date()
        source = (try? c.decode(ShelfSource.self, forKey: .source)) ?? .drop
        board = try? c.decode(UUID.self, forKey: .board)
        appID = try? c.decode(String.self, forKey: .appID)
    }

    var isText: Bool { text != nil }

    /// Картинку можно разметить карандашом прямо с полки.
    var isImage: Bool {
        guard let url else { return false }
        guard let t = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        else { return ["png", "jpg", "jpeg", "heic", "tiff", "gif"]
                    .contains(url.pathExtension.lowercased()) }
        return t.conforms(to: .image) && !t.conforms(to: .svg)
    }

    var isLink: Bool { url?.pathExtension.lowercased() == "webloc" }

    var kind: ShelfKind {
        if isText { return .text }
        if isLink { return .link }
        if isImage { return .image }
        if isFolder { return .folder }
        return .file
    }

    /// Адрес внутри .webloc — чтобы в карточке показать сам сайт, а не имя файла.
    var linkAddress: String? {
        guard isLink, let url,
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return plist["URL"] as? String
    }

    /// Заголовок куска текста — первая непустая строка.
    private static func title(for text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? "Текст"
        return line.count > 44 ? String(line.prefix(44)) + "…" : line
    }

    /// Вещь на месте. Если macOS ещё не дала доступ к папке — считаем,
    /// что файл есть: иначе полка молча съест то, что на ней лежало.
    var exists: Bool {
        if text != nil { return true }
        guard let url else { return false }
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return true }
        return !fm.isReadableFile(atPath: url.deletingLastPathComponent().path)
    }

    var byteSize: Int64 {
        if let text { return Int64(text.utf8.count) }
        guard let url else { return 0 }
        let v = try? url.resourceValues(forKeys: [.totalFileSizeKey, .fileSizeKey])
        return Int64(v?.totalFileSize ?? v?.fileSize ?? 0)
    }

    var isFolder: Bool {
        guard let url else { return false }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    var subtitle: String {
        if let text {
            let n = text.count
            return "текст · \(n) \(Plural.ru(n, "знак", "знака", "знаков"))"
        }
        if isFolder, let url {
            let n = (try? FileManager.default.contentsOfDirectory(atPath: url.path).count) ?? 0
            return n == 0 ? "папка · пусто" : "папка · \(n)"
        }
        return Bytes.str(byteSize)
    }

    var kindLabel: String {
        if isText { return "текст" }
        guard let url else { return "" }
        if isLink { return "ссылка" }
        if let t = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if t.conforms(to: .folder) { return "папка" }
            return t.localizedDescription ?? url.pathExtension.uppercased()
        }
        return url.pathExtension.uppercased()
    }

    /// Мера вещи для карточки: у текста — знаки, у картинки — пиксели,
    /// у файла — вес. Пиксели считаем без загрузки самой картинки.
    var measure: String {
        if let text {
            let n = text.count
            return "\(n) \(Plural.ru(n, "знак", "знака", "знаков"))"
        }
        if isImage, let url, let size = Self.pixelSize(url) {
            return "\(Int(size.width)) × \(Int(size.height))"
        }
        if isFolder { return subtitle }
        return Bytes.str(byteSize)
    }

    private static func pixelSize(_ url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double
        else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Когда попало на полку — коротко и по-человечески.
    var whenLabel: String {
        let s = Int(Date().timeIntervalSince(addedAt))
        if s < 60 { return "только что" }
        let m = s / 60
        if m < 60 { return "\(m) \(Plural.ru(m, "минуту", "минуты", "минут") ) назад" }
        let h = m / 60
        if h < 24 { return "\(h) \(Plural.ru(h, "час", "часа", "часов")) назад" }
        let d = h / 24
        if d < 7 { return "\(d) \(Plural.ru(d, "день", "дня", "дней")) назад" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f.string(from: addedAt)
    }

    /// По чему ищем: имя, содержимое, вид, программа-источник.
    var haystack: String {
        [name, text ?? "", url?.path ?? "", kindLabel, linkAddress ?? "",
         appID.flatMap(Apps.name) ?? ""].joined(separator: " ").lowercased()
    }
}

/// Программа, из которой вещь приехала: иконка и имя по bundle id.
enum Apps {
    private static var icons: [String: NSImage] = [:]
    private static var names: [String: String] = [:]

    static func url(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func icon(_ bundleID: String) -> NSImage? {
        if let hit = icons[bundleID] { return hit }
        guard let u = url(bundleID) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: u.path)
        img.size = NSSize(width: 32, height: 32)
        icons[bundleID] = img
        return img
    }

    static func name(_ bundleID: String) -> String? {
        if let hit = names[bundleID] { return hit }
        guard let u = url(bundleID) else { return nil }
        let title = FileManager.default.displayName(atPath: u.path)
        names[bundleID] = title
        return title
    }

    /// Кто был впереди в момент копирования (нас самих не считаем).
    static var frontmostID: String? {
        let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return id == Bundle.main.bundleIdentifier ? nil : id
    }
}

enum Plural {
    static func ru(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let hundred = abs(n) % 100, ten = abs(n) % 10
        if (11...14).contains(hundred) { return many }
        if ten == 1 { return one }
        if (2...4).contains(ten) { return few }
        return many
    }
}

enum Bytes {
    static let fmt: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()
    static func str(_ n: Int64) -> String { fmt.string(fromByteCount: max(0, n)) }
}
