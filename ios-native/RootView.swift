Warning: truncated output (original token count: 31330)
Total output lines: 2622

import SwiftUI
import CoreFoundation
import UIKit

struct RootView: View {
    @State private var selectedTab = 0
    @StateObject private var listingsService = ListingsService()
    @StateObject private var classifiedAdsService = ClassifiedAdsService()
    @StateObject private var professionalsService = ProfessionalsService()

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeDashboardView(selectedTab: $selectedTab)
                .tabItem { Label("Accueil", systemImage: "house.fill") }
                .tag(0)

            NativeListingsView(service: listingsService, classifiedAds: classifiedAdsService)
                .tabItem { Label("Annonces", systemImage: "magnifyingglass") }
                .tag(1)

            NativeProfessionalsView(service: professionalsService)
                .tabItem { Label("Professionnels", systemImage: "person.2") }
                .tag(2)

            NativeFavoritesView(service: listingsService, classifiedAds: classifiedAdsService)
                .tabItem { Label("Favoris", systemImage: "heart.fill") }
                .tag(3)

            NativeSpacePickerView()
                .tabItem { Label("Menu", systemImage: "line.3.horizontal") }
                .tag(4)
        }
        .tint(Color(red: 0.02, green: 0.38, blue: 0.34))
    }
}

private struct NativeProfessionalsView: View {
    @ObservedObject var service: ProfessionalsService
    @State private var searchText = ""

    private var filtered: [WixPublicProfessional] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return service.professionals }
        return service.professionals.filter {
            $0.resolvedName.localizedCaseInsensitiveContains(query) ||
            ($0.city ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.postalCode ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.resolvedActivity ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading && service.professionals.isEmpty {
                    ProgressView("Chargement des professionnels…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = service.errorMessage, service.professionals.isEmpty {
                    ContentUnavailableView {
                        Label("Annuaire indisponible", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Réessayer") { Task { await service.reload() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(filtered) { professional in
                        NavigationLink(value: professional.id) {
                            ProfessionalRow(professional: professional)
                        }
                        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                    }
                    .listStyle(.plain)
                    .refreshable { await service.reload() }
                    .navigationDestination(for: String.self) { id in
                        if let professional = service.professionals.first(where: { $0.id == id }) {
                            ProfessionalDetailView(professional: professional)
                        }
                    }
                }
            }
            .navigationTitle("Professionnels")
            .searchable(text: $searchText, prompt: "Métier, ville, code postal…")
            .task { await service.loadIfNeeded() }
        }
    }
}

private struct ProfessionalRow: View {
    let professional: WixPublicProfessional

