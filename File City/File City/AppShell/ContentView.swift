import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationView {
            SidebarView()
            ZStack(alignment: .topLeading) {
                MetalCityView()
                SelectionOverlayView()
            }
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
    }
}

private struct SelectionOverlayView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let selectedURL = appState.selectedURL {
            Text(selectedURL.path)
                .font(.caption)
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(12)
                .transition(.opacity)
        }
    }
}
