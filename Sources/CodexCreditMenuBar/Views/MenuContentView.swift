import SwiftUI

struct MenuContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Button(viewModel.localized(.refreshNow)) {
            viewModel.refreshNow()
        }

        Button(viewModel.localized(.settings)) {
            viewModel.openSettings()
        }

        Menu(viewModel.localized(.language)) {
            ForEach(LanguageMode.allCases) { mode in
                Button(viewModel.languageModeTitle(mode)) {
                    viewModel.setLanguageMode(mode)
                }
            }
        }

        Button(viewModel.localized(.quit)) {
            viewModel.quitApp()
        }
    }
}
