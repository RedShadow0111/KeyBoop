import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Toggle("Автоисправление", isOn: $model.enabled)
            Toggle("Двойной и тройной Shift", isOn: $model.gesturesEnabled)
            Toggle("Запускать при входе", isOn: $model.launchAtLogin)
            if !model.loginMessage.isEmpty {
                Text(model.loginMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Разрешения") {
                LabeledContent("Мониторинг ввода") {
                    Text(model.listenGranted ? "разрешён" : "нужен доступ")
                }
                LabeledContent("Универсальный доступ") {
                    Text(model.accessGranted ? "разрешён" : "нужен доступ")
                }
                HStack {
                    Button("Открыть мониторинг ввода") { model.openListenSettings() }
                    Button("Открыть универсальный доступ") { model.openAccessSettings() }
                }
            }

            Section("Не исправлять в приложениях") {
                if let name = model.lastOtherName, let id = model.lastOtherBundleID {
                    Text("Последнее другое приложение: \(name) (\(id))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                List {
                    ForEach(model.excluded, id: \.self) { id in
                        HStack {
                            Text(id)
                            Spacer()
                            Button("Удалить") { model.removeExcluded(id) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(minHeight: 120)
                Button("Добавить последнее приложение") { model.addLastOtherApp() }
            }

            Section("Выученные исключения") {
                Text("Слов, которые не нужно трогать: \(model.exceptionCount)")
                Button("Сбросить выученные слова") { model.resetExceptions() }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 520, height: 560)
    }
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("KeyBoop правит слово, набранное не в той раскладке, и переключает её. Текст остаётся на этом Mac.")
                .fixedSize(horizontal: false, vertical: true)
            permissionRow(
                title: "Мониторинг ввода",
                granted: model.listenGranted,
                detail: "Чтобы видеть физические клавиши, а не уже перепутанные буквы.",
                actionTitle: "Разрешить",
                action: model.requestListen,
                settings: model.openListenSettings
            )
            permissionRow(
                title: "Универсальный доступ",
                granted: model.accessGranted,
                detail: "Чтобы стереть ошибочное слово и напечатать его заново.",
                actionTitle: "Разрешить",
                action: model.requestAccess,
                settings: model.openAccessSettings
            )
            Text("Двойной Shift переводит последнее слово. Тройной — всю фразу. Повторный двойной Shift сразу после автозамены отменяет её.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(model.listenGranted && model.accessGranted ? "Готово" : "Позже") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void,
        settings: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(granted ? "Разрешено" : "Пока не разрешено")
                    .foregroundStyle(granted ? .green : .orange)
                Spacer()
                Button(actionTitle, action: action)
                Button("Настройки…", action: settings)
            }
        }
    }
}
