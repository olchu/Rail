import SwiftUI

enum ProjectPalette {
    static let colors: [(name: String, color: Color)] = [
        ("Синий", .blue),
        ("Фиолетовый", .purple),
        ("Розовый", .pink),
        ("Оранжевый", .orange),
        ("Зелёный", .green),
        ("Бирюзовый", .teal),
        ("Индиго", .indigo),
        ("Жёлтый", .yellow),
    ]

    static func color(_ index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count].color
    }
}

enum Plural {
    /// Russian plural: 1 окно, 2 окна, 5 окон.
    static func ru(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod10 = n % 10, mod100 = n % 100
        let word = if mod10 == 1 && mod100 != 11 { one }
            else if (2...4).contains(mod10) && !(12...14).contains(mod100) { few }
            else { many }
        return "\(n) \(word)"
    }
}

extension View {
    /// Blocks slide in from the edge one after another when the sidebar opens.
    /// With Reduce Motion they only fade.
    func entrance(_ index: Int, isOpen: Bool, reduceMotion: Bool) -> some View {
        let delay = isOpen ? Double(min(index, 10)) * 0.028 : 0
        return self
            .opacity(isOpen ? 1 : 0)
            .offset(x: isOpen || reduceMotion ? 0 : -18)
            .animation(.spring(response: 0.42, dampingFraction: 0.9).delay(delay), value: isOpen)
    }
}
