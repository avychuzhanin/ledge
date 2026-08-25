import AppKit
import Carbon.HIToolbox

/// Глобальная горячая клавиша ⌘⇧V — лента открывается поверх любой программы.
/// Carbon здесь единственный честный путь: он не требует особых разрешений.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var fire: (() -> Void)?

    var onFire: (() -> Void)? {
        didSet { HotKey.fire = onFire }
    }

    var isOn: Bool { ref != nil }

    func register() {
        guard ref == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.fire?() }
            return noErr
        }, 1, &type, nil, &handler)

        let id = EventHotKeyID(signature: OSType(0x4C454447), id: 1)  // 'LEDG'
        RegisterEventHotKey(UInt32(kVK_ANSI_V),
                            UInt32(cmdKey | shiftKey),
                            id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    deinit { unregister() }
}
