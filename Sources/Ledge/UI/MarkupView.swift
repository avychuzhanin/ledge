import AppKit
import SwiftUI

/// Картинка во весь холст и панель инструментов поверх неё.
struct MarkupView: View {
    @ObservedObject var model: MarkupModel
    var onCopy: () -> Void
    var onSave: () -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(nsColor: .underPageBackgroundColor)
            canvas
            MarkupBar(model: model, onCopy: onCopy, onSave: onSave, onClose: onClose)
                .padding(.bottom, 18)
        }
        .ignoresSafeArea()
    }

    private var canvas: some View {
        GeometryReader { geo in
            let box = CGSize(width: geo.size.width - 48, height: geo.size.height - 108)
            let shown = fit(into: box)
            let scale = shown.width / model.size.width
            ZStack(alignment: .topLeading) {
                Image(decorative: model.base, scale: 1)
                    .resizable()
                    .frame(width: shown.width, height: shown.height)
                Canvas { ctx, size in paint(&ctx, size: size, scale: scale) }
                    .frame(width: shown.width, height: shown.height)
            }
            .frame(width: shown.width, height: shown.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
            .contentShape(Rectangle())
            .gesture(drag(scale: scale))
            .position(x: geo.size.width / 2, y: (geo.size.height - 54) / 2)
        }
    }

    private func fit(into box: CGSize) -> CGSize {
        guard box.width > 0, box.height > 0 else { return model.size }
        let k = min(box.width / model.size.width, box.height / model.size.height, 2)
        return CGSize(width: model.size.width * k, height: model.size.height * k)
    }

    private func paint(_ ctx: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        let all = model.marks + (model.draft.map { [$0] } ?? [])
        let full = CGRect(origin: .zero, size: size)
        for mark in all {
            let path = mark.path.applying(CGAffineTransform(scaleX: scale, y: scale))
            if mark.tool == .blur {
                guard let pixels = model.pixels else { continue }
                ctx.drawLayer { layer in
                    layer.clip(to: path)
                    layer.draw(Image(decorative: pixels, scale: 1), in: full)
                }
            } else {
                ctx.stroke(path, with: .color(mark.color.swiftUI),
                           style: StrokeStyle(lineWidth: max(1, mark.width * scale),
                                              lineCap: mark.tool == .box ? .square : .round,
                                              lineJoin: .round))
            }
        }
    }

    private func drag(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let p = CGPoint(x: v.location.x / scale, y: v.location.y / scale)
                if model.draft == nil {
                    model.begin(at: CGPoint(x: v.startLocation.x / scale,
                                            y: v.startLocation.y / scale))
                }
                model.extend(to: p)
            }
            .onEnded { _ in model.finish() }
    }
}
