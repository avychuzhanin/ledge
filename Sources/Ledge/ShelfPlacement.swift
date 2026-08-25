import AppKit

enum ShelfEdge: String {
    case left, right, top, bottom
    var isVertical: Bool { self == .left || self == .right }
}

/// Полка живёт только на гранях экрана, на одном и том же отступе.
/// Куда её переставили — оттуда она и вызывается касанием курсора к грани.
final class ShelfPlacement {
    private static let edgeKey = "shelfEdge"
    private static let alongKey = "shelfAlong"
    private static let setKey = "shelfPlaced"
    private static let slack: CGFloat = 40   // запас зоны вызова вдоль грани

    var screen: NSScreen {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private(set) var edge: ShelfEdge = .left
    private var along: CGFloat?

    init() {
        let d = UserDefaults.standard
        guard d.bool(forKey: Self.setKey) else { return }
        edge = ShelfEdge(rawValue: d.string(forKey: Self.edgeKey) ?? "") ?? .left
        along = CGFloat(d.double(forKey: Self.alongKey))
    }

    func reset() {
        edge = .left
        along = nil
        UserDefaults.standard.set(false, forKey: Self.setKey)
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(edge.rawValue, forKey: Self.edgeKey)
        d.set(Double(along ?? 0), forKey: Self.alongKey)
        d.set(true, forKey: Self.setKey)
    }

    var isAtHome: Bool { along == nil || (edge == .left && homeBand.contains(along!)) }

    private var homeBand: ClosedRange<CGFloat> {
        let mid = screen.visibleFrame.midY
        return (mid - M.hotBand / 2)...(mid + M.hotBand / 2)
    }

    // MARK: геометрия

    /// Прямоугольник карточки в координатах экрана.
    func cardRect(rows: Int) -> NSRect {
        let size = NSSize(width: M.cardW, height: M.cardHeight(rows: rows))
        let vf = screen.visibleFrame
        let value = along ?? (edge.isVertical ? vf.midY : vf.midX)

        switch edge {
        case .left, .right:
            let x = edge == .left ? vf.minX + M.edgeGap : vf.maxX - M.edgeGap - size.width
            let midY = min(max(value, vf.minY + size.height / 2), vf.maxY - size.height / 2)
            return NSRect(x: x, y: midY - size.height / 2, width: size.width, height: size.height)
        case .top, .bottom:
            let y = edge == .top ? vf.maxY - M.edgeGap - size.height : vf.minY + M.edgeGap
            let midX = min(max(value, vf.minX + size.width / 2), vf.maxX - size.width / 2)
            return NSRect(x: midX - size.width / 2, y: y, width: size.width, height: size.height)
        }
    }

    func windowFrame(rows: Int) -> NSRect {
        cardRect(rows: rows).insetBy(dx: -M.gutter, dy: -M.gutter)
    }

    /// Пользователь тянет полку: прилипаем к ближайшей грани.
    func snap(windowOrigin: NSPoint, rows: Int) -> NSRect {
        let size = NSSize(width: M.cardW, height: M.cardHeight(rows: rows))
        let center = CGPoint(x: windowOrigin.x + M.gutter + size.width / 2,
                             y: windowOrigin.y + M.gutter + size.height / 2)
        let vf = screen.visibleFrame
        let d: [(ShelfEdge, CGFloat)] = [
            (.left, center.x - vf.minX), (.right, vf.maxX - center.x),
            (.bottom, center.y - vf.minY), (.top, vf.maxY - center.y)
        ]
        edge = d.min { $0.1 < $1.1 }?.0 ?? .left
        along = edge.isVertical ? center.y : center.x
        save()
        return windowFrame(rows: rows)
    }

    /// Насколько увести карточку за свою грань, чтобы торчал только краешек.
    /// Считаем от физической грани экрана, иначе из-за дока «краешек» выходит
    /// в треть карточки. Оси как в SwiftUI: y растёт вниз.
    func teaseOffset(rows: Int) -> CGSize {
        let card = cardRect(rows: rows)
        let f = screen.frame
        switch edge {
        case .left:
            return CGSize(width: (f.minX + M.teasePeek) - card.maxX, height: 0)
        case .right:
            return CGSize(width: (f.maxX - M.teasePeek) - card.minX, height: 0)
        case .top:
            return CGSize(width: 0, height: card.minY - (f.maxY - M.teasePeek))
        case .bottom:
            return CGSize(width: 0, height: card.maxY - (f.minY + M.teasePeek))
        }
    }

    /// Живая зона: карточка плюс полоса до самой грани экрана. Без неё полка
    /// у нижней грани пряталась сразу — курсор на краю, а карточка над доком.
    func liveRect(rows: Int) -> NSRect {
        var r = cardRect(rows: rows).insetBy(dx: -12, dy: -12)
        let f = screen.frame
        switch edge {
        case .left:
            let d = r.minX - f.minX
            r.origin.x = f.minX; r.size.width += d
        case .right:
            r.size.width += f.maxX - r.maxX
        case .bottom:
            let d = r.minY - f.minY
            r.origin.y = f.minY; r.size.height += d
        case .top:
            r.size.height += f.maxY - r.maxY
        }
        return r
    }

    // MARK: зоны вызова

    /// Курсор коснулся грани там, где лежит полка.
    func hotContains(_ p: CGPoint, rows: Int) -> Bool {
        let card = cardRect(rows: rows)
        let f = screen.frame, vf = screen.visibleFrame
        switch edge {
        case .left:
            guard p.x <= f.minX + M.hotZone else { return false }
            return band(p.y, card.minY, card.maxY)
        case .right:
            guard p.x >= f.maxX - M.hotZone else { return false }
            return band(p.y, card.minY, card.maxY)
        case .top:
            guard p.y >= vf.maxY - M.hotZone else { return false }
            return band(p.x, card.minX, card.maxX)
        case .bottom:
            guard p.y <= vf.minY + M.hotZone else { return false }
            return band(p.x, card.minX, card.maxX)
        }
    }

    /// Курсор пошёл в привычное место — левая грань по центру.
    func homeContains(_ p: CGPoint) -> Bool {
        p.x <= screen.frame.minX + M.hotZone && homeBand.contains(p.y)
    }

    private func band(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> Bool {
        v >= lo - Self.slack && v <= hi + Self.slack
    }
}
