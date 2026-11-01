import SwiftUI
import MapKit

private struct NativeSeasonalThemeResponse: Decodable {
    let activeTheme: String?
}

private struct NativeSeasonalTheme {
    let id: String
    let accent: Color
    let secondary: Color
    let soft: Color
    let decorations: [String]
    let passages: [String]

    init?(id: String?) {
        guard let id else { return nil }
        let values: (UInt, UInt, UInt, [String], [String])
        switch id {
        case "paques": values = (0xA84D9B,0x45A889,0xFFF0C9,["🐰","🥚","🌷","🐣","🌼","🪺","🦋","🌿","🥕","💐"],["🐣","🥚","🐰"])
        case "printemps": values = (0x32895E,0xEF9A43,0xE5F6DD,["🌼","🌿","🦋","🌸","🐝","🌱","🌷","🍃","🌻","🐞"],["🐝","🐞","🌻"])
        case "fete-des-meres": values = (0xC44578,0xE6A546,0xFFE8EF,["🌸","💐","💗","🌷","🌺","🎀","🌼","💕","🪻","🌹"],["🌹","💝","🌷"])
        case "fete-des-peres": values = (0x276AA5,0xEDAA39,0xE7F3FF,["☀️","🎁","💙","⭐","🎉","🧢","🛠️","🏆","🎈","🚙"],["👔","🏆","🎁"])
        case "14-juillet": values = (0x2456A6,0xE04455,0xE9F0FF,["🔵","⚪","🔴","🎆","🎇","🎉","🇫🇷","✨","🎊","🎈"],["🎆","🇫🇷","🎇"])
        case "ete": values = (0xDF762E,0x1E9EAA,0xFFF2D4,["☀️","🍋","🌊","🍉","🐚","🕶️","🌴","🧡","🐬","🍍"],["🐬","🍉","🕶️"])
        case "rentree": values = (0xB35C2E,0x586EB6,0xFFF0DB,["📚","✏️","🍂","🍁","🎒","🖍️","📒","🌰","📝","🍎"],["🎒","✏️","📚"])
        case "octobre-rose": values = (0xC93678,0xE98DB7,0xFFEBF4,["🎀","🌸","💗","🌷","💕","🩷","🌺","💞","🪷","💖"],["🎀","🌸","🩷"])
        case "halloween": values = (0x9B4DE0,0xF07825,0xF2EAFF,["🎃","🦇","👻","🕸️","🕷️","🍬","🧙","🌙","🧡","💜"],["🎃","🦇","🕷️","👻"])
        case "armistice": values = (0x365677,0xBB3440,0xEDF3F8,["🌺","🇫🇷","🕊️","🌹","⭐","💐","🪖","🎗️","🕯️","🌿"],["🕊️","🌺","🪖"])
        case "movember": values = (0x187F94,0x385AA0,0xE2F6F7,["🧔","💙","🎗️","🩵","⭐","🫶","💬","🌀","🌊","💠"],["🧔","🎗️","🩵"])
        case "noel": values = (0xB73543,0x268459,0xFFF0E9,["🎄","⭐","🎁","❄️","🦌","🔔","🎅","🧦","🕯️","🍪"],["🎅","🦌","⛄","🎄"])
        case "nouvel-an": values = (0x8262C5,0xD6A942,0xF0EAFF,["✨","🥂","🎆","🎇","🎉","🪩","⭐","🥳","💫","🎊"],["🍾","🎆","🪩"])
        case "saint-valentin": values = (0xCF3C65,0xF18CA6,0xFFEBF0,["💌","❤️","🌹","💘","💕","💞","💗","🌷","💝","🩷"],["💌","🌹","💘"])
        case "black-friday": values = (0x8056DB,0xF0B53E,0xEEE8FF,["✨","🖤","🏷️","💜","⚡","💎","🌟","🎁","💫","🛍️"],["🛍️","🏷️","💎"])
        default: return nil
        }
        self.id = id
        self.accent = Color(pfHex: values.0)
        self.secondary = Color(pfHex: values.1)
        self.soft = Color(pfHex: values.2)
        self.decorations = values.3
        self.passages = values.4
    }
}

private struct NativeSeasonalThemeKey: EnvironmentKey {
    static let defaultValue: NativeSeasonalTheme? = nil
}
private struct NativeSeasonalEnabledKey: EnvironmentKey {
    static let defaultValue = true
}
private extension EnvironmentValues {
    var pfNativeSeasonalTheme: NativeSeasonalTheme? {
        get { self[NativeSeasonalThemeKey.self] }
        set { self[NativeSeasonalThemeKey.self] = newValue }
    }
    var pfNativeSeasonalEnabled: Bool {
        get { self[NativeSeasonalEnabledKey.self] }
        set { self[NativeSeasonalEnabledKey.self] = newValue }
    }
}

