import SwiftUI

enum ShelfMode: Equatable { case hidden, open }

final class ShelfState: ObservableObject {
    @Published var mode: ShelfMode = .hidden
    @Published var shown = false          // выехала ли
    @Published var armed = false          // где-то идёт драг
    @Published var targeted = false       // драг над самой полкой
    @Published var edge: ShelfEdge = .left  // к какой грани прижата
    @Published var moving = false         // пользователь тащит саму полку
    @Published var teasing = false        // высунула краешек: «я тут»
    @Published var teaseOffset: CGSize = .zero
    @Published var shakeToken = 0         // дёрнуть карточку, чтобы её заметили
}
