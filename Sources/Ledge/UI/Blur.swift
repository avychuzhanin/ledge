import AppKit
import SwiftUI

/// Настоящий системный материал под карточкой.
struct Blur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var radius: CGFloat = M.radius

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.material = material
        v.wantsLayer = true
        v.layer?.cornerCurve = .continuous
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.layer?.cornerRadius = radius
        v.layer?.masksToBounds = true
    }
}
