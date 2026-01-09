import SwiftUI

struct TimeMachineSlider: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragging: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            // Commit info tooltip (shown while dragging or in historical mode)
            if let commit = currentCommit, (isDragging || !appState.timeTravelMode.isLive) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(commit.subject)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text("\(commit.displayDate) • \(commit.shortHash)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Slider bar
            HStack(spacing: 12) {
                // Historical indicator icon
                Image(systemName: appState.timeTravelMode.isLive ? "clock" : "clock.arrow.circlepath")
                    .font(.system(size: 14))
                    .foregroundColor(appState.timeTravelMode.isLive ? .secondary : .orange)

                // Custom slider track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track background
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)

                        // Fill
                        Capsule()
                            .fill(appState.timeTravelMode.isLive ? Color.accentColor : Color.orange)
                            .frame(width: max(0, geo.size.width * appState.sliderPosition), height: 4)

                        // Thumb
                        Circle()
                            .fill(appState.timeTravelMode.isLive ? Color.accentColor : Color.orange)
                            .frame(width: 16, height: 16)
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                            .offset(x: max(0, min(geo.size.width - 16, (geo.size.width - 16) * appState.sliderPosition)))
                    }
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let newPosition = max(0, min(1, value.location.x / geo.size.width))
                                appState.updateTimeTravelPosition(newPosition, live: true)
                            }
                            .onEnded { _ in
                                isDragging = false
                                appState.commitTimeTravel()
                            }
                    )
                }
                .frame(height: 20)

                // "Now" button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.returnToLive()
                    }
                } label: {
                    Text("Now")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(appState.timeTravelMode.isLive ? .secondary : .primary)
                }
                .buttonStyle(.borderless)
                .disabled(appState.timeTravelMode.isLive)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 80)
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .animation(.easeInOut(duration: 0.2), value: appState.timeTravelMode.isLive)
    }

    /// Get the commit currently pointed to by the slider
    private var currentCommit: GitCommit? {
        guard !appState.commitHistory.isEmpty else { return nil }

        if appState.sliderPosition >= 0.99 {
            // At live position, show most recent commit
            return appState.commitHistory.first
        }

        // Map position to commit index
        let invertedPosition = 1.0 - appState.sliderPosition
        let index = Int(invertedPosition * Double(appState.commitHistory.count - 1))
        let clampedIndex = max(0, min(appState.commitHistory.count - 1, index))
        return appState.commitHistory[clampedIndex]
    }
}
