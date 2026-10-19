import AppKit
import SwiftUI

/// AppKit glass in the look of the system's ⌘Tab switcher: light, lightly blurred, barely tinted.
/// SwiftUI's `glassEffect` offers only `.regular` and `.clear`, and on a surface this large
/// both come out dark and heavily frosted.
struct GlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    /// Private `NSGlassEffectView` variant. 23 matched the ⌘Tab switcher best side by side;
    /// without the private setter the view keeps the public regular glass.
    var variant = 23

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        if view.responds(to: NSSelectorFromString("set_variant:")) {
            view.setValue(variant, forKey: "_variant")
        }
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
    }
}
