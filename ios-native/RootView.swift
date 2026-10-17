import SwiftUI
import CoreFoundation

struct RootView: View {
    @State private var selectedTab = 0
    @StateObject private var listingsService = ListingsService()

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeDashboardView(selectedTab: $selectedTab)
                .tabItem { Label("Accueil", systemImage: "house.fill") }
                .tag(0)

            NativeListingsView(service: listingsService)
                .tabItem { Label("Annonces", systemImage: "magnifyingglass") }
                .tag(1)

            NativeFavoritesView(service: listingsService)
                .tabItem { Label("Favoris", systemImage: "heart.fill") }
                .tag(2)

            NativeSpacePickerView()
                .tabItem { Label("Menu", systemImage: "line.3.horizontal") }
                .tag(3)
        }
        .tint(Color(red: 0.02, green: 0.38, blue: 0.34))
    }
}

private struct NativeListingsView: View {
    @ObservedObject var service: ListingsService
    @ObservedObject private var favorites = FavoritesStore.shared
    @State private var searchText = ""

    private var filtered: [Listing] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return service.listings }
        return service.listings.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.city ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.postalCode ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading && service.listings.isEmpty {
                    ProgressView("Chargement des annonces…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = service.errorMessage, service.listings.isEmpty {
                    ContentUnavailableView {
                        Label("Annonces indisponibles", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Réessayer") { Task { await service.reload() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.teal)
                                Text("Annonces de professionnels actualisées depuis le catalogue PartenaireFoyer.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .listRowBackground(Color.teal.opacity(0.07))
                        }

                        if filtered.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else {
                            ForEach(filtered) { listing in
                                NavigationLink(value: listing) {
                                    ListingRow(listing: listing, isFavorite: favorites.contains(listing)) {
                                        favorites.toggle(listing)
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        }

                    }
                    .listStyle(.plain)
                    .refreshable { await service.reload() }
                    .navigationDestination(for: Listing.self) { listing in
                        ListingDetailView(listing: listing)
                    }
                }
            }
            .navigationTitle("Annonces")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Ville, code postal, bien…")
            .task { await service.loadIfNeeded() }
        }
    }
}

private struct NativeFavoritesView: View {
    @ObservedObject var service: ListingsService
    @ObservedObject private var favorites = FavoritesStore.shared
    private var saved: [Listing] { service.listings.filter { favorites.contains($0) } }

    var body: some View {
        NavigationStack {
            Group {
                if saved.isEmpty {
                    ContentUnavailableView {
                        Label("Aucun favori enregistré", systemImage: "heart")
                    } description: {
                        Text("Touchez le cœur d’une annonce pour la retrouver ici sur cet iPhone.")
                    }
                } else {
                    List {
                        ForEach(saved) { listing in
                            NavigationLink(value: listing) {
                                ListingRow(listing: listing, isFavorite: true) {
                                    favorites.toggle(listing)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .navigationDestination(for: Listing.self) { listing in
                        ListingDetailView(listing: listing)
                    }
                }
            }
            .navigationTitle("Favoris")
            .task { await service.loadIfNeeded() }
        }
    }
}

private struct ListingRow: View {
    let listing: Listing
    let isFavorite: Bool
    let onFavorite: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            ListingImage(url: listing.gallery.first)
                .frame(width: 112, height: 98)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(listing.formattedPrice)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(listing.title ?? "Annonce immobilière")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !listing.locationLabel.isEmpty {
                    Label(listing.locationLabel, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let surface = listing.formattedSurface {
                    Text(surface).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(isFavorite ? .pink : .secondary)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ListingImage: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        placeholder
                    } else {
                        ZStack { placeholder; ProgressView() }
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.teal.opacity(0.09))
            .overlay(Image(systemName: "house.fill").font(.title2).foregroundStyle(.teal.opacity(0.6)))
    }
}

private struct ListingDetailView: View {
    let listing: Listing
    @ObservedObject private var favorites = FavoritesStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if listing.gallery.isEmpty {
                    ListingImage(url: nil).frame(height: 290)
                } else {
                    TabView {
                        ForEach(Array(listing.gallery.enumerated()), id: \.offset) { entry in
                            ListingImage(url: entry.element)
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 290)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(listing.formattedPrice).font(.title2.bold())
                        if !listing.locationLabel.isEmpty {
                            Label(listing.locationLabel, systemImage: "mappin.and.ellipse")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button { favorites.toggle(listing) } label: {
                        Image(systemName: favorites.contains(listing) ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundStyle(favorites.contains(listing) ? .pink : .teal)
                            .frame(width: 48, height: 48)
                            .background(Color.teal.opacity(0.09), in: Circle())
                    }
                    .accessibilityLabel(favorites.contains(listing) ? "Retirer des favoris" : "Ajouter aux favoris")
                }

                Text(listing.title ?? "Annonce immobilière")
                    .font(.title3.weight(.semibold))

                HStack(spacing: 10) {
                    if let surface = listing.formattedSurface { ListingFact(symbol: "square.dashed", text: surface) }
                    if let rooms = listing.rooms { ListingFact(symbol: "door.left.hand.open", text: "\(rooms) pièces") }
                    if let bedrooms = listing.bedrooms { ListingFact(symbol: "bed.double", text: "\(bedrooms) ch.") }
                }

                if let description = listing.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description").font(.headline)
                        Text(description).font(.body).foregroundStyle(.secondary)
                    }
                }

                if let source = listing.sourceUrl, let sourceURL = URL(string: source) {
                    Link(destination: sourceURL) {
                        Label("Contacter le professionnel", systemImage: "arrow.up.right.square")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.02, green: 0.38, blue: 0.34))
                }
            }
            .padding(18)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Détail de l’annonce")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ListingFact: View {
    let symbol: String
    let text: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.teal.opacity(0.09), in: Capsule())
    }
}

private struct HomeDashboardView: View {
    @Binding var selectedTab: Int

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    Button { selectedTab = 1 } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "magnifyingglass")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.teal)
                                .frame(width: 46, height: 46)
                                .background(Color.teal.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Voir les annonces").font(.headline).foregroundStyle(.primary)
                                Text("Biens publiés par nos professionnels").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Votre projet immobilier, au même endroit")
                            .font(.title3.bold())
                        Text("Consultez les biens, enregistrez vos favoris et choisissez votre espace depuis le menu.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary, lineWidth: 1))

                    Button { selectedTab = 3 } label: {
                        Label("Vous êtes… ? Choisir mon espace", systemImage: "person.crop.circle.badge.questionmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.02, green: 0.38, blue: 0.34))
                }
                .padding(.horizontal, 17)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.12, blue: 0.19), Color(red: 0.02, green: 0.39, blue: 0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 230, height: 230)
                .offset(x: 245, y: -85)
            Circle()
                .stroke(.white.opacity(0.10), lineWidth: 1)
                .frame(width: 180, height: 180)
                .offset(x: 260, y: -72)

            VStack(alignment: .leading, spacing: 19) {
                HStack(spacing: 11) {
                    Image("BrandLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 1))
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 0) {
                            Text("Partenaire")
                                .foregroundStyle(.white)
                            Text("Foyer")
                                .foregroundStyle(Color(red: 0.35, green: 0.91, blue: 0.62))
                        }
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("PartenaireFoyer.com")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer()

                    Button { selectedTab = 3 } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.14), in: Circle())
                    }
                    .accessibilityLabel("Ouvrir mon compte")
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Réunir.")
                        .foregroundStyle(.white)
                    Text("Connecter.")
                        .foregroundStyle(Color(red: 0.45, green: 0.94, blue: 0.67))
                    Text("Avancer.")
                        .foregroundStyle(.white)
                }
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .lineSpacing(-2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Réunir. Connecter. Avancer.")

                Text("Annonces, projets et professionnels réunis dans votre application.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, minHeight: 286, maxHeight: 286, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}



private struct NativeSpacePickerView: View {
    @State private var selectedRole: AccountRole?
    @StateObject private var auth = WixAuthStore.shared
    @AppStorage("partenairefoyer.activeRole") private var activeRoleRaw = ""

    var body: some View {
        NavigationStack {
            Group {
                if let member = auth.member, let role = AccountRole(rawValue: activeRoleRaw) {
                    NativeRoleDashboardView(role: role, member: member) {
                        auth.signOut()
                        activeRoleRaw = ""
                    }
                } else {
                    rolePicker
                }
            }
            .navigationTitle("Mon espace")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedRole) { role in
                RoleEntryView(role: role) {
                    activeRoleRaw = role.rawValue
                    selectedRole = nil
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var rolePicker: some View {
        List {
                Section {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Vous êtes… ?")
                            .font(.largeTitle.bold())
                        Text("Choisissez votre profil. Chaque espace reste séparé ; les fonctions d’un compte ne s’affichent qu’après connexion à cet espace.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("Choisir un espace") {
                    ForEach(AccountRole.allCases) { role in
                        Button { selectedRole = role } label: {
                            HStack(spacing: 13) {
                                Image(systemName: role.symbol)
                                    .font(.title3)
                                    .foregroundStyle(.teal)
                                    .frame(width: 42, height: 42)
                                    .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(role.title).font(.headline).foregroundStyle(.primary)
                                    Text(role.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if auth.isSigningIn {
                ProgressView("Connexion sécurisée Wix…")
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

private enum AccountRole: String, CaseIterable, Identifiable {
    case particulier, professionnel, courtier, artisan, prestataire, hebergeur
    var id: String { rawValue }
    var title: String {
        switch self {
        case .particulier: "Particulier"
        case .professionnel: "Professionnel de l’immobilier"
        case .courtier: "Courtier"
        case .artisan: "Artisan / diagnostiqueur"
        case .prestataire: "Prestataire"
        case .hebergeur: "Hébergeur"
        }
    }
    var subtitle: String {
        switch self {
        case .particulier: "Mes annonces, recherches et favoris"
        case .professionnel: "Mes biens, acquéreurs et matchings"
        case .courtier: "Mon espace et mes demandes"
        case .artisan: "Mes services et demandes de diagnostic"
        case .prestataire: "Ma fiche, mes photos et mes contacts"
        case .hebergeur: "Mes hébergements et réservations"
        }
    }
    var symbol: String {
        switch self {
        case .particulier: "person.crop.circle"
        case .professionnel: "building.2"
        case .courtier: "briefcase"
        case .artisan: "wrench.and.screwdriver"
        case .prestataire: "person.2"
        case .hebergeur: "bed.double"
        }
    }
    var loginURL: URL {
        URL(string: "https://www.partenairefoyer.com\(loginPath)")!
    }
    var signupURL: URL {
        URL(string: "https://www.partenairefoyer.com\(signupPath)")!
    }
    private var loginPath: String {
        switch self {
        case .particulier: "/vendeur-login"
        case .professionnel: "/pro-app-login"
        case .courtier: "/broker-login"
        case .artisan: "/artisan-login"
        case .prestataire: "/connexion-prestataire"
        case .hebergeur: "/hebergeur-connexion"
        }
    }
    private var signupPath: String {
        switch self {
        case .particulier: "/vendeur-signup"
        case .professionnel: "/inscription-pro"
        case .courtier: "/broker-signup"
        case .artisan: "/artisan-signup"
        case .prestataire: "/inscription-prestataire"
        case .hebergeur: "/hebergeur-inscription"
        }
    }
}

private struct RoleEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var auth = WixAuthStore.shared
    @State private var email = ""
    @State private var password = ""
    let role: AccountRole
    let onSignedIn: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(role.title, systemImage: role.symbol)
                        .font(.title3.bold())
                    Text(role.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Connexion à votre compte") {
                    TextField("Adresse e-mail", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Mot de passe", text: $password)
                        .textContentType(.password)
                }

                if let error = auth.errorMessage {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task {
                            await auth.signIn(email: email, password: password)
                            if auth.member != nil { onSignedIn() }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Se connecter", systemImage: "lock.shield")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || auth.isSigningIn)

                    Link(destination: role.signupURL) {
                        Label("Créer un compte", systemImage: "person.badge.plus")
                    }
                } footer: {
                    Text("La validation du compte passe par l’authentification Wix sécurisée. Le mot de passe n’est pas conservé par l’application.")
                }
            }
            .navigationTitle("Accès à l’espace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
        }
    }
}

private struct NativeRoleDashboardView: View {
    @StateObject private var auth = WixAuthStore.shared
    let role: AccountRole
    let member: WixMember
    let onSignOut: () -> Void

    private var sections: [(String, String, [[String: Any]])] {
        guard let data = auth.dashboardData else { return [] }
        let keys: [(String, String, String)]
        switch role {
        case .particulier:
            keys = [("Mes biens", "house", "properties"), ("Mes petites annonces", "tag", "classifieds"), ("Mes favoris", "heart", "favorites")]
        case .professionnel:
            keys = [("Mes biens", "house", "properties"), ("Mes matchings", "sparkles", "matchings"), ("Demandes reçues", "person.2", "demands"), ("Messages", "bubble.left.and.bubble.right", "messages")]
        case .courtier:
            keys = [("Messages", "bubble.left.and.bubble.right", "messages")]
        case .artisan:
            keys = [("Demandes et messages", "bubble.left.and.bubble.right", "messages")]
        case .prestataire:
            keys = [("Demandes et messages", "bubble.left.and.bubble.right", "messages")]
        case .hebergeur:
            keys = []
        }
        return keys.compactMap { title, icon, key in
            guard let items = data[key] as? [[String: Any]] else { return nil }
            return (title, icon, items)
        }
    }

    private var profile: [String: Any]? { auth.dashboardData?["profile"] as? [String: Any] }

    var body: some View {
        List {
            Section {
                Label(role.title, systemImage: role.symbol)
                    .font(.title3.bold())
                LabeledContent("Compte connecté", value: member.loginEmail)
                if member.loginEmailVerified == false {
                    Label("Adresse e-mail à confirmer", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            }

            if auth.isLoadingDashboard && auth.dashboardData == nil {
                Section { HStack { Spacer(); ProgressView("Chargement de vos données Wix…"); Spacer() } }
            } else if let error = auth.dashboardError {
                Section("Données du compte") {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Button("Réessayer") { Task { await auth.loadDashboard(role: role.rawValue) } }
                }
            } else if let data = auth.dashboardData {
                if let profile {
                    Section("Mon profil") {
                        ForEach(Array(profileKeys(for: role).filter { profile[$0.1] != nil }.enumerated()), id: \.offset) { _, field in
                            LabeledContent(field.0, value: display(profile[field.1]))
                        }
                    }
                }
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    Section {
                        if section.2.isEmpty {
                            Text("Aucun élément pour le moment.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(section.2.enumerated()), id: \.offset) { index, item in
                                WixDashboardItem(item: item, fallbackTitle: "Élément \(index + 1)")
                            }
                        }
                    } header: {
                        Label("\(section.0) (\(section.2.count))", systemImage: section.1)
                    }
                }
                if role == .hebergeur {
                    Section("Mon activité") {
                        Text("Votre fiche hébergeur est reliée à Wix. Les réservations apparaîtront ici lorsque la collection correspondante sera associée à ce compte.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if data["profile"] is NSNull {
                    Section("Profil métier") {
                        Text("Le compte est reconnu, mais aucune fiche de profil correspondante n’a été trouvée dans Wix.")
                            .font(.subheadline).foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Button(role: .destructive, action: onSignOut) {
                    Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Tableau de bord")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await auth.loadDashboard(role: role.rawValue) }
        .task(id: role.rawValue) { await auth.loadDashboard(role: role.rawValue) }
    }

    private func profileKeys(for role: AccountRole) -> [(String, String)] {
        switch role {
        case .particulier: [("Prénom", "firstName"), ("Nom", "lastName"), ("Ville", "city"), ("Téléphone", "phone")]
        case .professionnel: [("Société", "companyName"), ("Contact", "contactName"), ("Ville", "city"), ("Téléphone", "phoneNumber"), ("Type d’activité", "professionalType"), ("Abonnement", "subscriptionStatus")]
        case .courtier: [("Nom", "fullName"), ("Titre", "professionalTitle"), ("Ville", "city"), ("Téléphone", "phoneNumber")]
        case .artisan, .prestataire: [("Entreprise", "businessName"), ("Activité", "category"), ("Ville", "city"), ("Téléphone", "phone")]
        case .hebergeur: [("Nom", "fullName"), ("Téléphone", "phoneNumber"), ("Vérifié", "isVerified")]
        }
    }

    private func display(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "—" }
        if let flag = value as? Bool { return flag ? "Oui" : "Non" }
        if let values = value as? [String] { return values.joined(separator: ", ") }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "Oui" : "Non" }
        return String(describing: value)
    }
}

private struct WixDashboardItem: View {
    let item: [String: Any]
    let fallbackTitle: String

    private var title: String {
        ["title", "itemName", "businessName", "senderName", "fullName"].compactMap { item[$0] as? String }.first ?? fallbackTitle
    }
    private var subtitle: String {
        ["city", "postalCode", "propertyType", "category", "status", "matchingType", "demandType"].compactMap { item[$0] as? String }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private var detail: String? {
        ["description", "itemDescription", "message", "messageContent", "content"].compactMap { item[$0] as? String }.first
    }
    private var imageURL: URL? {
        ["mainImageUrl", "mainImage", "itemImage", "photo"].compactMap { item[$0] as? String }.compactMap(URL.init(string:)).first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Image(systemName: "house.fill").foregroundStyle(.teal).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.teal.opacity(0.1)) }
                }
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if let detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                if let price = item["price"] ?? item["itemPrice"] {
                    Text("\(String(describing: price)) €").font(.caption.weight(.semibold)).foregroundStyle(.teal)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}
