import AppKit
import Combine
import SwiftUI

/// Ленте нужен настоящий фокус: иначе не работают ни поиск, ни клавиши.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Расширенный режим: широкая лента карточек вдоль той грани, где стоит полка.
final class WideController {
    private let store: ShelfStore
    private let boards = BoardStore()
    private let state = WideState()
    private let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                                 styleMask: [.borderless],
                                 backing: .buffered, defer: false)
    private var hosting: NSHostingView<AnyView>!
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    /// Куда возвращать фокус и куда вставлять.
    private var backTo: NSRunningApplication?

    private var subs: Set<AnyCancellable> = []

    /// Разметка картинки живёт у полки — зовём её оттуда.
    var onMarkup: ((ShelfItem) -> Void)?
    /// Лента открылась — полке на экране делать нечего.
    var onOpen: (() -> Void)?

    init(store: ShelfStore) {
        self.store = store
        configure()
        build()
        NotificationCenter.default.addObserver(
            self, selector: #selector(lostFocus),
            name: NSWindow.didResignKeyNotification, object: panel)

        // Колонка растёт по содержимому: вещей прибавилось — стало выше.
        // Поиск размер не трогает, иначе панель дёргалась бы на каждой букве.
        store.$items.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &subs)
        state.$board.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &subs)
        state.$filter.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &subs)
    }

    var isOpen: Bool { panel.isVisible && state.shown }

    // MARK: сборка

    private func configure() {
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
    }

    private func build() {
        let act = WideActions(
            paste: { [weak self] items, plain in self?.paste(items, plain: plain) },
            copy: { items, plain in Paster.copy(items, plain: plain) },
            open: { [weak self] item in self?.open(item) },
            edit: { [weak self] item in self?.markup(item) },
            remove: { [weak self] ids in self?.remove(ids) },
            afterDrag: { [weak self] item, op in
                guard Keep.shouldRemove(after: op) else { return }
                self?.remove([item.id])
            },
            accept: { [weak self] pb, board in self?.accept(pb, board: board) ?? false },
            collapse: { [weak self] in self?.hide() })

        let root = AnyView(WideView(store: store, boards: boards, state: state, act: act))
        hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    // MARK: показать и спрятать

    func toggle() { isOpen ? hide() : show() }

    func show() {
        guard Wide.isOn else { return }
        onOpen?()
        layout()
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { backTo = front }

        state.picked = []
        state.cursor = visible.first?.id
        if let id = state.cursor { state.picked = [id] }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(hosting)
        DispatchQueue.main.async { self.state.shown = true }
        watchKeys()
    }

    func hide() {
        guard panel.isVisible else { return }
        state.shown = false
        state.peek = nil
        state.keys = false
        state.renaming = nil
        stopKeys()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, !self.state.shown else { return }
            self.panel.orderOut(nil)
        }
        backTo?.activate()
    }

    @objc private func lostFocus() {
        guard state.shown, state.renaming == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, !self.panel.isKeyWindow else { return }
            self.hide()
        }
    }

    private func relayout() {
        guard state.shown else { return }
        layout()
    }

    /// Панель прижата к той же грани, где стоит полка. У верхней и нижней —
    /// лента во всю ширину, у боковых — колонка в два ряда: она вырастает
    /// оттуда, где лежит полка, и ровно настолько, сколько нужно карточкам.
    private func layout() {
        let place = ShelfPlacement()
        let vf = place.screen.visibleFrame
        let edge = place.edge
        let size: CGSize
        let origin: CGPoint

        switch edge {
        case .left, .right:
            let rows = max(1, Int(ceil(Double(visible.count) / 2)))
            let full = W.barTallH + W.pad * 2 + CGFloat(rows) * W.cardH
                + CGFloat(rows - 1) * W.gap
            let h = min(max(full, W.colMinH), vf.height - M.edgeGap * 2)
            size = CGSize(width: W.colW, height: h)
            let x = edge == .left ? vf.minX + M.edgeGap : vf.maxX - M.edgeGap - size.width
            let mid = min(max(place.cardRect(rows: 0).midY, vf.minY + h / 2), vf.maxY - h / 2)
            origin = CGPoint(x: x, y: mid - h / 2)
        case .top, .bottom:
            size = CGSize(width: vf.width - M.edgeGap * 2, height: W.stripH)
            let y = edge == .top ? vf.maxY - M.edgeGap - size.height : vf.minY + M.edgeGap
            origin = CGPoint(x: vf.minX + M.edgeGap, y: y)
        }

        state.size = size
        state.edge = edge
        panel.setFrame(NSRect(origin: origin, size: size).insetBy(dx: -M.gutter, dy: -M.gutter),
                       display: true)
    }

    // MARK: что видно и что выбрано

    private var visible: [ShelfItem] { state.visible(store.items) }

    private var current: ShelfItem? {
        guard let id = state.cursor else { return visible.first }
        return store.items.first { $0.id == id }
    }

    /// Выбранное — в том порядке, в каком его набирали.
    private func selection() -> [ShelfItem] {
        guard !state.picked.isEmpty else { return current.map { [$0] } ?? [] }
        return state.picked.compactMap { id in store.items.first { $0.id == id } }
    }

    // MARK: действия

    private func paste(_ items: [ShelfItem], plain: Bool) {
        guard !items.isEmpty else { return }
        let app = backTo
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Paster.paste(items, into: app, plain: plain)
        }
    }

    private func open(_ item: ShelfItem) {
        if let text = item.text {
            Paster.copy([item], plain: true)
            _ = text
        } else if let url = item.url {
            NSWorkspace.shared.open(url)
        }
        hide()
    }

    private func markup(_ item: ShelfItem) {
        hide()
        onMarkup?(item)
    }

    private func remove(_ ids: [UUID]) {
        let list = visible
        let next = list.firstIndex { $0.id == state.cursor }.map { min($0 + 1, list.count - 1) }
        store.remove(ids)
        state.picked.removeAll { ids.contains($0) }
        if let id = state.cursor, ids.contains(id) {
            let fresh = visible
            state.cursor = next.flatMap { i in fresh.indices.contains(i) ? fresh[i].id : fresh.last?.id }
                ?? fresh.first?.id
        }
    }

    /// Что-то бросили в ленту или на корешок стопки. Если это вещь, которая
    /// уже лежит на полке, — не плодим копию, а перекладываем в стопку.
    private func accept(_ pb: NSPasteboard, board: UUID?) -> Bool {
        let known = alreadyHere(pb)
        if !known.isEmpty {
            store.setBoard(known, to: board)
            return true
        }
        let fresh = Ingest.items(from: pb, store: store)
        guard !fresh.isEmpty else { return false }
        store.add(fresh)
        if board != nil { store.setBoard(fresh.map(\.id), to: board) }
        return true
    }

    private func alreadyHere(_ pb: NSPasteboard) -> [UUID] {
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let paths = Set(urls.map(\.standardizedFileURL.path))
            let hits = store.items.filter { item in
                guard let u = item.url else { return false }
                return paths.contains(u.standardizedFileURL.path)
            }
            if !hits.isEmpty { return hits.map(\.id) }
        }
        if let text = pb.string(forType: .string) {
            return store.items.filter { $0.text == text }.map(\.id)
        }
        return []
    }

    // MARK: клавиши

    private func watchKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            return self.handle(e) ? nil : e
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.state.quick = e.modifierFlags.contains(.command)
            return e
        }
    }

    private func stopKeys() {
        state.quick = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        keyMonitor = nil
        flagsMonitor = nil
    }

    private func handle(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command), shift = flags.contains(.shift)
        let plain = state.query.isEmpty && state.renaming == nil

        switch e.keyCode {
        case 53:  // Esc
            if state.peek != nil { state.peek = nil; return true }
            if state.keys { state.keys = false; return true }
            if state.renaming != nil { state.renaming = nil; return true }
            if !state.query.isEmpty { state.query = ""; return true }
            hide()
            return true
        case 36:  // ↩
            if state.renaming != nil { state.renaming = nil; return true }
            paste(selection(), plain: shift)
            return true
        case 49:  // пробел
            if state.peek != nil { state.peek = nil; return true }
            guard plain else { return false }
            state.peek = current
            return true
        case 51, 117:  // ⌫
            guard plain else { return false }
            remove(state.picked.isEmpty ? [state.cursor].compactMap { $0 } : state.picked)
            return true
        case 123:  // ←
            if cmd { hop(-1) } else { move(-1, extend: shift) }
            return true
        case 124:  // →
            if cmd { hop(1) } else { move(1, extend: shift) }
            return true
        case 126:  // ↑
            move(state.lane ? -1 : -2, extend: shift)
            return true
        case 125:  // ↓
            move(state.lane ? 1 : 2, extend: shift)
            return true
        default:
            break
        }

        guard cmd else { return false }
        let key = e.charactersIgnoringModifiers?.lowercased() ?? ""

        if let n = Int(key), (1...9).contains(n) {
            let list = visible
            guard list.indices.contains(n - 1) else { return true }
            paste([list[n - 1]], plain: shift)
            return true
        }

        switch key {
        case "f":
            state.focusSearch += 1
            return true
        case "a":
            state.picked = visible.map(\.id)
            return true
        case "c":
            Paster.copy(selection(), plain: shift)
            return true
        case "o":
            if let item = current { open(item) }
            return true
        case "e":
            if let item = current, item.isImage { markup(item) }
            return true
        case "n":
            guard shift else { return false }
            let board = boards.add()
            state.board = board.id
            state.renaming = board.id
            return true
        case "w":
            hide()
            return true
        default:
            return false
        }
    }

    /// Ходим по карточкам. С ⇧ выбранное копится, без него — заменяется.
    private func move(_ delta: Int, extend: Bool) {
        let list = visible
        guard !list.isEmpty else { return }
        let now = list.firstIndex { $0.id == state.cursor } ?? 0
        let next = min(max(now + delta, 0), list.count - 1)
        let id = list[next].id
        state.cursor = id
        if extend {
            if !state.picked.contains(id) { state.picked.append(id) }
        } else {
            state.picked = [id]
        }
    }

    /// Между стопками: сначала вся полка, потом свои стопки по кругу.
    private func hop(_ delta: Int) {
        let lanes: [UUID?] = [nil] + boards.boards.map { Optional($0.id) }
        guard lanes.count > 1 else { return }
        let now = lanes.firstIndex { $0 == state.board } ?? 0
        let next = (now + delta + lanes.count) % lanes.count
        state.board = lanes[next]
        state.picked = []
        state.cursor = visible.first?.id
    }
}
