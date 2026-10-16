import SwiftUI

struct RootView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeDashboardView(selectedTab: $selectedTab)
                .tabItem { Label("Accueil", systemImage: "house.fill") }
                .tag(0)

            FullSiteRootView(initialSection: .listings)
                .tabItem { Label("Annonces", systemImage: "magnifyingglass") }
                .tag(1)

            FullSiteRootView(initialSection: .favorites)
                .tabItem { Label("Favoris", systemImage: "heart.fill") }
                .tag(2)

            FullSiteRootView(initialSection: .deposit)
                .tabItem { Label("Déposer", systemImage: "plus.app.fill") }
                .tag(3)

            FullSiteRootView(initialSection: .account)
                .tabItem { Label("Compte", systemImage: "person.crop.circle") }
                .tag(4)
        }
        .tint(Color(red: 0.02, green: 0.38, blue: 0.34))
    }
}

private struct HomeFeature: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let destination: PortalSection
}

private struct ServiceDestination: Identifiable {
    let destination: PortalSection
    let detail: String
    var id: String { destination.rawValue }
    var title: String { destination.title }
    var symbol: String { destination.symbol }
}

private enum ServiceDirectoryData {
    static let groups: [(title: String, items: [ServiceDestination])] = [
        ("Immobilier", [
            .init(destination: .listings, detail: "Annonces de particuliers et de professionnels"),
            .init(destination: .deposit, detail: "Publier un bien depuis l’espace vendeur"),
            .init(destination: .matching, detail: "Découvrir le matching immobilier"),
            .init(destination: .estimate, detail: "Faire estimer un bien"),
            .init(destination: .professionals, detail: "Trouver un professionnel"),
            .init(destination: .becomeAgent, detail: "Rejoindre le réseau immobilier")
        ]),
        ("Particuliers", [
            .init(destination: .account, detail: "Se connecter à son compte vendeur"),
            .init(destination: .privateSignup, detail: "Créer un compte particulier"),
            .init(destination: .privateDashboard, detail: "Biens, photos, favoris et matchings"),
            .init(destination: .favorites, detail: "Retrouver ses annonces favorites"),
            .init(destination: .privateLegal, detail: "CGU applicables aux particuliers"),
            .init(destination: .privateSalesTerms, detail: "CGV applicables aux particuliers")
        ]),
        ("Professionnels de l’immobilier", [
            .init(destination: .proLogin, detail: "Connexion professionnelle PartenaireFoyer"),
            .init(destination: .proSignup, detail: "Créer un accès professionnel"),
            .init(destination: .proDashboard, detail: "Tableau de bord professionnel"),
            .init(destination: .proProperties, detail: "Biens importés et annonces"),
            .init(destination: .proBuyers, detail: "Recherches acquéreurs et matching"),
            .init(destination: .proRequests, detail: "Demandes reçues"),
            .init(destination: .proMatchings, detail: "Matchings immobiliers"),
            .init(destination: .proMessages, detail: "Messages liés aux annonces"),
            .init(destination: .proProfile, detail: "Profil professionnel"),
            .init(destination: .proLegal, detail: "CGU professionnelles"),
            .init(destination: .proSalesTerms, detail: "CGV professionnelles")
        ]),
        ("Courtiers", [
            .init(destination: .brokerLogin, detail: "Connexion courtier"),
            .init(destination: .brokerSignup, detail: "Inscription courtier"),
            .init(destination: .brokerDashboard, detail: "Tableau de bord et activité"),
            .init(destination: .brokerMessages, detail: "Messagerie courtier"),
            .init(destination: .brokerLegal, detail: "CGU courtiers"),
            .init(destination: .brokerSalesTerms, detail: "CGV courtiers")
        ]),
        ("Artisans et diagnostiqueurs", [
            .init(destination: .artisanLogin, detail: "Connexion artisan / diagnostiqueur"),
            .init(destination: .artisanSignup, detail: "Inscription artisan / diagnostiqueur"),
            .init(destination: .artisanDashboard, detail: "Tableau de bord et profil"),
            .init(destination: .artisanMessages, detail: "Demandes et messages"),
            .init(destination: .artisanLegal, detail: "CGU artisans"),
            .init(destination: .artisanSalesTerms, detail: "CGV artisans")
        ]),
        ("Prestataires", [
            .init(destination: .providerLogin, detail: "Connexion prestataire"),
            .init(destination: .providerSignup, detail: "Inscription prestataire"),
            .init(destination: .providerDashboard, detail: "Gérer sa fiche prestataire"),
            .init(destination: .providerProfile, detail: "Créer ou modifier sa fiche"),
            .init(destination: .providerPhotos, detail: "Galerie photos prestataire"),
            .init(destination: .providerLegal, detail: "CGU prestataires"),
            .init(destination: .providerSalesTerms, detail: "CGV prestataires")
        ]),
        ("Locations saisonnières", [
            .init(destination: .seasonalListings, detail: "Consulter les hébergements"),
            .init(destination: .hostLogin, detail: "Connexion hébergeur"),
            .init(destination: .hostSignup, detail: "Inscription hébergeur"),
            .init(destination: .hostDashboard, detail: "Gérer ses hébergements"),
            .init(destination: .hostCalendar, detail: "Calendrier de disponibilités"),
            .init(destination: .hostBookings, detail: "Demandes de réservation")
        ]),
        ("Informations légales", [
            .init(destination: .terms, detail: "Conditions générales d’utilisation"),
            .init(destination: .salesTerms, detail: "Conditions générales de vente"),
            .init(destination: .privacy, detail: "Politique de confidentialité"),
            .init(destination: .legalNotices, detail: "Mentions légales")
        ])
    ]
}

