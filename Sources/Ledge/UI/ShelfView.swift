import AppKit
import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var state: ShelfState
    var onDragAllOut: (NSDragOperation) -> Void
    var onClear: () -> Void
    var onPeek: (ShelfItem) -> Void
    var onEdit: (ShelfItem) -> Void
    var onExpand: () -> Void
    var move: MoveActions

    @State private var hoverRow: ShelfItem.ID?
    @State private var headerHot = false
    @State private var grabHot = false
    @State private var shakeOff: CGSize = .zero

    private var rows: Int { store.items.count }
    private var cardH: CGFloat { M.cardHeight(rows: rows) }
    /// Выезжает из-за той грани, к которой прижата.
    private var enter: CGSize {
        if state.teasing { return state.teaseOffset }
        guard !state.shown else { return .zero }
        return along(M.cardW + M.gutter, cardH + M.gutter)
    }

    /// Смещение за свою грань: по горизонтали для боков, по вертикали для верха и низа.
    private func along(_ dx: CGFloat, _ dy: CGFloat) -> CGSize {
        switch state.edge {
        case .left:   return CGSize(width: -dx, height: 0)
        case .right:  return CGSize(width: dx, height: 0)
        case .top:    return CGSize(width: 0, height: -dy)
        case .bottom: return CGSize(width: 0, height: dy)
        }
    }

    var body: some View {
        card
            .frame(width: M.cardW, height: cardH)
            .padding(M.gutter)
            .offset(x: enter.width, y: enter.height)
            .opacity(state.shown ? 1 : 0)
            .allowsHitTesting(!state.teasing)
            .animation(state.shown ? .spring(response: 0.32, dampingFraction: 0.85)
                                   : .easeIn(duration: 0.15), value: state.shown)
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: state.teasing)
            .offset(x: shakeOff.width, y: shakeOff.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: state.shown) { _, shown in
                if !shown { headerHot = false; grabHot = false; hoverRow = nil }
            }
            .onChange(of: state.shakeToken) { _, _ in shake() }
    }

    /// Аккуратно качнуть карточку — «полка вот здесь, ты её сюда унёс».
    /// Качнуть карточку поперёк её грани — первый рывок наружу, из-за края.
    private func shake() {
        let amps: [CGFloat] = [13, -9, 6, -3, 0]
        var delay: Double = 0
        for a in amps {
            let step = delay, value = a
            DispatchQueue.main.asyncAfter(deadline: .now() + step) {
                withAnimation(.easeInOut(duration: 0.085)) {
                    shakeOff = along(-value, -value)
                }
            }
            delay += 0.085
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            grabStrip
            header
            content
            Spacer(minLength: 0)
        }
        .frame(width: M.cardW, height: cardH, alignment: .top)
        .glassCard(radius: M.radius, targeted: state.targeted)
        .animation(.easeOut(duration: 0.15), value: state.targeted)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: rows)
    }

    /// Хваталка как у шторки: за неё полка переезжает куда угодно.
    private var grabStrip: some View {
        Capsule()
            .fill(grabHot || state.moving ? Ink.grabOn : Ink.grabber)
            .frame(width: grabHot || state.moving ? 46 : 38, height: 5)
            .animation(.easeOut(duration: 0.16), value: grabHot)
            .animation(.easeOut(duration: 0.16), value: state.moving)
            .frame(width: M.cardW, height: M.grabH)
            .contentShape(Rectangle())
            .overlay {
                MoveHandle(onBegin: move.begin, onMove: move.moved,
                           onEnd: move.end, onHover: { grabHot = $0 })
            }
            .help("Потяни — переставишь полку куда угодно")
    }

    /// Заголовок заодно ручка: потянул — уехали все файлы разом.
    private var header: some View {
        HStack(spacing: 7) {
            Text("Полка")
                .font(.system(size: 13, weight: .semibold))
            if !store.items.isEmpty {
                Text("\(store.items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.09), in: Capsule())
            }
            Spacer(minLength: 0)
            if Wide.isOn {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Разложить лентой — вся история, поиск и стопки (⌘⇧V)")
            }
            if !store.items.isEmpty {
                Button("Очистить", action: onClear)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                    .help("Убрать всё с полки")
            }
        }
        .padding(.horizontal, M.pad)
        .frame(width: M.cardW, height: M.headerH)
        .background {
            RoundedRectangle(cornerRadius: M.innerRadius, style: .continuous)
                .fill(Ink.rowOn)
                .padding(.horizontal, M.inset)
                .opacity(headerHot && !store.items.isEmpty ? 1 : 0)
        }
        .overlay(alignment: .leading) {
            if !store.items.isEmpty {
                DragOut(items: { store.items },
                        onSuccess: onDragAllOut,
                        onHover: { headerHot = $0 })
                    .frame(width: M.cardW - (Wide.isOn ? 118 : 92), height: M.headerH)
                    .help("Потяни заголовок — заберёшь всё разом")
            }
        }
    }

    @ViewBuilder private var content: some View {
        if store.items.isEmpty {
            empty
        } else if rows > M.maxRows {
            ScrollView(.vertical, showsIndicators: false) { list }
                .frame(height: CGFloat(M.maxRows) * M.rowH)
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.items.enumerated()), id: \.element.id) { idx, item in
                ItemRow(item: item,
                        isLast: idx == store.items.count - 1,
                        live: state.shown && !state.moving,
                        hovered: hoverRow == item.id,
                        onHover: { on in
                            if on { hoverRow = item.id }
                            else if hoverRow == item.id { hoverRow = nil }
                        },
                        onRemove: { store.remove(item.id) },
                        onDragOut: { op in
                            if Keep.shouldRemove(after: op) { store.remove(item.id) }
                        },
                        onPeek: { onPeek(item) },
                        onEdit: { onEdit(item) })
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: state.targeted ? "tray.and.arrow.down.fill" : "tray")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(state.targeted ? Color.accentColor : .secondary)
            Text(state.targeted ? "Отпускай" : "Перетащи файлы сюда")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(width: M.cardW, height: M.emptyH)
    }
}

struct MoveActions {
    var begin: () -> Void
    var moved: (NSPoint) -> Void
    var end: () -> Void
}
