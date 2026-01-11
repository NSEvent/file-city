import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchQuery: String = ""
    @State private var isSearchExpanded: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var keyboardMonitor: Any?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            HStack(spacing: 0) {
                // Left: Favorites sidebar (Finder-style)
                FavoritesSidebar()
                    .frame(width: 180)

                Divider()

                // Right: Current folder contents
                VStack(spacing: 0) {
                    SidebarToolbar(
                        searchQuery: $searchQuery,
                        isSearchExpanded: $isSearchExpanded,
                        isSearchFocused: $isSearchFocused
                    )

                    FinderListView(searchQuery: searchQuery)
                }
            }
            .frame(minWidth: 500)
            .navigationSplitViewColumnWidth(min: 500, ideal: 1000, max: 1000)
        } detail: {
            ZStack {
                MetalCityView()
                VStack {
                    HStack(alignment: .top) {
                        InfoOverlayView()
                        Spacer()
                        SelectionInfoPanel()
                    }
                    Spacer()
                    // Time Machine slider (only for git repos with history, hidden in FPS mode)
                    if appState.isRootGitRepo && !appState.commitHistory.isEmpty && !appState.isFirstPerson {
                        TimeMachineSlider()
                    }
                }
                // Minecraft-style crosshair in first-person mode
                if appState.isFirstPerson && !appState.isPilotingPlane {
                    CrosshairView()
                }
                // "Press E to board" prompt when attached to plane
                if appState.isFirstPerson && appState.canBoardPlane && !appState.isPilotingPlane {
                    BoardPlanePromptView()
                }
            }
        }
        .onAppear {
            bringToFront()
            setupKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
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

    private func setupKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
                withAnimation {
                    isSearchExpanded = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
                return nil  // Consume the event
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }
}

private struct InfoOverlayView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let session = appState.hoveredClaudeSession {
            // Claude session hover info
            VStack(alignment: .leading, spacing: 6) {
                // Header with state indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(stateColor(for: session.state))
                        .frame(width: 8, height: 8)
                    Text("Claude Code")
                        .font(.callout.weight(.semibold))
                    Text("• \(stateText(for: session.state))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Working directory
                Text(session.workingDirectory.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)

                // Last output lines (when idle)
                if session.state == .idle, let outputLines = appState.hoveredClaudeOutputLines, !outputLines.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(outputLines.suffix(3), id: \.self) { line in
                            Text(stripANSI(line))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }

                // Click hint
                Text("Click to focus terminal")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 300)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(12)
            .transition(.opacity)
        } else if let info = infoLines() {
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

    private func stateColor(for state: ClaudeSession.SessionState) -> Color {
        switch state {
        case .launching: return .orange
        case .idle: return .blue
        case .generating: return .red
        case .exiting: return .gray
        }
    }

    private func stateText(for state: ClaudeSession.SessionState) -> String {
        switch state {
        case .launching: return "Starting..."
        case .idle: return "Ready"
        case .generating: return "Working..."
        case .exiting: return "Exiting"
        }
    }

    /// Strip ANSI escape codes from terminal output
    private func stripANSI(_ string: String) -> String {
        // Remove ANSI escape sequences like \x1B[...m
        string.replacingOccurrences(
            of: "\\x1B\\[[0-9;]*[mK]|\\e\\[[0-9;]*[mK]",
            with: "",
            options: .regularExpression
        )
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
    @Binding var searchQuery: String
    @Binding var isSearchExpanded: Bool
    @FocusState.Binding var isSearchFocused: Bool

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

                // Current path (hidden when search is expanded)
                if !isSearchExpanded {
                    if let rootURL = appState.rootURL {
                        Text(rootURL.lastPathComponent)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                // Search bar
                if isSearchExpanded {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        TextField("Search", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .focused($isSearchFocused)
                            .onSubmit {
                                // Keep focus on search
                            }
                            .onExitCommand {
                                collapseSearch()
                            }

                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }

                        Button {
                            collapseSearch()
                        } label: {
                            Text("Done")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
                } else {
                    // Magnifying glass button
                    Button {
                        expandSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Search (⌘F)")
                }

                // Choose folder button
                if !isSearchExpanded {
                    Button {
                        appState.chooseRoot()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Choose Folder")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.2), value: isSearchExpanded)

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
                    if searchQuery.isEmpty {
                        Text("\(appState.nodeCount) items")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Searching...")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Divider()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func expandSearch() {
        withAnimation {
            isSearchExpanded = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isSearchFocused = true
        }
    }

    private func collapseSearch() {
        withAnimation {
            isSearchExpanded = false
            searchQuery = ""
        }
        isSearchFocused = false
    }
}

/// Minecraft-style crosshair for first-person mode
private struct CrosshairView: View {
    private let size: CGFloat = 20
    private let thickness: CGFloat = 2

    var body: some View {
        ZStack {
            // Horizontal line
            Rectangle()
                .fill(Color.white)
                .frame(width: size, height: thickness)

            // Vertical line
            Rectangle()
                .fill(Color.white)
                .frame(width: thickness, height: size)
        }
        .shadow(color: .black.opacity(0.5), radius: 1, x: 1, y: 1)
    }
}

/// Prompt shown when player can board a plane
private struct BoardPlanePromptView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Press E to board")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 100)
        }
    }
}
