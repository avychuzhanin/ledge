import AppKit
import SwiftUI

/// Что лента умеет делать с вещами — всё это же висит на клавишах.
struct WideActions {
    var paste: ([ShelfItem], Bool) -> Void       // вставить (простым текстом — вторым)
    var copy: ([ShelfItem], Bool) -> Void
    var open: (ShelfItem) -> Void
    var edit: (ShelfItem) -> Void
    var remove: ([UUID]) -> Void
    var afterDrag: (ShelfItem, NSDragOperation) -> Void
    var accept: (NSPasteboard, UUID?) -> Bool    // упало на ленту или на корешок стопки
    var collapse: () -> Void
}

/// Расширенный режим: та же полка, разложенная вдоль своей грани.
/// У боковых граней — два ряда карточек, у верхней и нижней — лента.
struct WideView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var boards: BoardStore
    @ObservedObject var state: WideState
    var act: WideActions

    @FocusState private var searching: Bool

    private var visible: [ShelfItem] { state.visible(store.items) }
    private var cardH: CGFloat { state.lane ? W.bandCardH : W.cardH }

    var body: some View {
        panel
            .frame(width: state.size.width, height: state.size.height)
            .padding(M.gutter)
            .offset(x: enter.width, y: enter.height)
            .opacity(state.shown ? 1 : 0)
            .animation(state.shown ? .spring(response: 0.34, dampingFraction: 0.86)
                                   : .easeIn(duration: 0.14), value: state.shown)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: state.focusSearch) { _, _ in searching = true }
            .onChange(of: state.shown) { _, shown in if shown { searching = true } }
    }

    /// Выезжает из-за своей грани — как полка, только шире.
    private var enter: CGSize {
        guard !state.shown else { return .zero }
        let dx = state.size.width + M.gutter, dy = state.size.height + M.gutter
        switch state.edge {
        case .left:   return CGSize(width: -dx, height: 0)
        case .right:  return CGSize(width: dx, height: 0)
        case .top:    return CGSize(width: 0, height: -dy)
        case .bottom: return CGSize(width: 0, height: dy)
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            bar
            Rectangle().fill(Ink.hairline).frame(height: 0.5)
            deck
        }
        .frame(width: state.size.width, height: state.size.height, alignment: .top)
        .glassCard(radius: M.radius, targeted: state.targeted)
        .overlay { peekLayer }
        .overlay { keysLayer }
        .animation(.easeOut(duration: 0.15), value: state.targeted)
    }

    // MARK: верхняя строка

    /// В ленте всё влезает в строку. В колонке ширины мало — корешки стопок
    /// уезжают на второй этаж, чтобы ничего не обрезалось.
    @ViewBuilder private var bar: some View {
        if state.lane {
            HStack(spacing: 10) {
                search
                spines
                Spacer(minLength: 0)
                more
                collapse
            }
            .padding(.horizontal, W.pad)
            .frame(height: W.barH)
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    search
                    Spacer(minLength: 0)
                    more
                    collapse
                }
                spines
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, W.pad)
            .frame(height: W.barTallH)
        }
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Найти", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searching)
            if !state.query.isEmpty {
                Button { state.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Очистить поиск")
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 176, height: 26)
        .background(Ink.rowOn, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
    }

    /// Корешки стопок: «Вся полка», дальше свои стопки, дальше «плюс».
    private var spines: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "Вся полка", tint: nil, count: store.items.count,
                     active: state.board == nil, board: nil)
                ForEach(boards.boards) { board in
                    if state.renaming == board.id {
                        rename(board)
                    } else {
                        chip(title: board.name, tint: Spine.color(board.tint),
                             count: store.count(in: board.id),
                             active: state.board == board.id, board: board.id)
                    }
                }
                plus
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: state.lane ? 420 : .infinity)
    }

    private func chip(title: String, tint: Color?, count: Int,
                      active: Bool, board: UUID?) -> some View {
        HStack(spacing: 6) {
            if let tint {
                Capsule().fill(tint).frame(width: 3, height: 13)
            }
            Text(title)
                .font(.system(size: 12, weight: active ? .medium : .regular))
                .lineLimit(1)
            Text("\(count)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(active ? Color.accentColor.opacity(0.18) : Ink.rowOn, in: Capsule())
        .overlay {
            Capsule().strokeBorder(state.dropBoard == board && board != nil
                                   ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .animation(.easeOut(duration: 0.14), value: state.dropBoard)
        .overlay {
            DropSpot(onEnter: { if board != nil { state.dropBoard = board } },
                     onExit: { state.dropBoard = nil },
                     onDrop: { act.accept($0, board) },
                     onClick: { state.board = board; state.cursor = nil; state.picked = [] })
        }
        .help(board == nil ? "Всё, что лежит на полке"
                           : "Стопка «\(title)» — брось сюда вещь, и она останется здесь")
    }

    private func rename(_ board: Board) -> some View {
        TextField("Имя стопки", text: Binding(
            get: { boards.board(board.id)?.name ?? "" },
            set: { boards.rename(board.id, to: $0) }))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .frame(width: 120, height: 26)
            .padding(.horizontal, 9)
            .background(Ink.rowOn, in: Capsule())
            .onSubmit { state.renaming = nil }
    }

    private var plus: some View {
        Button {
            let board = boards.add()
            state.board = board.id
            state.renaming = board.id
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Ink.rowOn, in: Circle())
        }
        .buttonStyle(.plain)
        .help("Новая стопка — ⌘⇧N")
    }

    private var more: some View {
        Menu {
            Picker("Показывать", selection: $state.filter) {
                ForEach(KindFilter.allCases) { f in
                    Label(f.title, systemImage: f.glyph).tag(f)
                }
            }
            .pickerStyle(.inline)

            if let id = state.board, let board = boards.board(id) {
                Divider()
                Button("Переименовать «\(board.name)»") { state.renaming = id }
                Menu("Цвет корешка") {
                    ForEach(Array(Spine.names.enumerated()), id: \.offset) { i, name in
                        Button(name) { boards.recolor(id, tint: i) }
                    }
                }
                Button("Убрать стопку") {
                    store.forgetBoard(id)
                    boards.remove(id)
                    state.board = nil
                }
            }

            if !state.picked.isEmpty {
                Divider()
                Menu("Положить в стопку") {
                    ForEach(boards.boards) { board in
                        Button(board.name) { store.setBoard(state.picked, to: board.id) }
                    }
                    Button("Новая стопка…") {
                        let board = boards.add()
                        store.setBoard(state.picked, to: board.id)
                        state.renaming = board.id
                    }
                    Divider()
                    Button("Вынуть из стопки") { store.setBoard(state.picked, to: nil) }
                }
            }

            Divider()
            Button("Клавиши") { state.keys.toggle() }
            Button("Очистить историю буфера") { store.removeHistory() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26, height: 26)
        .background(Ink.rowOn, in: Circle())
        .help("Стопки, фильтр, клавиши")
    }

    private var collapse: some View {
        Button(action: act.collapse) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Ink.rowOn, in: Circle())
        }
        .buttonStyle(.plain)
        .help("Свернуть обратно в полку — Esc")
    }

    // MARK: лента

    @ViewBuilder private var deck: some View {
        if visible.isEmpty {
            empty
        } else if state.lane {
            lane
        } else {
            grid
        }
    }

    private var lane: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: W.gap) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { i, item in
                        card(i, item)
                    }
                }
                .padding(W.pad)
            }
            .onChange(of: state.cursor) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .background { catcher }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.fixed(W.cardW), spacing: W.gap),
                                    GridItem(.fixed(W.cardW), spacing: W.gap)],
                          spacing: W.gap) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { i, item in
                        card(i, item)
                    }
                }
                .padding(W.pad)
            }
            .onChange(of: state.cursor) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .background { catcher }
    }

    /// Пустое место ленты принимает всё, что на него бросают.
    private var catcher: some View {
        DropSpot(onEnter: { state.targeted = true },
                 onExit: { state.targeted = false },
                 onDrop: { pb in
                     state.targeted = false
                     return act.accept(pb, state.board)
                 },
                 onClick: nil)
    }

    private func card(_ i: Int, _ item: ShelfItem) -> some View {
        CardView(item: item,
                 height: cardH,
                 tint: boards.color(of: item.board),
                 number: state.quick && i < 9 ? i + 1 : nil,
                 picked: state.isPicked(item.id),
                 onDown: { flags in
                     if flags.contains(.command) { state.toggle(item.id) }
                     else { state.pick(only: item.id) }
                 },
                 onOpen: { act.paste([item], false) },
                 onDragOut: { op in act.afterDrag(item, op) })
            .id(item.id)
            .contextMenu { menu(for: item) }
    }

    @ViewBuilder private func menu(for item: ShelfItem) -> some View {
        Button("Вставить") { act.paste([item], false) }
        Button("Вставить простым текстом") { act.paste([item], true) }
        Button("Скопировать") { act.copy([item], false) }
        Divider()
        if item.url != nil { Button("Открыть") { act.open(item) } }
        if item.isImage { Button("Разметить") { act.edit(item) } }
        Menu("Положить в стопку") {
            ForEach(boards.boards) { board in
                Button(board.name) { store.setBoard([item.id], to: board.id) }
            }
            Button("Новая стопка…") {
                let board = boards.add()
                store.setBoard([item.id], to: board.id)
                state.renaming = board.id
            }
            if item.board != nil {
                Divider()
                Button("Вынуть из стопки") { store.setBoard([item.id], to: nil) }
            }
        }
        Divider()
        Button("Убрать с полки") { act.remove([item.id]) }
    }

    private var empty: some View {
        VStack(spacing: 9) {
            Image(systemName: state.query.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { catcher }
    }

    private var emptyLine: String {
        if !state.query.isEmpty { return "По «\(state.query)» ничего нет" }
        if state.board != nil { return "Стопка пустая — брось сюда вещь с полки" }
        return "Пока пусто. Копируй, снимай экран, таскай файлы — всё окажется здесь"
    }

    // MARK: слои поверх

    @ViewBuilder private var peekLayer: some View {
        if let item = state.peek {
            ZStack {
                RoundedRectangle(cornerRadius: M.radius, style: .continuous)
                    .fill(.black.opacity(0.32))
                PeekBox(item: item)
                    .padding(W.peekPad)
            }
            .onTapGesture { state.peek = nil }
            .transition(.opacity)
        }
    }

    @ViewBuilder private var keysLayer: some View {
        if state.keys {
            ZStack {
                RoundedRectangle(cornerRadius: M.radius, style: .continuous)
                    .fill(.black.opacity(0.32))
                KeysBox()
                    .padding(W.peekPad)
            }
            .onTapGesture { state.keys = false }
            .transition(.opacity)
        }
    }
}

/// Раскрытая вещь: текст читается целиком, файл показывает QuickLook.
private struct PeekBox: View {
    let item: ShelfItem

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return content
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
    }

    @ViewBuilder private var content: some View {
        if let text = item.text {
            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
        } else if let url = item.url {
            QLView(url: url)
        } else {
            Color.clear
        }
    }
}

/// Шпаргалка по клавишам — чтобы не держать их в голове.
private struct KeysBox: View {
    private let rows: [(String, String)] = [
        ("⌘⇧V", "открыть и закрыть ленту"),
        ("← → ↑ ↓", "ходить по карточкам"),
        ("⇧ + стрелки", "взять несколько подряд"),
        ("⌘-клик", "добавить к выбранным"),
        ("↩", "вставить туда, где работал"),
        ("⇧↩", "вставить простым текстом"),
        ("⌘1 … ⌘9", "вставить карточку по номеру"),
        ("⌘C", "скопировать"),
        ("Пробел", "раскрыть превью"),
        ("⌘O", "открыть файл или ссылку"),
        ("⌘E", "разметить картинку"),
        ("⌫", "убрать с полки"),
        ("⌘F", "искать"),
        ("⌘← ⌘→", "между стопками"),
        ("⌘⇧N", "новая стопка"),
        ("Esc", "закрыть")
    ]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(rows, id: \.0) { key, what in
                    HStack(spacing: 12) {
                        Text(key)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .frame(width: 96, alignment: .leading)
                        Text(what)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
    }
}
