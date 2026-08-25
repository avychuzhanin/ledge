import AppKit
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ShelfStore()
    private var shelf: ShelfController!
    private let watcher = DragWatcher()
    private let edge = EdgeWatcher()
    private var countSub: AnyCancellable?
    private var statusItem: NSStatusItem!
    private var shots: ShotCatcher!
    private var clips: ClipWatcher!
    private var wide: WideController!
    private let hotKey = HotKey()

    func applicationDidFinishLaunching(_ note: Notification) {
        dropOtherInstances()
        Keep.register()
        Wide.register()
        store.dropMissing()
        shelf = ShelfController(store: store)

        wide = WideController(store: store)
        wide.onMarkup = { [weak self] item in self?.shelf.markup(item) }
        wide.onOpen = { [weak self] in self?.shelf.hide() }
        shelf.onExpand = { [weak self] in self?.wide.toggle() }
        hotKey.onFire = { [weak self] in self?.wide.toggle() }
        applyHotKey()

        watcher.onBegin = { [weak self] in self?.shelf.dragSessionBegan() }
        watcher.onEnd = { [weak self] in self?.shelf.dragSessionEnded() }
        watcher.start()

        edge.onMove = { [weak self] p in self?.shelf.pointerMoved(p) }
        edge.start()

        shots = ShotCatcher(store: store)
        shots.onCatch = { [weak self] in self?.shelf.flash() }
        shots.apply()

        clips = ClipWatcher(store: store)
        clips.apply()

        buildStatusItem()
        countSub = store.$items.receive(on: RunLoop.main).sink { [weak self] items in
            self?.statusItem.button?.title = items.isEmpty ? "" : " \(items.count)"
        }
        if ProcessInfo.processInfo.environment["LEDGE_DEBUG"] == "1" { shelf.debugPin() }
        if ProcessInfo.processInfo.environment["LEDGE_WIDE"] == "1" {
            UserDefaults.standard.set(true, forKey: Wide.key)
            applyHotKey()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.wide.show() }
        }
        if let path = ProcessInfo.processInfo.environment["LEDGE_MARKUP"] {
            let item = ShelfItem(url: URL(fileURLWithPath: path), owned: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.shelf.debugMarkup(item) }
        }
    }

    /// Две полки сразу — это две истории буфера. Оставляем свежую.
    private func dropOtherInstances() {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let id = Bundle.main.bundleIdentifier else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: id)
        where app.processIdentifier != me {
            app.forceTerminate()
        }
    }

    // MARK: меню-бар

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Mark.statusImage()
        statusItem.button?.toolTip = "Ledge — полка для перетаскивания"

        let menu = NSMenu()
        menu.addItem(item("Показать полку", #selector(togglePanel), "l"))
        let lane = item("Открыть ленту (⌘⇧V)", #selector(toggleWidePanel), "")
        lane.toolTip = "Вся история буфера карточками, поиск и стопки"
        menu.addItem(lane)
        menu.addItem(item("Очистить", #selector(clearShelf), "k"))
        menu.addItem(item("Вернуть полку на место", #selector(resetPlace), ""))
        menu.addItem(.separator())
        let wideItem = item("Расширенный режим", #selector(toggleWide), "")
        wideItem.state = Wide.isOn ? .on : .off
        wideItem.toolTip = "Полка разворачивается в ленту карточек по ⌘⇧V: "
            + "история буфера, поиск, стопки и вставка с клавиш"
        menu.addItem(wideItem)
        let catchShots = item("Скриншоты — сразу на полку", #selector(toggleShots), "")
        catchShots.state = shots.isOn ? .on : .off
        menu.addItem(catchShots)
        let catchClips = item("Буфер обмена — на полку", #selector(toggleClips), "")
        catchClips.state = clips.isOn ? .on : .off
        menu.addItem(catchClips)
        let keep = item("Оставлять после перетаскивания", #selector(toggleKeep), "")
        keep.state = Keep.isOn ? .on : .off
        keep.toolTip = "Вещь остаётся на полке, даже когда её утащили наружу"
        menu.addItem(keep)
        menu.addItem(item("Папка снимков", #selector(openShots), ""))
        menu.addItem(item("Папка хранилища", #selector(openStorage), ""))
        let launch = item("Запускать при входе", #selector(toggleLaunch), "")
        launch.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(launch)
        menu.addItem(.separator())
        menu.addItem(item("Выйти из Ledge", #selector(quit), "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    private func item(_ title: String, _ sel: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func togglePanel() { shelf.toggle() }
    @objc private func toggleWidePanel() { wide.toggle() }

    /// Расширенный режим: включён — работает ⌘⇧V и кнопка разворота на полке.
    @objc private func toggleWide() {
        Wide.toggle()
        applyHotKey()
        if !Wide.isOn { wide.hide() }
    }

    private func applyHotKey() {
        Wide.isOn ? hotKey.register() : hotKey.unregister()
    }
    @objc private func clearShelf() { store.removeAll() }
    @objc private func resetPlace() { shelf.resetPlacement() }
    @objc private func openStorage() { NSWorkspace.shared.open(ShelfStore.root) }
    @objc private func openShots() { NSWorkspace.shared.open(ShotCatcher.folder) }
    @objc private func toggleShots() { shots.toggle() }
    @objc private func toggleClips() { clips.toggle() }
    @objc private func toggleKeep() { Keep.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLaunch(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first(where: { $0.action == #selector(toggleLaunch) })?
            .state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.items.first(where: { $0.action == #selector(clearShelf) })?
            .isEnabled = !store.items.isEmpty
        menu.items.first(where: { $0.action == #selector(toggleShots) })?
            .state = shots.isOn ? .on : .off
        menu.items.first(where: { $0.action == #selector(toggleClips) })?
            .state = clips.isOn ? .on : .off
        menu.items.first(where: { $0.action == #selector(toggleKeep) })?
            .state = Keep.isOn ? .on : .off
        menu.items.first(where: { $0.action == #selector(toggleWide) })?
            .state = Wide.isOn ? .on : .off
        menu.items.first(where: { $0.action == #selector(toggleWidePanel) })?
            .isEnabled = Wide.isOn
    }
}
