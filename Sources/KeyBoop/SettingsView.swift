import KeyBoopCore
import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case words
    case exceptions
    case apps
    case permissions
    case updates
    case about
    case news
    case support

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Основное"
        case .words: "Слова"
        case .exceptions: "Исключения"
        case .apps: "Приложения"
        case .permissions: "Разрешения"
        case .updates: "Обновление"
        case .about: "О программе"
        case .news: "Что нового"
        case .support: "Поддержка"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .words: "textformat"
        case .exceptions: "hand.raised"
        case .apps: "macwindow"
        case .permissions: "checkmark.shield"
        case .updates: "arrow.triangle.2.circlepath"
        case .about: "info.circle"
        case .news: "sparkles"
        case .support: "heart"
        }
    }

    var group: String {
        switch self {
        case .general, .words, .exceptions, .apps: "Основное"
        case .permissions, .updates: "Приложение"
        case .about, .news, .support: "KeyBoop"
        }
    }

    static let groups = ["Основное", "Приложение", "KeyBoop"]
}

private enum KeyBoopLinks {
    static let repository = URL(string: "https://github.com/RedShadow0111/KeyBoop")!
    static let releases = URL(string: "https://github.com/RedShadow0111/KeyBoop/releases")!
    static let issues = URL(string: "https://github.com/RedShadow0111/KeyBoop/issues")!
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var page: SettingsPage = .general
    @State private var query = ""

