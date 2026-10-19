import AppKit
import ApplicationServices

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt (first time only) and opens the Accessibility pane.
    static func requestAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension AXUIElement {
    func value<T>(_ attribute: String) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &ref) == .success else { return nil }
        return ref as? T
    }

    func set(_ attribute: String, _ value: CFTypeRef) {
        AXUIElementSetAttributeValue(self, attribute as CFString, value)
    }
}
