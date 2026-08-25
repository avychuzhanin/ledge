import AppKit
import SwiftUI

/// Чем рисуем поверх картинки.
enum MarkTool: String, CaseIterable, Identifiable {
    case arrow, box, pen, blur
    var id: String { rawValue }

    var glyph: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .box:   return "rectangle"
        case .pen:   return "scribble"
        case .blur:  return "mosaic"
        }
    }
    var title: String {
        switch self {
        case .arrow: return "Стрелка"
        case .box:   return "Рамка"
        case .pen:   return "Карандаш"
        case .blur:  return "Замазать"
        }
    }
}

enum MarkColor: String, CaseIterable, Identifiable {
    case red, yellow, green, blue, white
    var id: String { rawValue }

    var ns: NSColor {
        switch self {
        case .red:    return NSColor(srgbRed: 0.937, green: 0.267, blue: 0.180, alpha: 1)
        case .yellow: return NSColor(srgbRed: 0.976, green: 0.741, blue: 0.180, alpha: 1)
        case .green:  return NSColor(srgbRed: 0.204, green: 0.780, blue: 0.349, alpha: 1)
        case .blue:   return NSColor(srgbRed: 0.184, green: 0.502, blue: 1.000, alpha: 1)
        case .white:  return NSColor.white
        }
    }
    var swiftUI: Color { Color(nsColor: ns) }
}

/// Один штрих. Координаты — в пикселях самой картинки, чтобы при
/// сохранении ничего не поехало от масштаба окна.
struct Stroke: Identifiable, Equatable {
    let id: UUID
    var tool: MarkTool
    var color: MarkColor
    var width: CGFloat
    var points: [CGPoint]

    init(tool: MarkTool, color: MarkColor, width: CGFloat, from: CGPoint) {
        self.id = UUID()
        self.tool = tool
        self.color = color
        self.width = width
        self.points = [from, from]
    }

    var rect: CGRect {
        guard let a = points.first, let b = points.last else { return .zero }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Заметен ли штрих вообще — совсем короткие не сохраняем.
    var meaningful: Bool {
        guard let a = points.first, let b = points.last else { return false }
        if tool == .pen { return points.count > 2 }
        return hypot(b.x - a.x, b.y - a.y) > width
    }

    var path: Path {
        var p = Path()
        guard let a = points.first, let b = points.last else { return p }
        switch tool {
        case .box, .blur:
            p.addRect(rect)
        case .pen:
            p.addLines(points)
        case .arrow:
            p.move(to: a)
            p.addLine(to: b)
            let angle = atan2(b.y - a.y, b.x - a.x)
            let wing = max(width * 3.4, 11)
            let spread = 0.42
            for side in [-1.0, 1.0] {
                let t = angle + .pi + spread * side
                p.move(to: b)
                p.addLine(to: CGPoint(x: b.x + cos(t) * wing, y: b.y + sin(t) * wing))
            }
        }
        return p
    }
}

/// Толщина считается от размера картинки, иначе на большом скриншоте
/// линия выходит волосяной, а на маленьком — как бревно.
enum MarkWidth: CaseIterable, Identifiable {
    case thin, medium, thick
    var id: String { String(describing: self) }
    var factor: CGFloat {
        switch self {
        case .thin: return 0.7
        case .medium: return 1.3
        case .thick: return 2.2
        }
    }
    var dot: CGFloat {
        switch self {
        case .thin: return 5
        case .medium: return 8
        case .thick: return 11
        }
    }
    func points(for size: CGSize) -> CGFloat {
        let base = max(2, min(size.width, size.height) / 220)
        return base * factor
    }
}
