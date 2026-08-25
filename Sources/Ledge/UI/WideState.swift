import SwiftUI

/// Что показываем в ленте: только текст, только картинки и так далее.
enum KindFilter: String, CaseIterable, Identifiable {
    case all, text, image, link, file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:   return "Всё подряд"
        case .text:  return "Текст"
        case .image: return "Картинки"
        case .link:  return "Ссылки"
        case .file:  return "Файлы"
        }
    }

    var glyph: String {
        switch self {
        case .all:   return "square.grid.2x2"
        case .text:  return "text.alignleft"
        case .image: return "photo"
        case .link:  return "link"
        case .file:  return "doc"
        }
    }

    func matches(_ item: ShelfItem) -> Bool {
        switch self {
        case .all:   return true
        case .text:  return item.kind == .text
        case .image: return item.kind == .image
        case .link:  return item.kind == .link
        case .file:  return item.kind == .file || item.kind == .folder
        }
    }
}

final class WideState: ObservableObject {
    @Published var shown = false
    @Published var edge: ShelfEdge = .left
    @Published var size: CGSize = .zero          // размер панели, считает контроллер
    @Published var query = ""
    @Published var board: UUID?                  // выбранная стопка, nil — вся полка
    @Published var filter: KindFilter = .all
    @Published var cursor: UUID?                 // на чём стоит рамка
    @Published var picked: [UUID] = []           // выбранное, в порядке вставки
    @Published var quick = false                 // зажат ⌘ — на карточках номера
    @Published var peek: ShelfItem?              // раскрытое превью
    @Published var targeted = false              // на ленту что-то тащат
    @Published var dropBoard: UUID?              // на какую стопку тащат
    @Published var renaming: UUID?               // стопка, у которой правим имя
    @Published var focusSearch = 0               // счётчик: увести фокус в поиск
    @Published var keys = false                  // шпаргалка по клавишам

    var lane: Bool { !edge.isVertical }          // лента вдоль верхней/нижней грани

    /// Что реально видно в ленте: стопка, фильтр по виду, поиск.
    func visible(_ items: [ShelfItem]) -> [ShelfItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            if let board, item.board != board { return false }
            guard filter.matches(item) else { return false }
            guard !q.isEmpty else { return true }
            return item.haystack.contains(q)
        }
    }

    func isPicked(_ id: UUID) -> Bool { picked.contains(id) }

    func pick(only id: UUID) {
        picked = [id]
        cursor = id
    }

    func toggle(_ id: UUID) {
        if let i = picked.firstIndex(of: id) { picked.remove(at: i) } else { picked.append(id) }
        cursor = id
    }

    func reset() {
        query = ""
        filter = .all
        picked = []
        cursor = nil
        peek = nil
        renaming = nil
    }
}
