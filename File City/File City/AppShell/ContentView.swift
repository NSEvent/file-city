import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationView {
            SidebarView()
            ZStack(alignment: .topLeading) {
                MetalCityView()
                InfoOverlayView()
            }
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
    }
}

private struct InfoOverlayView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let info = infoLines() {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(info, id: \.self) { line in
                    Text(line)
                        .font(line == info.first ? .callout.weight(.semibold) : .caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(12)
            .transition(.opacity)
        }
    }

    private func infoLines() -> [String]? {
        if let activityInfo = appState.activityInfoLines {
            return activityInfo
        }
        if let hoveredGitStatus = appState.hoveredGitStatus {
            return hoveredGitStatus
        }
        if let hoveredURL = appState.hoveredURL {
            return appState.infoLines(for: hoveredURL)
        }
        if let selectedURL = appState.selectedURL {
            return appState.infoLines(for: selectedURL)
        }
        return nil
    }
}
