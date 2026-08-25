import AppKit

/// Оставлять ли вещь на полке после того, как её утащили наружу.
/// Полка по смыслу — то, что носишь: взял и унёс. Но одну и ту же вещь часто
/// нужно разложить в несколько мест, поэтому поведение переключается.
enum Keep {
    static let key = "keepAfterDrag"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    static func register() {
        UserDefaults.standard.register(defaults: [key: true])
    }

    static func toggle() {
        UserDefaults.standard.set(!isOn, forKey: key)
    }

    /// Убирать ли вещь после удачного перетаскивания. Переезд файла — особый
    /// случай: оригинал физически уехал, и строка на полке осталась бы пустой.
    static func shouldRemove(after operation: NSDragOperation) -> Bool {
        if operation.contains(.move) { return true }
        return !isOn
    }
}
