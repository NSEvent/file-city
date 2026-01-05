import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            Section("Root") {
                Button("Choose Folder") {
                    appState.chooseRoot()
                }
                if let url = appState.rootURL {
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(appState.nodeCount) nodes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Search") {
                TextField("Search", text: $appState.searchQuery)
                ForEach(appState.searchResults, id: \.self) { url in
                    HStack {
                        Button(url.lastPathComponent) {
                            appState.open(url)
                        }
                        Spacer()
                        Button {
                            appState.togglePin(url)
                        } label: {
                            Image(systemName: "pin")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
            }

            Section("Pins") {
                ForEach(appState.pinnedURLs(), id: \.self) { url in
                    HStack {
                        Button(url.lastPathComponent) {
                            appState.reveal(url)
                        }
                        Spacer()
                        Button {
                            appState.togglePin(url)
                        } label: {
                            Image(systemName: "pin.slash")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
            }
        }
        .listStyle(SidebarListStyle())
    }
}
