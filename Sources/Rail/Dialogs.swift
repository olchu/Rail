import AppKit

/// Small modal forms. Rail is an accessory app, so each dialog activates it for typing
/// and hands focus back to the previous app afterwards.
@MainActor
enum Dialogs {
    struct AddToProject {
        let projectName: String
        let titleContains: String
    }

    static func addToProject(_ window: WindowItem, projectNames: [String]) -> AddToProject? {
        let combo = NSComboBox()
        combo.addItems(withObjectValues: projectNames)
        combo.stringValue = projectNames.first ?? ""
        combo.placeholderString = "Название проекта"
        combo.completes = true

        let field = NSTextField(string: window.title)
        field.placeholderString = "Все окна \(window.appName)"

        let hint = NSTextField(wrappingLabelWithString:
            "Rail узнаёт окна по слову в заголовке. Оставь только ту часть, которая не меняется, например имя папки. Пустое поле: все окна \(window.appName).")
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor

        let alert = NSAlert()
        alert.messageText = "Добавить в проект"
        alert.informativeText = window.appName
        alert.addButton(withTitle: "Добавить")
        alert.addButton(withTitle: "Отмена")
        alert.accessoryView = form([
            label("Проект"), combo,
            label("Заголовок окна содержит"), field, hint,
        ])
        alert.window.initialFirstResponder = combo

        guard run(alert) == .alertFirstButtonReturn else { return nil }
        let name = combo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return AddToProject(
            projectName: name,
            titleContains: field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Name and link of a pin. Apps without tabs or documents do not report what a window shows,
    /// so the link is the only way back to, say, one chat.
    static func editPin(_ pin: PinnedItem, isNew: Bool) -> PinnedItem? {
        let name = NSTextField(string: pin.title)
        name.placeholderString = pin.appName
        let link = NSTextField(string: pin.url?.absoluteString ?? "")
        link.placeholderString = "https://…"

        let isTelegram = pin.appID.localizedCaseInsensitiveContains("telegram")
        let hint = NSTextField(wrappingLabelWithString: isTelegram
            ? "Чат: t.me/username, @username или номер телефона +7…. Пустое поле: просто открыть Telegram."
            : "\(pin.appName) не сообщает, что открыто в окне. Ссылка или путь к файлу откроются в нём по клику. Пустое поле: просто открыть приложение.")
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor

        let alert = NSAlert()
        alert.messageText = isNew ? "Закрепить" : "Изменить закреплённое"
        alert.informativeText = pin.appName
        alert.addButton(withTitle: isNew ? "Закрепить" : "Сохранить")
        alert.addButton(withTitle: "Отмена")
        alert.accessoryView = form([label("Название"), name, label("Ссылка"), link, hint])
        alert.window.initialFirstResponder = isNew ? link : name

        guard run(alert) == .alertFirstButtonReturn else { return nil }
        var edited = pin
        let title = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.title = title.isEmpty ? pin.title : title
        edited.url = PinnedItem.link(link.stringValue, appID: pin.appID)
        return edited
    }

    static func rename(_ project: Project) -> String? {
        let field = NSTextField(string: project.name)
        let alert = NSAlert()
        alert.messageText = "Переименовать проект"
        alert.addButton(withTitle: "Сохранить")
        alert.addButton(withTitle: "Отмена")
        alert.accessoryView = form([field])
        alert.window.initialFirstResponder = field

        guard run(alert) == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        let response = alert.runModal()
        previous?.activate()
        return response
    }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        return label
    }

    private static func form(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        for view in views {
            view.widthAnchor.constraint(equalToConstant: 300).isActive = true
        }
        stack.setFrameSize(stack.fittingSize)
        return stack
    }
}
