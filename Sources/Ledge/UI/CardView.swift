import AppKit
import SwiftUI

/// Карточка вещи в ленте. Слева — корешок цвета стопки: вещи стоят на полке
/// корешками наружу, по корешку и видно, откуда она.
struct CardView: View {
    let item: ShelfItem
    let height: CGFloat
    let tint: Color?
    let number: Int?          // номер быстрой вставки, пока зажат ⌘
    let picked: Bool
    let onDown: (NSEvent.ModifierFlags) -> Void
    let onOpen: () -> Void
    let onDragOut: (NSDragOperation) -> Void

    @State private var shot: NSImage?
    @State private var hot = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: W.cardRadius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            head
            preview
            foot
        }
        .padding(.leading, tint == nil ? 0 : W.spine)
        .frame(width: W.cardW, height: height, alignment: .top)
        .background {
            shape.fill(Color.primary.opacity(picked ? 0.14 : hot ? 0.10 : 0.06))
        }
        .overlay(alignment: .leading) { spine }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(picked ? Color.accentColor : Color.primary.opacity(0.10),
                               lineWidth: picked ? 2 : 0.5)
        }
        .overlay(alignment: .bottomTrailing) { badge }
        .animation(.easeOut(duration: 0.14), value: picked)
        .animation(.easeOut(duration: 0.14), value: hot)
        .overlay {
            DragOut(items: { [item] },
                    onSuccess: onDragOut,
                    onHover: { hot = $0 },
                    onDoubleClick: onOpen,
                    onDown: onDown)
        }
        .task(id: item.id) { await load() }
    }

    /// Корешок: тонкая полоса цвета стопки во всю высоту.
    @ViewBuilder private var spine: some View {
        if let tint {
            Rectangle().fill(tint).frame(width: W.spine)
        }
    }

    /// У файла в шапке имя, у текста — откуда он приехал: сам текст и так
    /// виден в карточке, дублировать его строкой выше незачем.
    private var title: String {
        guard item.isText else { return item.name }
        if let id = item.appID, let app = Apps.name(id) { return app }
        return item.source == .shot ? "Снимок" : "Текст"
    }

    private var head: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(item.isText ? .tail : .middle)
            Spacer(minLength: 0)
            source
        }
        .padding(.horizontal, 10)
        .frame(height: W.headH)
    }

    /// Откуда приехало: значок программы или камера у снимков экрана.
    @ViewBuilder private var source: some View {
        if let id = item.appID, let icon = Apps.icon(id) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 13, height: 13)
                .help(Apps.name(id) ?? id)
        } else if item.source == .shot {
            Image(systemName: "camera")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .help("Снимок экрана")
        }
    }

    @ViewBuilder private var preview: some View {
        Group {
            switch item.kind {
            case .text:
                Text(item.text ?? "")
                    .font(.system(size: 11.5))
                    .lineSpacing(1.5)
                    .foregroundStyle(.primary.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                    .mask(fade)
            case .link:
                link
            default:
                picture
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// Длинный текст не обрывается по-живому, а тает к нижнему краю.
    private var fade: LinearGradient {
        LinearGradient(stops: [.init(color: .black, location: 0),
                               .init(color: .black, location: 0.88),
                               .init(color: .clear, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var link: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text(item.linkAddress ?? item.name)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    @ViewBuilder private var picture: some View {
        if let shot {
            Image(nsImage: shot)
                .resizable()
                .aspectRatio(contentMode: item.kind == .image ? .fill : .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(item.kind == .image ? 0 : 12)
        } else {
            Color.primary.opacity(0.04)
        }
    }

    private var foot: some View {
        HStack(spacing: 6) {
            Text(item.measure)
                .monospacedDigit()
            Spacer(minLength: 0)
            Text(item.whenLabel)
                .lineLimit(1)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: W.footH)
    }

    /// Номер для быстрой вставки: проступает, пока держишь ⌘.
    @ViewBuilder private var badge: some View {
        if let number {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(width: 19, height: 19)
                .background(.regularMaterial, in: Circle())
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
                .padding(6)
                .transition(.opacity)
        }
    }

    private func load() async {
        guard item.kind != .text, item.kind != .link, let url = item.url else { return }
        if let hit = Thumbs.shared.cachedBig(url) { shot = hit; return }
        shot = await Thumbs.shared.big(url) ?? Thumbs.shared.icon(url)
    }
}
