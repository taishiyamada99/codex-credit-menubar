import SwiftUI

@main
struct CodexCreditMenuBarApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra(viewModel.menuBarTitle()) {
            MenuContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRootView(viewModel: viewModel)
                .frame(minWidth: 500, minHeight: 340)
        }
    }
}
