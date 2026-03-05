import AppKit
import SwiftUI

@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private let defaultSize = NSSize(width: 900, height: 700)
    private let minimumSize = NSSize(width: 820, height: 620)

    private var window: NSWindow?

    private init() {}

    func show(viewModel: AppViewModel) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: defaultSize.width, height: defaultSize.height),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = viewModel.localized(.settings)
            window.setFrameAutosaveName("CodexCreditMenuBar.SettingsWindow")
            window.isReleasedWhenClosed = false
            window.contentMinSize = minimumSize
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
        _ = tab
        window.contentMinSize = minimumSize
    }
}