private struct SeasonalDecorationsLayer: View {
    let theme: NativeSeasonalTheme
    @State private var passageIndex = 0
    @State private var flybyX: CGFloat = -140

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                theme.soft.opacity(0.055).ignoresSafeArea()
                LinearGradient(colors: [theme.accent, theme.secondary, theme.accent], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 7)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)

                ForEach(0..<theme.decorations.count, id: \.self) { index in
                    Text(theme.decorations[index])
                        .font(.system(size: index.isMultiple(of: 3) ? 25 : 21))
                        .opacity(index.isMultiple(of: 3) ? 0.82 : 0.66)
                        .position(
                            x: index.isMultiple(of: 2) ? 18 : max(18, geometry.size.width - 18),
                            y: geometry.size.height * (0.13 + CGFloat(index % 7) * 0.115)
                        )
                }

                Text(theme.passages[passageIndex % theme.passages.count])
                    .font(.system(size: 48))
                    .shadow(color: theme.accent.opacity(0.35), radius: 8, y: 4)
                    .position(x: flybyX, y: max(48, geometry.safeAreaInsets.top + 42))
                    .task(id: theme.id) {
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 45_000_000_000)
                            guard !Task.isCancelled else { return }
                            flybyX = -140
                            withAnimation(.linear(duration: 7.5)) {
                                flybyX = geometry.size.width + 140
                            }
                            try? await Task.sleep(nanoseconds: 8_000_000_000)
                            passageIndex = (passageIndex + 1) % theme.passages.count
                            flybyX = -140
                        }
                    }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
private extension Color {
    init(pfHex: UInt) {
        self.init(.sRGB, red: Double((pfHex >> 16) & 0xFF) / 255, green: Double((pfHex >> 8) & 0xFF) / 255, blue: Double(pfHex & 0xFF) / 255, opacity: 1)
    }
}

struct RootView: View {
    @State private var seasonalTheme: NativeSeasonalTheme?
    @State private var seasonalThemeEnabled = true

    private var visibleSeasonalTheme: NativeSeasonalTheme? {
        seasonalThemeEnabled ? seasonalTheme : nil
    }

    var body: some View {
        TabView {
            SearchView()
                .tabItem { Label("Annonces", systemImage: "magnifyingglass") }
            FavoritesView()
                .tabItem { Label("Favoris", systemImage: "heart") }
            AccountView(showSeasonalTheme: $seasonalThemeEnabled)
                .tabItem { Label("Aide", systemImage: "questionmark.circle") }
        }
        .tint(visibleSeasonalTheme?.accent ?? Color(red: 0.02, green: 0.38, blue: 0.34))
        .toolbarBackground(visibleSeasonalTheme?.soft ?? Color(uiColor: .systemBackground), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .overlay {
            if let theme = visibleSeasonalTheme {
                SeasonalDecorationsLayer(theme: theme)
            }
        }
        .environment(\.pfNativeSeasonalTheme, seasonalTheme)
        .environment(\.pfNativeSeasonalEnabled, seasonalThemeEnabled)
        .task { await loadSeasonalTheme() }
    }

    private func loadSeasonalTheme() async {
        guard let url = URL(string: "https://www.partenairefoyer.com/api/seasonal-theme") else { return }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let payload = try JSONDecoder().decode(NativeSeasonalThemeResponse.self, from: data)
            seasonalTheme = NativeSeasonalTheme(id: payload.activeTheme)
        } catch {
            // Keep the native app usable when the seasonal endpoint is unavailable.
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
    @Environment(\.pfNativeSeasonalTheme) private var pfNativeSeasonalTheme
    @Environment(\.pfNativeSeasonalEnabled) private var pfNativeSeasonalEnabled

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
            .overlay {
                if pfNativeSeasonalEnabled, let theme = pfNativeSeasonalTheme {
                    SeasonalDecorationsLayer(theme: theme)
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
    @Environment(\.pfNativeSeasonalTheme) private var pfNativeSeasonalTheme
    @Environment(\.pfNativeSeasonalEnabled) private var pfNativeSeasonalEnabled
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
            .overlay {
                if pfNativeSeasonalEnabled, let theme = pfNativeSeasonalTheme {
                    SeasonalDecorationsLayer(theme: theme)
                }
            }
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
    @Binding var showSeasonalTheme: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("Ambiance") {
                    Toggle(isOn: $showSeasonalTheme) {
                        Label("Afficher les thèmes saisonniers", systemImage: "sparkles")
                    }
                    Text("Ce réglage s’applique uniquement à cette application sur cet appareil.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

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
