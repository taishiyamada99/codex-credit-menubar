import AppKit
import SwiftUI

@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private var window: NSWindow?

    private init() {}

    func show(viewModel: AppViewModel) {
        if window == nil {
            let size = targetSize(for: viewModel.activeSettingsTab)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = viewModel.localized(.settings)
            window.setFrameAutosaveName("CodexCreditMenuBar.SettingsWindow")
            window.isReleasedWhenClosed = false
            self.window = window
        }

        window?.title = viewModel.localized(.settings)
        window?.contentView = NSHostingView(rootView: SettingsRootView(viewModel: viewModel))
        updateSize(for: viewModel.activeSettingsTab)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateSize(for tab: SettingsTab) {
        guard let window else {
            return
        }
        let size = targetSize(for: tab)
        window.contentMinSize = NSSize(width: size.minWidth, height: size.minHeight)
        window.setContentSize(NSSize(width: size.width, height: size.height))
    }

    private func targetSize(for tab: SettingsTab) -> (width: CGFloat, height: CGFloat, minWidth: CGFloat, minHeight: CGFloat) {
        switch tab {
        case .general, .language:
            return (560, 380, 500, 340)
        case .display:
            return (620, 430, 540, 360)
        case .history:
            return (680, 460, 580, 400)
        case .notifications:
            return (580, 390, 500, 340)
        case .diagnostics:
            return (680, 460, 580, 400)
        }
    }
}