    private var initials: String {
        professional.resolvedName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    var body: some View {
        HStack(spacing: 13) {
            if let source = professional.logo {
                NativeProfileImage(source: source, fallback: "building.2")
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            } else {
                Text(initials.isEmpty ? "PF" : initials.uppercased())
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.teal)
                    .frame(width: 58, height: 58)
                    .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(professional.resolvedName).font(.headline).foregroundStyle(.primary).lineLimit(2)
                if let activity = professional.resolvedActivity {
                    Text(activity).font(.subheadline).foregroundStyle(.teal).lineLimit(1)
                }
                if !professional.locationLabel.isEmpty {
                    Label(professional.locationLabel, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

private struct ProfessionalDetailView: View {
    let professional: WixPublicProfessional

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if let source = professional.logo {
                        NativeProfileImage(source: source, fallback: "building.2")
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        Image(systemName: "building.2.crop.circle.fill")
                            .font(.system(size: 50)).foregroundStyle(.teal)
                    }
                    Text(professional.resolvedName).font(.title2.bold())
                    if let activity = professional.resolvedActivity {
                        Label(activity, systemImage: "briefcase")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.teal)
                    }
                    if !professional.locationLabel.isEmpty {
                        Label(professional.locationLabel, systemImage: "mappin.and.ellipse")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }

            if let description = professional.description, !description.isEmpty {
                Section("Présentation") {
                    Text(description).textSelection(.enabled)
                }
            }

            if let website = professional.website?.trimmingCharacters(in: .whitespacesAndNewlines),
               let url = URL(string: website.hasPrefix("http") ? website : "https://\(website)"),
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                Section {
                    Link(destination: url) {
                        Label("Ouvrir le site professionnel", systemImage: "safari")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Fiche professionnelle")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum NativeCatalogSection: String, CaseIterable, Identifiable {
    case realEstate = "Immobilier"
    case classifiedAds = "Petites annonces"
    var id: String { rawValue }
}

private struct NativeListingsView: View {
    @ObservedObject var service: ListingsService
    @ObservedObject var classifiedAds: ClassifiedAdsService
    @ObservedObject private var favorites = FavoritesStore.shared
    @State private var searchText = ""
    @State private var catalogSection: NativeCatalogSection = .realEstate

    private var filteredListings: [Listing] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return service.listings }
        return service.listings.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.city ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.postalCode ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredClassifiedAds: [ClassifiedAd] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return classifiedAds.ads }
        return classifiedAds.ads.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            ($0.category ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.subcategory ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.city ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.postalCode ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Type d’annonce", selection: $catalogSection) {
                        ForEach(NativeCatalogSection.allCases) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }

                if catalogSection == .realEstate {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles").foregroundStyle(.teal)
                            Text("Biens particuliers et professionnels publiés sur Wix, avec les annonces immobilières importées du catalogue PartenaireFoyer.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.teal.opacity(0.07))
                    }
                    if service.isLoading && service.listings.isEmpty {
                        Section { HStack { Spacer(); ProgressView("Chargement des biens…"); Spacer() } }
                    } else if let error = service.errorMessage, service.listings.isEmpty {
                        Section("Annonces immobilières") {
                            Label(error, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.orange)
                            Button("Réessayer") { Task { await service.reload() } }
                        }
                    } else if filteredListings.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ForEach(filteredListings) { listing in
                            NavigationLink(value: listing) {
                                ListingRow(listing: listing, isFavorite: favorites.contains(listing)) {
                                    favorites.toggle(listing)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                } else {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "tag.fill").foregroundStyle(.teal)
                            Text("Petites annonces publiées sur Wix, avec leurs photos, prix, catégorie et localisation.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.teal.opacity(0.07))
                    }
                    if classifiedAds.isLoading && classifiedAds.ads.isEmpty {
                        Section { HStack { Spacer(); ProgressView("Chargement des petites annonces…"); Spacer() } }
                    } else if let error = classifiedAds.errorMessage, classifiedAds.ads.isEmpty {
                        Section("Petites annonces") {
                            Label(error, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.orange)
                            Button("Réessayer") { Task { await classifiedAds.reload() } }
                        }
                    } else if filteredClassifiedAds.isEmpty {
                        ContentUnavailableView {
                            Label("Aucune petite annonce trouvée", systemImage: "tag")
                        } description: {
                            Text(searchText.isEmpty ? "Les nouvelles annonces publiées sur PartenaireFoyer apparaîtront ici." : "Essayez une autre recherche.")
                        }
                    } else {
                        ForEach(filteredClassifiedAds) { ad in
                            NavigationLink(value: ad) {
                                ClassifiedAdRow(ad: ad, isFavorite: favorites.contains(ad)) {
                                    favorites.toggle(ad)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                if catalogSection == .realEstate { await service.reload() }
                else { await classifiedAds.reload() }
            }
            .navigationDestination(for: Listing.self) { listing in
                ListingDetailView(listing: listing)
            }
            .navigationDestination(for: ClassifiedAd.self) { ad in
                NativeClassifiedAdDetailView(ad: ad)
            }
            .navigationTitle("Annonces")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: catalogSection == .realEstate ? "Ville, code postal, bien…" : "Article, catégorie, ville…")
            .task(id: catalogSection) {
                if catalogSection == .realEstate { await service.loadIfNeeded() }
                else { await classifiedAds.loadIfNeeded() }
            }
        }
    }
}

private struct ClassifiedAdRow: View {
    let ad: ClassifiedAd
    var isFavorite = false
    var onFavorite: () -> Void = {}

    var body: some View {
        HStack(spacing: 13) {
            ListingImage(url: ad.images.first)
                .frame(width: 112, height: 98)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(ad.formattedPrice).font(.headline.weight(.bold))
                Text(ad.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let category = ad.category {
                    Text([category, ad.subcategory].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.teal).lineLimit(1)
                }
                if !ad.locationLabel.isEmpty {
                    Label(ad.locationLabel, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

private struct NativeClassifiedAdDetailView: View {
    let ad: ClassifiedAd
    @ObservedObject private var favorites = FavoritesStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if ad.images.isEmpty {
                    ListingImage(url: nil).frame(height: 290)
                } else {
                    TabView {
                        ForEach(Array(ad.images.enumerated()), id: \.offset) { _, url in
                            ListingImage(url: url)
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 290)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityLabel("Galerie de photos de la petite annonce")
                }
                HStack(alignment: .top) {
                    Text(ad.formattedPrice).font(.title2.bold())
                    Spacer()
                    Button { favorites.toggle(ad) } label: {
                        Image(systemName: favorites.contains(ad) ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundStyle(favorites.contains(ad) ? .pink : .teal)
                            .frame(width: 48, height: 48)
                            .background(Color.teal.opacity(0.09), in: Circle())
                    }
                    .accessibilityLabel(favorites.contains(ad) ? "Retirer des favoris" : "Ajouter aux favoris")
                }
                Text(ad.title).font(.title3.weight(.semibold))
                if let category = ad.category {
                    Label([category, ad.subcategory].compactMap { $0 }.joined(separator: " · "), systemImage: "tag")
                        .font(.subheadline).foregroundStyle(.teal)
                }
                if let condition = ad.condition, !condition.isEmpty {
                    Label(condition, systemImage: "checkmark.seal")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !ad.locationLabel.isEmpty {
                    Label(ad.locationLabel, systemImage: "mappin.and.ellipse")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let description = ad.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description").font(.headline)
                        Text(description).font(.body).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            .padding(18)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Petite annonce")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NativeFavoritesView: View {
    @ObservedObject var service: ListingsService
    @ObservedObject var classifiedAds: ClassifiedAdsService
    @ObservedObject private var favorites = FavoritesStore.shared
    private var savedListings: [Listing] { service.listings.filter { favorites.contains($0) } }
    private var savedClassifiedAds: [ClassifiedAd] { classifiedAds.ads.filter { favorites.contains($0) } }

    var body: some View {
        NavigationStack {
            List {
                Section("Biens immobiliers") {
                    if savedListings.isEmpty {
                        Text("Aucun bien immobilier enregistré.").foregroundStyle(.secondary)
                    } else {
                        ForEach(savedListings) { listing in
                            NavigationLink(value: listing) {
                                ListingRow(listing: listing, isFavorite: true) { favorites.toggle(listing) }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }
                Section("Petites annonces") {
                    if savedClassifiedAds.isEmpty {
                        Text("Aucune petite annonce enregistrée.").foregroundStyle(.secondary)
                    } else {
                        ForEach(savedClassifiedAds) { ad in
                            NavigationLink(value: ad) {
                                ClassifiedAdRow(ad: ad, isFavorite: true) { favorites.toggle(ad) }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationDestination(for: Listing.self) { ListingDetailView(listing: $0) }
            .navigationDestination(for: ClassifiedAd.self) { NativeClassifiedAdDetailView(ad: $0) }
            .navigationTitle("Favoris")
            .safeAreaInset(edge: .bottom) {
                if let message = favorites.syncMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(.bar)
                }
            }
            .task {
                await service.loadIfNeeded()
                await classifiedAds.loadIfNeeded()
                favorites.inferSources(listings: service.listings, ads: classifiedAds.ads)
                await favorites.syncFromWix()
            }
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
    @State private var showNativeEstimation = false

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

                    Button { selectedTab = 2 } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "person.2")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.teal)
                                .frame(width: 46, height: 46)
                                .background(Color.teal.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Trouver un professionnel").font(.headline).foregroundStyle(.primary)
                                Text("Des profils actifs et visibles sur Wix").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button { showNativeEstimation = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.teal)
                                .frame(width: 46, height: 46)
                                .background(Color.teal.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 3) {
                …15330 tokens truncated…servations", "reservations", "bed.double.fill")]
        }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                let items = data[metric.1] as? [[String: Any]] ?? []
                VStack(alignment: .leading, spacing: 7) {
                    Label(metric.0, systemImage: metric.2)
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(items.count.formatted())
                        .font(.title2.bold()).contentTransition(.numericText())
                    if metric.1 == "messages" {
                        let unread = items.filter { $0["isRead"] as? Bool == false || $0["seen"] as? Bool == false }.count
                        Text(unread == 0 ? "À jour" : "\(unread) non lu(s)")
                            .font(.caption2).foregroundStyle(unread == 0 ? .secondary : .orange)
                    } else {
                        Text(items.isEmpty ? "Aucun élément" : "Données Wix")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ProfessionalImportCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var service: ProfessionalImportService
    @State private var confirmRevocation = false

    var body: some View {
        List {
            Section("Autorisation de republication") {
                Label(service.isAuthorized ? "Autorisation active" : "Autorisation non accordée",
                      systemImage: service.isAuthorized ? "checkmark.seal.fill" : "hand.raised.fill")
                    .foregroundStyle(service.isAuthorized ? .green : .secondary)
                Text("Cette autorisation permet de présenter les annonces importées, leurs photos et leurs caractéristiques dans PartenaireFoyer, et de les rendre éligibles au matching lorsqu’elles sont validées.")
                    .font(.footnote).foregroundStyle(.secondary)
                if service.isAuthorized {
                    Button("Retirer mon autorisation", role: .destructive) { confirmRevocation = true }
                } else {
                    Button {
                        Task { await service.setConsent(true) }
                    } label: {
                        Label("Autoriser l’import et la diffusion", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Import automatique") {
                Toggle(isOn: Binding(
                    get: { service.autoImportEnabled },
                    set: { enabled in Task { await service.setAutoImport(enabled) } }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Actualiser mes annonces automatiquement")
                        Text("Les nouveaux biens et mises à jour sont récupérés par le service existant.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!service.isAuthorized || service.isLoading)
            }

            if service.isLoading {
                Section { HStack { Spacer(); ProgressView("Synchronisation avec le service d’import…"); Spacer() } }
            }
            if let state = service.state, state["linked"] as? Bool == false {
                Section("Compte professionnel") {
                    Label("Aucun compte immobilier éligible n’est associé à cette adresse.", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
            if let message = service.statusMessage {
                Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            if let error = service.errorMessage {
                Section("Erreur") {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button("Réessayer") { Task { await service.load() } }
                }
            }

            Section("Annonces du réseau (\(service.listings.count))") {
                if !service.isAuthorized {
                    Text("Accordez l’autorisation ci-dessus pour afficher et gérer la diffusion des annonces importées.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if service.listings.isEmpty && !service.isLoading {
                    Text("Aucune annonce importée pour le moment. L’import est relancé par le service PartenaireFoyer après validation de l’autorisation.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(Array(service.listings.enumerated()), id: \.offset) { _, listing in
                    ImportedListingControlRow(listing: listing, disabled: service.isLoading) { visible in
                        guard let id = listing["id"] as? String else { return }
                        Task { await service.setListingVisible(id, visible: visible) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Imports immobiliers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Fermer") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await service.load() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Actualiser les annonces importées")
            }
        }
        .confirmationDialog("Retirer l’autorisation d’import ?", isPresented: $confirmRevocation, titleVisibility: .visible) {
            Button("Retirer l’autorisation", role: .destructive) { Task { await service.setConsent(false) } }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Les annonces importées seront retirées de la diffusion PartenaireFoyer et ne pourront plus participer au matching.")
        }
        .task { await service.load() }
    }
}

private struct ImportedListingControlRow: View {
    let listing: [String: Any]
    let disabled: Bool
    let onVisibilityChange: (Bool) -> Void

    private func string(_ key: String) -> String? { listing[key] as? String }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let raw = string("imageUrl"), let url = WixImageSource.url(raw) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Image(systemName: "house.fill").foregroundStyle(.teal).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.teal.opacity(0.1)) }
                    }
                    .frame(width: 76, height: 62).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(string("title") ?? "Bien immobilier").font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text([string("postalCode"), string("city")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
                        .font(.caption).foregroundStyle(.secondary)
                    if let price = listing["price"] { Text("\(String(describing: price)) €").font(.caption.weight(.semibold)).foregroundStyle(.teal) }
                }
                Spacer(minLength: 0)
            }
            HStack {
                Label(listing["matchingActive"] as? Bool == true ? "Dans le matching" : (listing["publicVisible"] as? Bool == true ? "Publié" : "Non diffusé"),
                      systemImage: listing["matchingActive"] as? Bool == true ? "sparkles" : "eye")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(listing["professionalVisible"] as? Bool == true ? "Masquer" : "Afficher") {
                    onVisibilityChange(listing["professionalVisible"] as? Bool != true)
                }
                .font(.caption.weight(.semibold)).buttonStyle(.bordered).disabled(disabled)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct NativeProfileShowcase: View {
    let profile: [String: Any]
    let role: AccountRole

    private var name: String {
        let keys = ["companyName", "businessName", "fullName", "contactName"]
        if let value = keys.compactMap({ profile[$0] as? String }).first(where: { !$0.isEmpty }) { return value }
        return [profile["firstName"] as? String, profile["lastName"] as? String].compactMap { $0 }.joined(separator: " ")
    }

    private var photos: [String] {
        var values = ["logo", "photo", "profilePicture"].compactMap { profile[$0] as? String }
        values += (profile["photoUrls"] as? [String] ?? [])
        return values.filter { $0.hasPrefix("data:image/") || WixImageSource.url($0) != nil }
    }

    private var description: String? {
        ["description", "bio", "biography"].compactMap { profile[$0] as? String }.first { !$0.isEmpty }
    }

    private var serviceNames: [String] {
        (profile["services"] as? [String] ?? []).filter { !$0.isEmpty }
    }

    private var contactLinks: [(String, String, String)] {
        var links: [(String, String, String)] = []
        if let email = (profile["contactEmail"] as? String) ?? (profile["email"] as? String), !email.isEmpty {
            links.append(("E-mail", "envelope", "mailto:\(email)"))
        }
        if let phone = (profile["phoneNumber"] as? String) ?? (profile["phone"] as? String), !phone.isEmpty {
            let digits = phone.filter { $0.isNumber || $0 == "+" }
            links.append(("Appeler", "phone", "tel:\(digits)"))
        }
        if let website = (profile["website"] as? String) ?? (profile["websiteUrl"] as? String),
           let url = URL(string: website.hasPrefix("http") ? website : "https://\(website)") {
            links.append(("Site web", "globe", url.absoluteString))
        }
        return links
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 12) {
                if let source = photos.first {
                    NativeProfileImage(source: source, fallback: role.symbol)
                    .frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Image(systemName: role.symbol).font(.title2).foregroundStyle(.teal)
                        .frame(width: 62, height: 62).background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(name.isEmpty ? role.title : name).font(.headline)
                    Text([profile["professionalTitle"] as? String, profile["category"] as? String, profile["subcategory"] as? String,
                          profile["city"] as? String, profile["postalCode"] as? String]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let description {
                Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(5)
            }
            if !serviceNames.isEmpty {
                Text(serviceNames.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            if photos.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photos.dropFirst().enumerated()), id: \.offset) { _, url in
                            NativeProfileImage(source: url, fallback: "photo")
                            .frame(width: 100, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            if !contactLinks.isEmpty {
                HStack(spacing: 16) {
                    ForEach(Array(contactLinks.enumerated()), id: \.offset) { _, item in
            if let url = URL(string: item.2) {
                            Link(destination: url) { Label(item.0, systemImage: item.1).font(.caption.weight(.medium)) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
    }
}

private struct NativeProfileImage: View {
    let source: String
    let fallback: String

    private var inlineImage: UIImage? {
        guard source.hasPrefix("data:image/"), let comma = source.firstIndex(of: ",") else { return nil }
        let encoded = String(source[source.index(after: comma)...])
        guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        Group {
            if let image = inlineImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url = WixImageSource.url(source) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Image(systemName: fallback).foregroundStyle(.teal).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.teal.opacity(0.1)) }
                }
            } else {
                Image(systemName: fallback).foregroundStyle(.teal).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.teal.opacity(0.1))
            }
        }
        .clipped()
    }
}

private struct WixDashboardItem: View {
    let item: [String: Any]
    let fallbackTitle: String
    let onOpen: () -> Void

    private var title: String {
        if let score = item["matchingScore"] {
            return "Matching immobilier · \(String(describing: score)) %"
        }
        if let demand = item["demandType"] as? String, !demand.isEmpty {
            return "Demande · \(demand)"
        }
        return ["title", "itemName", "propertyTitle", "searchName", "businessName", "professionalName", "senderName", "fullName"]
            .compactMap { item[$0] as? String }.first ?? fallbackTitle
    }
    private var subtitle: String {
        ["city", "postalCode", "propertyType", "category", "status", "matchingType", "demandType"].compactMap { item[$0] as? String }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private var detail: String? {
        ["description", "itemDescription", "message", "messageContent", "content"].compactMap { item[$0] as? String }.first
    }
    private var imageURL: URL? {
        ["mainImageUrl", "mainImage", "itemImage", "photo"].compactMap { item[$0] as? String }.compactMap(WixImageSource.url).first
    }

    var body: some View {
        Button(action: onOpen) {
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
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Afficher le détail")
    }
}

private struct ReferralCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var service: ReferralService
    @State private var showForm = false
    @State private var confirmCandidate: [String: Any]?

    var body: some View {
        List {
            Section {
                Button { showForm = true } label: {
                    Label("Recommander un candidat", systemImage: "person.badge.plus")
                        .font(.headline)
                }
                Text("La candidature est envoyée au programme de parrainage existant. Le candidat sera contacté selon le processus PartenaireFoyer.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if service.isLoading {
                Section { HStack { Spacer(); ProgressView("Chargement des candidatures…"); Spacer() } }
            }
            if let error = service.errorMessage {
                Section("Information") {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button("Réessayer") { Task { await service.load() } }
                }
            }
            if let status = service.statusMessage {
                Section { Label(status, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }

            Section("Candidatures disponibles (\(service.candidates.count))") {
                if service.candidates.isEmpty && !service.isLoading && service.errorMessage == nil {
                    Text("Aucune candidature disponible pour votre espace.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(service.candidates.enumerated()), id: \.offset) { _, candidate in
                    ReferralCandidateRow(candidate: candidate) {
                        confirmCandidate = candidate
                    } onHide: {
                        Task { await service.update(action: "hide", candidateID: candidate["id"] as? String ?? "") }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Parrainage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Fermer") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await service.load() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Actualiser les candidatures")
            }
        }
        .task { await service.load() }
        .sheet(isPresented: $showForm) {
            NavigationStack { ReferralCandidateForm(service: service) }
        }
        .confirmationDialog("Attribuer ce contact à votre espace ?", isPresented: Binding(
            get: { confirmCandidate != nil }, set: { if !$0 { confirmCandidate = nil } }
        ), titleVisibility: .visible) {
            Button("Attribuer le contact") {
                guard let candidate = confirmCandidate,
                      let id = candidate["id"] as? String else { return }
                Task { await service.update(action: "claim", candidateID: id) }
                confirmCandidate = nil
            }
            Button("Annuler", role: .cancel) { confirmCandidate = nil }
        } message: {
            Text("Une attribution réussie affichera les coordonnées transmises par le candidat dans ce programme.")
        }
    }
}

private struct ReferralCandidateRow: View {
    let candidate: [String: Any]
    let onClaim: () -> Void
    let onHide: () -> Void

    private func text(_ key: String, fallback: String = "") -> String {
        (candidate[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallback
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(text("city", fallback: "Candidat immobilier"))
                    .font(.headline)
                Spacer()
                Text("\(candidate["placesRemaining"] as? Int ?? 0) places")
                    .font(.caption.weight(.semibold)).foregroundStyle(.teal)
            }
            Text([text("postalCode"), text("experience"), text("project")].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondary)
            if candidate["mine"] as? Bool == true {
                Text([text("firstName"), text("lastName")].filter { !$0.isEmpty }.joined(separator: " "))
                    .font(.subheadline.weight(.semibold))
                if !text("email").isEmpty { Label(text("email"), systemImage: "envelope").font(.caption) }
                if !text("phone").isEmpty { Label(text("phone"), systemImage: "phone").font(.caption) }
                if !text("message").isEmpty { Text(text("message")).font(.caption).foregroundStyle(.secondary) }
            } else {
                HStack {
                    Button("Attribuer", action: onClaim).buttonStyle(.borderedProminent)
                    Button("Masquer", action: onHide).buttonStyle(.bordered)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct ReferralCandidateForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var service: ReferralService
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var city = ""
    @State private var postalCode = ""
    @State private var experience = "debutant"
    @State private var project = "decouvrir"
    @State private var message = ""
    @State private var consent = false
    @State private var isSubmitting = false

    private var canSubmit: Bool {
        firstName.trimmingCharacters(in: .whitespaces).count >= 2 &&
        lastName.trimmingCharacters(in: .whitespaces).count >= 2 &&
        email.contains("@") && phone.filter(\.isNumber).count >= 8 &&
        city.trimmingCharacters(in: .whitespaces).count >= 2 && postalCode.count == 5 && consent
    }

    var body: some View {
        Form {
            Section("Coordonnées du candidat") {
                TextField("Prénom", text: $firstName).textContentType(.givenName)
                TextField("Nom", text: $lastName).textContentType(.familyName)
                TextField("Adresse e-mail", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Téléphone", text: $phone).keyboardType(.phonePad)
                TextField("Ville", text: $city)
                TextField("Code postal", text: $postalCode).keyboardType(.numberPad).onChange(of: postalCode) { _, value in postalCode = String(value.filter(\.isNumber).prefix(5)) }
            }
            Section("Projet immobilier") {
                Picker("Expérience", selection: $experience) {
                    Text("Débutant").tag("debutant")
                    Text("Déjà dans l’immobilier").tag("immobilier")
                    Text("Mandataire").tag("mandataire")
                }
                Picker("Projet", selection: $project) {
                    Text("Découvrir").tag("decouvrir")
                    Text("Démarrer").tag("demarrer")
                    Text("Changer de réseau").tag("changer-reseau")
                }
                TextField("Message (facultatif)", text: $message, axis: .vertical).lineLimit(3...6)
            }
            Section {
                Toggle("J’ai l’accord du candidat pour transmettre ses coordonnées.", isOn: $consent)
            } footer: {
                Text("Les coordonnées seront transmises au programme de parrainage pour recontacter le candidat.")
            }
            if let error = service.errorMessage {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            Section {
                Button {
                    isSubmitting = true
                    Task {
                        let success = await service.create(firstName: firstName, lastName: lastName, email: email,
                            phone: phone, city: city, postalCode: postalCode, experience: experience,
                            project: project, message: message, consent: consent)
                        isSubmitting = false
                        if success { dismiss() }
                    }
                } label: {
                    HStack { Spacer(); if isSubmitting { ProgressView() } else { Text("Envoyer la recommandation") }; Spacer() }
                }
                .disabled(!canSubmit || isSubmitting)
            }
        }
        .navigationTitle("Nouveau parrainage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Annuler") { dismiss() } } }
    }
}

private struct DashboardItemSelection: Identifiable {
    let id = UUID()
    let item: [String: Any]
}

private struct DashboardItemDetailView: View {
    let item: [String: Any]

    private let displayFields: [(String, String)] = [
        ("description", "Description"), ("itemDescription", "Description"),
        ("message", "Message"), ("messageContent", "Message"), ("content", "Message"),
        ("searchName", "Nom de la recherche"), ("propertyTitle", "Bien correspondant"),
        ("city", "Ville"), ("propertyCity", "Ville du bien"), ("postalCode", "Code postal"),
        ("propertyType", "Type de bien"), ("propertyTypes", "Types recherchés"), ("transactionType", "Transaction"),
        ("propertySurface", "Surface du bien"), ("minSurface", "Surface minimale"), ("maxSurface", "Surface maximale"),
        ("propertyPrice", "Prix du bien"), ("minBudget", "Budget minimum"), ("maxBudget", "Budget maximum"),
        ("radius", "Rayon (km)"), ("minRooms", "Pièces minimum"), ("minBedrooms", "Chambres minimum"),
        ("emailAlertsEnabled", "Alertes e-mail"), ("professionalName", "Professionnel"), ("professionalEmail", "E-mail du professionnel"),
        ("category", "Catégorie"), ("condition", "État"), ("status", "Statut"),
        ("matchingType", "Type de matching"), ("matchingScore", "Compatibilité"),
        ("demandType", "Type de demande"), ("seen", "Consulté"),
        ("senderEmail", "E-mail du contact"), ("senderPhone", "Téléphone du contact"),
        ("contactEmail", "E-mail"), ("phoneNumber", "Téléphone"),
        ("propertyId", "Bien associé"), ("acquereurId", "Acquéreur associé"),
        ("createdAt", "Reçu le"), ("notifiedAt", "Notification envoyée le")
    ]

    private var title: String {
        ["title", "itemName", "businessName", "senderName", "fullName"]
            .compactMap { item[$0] as? String }
            .first ?? "Détail"
    }

    private var imageURLs: [URL] {
        var values = ["mainImageUrl", "mainImage", "itemImage", "photo", "photo2", "photo3", "photo4", "photo5"]
            .compactMap { item[$0] as? String }
        values += item["photoUrls"] as? [String] ?? []
        values += item["galleryImages"] as? [String] ?? []
        return values.compactMap(WixImageSource.url)
    }

    private var rows: [(String, String)] {
        var seen = Set<String>()
        return displayFields.compactMap { key, label in
            guard let value = item[key], !(value is NSNull), !seen.contains(label) else { return nil }
            let text: String
            if let flag = value as? Bool {
                text = flag ? "Oui" : "Non"
            } else if let values = value as? [String] {
                text = values.joined(separator: ", ")
            } else {
                text = String(describing: value)
            }
            guard !text.isEmpty else { return nil }
            seen.insert(label)
            return (label, text)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !imageURLs.isEmpty {
                    TabView {
                        ForEach(Array(imageURLs.enumerated()), id: \.offset) { _, url in
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(Color.teal.opacity(0.08))
                                }
                            }
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("Galerie de photos")
                }

                Text(title).font(.title2.bold())

                if let price = item["price"] ?? item["itemPrice"] {
                    Text("\(String(describing: price)) €")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.teal)
                }

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.0).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(row.1).font(.body).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let email = ["senderEmail", "contactEmail", "email"].compactMap({ item[$0] as? String }).first,
                   let emailURL = URL(string: "mailto:\(email)") {
                    Link(destination: emailURL) { Label("Répondre par e-mail", systemImage: "envelope") }
                        .buttonStyle(.borderedProminent)
                }
                if let phone = ["senderPhone", "phoneNumber", "phone"].compactMap({ item[$0] as? String }).first {
                    let number = phone.filter { $0.isNumber || $0 == "+" }
                    if let phoneURL = URL(string: "tel:\(number)") {
                        Link(destination: phoneURL) { Label("Appeler le contact", systemImage: "phone") }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Détail")
        .navigationBarTitleDisplayMode(.inline)
    }
}
