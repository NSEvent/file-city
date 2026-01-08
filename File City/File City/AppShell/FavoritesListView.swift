import SwiftUI

struct FavoritesListView: View {
    @EnvironmentObject var appState: AppState
    @State private var favorites: [FinderFavoritesReader.Favorite] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if favorites.isEmpty {
                emptyState
            } else {
                favoritesList
            }
        }
        .onAppear {
            loadFavorites()
        }
    }

    private var favoritesList: some View {
        List(favorites) { favorite in
            Button {
                appState.openRoot(favorite.url)
            } label: {
                HStack(spacing: 8) {
                    if let icon = favorite.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                    }

                    Text(favorite.name)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.slash")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("No Favorites")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Add folders to Finder's sidebar to see them here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadFavorites() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = FinderFavoritesReader.readFavorites()
            DispatchQueue.main.async {
                favorites = loaded
                isLoading = false
            }
        }
    }
}
