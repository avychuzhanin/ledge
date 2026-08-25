import Foundation
import SwiftUI

/// Стопка — именованная кучка вещей, которая не тает вместе с историей буфера.
/// Каждой стопке достаётся цвет: им красится корешок карточки, как у книжки
/// на полке, — по корешку и видно, из какой она стопки.
struct Board: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var tint: Int

    init(name: String, tint: Int) {
        self.id = UUID()
        self.name = name
        self.tint = tint
    }
}

enum Spine {
    /// Системные цвета macOS: родные и в светлой, и в тёмной теме.
    static let all: [Color] = [.red, .orange, .yellow, .green, .teal, .blue, .purple, .pink]

    static func color(_ i: Int) -> Color {
        all[((i % all.count) + all.count) % all.count]
    }

    static let names = ["красный", "оранжевый", "жёлтый", "зелёный",
                        "бирюзовый", "синий", "фиолетовый", "розовый"]
}

final class BoardStore: ObservableObject {
    @Published private(set) var boards: [Board] = []

    private var fileURL: URL { ShelfStore.root.appendingPathComponent("boards.json") }

    init() { load() }

    func board(_ id: UUID?) -> Board? {
        guard let id else { return nil }
        return boards.first { $0.id == id }
    }

    func color(of id: UUID?) -> Color? {
        board(id).map { Spine.color($0.tint) }
    }

    @discardableResult
    func add(name: String? = nil) -> Board {
        let title = name ?? "Стопка \(boards.count + 1)"
        let board = Board(name: title, tint: boards.count % Spine.all.count)
        boards.append(board)
        save()
        return board
    }

    func rename(_ id: UUID, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[i].name = clean
        save()
    }

    func recolor(_ id: UUID, tint: Int) {
        guard let i = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[i].tint = tint
        save()
    }

    func remove(_ id: UUID) {
        boards.removeAll { $0.id == id }
        save()
    }

    // MARK: диск

    private func save() {
        try? JSONEncoder().encode(boards).write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        boards = (try? JSONDecoder().decode([Board].self, from: data)) ?? []
    }
}
