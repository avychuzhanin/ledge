import AppKit
import SwiftUI

/// Материал карточки. На macOS 26 — Liquid Glass, ниже — системный blur.
struct GlassCard: ViewModifier {
    var radius: CGFloat
    var targeted: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    /// Обводка-волосок и мягкая тень как у окон macOS:
    /// широкая рассеянная плюс короткая контактная.
    private var trim: some View {
        shape
            .strokeBorder(targeted ? Color.accentColor : Color.primary.opacity(0.13),
                          lineWidth: targeted ? 2 : 0.5)
            .allowsHitTesting(false)
    }

    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26.0, *) {
                content
                    .glassEffect(targeted
                                 ? .regular.tint(Color.accentColor.opacity(0.40))
                                 : .regular,
                                 in: .rect(cornerRadius: radius))
                    .overlay { trim }
            } else {
                content
                    .background(Blur(radius: radius))
                    .clipShape(shape)
                    .overlay { trim }
            }
        }
        .shadow(color: .black.opacity(0.17), radius: 24, y: 12)
        .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
    }
}

extension View {
    func glassCard(radius: CGFloat, targeted: Bool) -> some View {
        modifier(GlassCard(radius: radius, targeted: targeted))
    }
}
