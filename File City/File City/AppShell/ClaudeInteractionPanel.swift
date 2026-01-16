import SwiftUI

struct ClaudeInteractionPanel: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var isInputFocused: Bool
    @State private var lastSeenOutputCount: Int = 0
    @State private var panelHeight: CGFloat = 300
    @State private var dragStartHeight: CGFloat = 0

    var body: some View {
        guard let session = appState.selectedClaudeSession else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(spacing: 0) {
                // Header with buttons and status
                HStack(spacing: 8) {
                    Circle()
                        .fill(stateColor(for: session.state))
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Code")
                            .font(.headline)
                            .lineLimit(1)
                        Text(session.workingDirectory.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Open iTerm window button
                    Button {
                        appState.focusClaudeSession(session.id)
                    } label: {
                        Image(systemName: "terminal")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Open iTerm window")

                    // Terminate button
                    Button {
                        appState.terminateClaudeSession(session.id)
                        appState.deselectClaudeSession()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Terminate this Claude instance")

                    // Close panel button
                    Button {
                        appState.deselectClaudeSession()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Close this panel")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Resize handle at top
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                    Image(systemName: "ellipsis")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 6)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if dragStartHeight == 0 {
                                dragStartHeight = panelHeight
                            }
                            // Drag up (negative y) increases height, drag down (positive y) decreases height
                            let newHeight = dragStartHeight - value.translation.height
                            panelHeight = max(150, min(600, newHeight))
                        }
                        .onEnded { _ in
                            dragStartHeight = 0
                        }
                )

                // Scrollable conversation history
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(session.outputHistory.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .lineLimit(nil)
                                    .id(index)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            // Extra space at the bottom for better scrolling
                            Color.clear.frame(height: 4).id("bottom")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .frame(height: panelHeight)
                    .onChange(of: session.outputHistory.count) { newCount in
                        // Only scroll if count actually increased
                        if newCount > lastSeenOutputCount {
                            lastSeenOutputCount = newCount
                            withAnimation {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        // Initialize count and scroll to bottom when panel first appears
                        lastSeenOutputCount = session.outputHistory.count
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                Divider()

                // Input field
                HStack(spacing: 8) {
                    TextField("Send message to Claude...", text: $appState.claudePanelInputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isInputFocused)
                        .onSubmit {
                            sendMessage()
                        }

                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.claudePanelInputText.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: -2)
            .padding(12)
            .onAppear {
                // Auto-focus input when panel appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInputFocused = true
                }
            }
            .onExitCommand {
                // ESC closes panel
                appState.deselectClaudeSession()
            }
        )
    }

    private func sendMessage() {
        guard var session = appState.selectedClaudeSession,
              !appState.claudePanelInputText.isEmpty else { return }

        let messageText = appState.claudePanelInputText

        // Echo the user's message to the panel immediately
        session.outputHistory.append("❯ \(messageText)")
        appState.selectedClaudeSession = session

        // Update the session in claudeSessions as well
        if let index = appState.claudeSessions.firstIndex(where: { $0.id == session.id }) {
            appState.claudeSessions[index].outputHistory.append("❯ \(messageText)")
        }

        // Clear input and send
        appState.claudePanelInputText = ""
        appState.sendClaudeInput(sessionID: session.id, text: messageText)
    }

    private func stateColor(for state: ClaudeSession.SessionState) -> Color {
        switch state {
        case .launching:
            return .orange
        case .idle:
            return .blue
        case .generating:
            return .red
        case .exiting:
            return .gray
        }
    }
}

#Preview {
    ClaudeInteractionPanel()
        .environmentObject(AppState())
}