    private var pages: [SettingsPage] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return SettingsPage.allCases }
        return SettingsPage.allCases.filter { $0.title.lowercased().contains(needle) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 620, height: 300)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Поиск в настройках", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.horizontal, 10)
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                    if pages.isEmpty {
                        Text("Ничего не найдено")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                    } else {
                        ForEach(SettingsPage.groups, id: \.self) { group in
                            let items = pages.filter { $0.group == group }
                            if !items.isEmpty {
                                Text(group)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                VStack(spacing: 2) {
                                    ForEach(items) { item in
                                        sidebarRow(item)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            Spacer(minLength: 0)
        }
        .frame(width: 188)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sidebarRow(_ item: SettingsPage) -> some View {
        let selected = page == item
        return Button {
            page = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .frame(width: 16)
                Text(item.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(page.title)
                .font(.system(size: 15, weight: .semibold))
            switch page {
            case .general: generalPage
            case .words: wordsPage
            case .exceptions: exceptionsPage
            case .apps: appsPage
            case .permissions: permissionsPage
            case .updates: updatesPage
            case .about: aboutPage
            case .news: newsPage
            case .support: supportPage
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingsCard {
                Text("KeyBoop исправляет слово, набранное не в той раскладке. Сейчас: \(model.status).")
                    .settingsBody()
                Toggle("Автоисправление", isOn: $model.enabled)
                Toggle("Пауза", isOn: $model.paused)
                Toggle("Двойной и тройной Shift", isOn: $model.gesturesEnabled)
            }
            settingsCard {
                Text("KeyBoop может открываться сам при входе в систему.")
                    .settingsBody()
                Toggle("Запускать при входе", isOn: $model.launchAtLogin)
                if !model.loginMessage.isEmpty {
                    Text(model.loginMessage).settingsBody()
                }
            }
        }
        .toggleStyle(.switch)
        .font(.system(size: 13))
    }

    private var wordsPage: some View {
        settingsCard {
            Text("Короткие пары вроде «ты» и «we». Снимите галочку, если пару исправлять не нужно. Своё слово остаётся своим.")
                .settingsBody()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), alignment: .leading, spacing: 2) {
                ForEach(ShortWords.pairs(), id: \.word) { pair in
                    Toggle(isOn: shortBinding(pair.word)) {
                        HStack(spacing: 4) {
                            Text(pair.word)
                            Text(pair.other)
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12))
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var exceptionsPage: some View {
        settingsCard {
            Text("Слова, которые KeyBoop больше не трогает. Нажмите на слово, чтобы забыть его.")
                .settingsBody()
            if model.exceptionWords.isEmpty {
                Text("Пока нет").settingsBody()
            } else {
                ChipFlow(spacing: 6) {
                    ForEach(model.exceptionWords, id: \.self) { word in
                        Button(word) { model.removeException(word) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.08)))
                    }
                }
            }
            Button("Сбросить исключения") { model.resetExceptions() }
                .controlSize(.regular)
        }
    }

    private var appsPage: some View {
        settingsCard {
            Text("В этих приложениях KeyBoop молчит. Добавляется то приложение, которым вы пользовались перед KeyBoop.")
                .settingsBody()
            if let name = model.lastOtherName, let id = model.lastOtherBundleID {
                Text("Последнее: \(name) (\(id))").settingsBody()
            }
            ForEach(model.excluded, id: \.self) { id in
                HStack(spacing: 8) {
                    Text(id)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("Удалить") { model.removeExcluded(id) }
                }
            }
            Button("Добавить последнее приложение") { model.addLastOtherApp() }
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingsCard {
                Text("Нужен, чтобы видеть физические клавиши. KeyBoop сам появляется в списке «Мониторинг ввода».")
                    .settingsBody()
                permissionButton(title: "Мониторинг ввода", granted: model.listenGranted, action: model.requestListen)
            }
            settingsCard {
                Text("Нужен, чтобы заменить выделенный текст и понять, какое приложение сейчас активно.")
                    .settingsBody()
                permissionButton(title: "Универсальный доступ", granted: model.accessGranted, action: model.requestAccess)
            }
            if !model.permissionNote.isEmpty || model.showRelaunch {
                settingsCard {
                    if !model.permissionNote.isEmpty {
                        Text(model.permissionNote).settingsBody()
                    }
                    if model.showRelaunch {
                        Button("Перезапустить") { model.relaunch() }
                    }
                }
            }
        }
    }

    private var updatesPage: some View {
        settingsCard {
            Text("Новая версия скачивается с релизов KeyBoop на GitHub и подменяет это приложение.")
                .settingsBody()
            PanelUpdateRow(model: model)
            Button("Открыть релизы на GitHub") { NSWorkspace.shared.open(KeyBoopLinks.releases) }
        }
    }

    private var aboutPage: some View {
        settingsCard {
            HStack(spacing: 12) {
                KeyBadge(size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("KeyBoop")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Версия \(appVersion)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Text("Бесплатное исправление русской и английской раскладки. Текст остаётся на этом Mac и никуда не отправляется.")
                .settingsBody()
            Button("Открыть GitHub") { NSWorkspace.shared.open(KeyBoopLinks.repository) }
        }
    }

    private var newsPage: some View {
        settingsCard {
            Text("Версия 1.2.3")
                .font(.system(size: 13, weight: .semibold))
            Text("Проверка обновления повторяет запрос, если GitHub отвечает 504, и берёт файл прямо со страницы релиза.")
                .settingsBody()
            Button("Все версии на GitHub") { NSWorkspace.shared.open(KeyBoopLinks.releases) }
        }
    }

    private var supportPage: some View {
        settingsCard {
            Text("Ошибка, идея или вопрос пишутся в задачах репозитория. Так же оттуда можно открыть исходный код.")
                .settingsBody()
            HStack(spacing: 8) {
                Button("Сообщить о проблеме") { NSWorkspace.shared.open(KeyBoopLinks.issues) }
                Button("Репозиторий на GitHub") { NSWorkspace.shared.open(KeyBoopLinks.repository) }
            }
        }
    }

    private func permissionButton(title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? Color.green : Color.orange)
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 8)
            if granted {
                Text("разрешён")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Button("Разрешить", action: action)
            }
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
    }

    private func shortBinding(_ word: String) -> Binding<Bool> {
        Binding(
            get: { !model.disabledShortWords.contains(word) },
            set: { model.setShortWord(word, enabled: $0) }
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.3"
    }
}

private extension Text {
    func settingsBody() -> some View {
        self.font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
