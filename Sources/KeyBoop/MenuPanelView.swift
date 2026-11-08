import SwiftUI

struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    var onSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.section) {
            MenuBanner(status: model.status)

            PanelCard {
                VStack(alignment: .leading, spacing: PanelMetrics.row) {
                    Toggle("Включено", isOn: $model.enabled)
                    Toggle("Пауза", isOn: $model.paused)
                }
                .toggleStyle(.switch)
                .font(PanelMetrics.body)
            }

            HStack(spacing: PanelMetrics.row) {
                PanelBarButton(title: "Настройки", systemImage: "gearshape", action: onSettings)
                PanelBarButton(title: "Выйти", systemImage: "power", action: onQuit)
            }
        }
        .padding(PanelMetrics.outer)
        .frame(width: PanelMetrics.menuWidth)
        .background(.regularMaterial)
    }
}
