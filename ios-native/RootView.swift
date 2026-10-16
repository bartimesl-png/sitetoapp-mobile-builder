import SwiftUI
import MapKit

struct RootView: View {
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeDashboardView(selectedTab: $selectedTab)
                .tabItem { Label("Accueil", systemImage: "house.fill") }.tag(0)
            SearchView()
                .tabItem { Label("Annonces", systemImage: "magnifyingglass") }.tag(1)
            FavoritesView()
                .tabItem { Label("Favoris", systemImage: "heart.fill") }.tag(2)
            FullSiteRootView(initialSection: .deposit)
                .tabItem { Label("Déposer", systemImage: "plus.app.fill") }.tag(3)
            FullSiteRootView(initialSection: .account)
                .tabItem { Label("Compte", systemImage: "person.crop.circle") }.tag(4)
        }
        .tint(Color(red: 0.02, green: 0.38, blue: 0.34))
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

                            if let error {
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
                    Group {
                        if listing.imageURLs.isEmpty {
                            Rectangle()
                                .fill(.quaternary)
                                .overlay(
                                    Image(systemName: "house.fill")
                                        .font(.largeTitle)
                                        .foregroundStyle(.tertiary)
                                )
                        } else {
                            TabView {
                                ForEach(listing.imageURLs, id: \.absoluteString) { url in
                                    AsyncImage(url: url) { phase in
                                        if let image = phase.image {
                                            image.resizable().scaledToFill()
                                        } else {
                                            Rectangle()
                                                .fill(.quaternary)
                                                .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
                                        }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: listing.imageURLs.count > 1 ? .always : .never))
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


private struct MatchingRequest: Encodable {
    let transactionType: String
    let propertyType: String?
    let priceMin: Double?
    let priceMax: Double?
    let surfaceMin: Double?
    let surfaceMax: Double?
    let roomsMin: Double?
    let city: String?
    let postalCode: String?
    let threshold: Int
    let limit: Int
}

private struct MatchingResponse: Decodable {
    let success: Bool
    let threshold: Int?
    let total: Int?
    let items: [MatchingResult]
    let error: String?
}

private struct MatchingResult: Decodable, Identifiable {
    let score: Int
    let listing: MatchingListing
    let publisher: MatchingPublisher
    var id: String { listing.id }
}

private struct MatchingListing: Decodable {
    let id: String
    let title: String
    let transactionType: String?
    let propertyType: String?
    let price: Double?
    let surface: Double?
    let landSurface: Double?
    let rooms: Int?
    let bedrooms: Int?
    let bathrooms: Int?
    let postalCode: String?
    let city: String?
    let sourceUrl: URL?
    let imageUrl: URL?
    let priceVerified: Bool?
}

private struct MatchingPublisher: Decodable {
    let displayName: String?
    let companyName: String?
    let professionalType: String?
    let website: URL?
    let phone: String?
    let photoUrl: URL?
}

private struct MatchingService {
    func find(_ criteria: MatchingRequest) async throws -> MatchingResponse {
        var request = URLRequest(url: AppConfig.matchingEndpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(criteria)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ListingsError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            throw ListingsError.server(payload["error"] ?? "Le matching est momentanément indisponible.")
        }
        let result = try JSONDecoder().decode(MatchingResponse.self, from: data)
        guard result.success else {
            throw ListingsError.server(result.error ?? "Le matching n’a pas pu être calculé.")
        }
        return result
    }
}

struct MatchingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var transactionType = "SALE"
    @State private var propertyType = "ANY"
    @State private var city = ""
    @State private var postalCode = ""
    @State private var maxBudget = ""
    @State private var minSurface = ""
    @State private var minRooms = ""
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var errorMessage: String?
    @State private var matches: [MatchingResult] = []
    @State private var selectedMatch: MatchingResult?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Projet", selection: $transactionType) {
                        Text("Acheter").tag("SALE")
                        Text("Louer").tag("RENT")
                    }
                    Picker("Type de bien", selection: $propertyType) {
                        Text("Tous les biens").tag("ANY")
                        Text("Maison").tag("HOUSE")
                        Text("Appartement").tag("APARTMENT")
                        Text("Terrain").tag("LAND")
                        Text("Local commercial").tag("COMMERCIAL")
                    }
                    TextField("Ville", text: $city)
                        .textInputAutocapitalization(.words)
                    TextField("Code postal", text: $postalCode)
                        .keyboardType(.numberPad)
                    TextField("Budget maximum (€)", text: $maxBudget)
                        .keyboardType(.numberPad)
                    TextField("Surface minimum (m²)", text: $minSurface)
                        .keyboardType(.numberPad)
                    TextField("Nombre de pièces minimum", text: $minRooms)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Votre projet")
                } footer: {
                    Text("Le moteur compare ces critères aux annonces professionnelles éligibles et calcule un score de compatibilité.")
                }

                Section {
                    Button {
                        Task { await search() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView().padding(.trailing, 8)
                            }
                            Text(isLoading ? "Calcul en cours…" : "Trouver mes correspondances")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isLoading || (city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && postalCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if hasSearched && matches.isEmpty && errorMessage == nil {
                    Section {
                        ContentUnavailableView(
                            "Aucune correspondance",
                            systemImage: "arrow.left.arrow.right",
                            description: Text("Essayez d’élargir votre budget, votre ville ou vos critères.")
                        )
                    }
                }

                if !matches.isEmpty {
                    Section("Correspondances · \(matches.count)") {
                        ForEach(matches) { match in
                            Button { selectedMatch = match } label: {
                                MatchingResultRow(match: match)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Matching immobilier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(item: $selectedMatch) { match in
                MatchingDetailView(match: match)
            }
        }
    }

    @MainActor
    private func search() async {
        isLoading = true
        hasSearched = false
        errorMessage = nil
        matches = []
        defer { isLoading = false }

        func number(_ text: String) -> Double? {
            Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        }

        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPostalCode = postalCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = MatchingRequest(
            transactionType: transactionType,
            propertyType: propertyType == "ANY" ? nil : propertyType,
            priceMin: nil,
            priceMax: number(maxBudget),
            surfaceMin: number(minSurface),
            surfaceMax: nil,
            roomsMin: number(minRooms),
            city: trimmedCity.isEmpty ? nil : trimmedCity,
            postalCode: trimmedPostalCode.isEmpty ? nil : trimmedPostalCode,
            threshold: 60,
            limit: 50
        )

        do {
            let response = try await MatchingService().find(request)
            matches = response.items
            hasSearched = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MatchingResultRow: View {
    let match: MatchingResult

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: match.listing.imageUrl) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay(Image(systemName: "house.fill").foregroundStyle(.tertiary))
                }
            }
            .frame(width: 104, height: 92)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("\(match.score)%")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.teal.opacity(0.13), in: Capsule())
                        .foregroundStyle(.teal)
                    Spacer(minLength: 0)
                    if match.listing.priceVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Prix vérifié")
                    }
                }
                Text(match.listing.price.map {
                    $0.formatted(.currency(code: "EUR").locale(Locale(identifier: "fr_FR")))
                } ?? "Prix sur demande")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                Text(match.listing.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text([match.listing.postalCode, match.listing.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct MatchingDetailView: View {
    let match: MatchingResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AsyncImage(url: match.listing.imageUrl) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(.quaternary)
                                .overlay(Image(systemName: "house.fill").font(.largeTitle).foregroundStyle(.tertiary))
                        }
                    }
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(match.score)% compatible")
                            .font(.title3.bold())
                            .foregroundStyle(.teal)
                        Text(match.listing.price.map {
                            $0.formatted(.currency(code: "EUR").locale(Locale(identifier: "fr_FR")))
                        } ?? "Prix sur demande")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.accentColor)
                        Text(match.listing.title)
                            .font(.title2.bold())
                        Text([match.listing.postalCode, match.listing.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
                            .foregroundStyle(.secondary)

                        if let surface = match.listing.surface {
                            Label("\(surface.formatted(.number.precision(.fractionLength(0...1)))) m²", systemImage: "square.dashed")
                        }
                        if let rooms = match.listing.rooms {
                            Label("\(rooms) pièces", systemImage: "bed.double")
                        }

                        Divider()
                        Text("Publié par")
                            .font(.headline)
                        Text(match.publisher.companyName ?? match.publisher.displayName ?? "Professionnel PartenaireFoyer")
                            .font(.subheadline.weight(.semibold))
                        if let type = match.publisher.professionalType, !type.isEmpty {
                            Text(type).font(.caption).foregroundStyle(.secondary)
                        }
                        if let phone = match.publisher.phone,
                           let callURL = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                            Link(destination: callURL) {
                                Label("Appeler le professionnel", systemImage: "phone.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if let url = match.listing.sourceUrl {
                            Link(destination: url) {
                                Label("Voir l’annonce", systemImage: "safari")
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
            }
        }
    }
}

private struct HomeFeature: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let page: PortalSection?
}

struct HomeDashboardView: View {
    @Binding var selectedTab: Int
    @State private var selectedPage: PortalSection?
    @State private var featuredListings: [Listing] = []
    @State private var selectedListing: Listing?
    @State private var showMatching = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private let features: [HomeFeature] = [
        .init(id: "deposit", title: "Déposer une annonce", detail: "Publier un bien", symbol: "plus.app.fill", color: .teal, page: .deposit),
        .init(id: "matching", title: "Matching immobilier", detail: "Biens et projets compatibles", symbol: "arrow.left.arrow.right", color: .indigo, page: .matching),
        .init(id: "estimate", title: "Estimation", detail: "Préparer votre projet", symbol: "chart.bar.xaxis", color: .orange, page: .estimate),
        .init(id: "classifieds", title: "Petites annonces", detail: "Acheter, vendre, donner", symbol: "shippingbox.fill", color: .purple, page: .classifieds),
        .init(id: "professionals", title: "Professionnels", detail: "Immobilier et habitat", symbol: "person.2.fill", color: .blue, page: .professionals),
        .init(id: "private", title: "Espace particulier", detail: "Connexion et tableau de bord", symbol: "person.crop.circle.fill", color: .green, page: .account),
        .init(id: "pro", title: "Espace professionnel", detail: "Activité et annonces", symbol: "building.2.fill", color: .brown, page: .proLogin),
        .init(id: "native-favorites", title: "Mes favoris", detail: "Vos biens sauvegardés sur cet iPhone", symbol: "heart.circle.fill", color: .pink, page: nil)
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    featuredSection
                    Button { selectedTab = 1 } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "magnifyingglass")
                                .font(.title3.weight(.semibold)).foregroundStyle(.teal)
                                .frame(width: 46, height: 46)
                                .background(Color.teal.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Trouver un bien").font(.headline).foregroundStyle(.primary)
                                Text("Acheter ou louer partout en France").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        }
                        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Ouvre la recherche native d’annonces immobilières")

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Tous vos services").font(.title2.bold())
                            Spacer()
                            Text("PARTENAIREFOYER").font(.caption2.bold()).tracking(0.8).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(features) { feature in
                                Button {
                                    if feature.id == "native-favorites" { selectedTab = 2 }
                                    else if feature.id == "matching" { showMatching = true }
                                    else { selectedPage = feature.page }
                                } label: {
                                    VStack(alignment: .leading, spacing: 11) {
                                        Image(systemName: feature.symbol)
                                            .font(.title3.weight(.semibold)).foregroundStyle(feature.color)
                                            .frame(width: 43, height: 43)
                                            .background(feature.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                                        Text(feature.title).font(.headline).foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(feature.detail).font(.caption).foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(14).frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 20))
                                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Label("Une application pensée pour iPhone", systemImage: "iphone")
                        .font(.headline)
                        .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 17).padding(.top, 14).padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .task { await loadFeaturedListings() }
            .sheet(item: $selectedPage) { page in
                FullSiteRootView(initialSection: page).presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedListing) { listing in
                ListingDetailView(listing: listing)
            }
            .sheet(isPresented: $showMatching) {
                MatchingView().presentationDetents([.large])
            }
        }
    }

    @ViewBuilder
    private var featuredSection: some View {
        if !featuredListings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("À découvrir").font(.title2.bold())
                    Spacer()
                    Button("Toutes les annonces") { selectedTab = 1 }
                        .font(.subheadline.weight(.semibold))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(featuredListings) { listing in
                            Button { selectedListing = listing } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    AsyncImage(url: listing.imageURL) { phase in
                                        if let image = phase.image {
                                            image.resizable().scaledToFill()
                                        } else {
                                            Rectangle().fill(.quaternary)
                                                .overlay(Image(systemName: "house.fill").foregroundStyle(.tertiary))
                                        }
                                    }
                                    .frame(height: 148)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    Text(listing.priceLabel)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(Color.accentColor)
                                    Text(listing.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(listing.locationLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .frame(width: 248, alignment: .leading)
                                .background(.background, in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func loadFeaturedListings() async {
        do {
            let page = try await ListingsService().fetch(filters: ListingFilters())
            featuredListings = Array(page.items.filter { $0.imageURL != nil }.prefix(8))
        } catch {
            featuredListings = []
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(red: 0.025, green: 0.22, blue: 0.25), Color(red: 0.02, green: 0.46, blue: 0.39)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(0.08)).frame(width: 200, height: 200).offset(x: 240, y: -90)
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Label("PARTENAIREFOYER", systemImage: "house.and.flag.fill")
                        .font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(.white)
                    Spacer()
                    Button { selectedTab = 4 } label: {
                        Image(systemName: "person.crop.circle").font(.title3).foregroundStyle(.white)
                            .frame(width: 42, height: 42).background(.white.opacity(0.16), in: Circle())
                    }.accessibilityLabel("Ouvrir mon compte")
                }
                Text("Votre prochain projet\ncommence ici.")
                    .font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("Annonces, professionnels et outils pour avancer.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.86))
            }
            .padding(22)
        }
        .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
