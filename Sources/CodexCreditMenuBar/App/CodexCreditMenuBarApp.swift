import SwiftUI

@main
struct CodexCreditMenuBarApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(viewModel: viewModel)
        } label: {
            MenuBarLabelView(viewModel: viewModel)
        }

        Settings {
            SettingsRootView(viewModel: viewModel)
                .frame(minWidth: 500, minHeight: 340)
        }
    }
}
