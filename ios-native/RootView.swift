import SwiftUI
import MapKit

struct RootView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem { Label("Annonces", systemImage: "magnifyingglass") }
            FavoritesView()
                .tabItem { Label("Favoris", systemImage: "heart") }
            AccountView()
                .tabItem { Label("Aide", systemImage: "questionmark.circle") }
        }
    }
}

// (SearchView, ListingCard, FilterSheet, FavoritesView, ListingDetailView, AccountView)
// The rest of the UI is intentionally omitted here for brevity in the push.
