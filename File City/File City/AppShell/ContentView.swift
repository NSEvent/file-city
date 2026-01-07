import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Toolbar with navigation
                SidebarToolbar()

                // Finder-style list view
                FinderListView()
            }
            .frame(minWidth: 320)

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

private struct SidebarToolbar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Back button
                Button {
                    appState.goToParent()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(!appState.canGoToParent())

                // Current path
                if let rootURL = appState.rootURL {
                    Text(rootURL.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                // Choose folder button
                Button {
                    appState.chooseRoot()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Choose Folder")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Path breadcrumb
            if let rootURL = appState.rootURL {
                HStack {
                    Text(rootURL.path)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Text("\(appState.nodeCount) items")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Divider()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}
