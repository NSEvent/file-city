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
                            appState.focus(url)
                        }
                        .fontWeight(appState.selectedURL == url ? .semibold : .regular)
                        .contextMenu {
                            Button("Open") {
                                appState.open(url)
                            }
                            Button("Reveal in Finder") {
                                appState.reveal(url)
                            }
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

            Section("Actions") {
                if let selectedURL = appState.selectedURL {
                    Text("Selected: \(selectedURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Selected: none")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("New Folder") {
                    appState.createFolder()
                }
                .disabled(appState.actionContainerURL() == nil)

                Button("New File") {
                    appState.createFile()
                }
                .disabled(appState.actionContainerURL() == nil)

                Button("Rename") {
                    appState.renameSelected()
                }
                .disabled(appState.selectedURL == nil)

                Button("Move") {
                    appState.moveSelected()
                }
                .disabled(appState.selectedURL == nil)

                Button("Move to Trash") {
                    appState.trashSelected()
                }
                .disabled(appState.selectedURL == nil)
            }
        }
        .listStyle(SidebarListStyle())
    }
}
