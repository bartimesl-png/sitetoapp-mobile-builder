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

struct SearchView: View {
    @Environment(FavoritesStore.self) private var favorites
    @State private var filters = ListingFilters()
    @State private var response: ListingsResponse?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var nextOffset = 0
    @State private var hasMore = false
    @State private var error: String?
    @State private var selected: Listing?
    @State private var showFilters = false

    private let service = ListingsService()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && response == nil {
                    ProgressView("Chargement des annonces…")
                } else if let error, response == nil {
                    errorView(error)
                } else if let response, response.items.isEmpty {
                    ContentUnavailableView(
                        "Aucune annonce",
                        systemImage: "house",
                        description: Text("Essayez une autre ville ou modifiez vos filtres.")
                    )
                } else {
                    ScrollView {
                        if let response {
                            HStack {
                                Text("\(response.total ?? response.items.count) annonces")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if isLoading {
                                    ProgressView().controlSize(.small)
                                }
                            }
                            .padding(.horizontal)

                            LazyVStack(spacing: 14) {
                                ForEach(response.items) { listing in
                                    ListingCard(
                                        listing: listing,
                                        isFavorite: favorites.contains(listing),
                                        onFavorite: { favorites.toggle(listing) }
                                    )
                                    .onTapGesture { selected = listing }
                                }
                            }
                            .padding()

                            if hasMore {
                                Button {
                                    Task { await load(reset: false) }
                                } label: {
                                    HStack {
                                        if isLoadingMore {
                                            ProgressView().controlSize(.small)
                                        }
                                        Text(
                                            isLoadingMore
                                                ? "Chargement…"
                                                : "Afficher plus d’annonces"
                                        )
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isLoadingMore)
                                .padding(.horizontal)
                                .padding(.bottom)
                            }

                            if let error, response != nil {
                                VStack(spacing: 8) {
                                    Text(error)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                    Button("Réessayer") {
                                        Task { await load(reset: false) }
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal)
                                .padding(.bottom)
                            }
                        }
                    }
                    .refreshable { await load(reset: true) }
                }
            }
            .navigationTitle("PartenaireFoyer")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showFilters = true } label: {
                        Label("Filtres", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load(reset: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Actualiser les annonces")
                }
            }
            .searchable(text: $filters.city, prompt: "Ville ou code postal")
            .onSubmit(of: .search) {
                Task { await load(reset: true) }
            }
            .task {
                if response == nil {
                    await load(reset: true)
                }
            }
            .sheet(isPresented: $showFilters) {
                FilterSheet(filters: $filters) {
                    Task { await load(reset: true) }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $selected) { listing in
                ListingDetailView(listing: listing)
            }
        }
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Annonces indisponibles", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Réessayer") {
                Task { await load(reset: true) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @MainActor
    private func load(reset: Bool) async {
        if reset {
            isLoading = true
            nextOffset = 0
            hasMore = false
            response = nil
        } else {
            guard !isLoadingMore else { return }
            isLoadingMore = true
        }

        error = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let page = try await service.fetch(
                filters: filters,
                offset: reset ? 0 : nextOffset
            )

            if reset {
                response = page
            } else if let current = response {
                response = ListingsResponse(
                    items: current.items + page.items,
                    total: page.total ?? current.total
                )
            } else {
                response = page
            }

            nextOffset = response?.items.count ?? 0
            hasMore = !page.items.isEmpty
                && (page.total.map { nextOffset < $0 } ?? (page.items.count == 100))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ListingCard: View {
    let listing: Listing
    let isFavorite: Bool
    let onFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                if let url = listing.imageURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            imagePlaceholder
                        }
                    }
                } else {
                    imagePlaceholder
                }

                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isFavorite ? .red : .primary)
                        .padding(10)
                        .background(.regularMaterial, in: Circle())
                }
                .padding(12)
                .accessibilityLabel(
                    isFavorite ? "Retirer des favoris" : "Ajouter aux favoris"
                )
            }
            .frame(height: 190)
            .clipped()

            VStack(alignment: .leading, spacing: 7) {
                Text(listing.priceLabel)
                    .font(.title3.bold())
                    .foregroundStyle(Color.accentColor)

                Text(listing.title)
                    .font(.headline)
                    .lineLimit(2)

                if !listing.locationLabel.isEmpty {
                    Label(listing.locationLabel, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    if let area = listing.livingArea {
                        Label(
                            "\(area.formatted(.number.precision(.fractionLength(0...1)))) m²",
                            systemImage: "square.dashed"
                        )
                    }
                    if let rooms = listing.rooms {
                        Label("\(rooms) pièces", systemImage: "bed.double")
                    }
                    if !listing.propertyType.isEmpty {
                        Text(listing.propertyType.capitalized)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        .contentShape(Rectangle())
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color(uiColor: .secondarySystemBackground))
            .overlay(
                Image(systemName: "house.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            )
    }
}

struct FilterSheet: View {
    @Binding var filters: ListingFilters
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let transactions = [
        ("", "Tous"),
        ("SALE", "Acheter"),
        ("RENT", "Louer")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    Picker("Type", selection: $filters.transactionType) {
                        ForEach(transactions, id: \.0) {
                            Text($0.1).tag($0.0)
                        }
                    }
                }

                Section("Bien") {
                    TextField(
                        "Type de bien (maison, appartement…)",
                        text: $filters.propertyType
                    )
                    .textInputAutocapitalization(.never)
                }

                Section("Budget (€)") {
                    TextField("Minimum", text: $filters.minPrice)
                        .keyboardType(.numberPad)
                    TextField("Maximum", text: $filters.maxPrice)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Effacer") { filters = ListingFilters() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Voir les annonces") {
                        onApply()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FavoritesView: View {
    @Environment(FavoritesStore.self) private var favorites
    @State private var selected: Listing?

    var body: some View {
        NavigationStack {
            Group {
                if favorites.ids.isEmpty {
                    ContentUnavailableView(
                        "Vos favoris",
                        systemImage: "heart",
                        description: Text(
                            "Touchez le cœur d’une annonce pour la retrouver ici."
                        )
                    )
                } else if favorites.listings.isEmpty {
                    ContentUnavailableView(
                        "Annonces indisponibles",
                        systemImage: "house",
                        description: Text(
                            "Les annonces sauvegardées ne sont peut-être plus en ligne."
                        )
                    )
                } else {
                    List(favorites.listings) { listing in
                        Button {
                            selected = listing
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: listing.imageURL) {
                                    $0.resizable().scaledToFill()
                                } placeholder: {
                                    Image(systemName: "house.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 82, height: 70)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(listing.priceLabel)
                                        .font(.headline)
                                        .foregroundStyle(Color.accentColor)
                                    Text(listing.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(listing.locationLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                favorites.toggle(listing)
                            } label: {
                                Label("Retirer", systemImage: "heart.slash")
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Mes favoris")
            .sheet(item: $selected) {
                ListingDetailView(listing: $0)
            }
        }
    }
}

struct ListingDetailView: View {
    let listing: Listing

    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AsyncImage(url: listing.imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle()
                                .fill(.quaternary)
                                .overlay(
                                    Image(systemName: "house.fill")
                                        .font(.largeTitle)
                                        .foregroundStyle(.tertiary)
                                )
                        }
                    }
                    .frame(height: 260)
                    .clipped()

                    VStack(alignment: .leading, spacing: 12) {
                        Text(listing.priceLabel)
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.accentColor)

                        Text(listing.title)
                            .font(.title2.bold())

                        if !listing.locationLabel.isEmpty {
                            Label(
                                listing.locationLabel,
                                systemImage: "mappin.and.ellipse"
                            )
                            .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 18) {
                            if let area = listing.livingArea {
                                Label(
                                    "\(area.formatted(.number.precision(.fractionLength(0...1)))) m²",
                                    systemImage: "square.dashed"
                                )
                            }
                            if let rooms = listing.rooms {
                                Label("\(rooms) pièces", systemImage: "bed.double")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        if let latitude = listing.latitude,
                           let longitude = listing.longitude,
                           (-90...90).contains(latitude),
                           (-180...180).contains(longitude) {
                            Map(
                                initialPosition: .region(
                                    MKCoordinateRegion(
                                        center: CLLocationCoordinate2D(
                                            latitude: latitude,
                                            longitude: longitude
                                        ),
                                        span: MKCoordinateSpan(
                                            latitudeDelta: 0.025,
                                            longitudeDelta: 0.025
                                        )
                                    )
                                )
                            ) {
                                Marker(
                                    listing.city.isEmpty
                                        ? "Bien immobilier"
                                        : listing.city,
                                    coordinate: CLLocationCoordinate2D(
                                        latitude: latitude,
                                        longitude: longitude
                                    )
                                )
                            }
                            .frame(height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel(
                                "Carte de localisation de l’annonce"
                            )
                        }

                        if !listing.summary.isEmpty {
                            Text(listing.summary)
                                .font(.body)
                                .textSelection(.enabled)
                        }

                        Button {
                            favorites.toggle(listing)
                        } label: {
                            Label(
                                favorites.contains(listing)
                                    ? "Retirer des favoris"
                                    : "Ajouter aux favoris",
                                systemImage: favorites.contains(listing)
                                    ? "heart.fill"
                                    : "heart"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        if let phone = listing.phone {
                            let digits = phone.filter {
                                $0.isNumber || $0 == "+"
                            }
                            if let phoneURL = URL(string: "tel:\(digits)") {
                                Link(destination: phoneURL) {
                                    Label("Appeler", systemImage: "phone.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        if let url = listing.sourceURL {
                            Link(destination: url) {
                                Label(
                                    "Voir l’annonce d’origine",
                                    systemImage: "safari"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .ignoresSafeArea(edges: .top)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: listing.sourceURL?.absoluteString
                            ?? "\(listing.title)\n\(listing.locationLabel)\n\(listing.priceLabel)"
                    )
                }
            }
        }
    }
}

struct AccountView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("PartenaireFoyer", systemImage: "house.fill")
                        .font(.headline)
                    Text(
                        "Retrouvez des annonces immobilières et gardez vos biens favoris sur cet appareil."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Section("Contact") {
                    Link(
                        destination: URL(
                            string: "mailto:\(AppConfig.supportEmail)"
                        )!
                    ) {
                        Label("Contacter le support", systemImage: "envelope")
                    }
                }

                Section("Informations") {
                    Link(destination: AppConfig.privacyURL) {
                        Label("Confidentialité", systemImage: "hand.raised")
                    }
                    LabeledContent(
                        "Version",
                        value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                    )
                }
            }
            .navigationTitle("Aide et informations")
        }
    }
}
