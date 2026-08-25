import AppKit
import SwiftUI

struct ItemRow: View {
    let item: ShelfItem
    let isLast: Bool
    let live: Bool
    let hovered: Bool
    let onHover: (Bool) -> Void
    let onRemove: () -> Void
    let onDragOut: (NSDragOperation) -> Void
    let onPeek: () -> Void
    let onEdit: () -> Void

    @State private var thumb: NSImage?
    @State private var hotDrag = false
    @State private var hotPlain = false

    private var hot: Bool { live && hovered }

    /// Ховер строки уходит наверх: на всю полку подсвечена ровно одна.
    private func report() { onHover(hotPlain || hotDrag) }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: M.innerRadius, style: .continuous)
                .fill(Ink.rowOn)
                .opacity(hot ? 1 : 0)
                .padding(.horizontal, M.inset)

            HStack(spacing: 10) {
                thumbView
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(item.isText ? .tail : .middle)
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if item.isImage {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.tip.crop.circle")
                            .font(.system(size: 15))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(hot ? 1 : 0)
                    .help("Разметить: стрелки, рамки, замазка")
                }
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(hot ? 1 : 0)
                .help("Убрать с полки")
            }
            .padding(.horizontal, M.pad)

            if !isLast {
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Ink.hairline)
                        .frame(height: 0.5)
                        .padding(.leading, M.textInset)
                }
            }
        }
        .frame(width: M.cardW, height: M.rowH)
        .contentShape(Rectangle())
        .onHover { hotPlain = $0; report() }
        .overlay(alignment: .leading) {
            DragOut(items: { [item] },
                    onSuccess: onDragOut,
                    onHover: { hotDrag = $0; report() },
                    onDoubleClick: open,
                    onClick: onPeek)
                .frame(width: M.cardW - (item.isImage ? 62 : 36), height: M.rowH)
        }
        .task(id: item.id) { await loadThumb() }
        .onChange(of: live) { _, on in
            guard !on else { return }
            hotPlain = false; hotDrag = false; report()
        }
    }

    /// Двойной клик: файл открываем, текст кладём в буфер — открывать нечего.
    private func open() {
        if let text = item.text {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } else if let url = item.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func loadThumb() async {
        if let text = item.text { thumb = Thumbs.shared.textCard(text) }
        else if let url = item.url { thumb = await Thumbs.shared.preview(url) }
    }

    private var thumbView: some View {
        Group {
            if let thumb {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
        }
        .frame(width: M.thumb, height: M.thumb)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