private struct HomeDashboardView: View {
    @Binding var selectedTab: Int
    @State private var selectedPage: PortalSection?
    @State private var showServiceDirectory = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private let features: [HomeFeature] = [
        .init(id: "matching", title: "Matching immobilier", detail: "Trouvez les biens adaptés à votre projet", symbol: "arrow.left.arrow.right", tint: .indigo, destination: .matching),
        .init(id: "estimate", title: "Estimation", detail: "Préparez votre estimation en ligne", symbol: "chart.bar.xaxis", tint: .orange, destination: .estimate),
        .init(id: "classifieds", title: "Petites annonces", detail: "Acheter, vendre ou donner", symbol: "shippingbox.fill", tint: .purple, destination: .classifieds),
        .init(id: "professionals", title: "Professionnels", detail: "Immobilier et habitat", symbol: "person.2.fill", tint: .blue, destination: .professionals),
        .init(id: "private", title: "Espace particulier", detail: "Connexion et tableau de bord", symbol: "person.crop.circle.fill", tint: .green, destination: .account),
        .init(id: "pro", title: "Espace professionnel", detail: "Activité et annonces", symbol: "building.2.fill", tint: .brown, destination: .proLogin),
        .init(id: "agent", title: "Devenir mandataire", detail: "Découvrir les opportunités", symbol: "person.badge.plus", tint: .teal, destination: .becomeAgent)
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    hero

                    Button { selectedTab = 1 } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "magnifyingglass")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.teal)
                                .frame(width: 46, height: 46)
                                .background(Color.teal.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Voir toutes les annonces").font(.headline).foregroundStyle(.primary)
                                Text("Particuliers et professionnels").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Tous vos services").font(.title2.bold())
                            Spacer()
                            Text("PARTENAIREFOYER")
                                .font(.caption2.bold())
                                .tracking(0.8)
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(features) { feature in
                                Button {
                                    selectedPage = feature.destination
                                } label: {
                                    VStack(alignment: .leading, spacing: 11) {
                                        Image(systemName: feature.symbol)
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(feature.tint)
                                            .frame(width: 43, height: 43)
                                            .background(feature.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                                        Text(feature.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(feature.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 20))
                                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button { showServiceDirectory = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.teal)
                                .frame(width: 46, height: 46)
                                .background(Color.teal.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Tous les espaces et services")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Particuliers, pros, courtiers, artisans, prestataires et hébergeurs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Label("Pages et données du site PartenaireFoyer", systemImage: "link")
                        .font(.subheadline.weight(.medium))
                        .padding(17)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 17)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedPage) { page in
                FullSiteRootView(initialSection: page)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showServiceDirectory) {
                ServiceDirectoryView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
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
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white)
                        Image(systemName: "house.fill")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(Color(red: 0.035, green: 0.20, blue: 0.23))
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.12, green: 0.72, blue: 0.46))
                            .offset(y: 7)
                    }
                    .frame(width: 46, height: 46)
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

                    Button { selectedTab = 4 } label: {
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

private struct ServiceDirectoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredGroups: [(title: String, items: [ServiceDestination])] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ServiceDirectoryData.groups
        }
        return ServiceDirectoryData.groups.compactMap { group in
            let matches = group.items.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.detail.localizedCaseInsensitiveContains(searchText) ||
                group.title.localizedCaseInsensitiveContains(searchText)
            }
            return matches.isEmpty ? nil : (group.title, matches)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredGroups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.items) { item in
                            NavigationLink {
                                FullSiteRootView(initialSection: item.destination)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title).font(.body.weight(.semibold))
                                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: item.symbol)
                                        .foregroundStyle(.teal)
                                        .frame(width: 24)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Rechercher un espace ou service")
            .navigationTitle("PartenaireFoyer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
