import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationView {
            SidebarView()
            ZStack {
                MetalCityView()
                VStack {
                    HStack(alignment: .top) {
                        InfoOverlayView()
                        Spacer()
                        SelectionInfoPanel()
                    }
                    Spacer()
                }
            }
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
        .onAppear {
            bringToFront()
        }
    }

    private func bringToFront() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.unhide(nil)
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
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
        if let hoveredGitStatus = appState.hoveredGitStatus {
            return hoveredGitStatus
        }
        if let hoveredURL = appState.hoveredURL {
            return appState.infoLines(for: hoveredURL)
        }
        return nil
    }
}

private struct SelectionInfoPanel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let selectedURL = appState.selectedURL {
            let info = appState.infoLines(for: selectedURL)
            VStack(alignment: .trailing, spacing: 8) {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(info, id: \.self) { line in
                        Text(line)
                            .font(line == info.first ? .callout.weight(.semibold) : .caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    Button {
                        appState.open(selectedURL)
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        appState.reveal(selectedURL)
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)

                    if appState.isDirectory(selectedURL) {
                        Button {
                            appState.enter(selectedURL)
                        } label: {
                            Label("Enter", systemImage: "arrow.right.circle")
                        }
                        .buttonStyle(.borderless)
                    }
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
}
