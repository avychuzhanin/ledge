import SwiftUI

/// Оформление в стиле macOS 26: Liquid Glass, семантические цвета,
/// системный акцент. Светлая и тёмная тема — автоматически.
enum Ink {
    static let hairline = Color(nsColor: .separatorColor)
    static let rowOn    = Color.primary.opacity(0.07)
    static let grabber  = Color.secondary.opacity(0.4)
    static let grabOn   = Color.secondary.opacity(0.75)
}

enum M {
    static let cardW: CGFloat    = 262
    static let radius: CGFloat   = 24
    /// Вложенное скругление = внешнее − расстояние между ними.
    static let inset: CGFloat    = 12
    static var innerRadius: CGFloat { radius - inset }

    static let edgeGap: CGFloat  = 10     // отступ карточки от торца экрана
    static let hotZone: CGFloat  = 4      // полоска у края, будящая полку
    static let hotBand: CGFloat  = 460    // высота зоны наведения

    static let grabH: CGFloat    = 20     // полоска-хваталка сверху
    static let headerH: CGFloat  = 34
    static let rowH: CGFloat     = 56
    static let padBot: CGFloat   = 12
    static let emptyH: CGFloat   = 112
    static let maxRows           = 7
    static let thumb: CGFloat    = 40
    static let pad: CGFloat      = 18    // поля контента
    static let textInset: CGFloat = 70    // куда сдвинут разделитель
    static let gutter: CGFloat   = 60     // поле под тень со всех сторон
    static let peekW: CGFloat    = 380    // быстрое превью по клику
    static let peekH: CGFloat    = 300
    static let peekGap: CGFloat  = 12
    static let teasePeek: CGFloat = 34   // сколько торчит краешка при «я тут»

    static func cardHeight(rows: Int) -> CGFloat {
        let list = rows == 0 ? emptyH : CGFloat(min(rows, maxRows)) * rowH
        return grabH + headerH + list + padBot
    }
}
