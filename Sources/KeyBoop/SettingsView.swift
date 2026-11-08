import KeyBoopCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    private let wordColumns = [
        GridItem(.flexible(minimum: 70), spacing: 4),
        GridItem(.flexible(minimum: 70), spacing: 4),
        GridItem(.flexible(minimum: 70), spacing: 4),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.section) {
            HStack(spacing: PanelMetrics.row) {
                KeyBadge(size: 28)
                Text("KeyBoop")
                    .font(PanelMetrics.title)
                Spacer(minLength: 8)
                Text(model.status)
                    .font(PanelMetrics.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .top, spacing: PanelMetrics.section) {
                VStack(alignment: .leading, spacing: PanelMetrics.section) {
                    sectionTitle("Набор")
                    PanelCard {
                        VStack(alignment: .leading, spacing: PanelMetrics.row) {
                            Toggle("Автоисправление", isOn: $model.enabled)
                            Toggle("Двойной и тройной Shift", isOn: $model.gesturesEnabled)
                            Toggle("Запускать при входе", isOn: $model.launchAtLogin)
                            if !model.loginMessage.isEmpty {
                                Text(model.loginMessage)
                                    .font(PanelMetrics.body)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .toggleStyle(.switch)
                        .font(PanelMetrics.body)
                    }

                    sectionTitle("Разрешения")
                    PanelCard {
                        VStack(alignment: .leading, spacing: PanelMetrics.row) {
                            permissionLine(
                                title: "Мониторинг ввода",
                                granted: model.listenGranted,
                                action: model.requestListen
                            )
                            permissionLine(
                                title: "Универсальный доступ",
                                granted: model.accessGranted,
                                action: model.requestAccess
                            )
                            if !model.permissionNote.isEmpty {
                                Text(model.permissionNote)
                                    .font(PanelMetrics.body)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if model.showRelaunch {
                                Button("Перезапустить") { model.relaunch() }
                                    .controlSize(.small)
                            }
                        }
                    }

                    sectionTitle("Кроме приложений")
                    PanelCard {
                        VStack(alignment: .leading, spacing: PanelMetrics.row) {
                            ForEach(model.excluded, id: \.self) { id in
                                HStack(spacing: PanelMetrics.row) {
                                    Text(id)
                                        .font(PanelMetrics.body)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Button("Удалить") { model.removeExcluded(id) }
                                        .controlSize(.small)
                                }
                                .frame(minHeight: 22)
                            }
                            Button("Добавить текущее") { model.addLastOtherApp() }
                                .controlSize(.small)
                        }
                    }

                    sectionTitle("Обновление")
                    PanelCard {
                        PanelUpdateRow(model: model)
                    }
                }
                .frame(width: 292)

                VStack(alignment: .leading, spacing: PanelMetrics.section) {
                    sectionTitle("Слова")
                    PanelCard {
                        LazyVGrid(columns: wordColumns, alignment: .leading, spacing: 2) {
                            ForEach(ShortWords.pairs(), id: \.word) { pair in
                                Toggle(isOn: shortBinding(pair.word)) {
                                    HStack(spacing: 4) {
                                        Text(pair.word)
                                        Text(pair.other)
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                }
                                .toggleStyle(.checkbox)
                                .frame(height: 18)
                            }
                        }
                    }

                    HStack(spacing: PanelMetrics.row) {
                        sectionTitle("Исключения")
                        Spacer(minLength: 8)
                        Button("Сбросить") { model.resetExceptions() }
                            .controlSize(.small)
                    }
                    PanelCard {
                        if model.exceptionWords.isEmpty {
                            Text("Пока нет. Двойной Shift после автозамены запоминает слово.")
                                .font(PanelMetrics.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ChipFlow(spacing: 6) {
                                ForEach(model.exceptionWords, id: \.self) { word in
                                    Button(action: { model.removeException(word) }) {
                                        Text(word)
                                            .font(.system(size: 11))
                                            .padding(.horizontal, 6)
                                            .frame(height: 18)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(Color.primary.opacity(0.08))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(PanelMetrics.outer)
        .frame(width: PanelMetrics.settingsWidth)
        .fixedSize(horizontal: true, vertical: true)
        .background(.regularMaterial)
    }

    private func permissionLine(title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: PanelMetrics.row) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? Color.green : Color.orange)
                .frame(width: 16)
            Text(title)
                .font(PanelMetrics.body)
                .lineLimit(1)
            Spacer(minLength: 8)
            if granted {
                Text("разрешён")
                    .font(PanelMetrics.body)
                    .foregroundStyle(.secondary)
            } else {
                Button("Разрешить", action: action)
                    .controlSize(.small)
            }
        }
        .frame(minHeight: 22)
    }

    private func shortBinding(_ word: String) -> Binding<Bool> {
        Binding(
            get: { !model.disabledShortWords.contains(word) },
            set: { model.setShortWord(word, enabled: $0) }
        )
    }
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.section) {
            MenuBanner(status: "Текст остаётся на этом Mac")
            permissionCard(
                title: "Мониторинг ввода",
                detail: "Чтобы видеть физические клавиши. KeyBoop сам появится в списке.",
                granted: model.listenGranted,
                action: model.requestListen
            )
            permissionCard(
                title: "Универсальный доступ",
                detail: "Чтобы стереть ошибочное слово и напечатать его заново.",
                granted: model.accessGranted,
                action: model.requestAccess
            )
            if !model.permissionNote.isEmpty {
                Text(model.permissionNote)
                    .font(PanelMetrics.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.showRelaunch {
                Button("Перезапустить") { model.relaunch() }
                    .controlSize(.small)
            }
            Text("Двойной Shift переводит последнее слово или выделение. Тройной — всю фразу.")
                .font(PanelMetrics.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 8)
                Button(model.listenGranted && model.accessGranted ? "Готово" : "Позже") {
                    onClose()
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(PanelMetrics.outer)
        .frame(width: PanelMetrics.menuWidth)
        .background(.regularMaterial)
    }

    private func permissionCard(title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        PanelCard {
            VStack(alignment: .leading, spacing: PanelMetrics.row) {
                HStack(spacing: PanelMetrics.row) {
                    Text(title)
                        .font(PanelMetrics.title)
                    Spacer(minLength: 8)
                    Text(granted ? "Разрешено" : "Пока не разрешено")
                        .font(PanelMetrics.body)
                        .foregroundStyle(granted ? Color.green : Color.orange)
                }
                Text(detail)
                    .font(PanelMetrics.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button("Разрешить", action: action)
                        .controlSize(.small)
                }
            }
        }
    }
}
