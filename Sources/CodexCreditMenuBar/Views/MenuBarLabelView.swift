import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Text(viewModel.menuBarTitle())
    }
}
