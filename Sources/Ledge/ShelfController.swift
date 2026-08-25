import AppKit
import Combine
import SwiftUI

/// Окно-полка: где стоит, когда выезжает, когда прячется.
final class ShelfController {
    private let store: ShelfStore
    private let state = ShelfState()
    private let panel: NSPanel
    private let catcher = DropCatcherView(frame: .zero)
    private var hosting: NSHostingView<AnyView>!

    private var poll: Timer?
    private var outsideSince: Date?
    private var storeSub: AnyCancellable?
    private var lastTease: Date?
    private var holdUntil: Date?

    /// Полку просят развернуть в ленту — этим занимается расширенный режим.
    var onExpand: (() -> Void)?

    private let place = ShelfPlacement()
    private let peek = PeekPanel()
    private let markup = MarkupWindow()

    init(store: ShelfStore) {
        self.store = store
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        configurePanel()
        buildContent()

        storeSub = store.$items.dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                guard let self, self.state.mode == .open, !self.state.moving else { return }
                self.apply(rows: items.count)
            }
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // MARK: сборка

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
    }

    private func buildContent() {
        catcher.autoresizingMask = [.width, .height]
        catcher.onEnter = { [weak self] in self?.dragTarget(true) }
        catcher.onExit = { [weak self] in self?.dragTarget(false) }
        catcher.onDrop = { [weak self] pb in self?.accept(pb) ?? false }
        panel.contentView = catcher

        let moves = MoveActions(begin: { [weak self] in self?.state.moving = true },
                                moved: { [weak self] in self?.dragged(to: $0) },
                                end: { [weak self] in self?.endMove() })
        let root = AnyView(ShelfView(store: store, state: state,
                                     onDragAllOut: { [weak self] op in self?.afterDragAll(op) },
                                     onClear: { [weak self] in self?.clearAll() },
                                     onPeek: { [weak self] in self?.peekAt($0) },
                                     onEdit: { [weak self] in self?.edit($0) },
                                     onExpand: { [weak self] in self?.expand() },
                                     move: moves))
        hosting = NSHostingView(rootView: root)
        hosting.frame = catcher.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.unregisterDraggedTypes()
        catcher.addSubview(hosting)
    }

    // MARK: состояния

    /// Курсор коснулся грани экрана.
    func pointerMoved(_ p: CGPoint) {
        let rows = store.items.count
        if place.hotContains(p, rows: rows) {
            // из «краешка» тоже разворачиваемся целиком
            if state.mode == .hidden || state.teasing { open() }
            return
        }
        guard state.mode == .hidden else { return }
        // Рука пошла в привычное место, а полка теперь в другом: высовываем
        // краешек там, где она лежит, и качаем — «привет, я тут».
        guard place.homeContains(p), !place.isAtHome else { return }
        tease()
    }

    func dragSessionBegan() { state.armed = true }

    func dragSessionEnded() {
        state.armed = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.state.targeted = false
            if !self.pointerInside() { self.hide() }
        }
    }

    func open() {
        state.teasing = false
        holdUntil = nil
        state.mode = .open
        apply(rows: store.items.count)
        panel.orderFrontRegardless()
        DispatchQueue.main.async { self.state.shown = true }
        startPolling()
    }

    /// Показать только краешек полки на её грани и качнуть им.
    private func tease() {
        if let last = lastTease, Date().timeIntervalSince(last) < 2.5 { return }
        lastTease = Date()

        let rows = store.items.count
        state.mode = .open
        state.teaseOffset = place.teaseOffset(rows: rows)
        state.teasing = true
        apply(rows: rows)
        panel.orderFrontRegardless()
        holdUntil = Date().addingTimeInterval(1.6)
        DispatchQueue.main.async { self.state.shown = true }
        startPolling()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
            guard let self, self.state.teasing else { return }
            self.state.shakeToken += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.state.teasing else { return }
            self.state.teasing = false
            self.holdUntil = nil
            self.hide()
        }
    }

    func hide() {
        guard state.mode != .hidden else { return }
        state.shown = false
        state.mode = .hidden
        state.teasing = false
        peek.hide()
        poll?.invalidate(); poll = nil
        outsideSince = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) { [weak self] in
            guard let self, self.state.mode == .hidden else { return }
            self.panel.orderOut(nil)
        }
    }

    func toggle() { state.mode == .open ? hide() : open() }

    /// Карандаш: прячем полку и открываем разметку — дальше работа там.
    private func edit(_ item: ShelfItem) {
        peek.hide()
        hide()
        markup.onSaved = { [weak self] in self?.store.reload(item.id) }
        markup.open(item)
    }

    /// Разметить картинку — зовётся и с полки, и из ленты.
    func markup(_ item: ShelfItem) { edit(item) }

    func debugMarkup(_ item: ShelfItem) { edit(item) }

    private func peekAt(_ item: ShelfItem) {
        peek.toggle(item, card: panel.frame.insetBy(dx: M.gutter, dy: M.gutter))
    }

    /// Показать полку и подержать её на экране (прилетел скриншот).
    func flash(seconds: TimeInterval = 2.6) {
        open()
        holdUntil = Date().addingTimeInterval(seconds)
    }

    /// Отладка: держать полку открытой, не давая свернуться.
    func debugPin() { open(); holdUntil = .distantFuture }


    func resetPlacement() {
        place.reset()
        state.edge = .left
        if state.mode == .open { apply(rows: store.items.count) } else { open() }
    }

    // MARK: геометрия

    private func apply(rows: Int) {
        let frame = place.windowFrame(rows: rows)
        panel.setFrame(frame, display: true)
        catcher.hotRect = NSRect(x: M.gutter, y: M.gutter,
                                 width: M.cardW, height: M.cardHeight(rows: rows))
        state.edge = place.edge
    }

    private func dragged(to origin: NSPoint) {
        peek.hide()
        let rows = store.items.count
        panel.setFrame(place.snap(windowOrigin: origin, rows: rows), display: true)
        state.edge = place.edge
    }

    private func endMove() {
        state.moving = false
        outsideSince = nil
        apply(rows: store.items.count)
    }

    @objc private func screensChanged() {
        if state.mode == .open { apply(rows: store.items.count) }
    }

    // MARK: указатель

    private func startPolling() {
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func pointerInside() -> Bool {
        let p = NSEvent.mouseLocation
        if place.liveRect(rows: store.items.count).contains(p) { return true }
        return peek.isVisible
            && peek.frame.insetBy(dx: M.gutter - 10, dy: M.gutter - 10).contains(p)
    }

    private func tick() {
        guard state.mode == .open else { return }
        if let hold = holdUntil, Date() < hold { outsideSince = nil; return }
        if pointerInside() || state.armed || state.targeted || state.moving {
            outsideSince = nil
            return
        }
        if let since = outsideSince {
            if Date().timeIntervalSince(since) > 0.25 { hide() }
        } else {
            outsideSince = Date()
        }
    }

    // MARK: события драга

    private func dragTarget(_ on: Bool) {
        guard state.targeted != on else { return }
        state.targeted = on
    }

    private func accept(_ pb: NSPasteboard) -> Bool {
        let items = Ingest.items(from: pb, store: store)
        guard !items.isEmpty else { return false }
        store.add(items)
        state.targeted = false
        return true
    }

    private func clearAll() { store.removeAll() }

    /// Полка уходит с экрана, её место занимает лента.
    private func expand() {
        hide()
        onExpand?()
    }

    /// Утащили всё разом с заголовка. Чистим полку только если так настроено.
    private func afterDragAll(_ operation: NSDragOperation) {
        guard Keep.shouldRemove(after: operation) else { return }
        store.removeAll()
    }
}
