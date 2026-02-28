import SwiftUI

@main
struct CodexCreditMenuBarApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(viewModel: viewModel)
        } label: {
            Text(viewModel.menuBarTitle())
        }

        Settings {
            SettingsRootView(viewModel: viewModel)
                .frame(minWidth: 760, minHeight: 560)
        }
    }
}
