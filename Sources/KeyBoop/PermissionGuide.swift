import AppKit
import SwiftUI

@MainActor
final class PermissionGuide {
    static let shared = PermissionGuide()

    private var panel: NSPanel?
    private var timer: Timer?
    private var isGranted: (() -> Bool)?

    func show(title: String, steps: [String], retryTitle: String, granted: @escaping () -> Bool, retry: @escaping () -> Void) {
        dismiss()
        isGranted = granted
        let host = NSHostingView(rootView: PermissionGuideCard(title: title, steps: steps, retryTitle: retryTitle, onRetry: retry, onClose: { [weak self] in
            self?.dismiss()
        }))
        let size = host.fittingSize
        let visible = NSScreen.main?.visibleFrame ?? .zero
        let frame = NSRect(
            x: visible.maxX - size.width - 20,
            y: visible.maxY - size.height - 20,
            width: max(size.width, 300),
            height: size.height
        )
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isGranted?() == true { self.dismiss() }
            }
        }
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        isGranted = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct PermissionGuideCard: View {
    var title: String
    var steps: [String]
    var retryTitle: String
    var onRetry: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.accentColor))
                        .foregroundStyle(.white)
                    Text(step)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(retryTitle, action: onRetry)
                .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}
