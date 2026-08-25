import Foundation

/// Расширенный режим. Полка остаётся полкой — узкой карточкой у грани, куда
/// таскают файлы. Расширенный режим добавляет ей вторую ипостась: широкую
/// ленту карточек вдоль той же грани, с историей буфера, поиском и стопками.
/// Вызывается ⌘⇧V, кнопкой в шапке полки и пунктом меню.
enum Wide {
    static let key = "wideMode"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    static func register() { UserDefaults.standard.register(defaults: [key: false]) }

    static func toggle() { UserDefaults.standard.set(!isOn, forKey: key) }

    /// Сколько записей буфера держим. В расширенном режиме история — смысл
    /// режима, поэтому она заметно длиннее. Вещи, разложенные по стопкам,
    /// этот лимит не трогает: они лежат, пока сам не уберёшь.
    static var historyLimit: Int { isOn ? 200 : 25 }
}
