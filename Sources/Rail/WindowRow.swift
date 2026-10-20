import SwiftUI

/// A window, a tab, or a pin whose window is closed.
struct WindowRow: View {
    let title: String
    let icon: NSImage?
    var isFocused = false
    var isMinimized = false
    var isPinned = false
    /// A pin whose window is closed: clicking opens it again.
    var isClosed = false
    let tint: Color
    let action: () -> Void

    /// Local and unanimated, so the highlight is under the pointer at once
    /// and moving between rows does not redraw the whole list.
    @State private var isHovered = false

    init(window: WindowItem, tint: Color, showsIcon: Bool, isPinned: Bool = false, action: @escaping () -> Void) {
        title = window.title
        icon = showsIcon ? window.app.icon : nil
        isFocused = window.isFocused
        isMinimized = window.isMinimized
        self.isPinned = isPinned
        self.tint = tint
        self.action = action
    }

    init(closedPin pin: PinnedItem, icon: NSImage?, tint: Color, action: @escaping () -> Void) {
        title = pin.title
        self.icon = icon
        isPinned = true
        isClosed = true
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                }
                titles
                Spacer(minLength: 0)
                if isMinimized {
                    Image(systemName: "dock.arrow.down.rectangle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(45))
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .frame(minHeight: 30)
            .background { highlight }
            .overlay(alignment: .leading) { focusMark }
            .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
        .opacity(isClosed ? 0.5 : isMinimized ? 0.6 : 1)
        .onHover { isHovered = $0 }
    }

    private var titles: some View {
        let parts = titleParts
        return VStack(alignment: .leading, spacing: 1) {
            Text(parts.primary)
                .font(.system(size: 13, weight: isFocused ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
            if let secondary = parts.secondary {
                Text(secondary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// Splits "file.swift — Rail" into a headline and a quieter context line.
    private var titleParts: (primary: String, secondary: String?) {
        for separator in [" — ", " – "] {
            if let range = title.range(of: separator) {
                return (String(title[..<range.lowerBound]), String(title[range.upperBound...]))
            }
        }
        return (title, nil)
    }

    @ViewBuilder private var highlight: some View {
        if isHovered {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(0.09))
        } else if isFocused {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.14))
        }
    }

    @ViewBuilder private var focusMark: some View {
        if isFocused {
            Capsule()
                .fill(tint)
                .frame(width: 3, height: 14)
                .offset(x: 2)
                .shadow(color: tint.opacity(0.6), radius: 3)
        }
    }
}

/// Feedback on press, not on release.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.15, dampingFraction: 1), value: configuration.isPressed)
    }
}
