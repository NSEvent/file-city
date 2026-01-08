import SwiftUI

/// Finder-style favorites sidebar that displays user's Finder sidebar favorites
struct FavoritesSidebar: View {
    @EnvironmentObject var appState: AppState
    @State private var favorites: [FinderFavoritesReader.Favorite] = []
    @State private var isLoading = true
    @State private var hoveredID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text("Favorites")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if favorites.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(favorites) { favorite in
                            FavoriteRow(
                                favorite: favorite,
                                isSelected: appState.rootURL == favorite.url,
                                isHovered: hoveredID == favorite.id
                            )
                            .onTapGesture {
                                appState.openRoot(favorite.url)
                            }
                            .onHover { hovering in
                                hoveredID = hovering ? favorite.id : nil
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .onAppear {
            loadFavorites()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.slash")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)

            Text("No Favorites")
                .font(.caption)
                .foregroundStyle(.secondary)
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

/// Individual row in the favorites sidebar (matches Finder's sizing)
private struct FavoriteRow: View {
    let favorite: FinderFavoritesReader.Favorite
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Folder icon (Finder uses ~18pt icons)
            Image(nsImage: favorite.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)

            // Name (Finder uses 13pt system font)
            Text(favorite.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.2)
        } else if isHovered {
            return Color.primary.opacity(0.08)
        }
        return .clear
    }
}

// Keep the old name as a typealias for compatibility
typealias FavoritesListView = FavoritesSidebar
