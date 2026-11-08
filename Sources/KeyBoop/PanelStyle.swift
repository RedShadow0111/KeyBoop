import KeyBoopBrand
import SwiftUI

enum PanelSurface {
    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.55) : Color.white.opacity(0.08)
    }

    static func line(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.12)
    }
}

enum PanelMetrics {
    static let outer: CGFloat = 12
    static let section: CGFloat = 10
    static let row: CGFloat = 8
    static let card: CGFloat = 10
    static let menuWidth: CGFloat = 300
    static let settingsWidth: CGFloat = 640
    static let title = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 12)
}

struct PanelCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(PanelMetrics.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PanelSurface.card(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PanelSurface.line(colorScheme), lineWidth: 0.7)
            )
    }
}

func sectionTitle(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .kerning(0.5)
        .foregroundStyle(.secondary)
}

struct KeyBadge: View {
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: BrandMark.image(side: size, template: false))
            .frame(width: size, height: size)
    }
}

struct MenuBanner: View {
    var status: String

    var body: some View {
        VStack(spacing: 6) {
            KeyBadge(size: 48)
            Text(status)
                .font(PanelMetrics.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PanelBarButton: View {
    @Environment(\.colorScheme) private var colorScheme
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
}

struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 280
        let rows = rows(width: width, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                item.view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Item {
        var view: LayoutSubview
        var size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var used: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            let next = used == 0 ? size.width : used + spacing + size.width
            if used > 0, next > width {
                rows.append(current)
                current = Row()
                used = 0
            }
            current.items.append(Item(view: view, size: size))
            current.height = max(current.height, size.height)
            used = used == 0 ? size.width : used + spacing + size.width
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

struct PanelUpdateRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.row) {
            HStack(spacing: PanelMetrics.row) {
                Text("GitHub")
                    .font(PanelMetrics.body)
                Spacer(minLength: 8)
                Button(model.updateVersion == nil ? "Проверить" : "Обновить до \(model.updateVersion ?? "")") {
                    if model.updateVersion == nil {
                        model.checkForUpdate(force: true)
                    } else {
                        model.installUpdate()
                    }
                }
                .controlSize(.small)
            }
            if !model.updateMessage.isEmpty {
                Text(model.updateMessage)
                    .font(PanelMetrics.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
