import SwiftUI

/// Панель инструментов — стеклянная плашка того же языка, что и полка.
struct MarkupBar: View {
    @ObservedObject var model: MarkupModel
    var onCopy: () -> Void
    var onSave: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MarkTool.allCases) { tool in
                button(tool.glyph, active: model.tool == tool, help: tool.title) {
                    model.tool = tool
                }
            }
            divider
            ForEach(MarkColor.allCases) { c in
                Button { model.color = c } label: {
                    Circle()
                        .fill(c.swiftUI)
                        .frame(width: 16, height: 16)
                        .overlay {
                            Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(Color.primary, lineWidth: 2)
                                .padding(-3.5)
                                .opacity(model.color == c ? 1 : 0)
                        }
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            divider
            ForEach(MarkWidth.allCases) { w in
                Button { model.weight = w } label: {
                    Circle()
                        .fill(model.weight == w ? Color.white : Color.secondary.opacity(0.75))
                        .frame(width: w.dot, height: w.dot)
                        .frame(width: 26, height: 30)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor)
                                .opacity(model.weight == w ? 1 : 0)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Толщина линии")
            }
            divider
            button("arrow.uturn.backward", active: false, help: "Отменить ⌘Z",
                   enabled: model.canUndo) { model.undo() }
            button("doc.on.doc", active: false, help: "Скопировать ⌘C", action: onCopy)
            button("checkmark", active: false, help: "Сохранить ⌘S", action: onSave)

            if !model.note.isEmpty {
                Text(model.note)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .glassCard(radius: 22, targeted: false)
        .animation(.easeOut(duration: 0.16), value: model.note)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 3)
    }

    private func button(_ glyph: String, active: Bool, help: String,
                        enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? Color.white : Color.primary)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor)
                        .opacity(active ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .help(help)
    }
}
