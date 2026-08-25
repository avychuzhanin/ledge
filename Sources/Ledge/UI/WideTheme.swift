import SwiftUI

/// Метрики расширенного режима. Полка та же, только разложена вдоль грани:
/// у боковых граней — колонка в два ряда, у верхней и нижней — лента.
enum W {
    static let cardW: CGFloat    = 194
    static let cardH: CGFloat    = 186     // карточка в колонке
    static let bandCardH: CGFloat = 288    // карточка в ленте
    static let cardRadius: CGFloat = 14
    static let spine: CGFloat    = 3       // корешок стопки

    static let pad: CGFloat      = 14
    static let gap: CGFloat      = 12
    static let barH: CGFloat     = 48      // строка над лентой
    static let barTallH: CGFloat = 86      // у боковых граней она в два этажа
    static let footH: CGFloat    = 24      // подвал карточки
    static let headH: CGFloat    = 28      // шапка карточки

    /// Ширина панели у левой и правой грани: два ряда карточек.
    static var colW: CGFloat { pad * 2 + cardW * 2 + gap }
    /// Высота панели у верхней и нижней грани.
    static var stripH: CGFloat { barH + pad * 2 + bandCardH }
    /// Ниже этого колонка не сжимается, даже когда на полке пусто.
    static var colMinH: CGFloat { barTallH + pad * 2 + cardH }

    static let peekPad: CGFloat  = 28      // поле вокруг раскрытого превью
}
