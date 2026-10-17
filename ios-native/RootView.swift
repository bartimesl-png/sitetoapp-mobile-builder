Warning: truncated output (original token count: 31959)
Total output lines: 2658

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
                                Text("Faire estimer mon bien").font(.headline).foregroundStyle(.primary)
                                Text("Envoyez votre demande depuis l’app").font(.subheadline).foregroundStyle(.secondary)
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

                    Button { selectedTab = 4 } label: {
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
        .sheet(isPresented: $showNativeEstimation) {
            NavigationStack { NativeEstimationRequestView() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
                        .font(.system(size: 17, weight: .bold, desi…13959 tokens truncated…                      Task { await sendMessage() }
                    } label: {
                        if isSending { ProgressView() }
                        else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                    }
                    .disabled(isSending || composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Envoyer le message")
                }
                .padding(.horizontal).padding(.top, 8)
                if let email = preview["senderEmail"] as? String,
                   let url = URL(string: "mailto:\(email)") {
                    Link("Contacter aussi par e-mail", destination: url)
                        .font(.caption).padding(.bottom, 5)
                }
            }
            .background(.bar)
        }
        .navigationTitle(contactName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .alert("Envoi impossible", isPresented: Binding(
            get: { sendError != nil },
            set: { if !$0 { sendError = nil } }
        )) {
            Button("OK", role: .cancel) { sendError = nil }
        } message: {
            Text(sendError ?? "Réessayez dans un instant.")
        }
    }

    @MainActor
    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await auth.loadProfessionalConversation(id: conversationID)
            messages = loaded
            error = nil
            do {
                try await auth.markProfessionalConversationRead(conversationID: conversationID)
                messages = messages.map { message in
                    var updated = message
                    if (updated["receiverId"] as? String) == professionalID {
                        updated["isRead"] = true
                        updated["seen"] = true
                    }
                    return updated
                }
            } catch {
                // Keep the thread readable even if Wix declines the optional read receipt.
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func sendMessage() async {
        let content = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let sent = try await auth.sendProfessionalMessage(conversationID: conversationID, content: content)
            messages.append(sent)
            composerText = ""
        } catch {
            sendError = error.localizedDescription
        }
    }
}

private struct NativeEstimationRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var city = ""
    @State private var postalCode = ""
    @State private var propertyType = "Maison"
    @State private var propertyCondition = "Bon état"
    @State private var occupancyStatus = "Occupé par le propriétaire"
    @State private var projectTimeline = "Dans les 3 mois"
    @State private var livingArea = ""
    @State private var landArea = ""
    @State private var rooms = ""
    @State private var bedrooms = ""
    @State private var budget = ""
    @State private var consent = false
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        lastName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        email.contains("@") && email.contains(".") &&
        phone.filter(\.isNumber).count >= 8 &&
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        postalCode.count == 5 && postalCode.allSatisfy(\.isNumber) &&
        (number(livingArea) ?? 0) > 0 && consent
    }

    var body: some View {
        Form {
            Section {
                Label("Demande d’estimation", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.title3.bold())
                Text("Décrivez votre bien. Votre demande sera transmise à PartenaireFoyer pour être traitée selon le parcours d’estimation existant.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Vos coordonnées") {
                TextField("Prénom", text: $firstName).textContentType(.givenName)
                TextField("Nom", text: $lastName).textContentType(.familyName)
                TextField("Adresse e-mail", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Téléphone", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
            }

            Section("Le bien à estimer") {
                Picker("Type de bien", selection: $propertyType) {
                    ForEach(["Maison", "Appartement", "Terrain", "Immeuble", "Autre"], id: \.self) { Text($0) }
                }
                TextField("Adresse", text: $address)
                    .textContentType(.fullStreetAddress)
                TextField("Ville", text: $city)
                    .textContentType(.addressCity)
                TextField("Code postal", text: $postalCode)
                    .keyboardType(.numberPad)
                    .onChange(of: postalCode) { _, value in
                        postalCode = String(value.filter(\.isNumber).prefix(5))
                    }
                TextField("Surface habitable (m²)", text: $livingArea)
                    .keyboardType(.decimalPad)
                TextField("Surface du terrain (m²), facultatif", text: $landArea)
                    .keyboardType(.decimalPad)
                TextField("Nombre de pièces, facultatif", text: $rooms)
                    .keyboardType(.numberPad)
                TextField("Nombre de chambres, facultatif", text: $bedrooms)
                    .keyboardType(.numberPad)
                Picker("État général", selection: $propertyCondition) {
                    ForEach(["Neuf", "Très bon état", "Bon état", "À rafraîchir", "À rénover"], id: \.self) { Text($0) }
                }
                Picker("Occupation", selection: $occupancyStatus) {
                    ForEach(["Occupé par le propriétaire", "Loué", "Vacant"], id: \.self) { Text($0) }
                }
                Picker("Délai du projet", selection: $projectTimeline) {
                    ForEach(["Au plus vite", "Dans les 3 mois", "Dans les 6 mois", "Plus tard / information"], id: \.self) { Text($0) }
                }
                TextField("Budget souhaité, facultatif (€)", text: $budget)
                    .keyboardType(.decimalPad)
            }

            Section {
                Toggle("J’accepte que mes coordonnées et les informations du bien soient transmises pour traiter cette demande.", isOn: $consent)
                Text("Les informations sont envoyées à la collection Wix existante des demandes d’estimation. L’application n’affiche pas de valeur automatique et ne remplace pas l’avis d’un professionnel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section("Envoi impossible") {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            if didSubmit {
                Section {
                    Label("Votre demande a été transmise.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Vous pouvez fermer cet écran. L’équipe PartenaireFoyer pourra vous recontacter avec les coordonnées fournies.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting { ProgressView("Envoi…") }
                        else { Label("Envoyer ma demande", systemImage: "paperplane.fill").font(.headline) }
                        Spacer()
                    }
                }
                .disabled(!canSubmit || isSubmitting || didSubmit)
            } footer: {
                Text("Les champs marqués facultatifs peuvent rester vides. Le code postal doit comporter 5 chiffres.")
            }
        }
        .navigationTitle("Estimation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(didSubmit ? "Terminé" : "Fermer") { dismiss() }
            }
        }
    }

    private func number(_ value: String) -> Double? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await WixAuthStore.shared.submitEstimationRequest(
                firstName: firstName,
                lastName: lastName,
                email: email,
                phone: phone,
                address: address,
                city: city,
                postalCode: postalCode,
                propertyType: propertyType,
                propertyCondition: propertyCondition,
                occupancyStatus: occupancyStatus,
                projectTimeline: projectTimeline,
                livingArea: number(livingArea),
                landArea: number(landArea),
                rooms: number(rooms),
                bedrooms: number(bedrooms),
                budget: number(budget)
            )
            didSubmit = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NativeBuyerSearchForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var service: BuyerSearchService
    @State private var searchName = ""
    @State private var transactionType = "buy"
    @State private var selectedTypes: Set<String> = ["Maison"]
    @State private var city = ""
    @State private var postalCode = ""
    @State private var radius = 10.0
    @State private var minBudget = ""
    @State private var maxBudget = ""
    @State private var minSurface = ""
    @State private var maxSurface = ""
    @State private var minRooms = ""
    @State private var minBedrooms = ""
    @State private var emailAlertsEnabled = false
    private let propertyTypes = ["Maison", "Appartement", "Immeuble", "Terrain", "Commerce", "Bureau", "Mas", "Autre"]

    private var canSubmit: Bool {
        searchName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        (!city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || postalCode.count == 5) &&
        !selectedTypes.isEmpty && radius >= 1 && radius <= 100 &&
        validRange(minBudget, maxBudget) && validRange(minSurface, maxSurface)
    }

    var body: some View {
        Form {
            Section {
                Label("Nouvelle recherche immobilière", systemImage: "sparkles")
                    .font(.title3.bold())
                Text("Cette recherche sera enregistrée dans votre compte Wix et alimentera les matchings liés aux biens correspondants.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Recherche") {
                TextField("Nom de la recherche", text: $searchName)
                    .textInputAutocapitalization(.sentences)
                Picker("Projet", selection: $transactionType) {
                    Text("Acheter").tag("buy")
                    Text("Louer").tag("rent")
                }
                TextField("Ville", text: $city).textContentType(.addressCity)
                TextField("Code postal", text: $postalCode)
                    .keyboardType(.numberPad)
                    .onChange(of: postalCode) { _, value in
                        postalCode = String(value.filter(\.isNumber).prefix(5))
                    }
                Stepper("Rayon : \(Int(radius)) km", value: $radius, in: 1...100, step: 1)
            }
            Section("Types de biens") {
                ForEach(propertyTypes, id: \.self) { type in
                    Toggle(type, isOn: Binding(
                        get: { selectedTypes.contains(type) },
                        set: { enabled in
                            if enabled { selectedTypes.insert(type) }
                            else { selectedTypes.remove(type) }
                        }
                    ))
                }
            }
            Section("Critères (facultatifs)") {
                TextField("Budget minimum (€)", text: $minBudget).keyboardType(.decimalPad)
                TextField("Budget maximum (€)", text: $maxBudget).keyboardType(.decimalPad)
                TextField("Surface minimale (m²)", text: $minSurface).keyboardType(.decimalPad)
                TextField("Surface maximale (m²)", text: $maxSurface).keyboardType(.decimalPad)
                TextField("Pièces minimum", text: $minRooms).keyboardType(.numberPad)
                TextField("Chambres minimum", text: $minBedrooms).keyboardType(.numberPad)
            }
            Section {
                Toggle("Recevoir les alertes par e-mail", isOn: $emailAlertsEnabled)
                Text("Vous pourrez désactiver cette recherche depuis le tableau de bord.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error = service.errorMessage {
                Section("Enregistrement impossible") {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if service.isSubmitting { ProgressView("Enregistrement…") }
                        else { Label("Créer ma recherche", systemImage: "checkmark.circle.fill").font(.headline) }
                        Spacer()
                    }
                }
                .disabled(!canSubmit || service.isSubmitting)
            }
        }
        .navigationTitle("Nouvelle recherche")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
    }

    private func number(_ value: String, defaultValue: Double = 0) -> Double {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return normalized.isEmpty ? defaultValue : (Double(normalized) ?? -1)
    }

    private func optionalNumber(_ value: String) -> Double? {
        let parsed = number(value, defaultValue: -1)
        return parsed < 0 ? nil : parsed
    }

    private func validRange(_ low: String, _ high: String) -> Bool {
        let lower = number(low)
        let upper = optionalNumber(high)
        return lower >= 0 && (upper == nil || upper! == 0 || lower <= upper!)
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        let success = await service.create(
            searchName: searchName,
            transactionType: transactionType,
            propertyTypes: propertyTypes.filter { selectedTypes.contains($0) },
            city: city,
            postalCode: postalCode,
            radius: radius,
            minBudget: number(minBudget),
            maxBudget: number(maxBudget),
            minSurface: number(minSurface),
            maxSurface: optionalNumber(maxSurface),
            minRooms: number(minRooms),
            minBedrooms: number(minBedrooms),
            emailAlertsEnabled: emailAlertsEnabled
        )
        if success { dismiss() }
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
                    } onSwitchSpace: {
                        auth.resetDashboard()
                        activeRoleRaw = ""
                    }
                } else {
                    rolePicker
                }
            }
            .navigationTitle("Mon espace")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: activeRoleRaw) {
                guard activeRoleRaw == AccountRole.particulier.rawValue,
                      auth.member != nil else { return }
                await FavoritesStore.shared.syncFromWix()
            }
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
                        Button { select(role) } label: {
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

    private func select(_ role: AccountRole) {
        // Keep the role spaces distinct while allowing a signed-in Wix member to
        // move between their own linked spaces without entering their password again.
        if auth.member != nil {
            auth.resetDashboard()
            activeRoleRaw = role.rawValue
            selectedRole = nil
        } else {
            selectedRole = role
        }
    }
}

private enum AccountRole: String, CaseIterable, Identifiable {
    case particulier, professionnel, courtier, artisan, diagnostiqueur, prestataire, hebergeur
    var id: String { rawValue }
    var title: String {
        switch self {
        case .particulier: "Particulier"
        case .professionnel: "Professionnel de l’immobilier"
        case .courtier: "Courtier"
        case .artisan: "Artisan / diagnostiqueur"
        case .diagnostiqueur: "Diagnostiqueur"
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
        case .diagnostiqueur: "Mes diagnostics et demandes reçues"
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
        case .diagnostiqueur: "doc.text.magnifyingglass"
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
    var dashboardQueryRole: String {
        rawValue
    }
    private var loginPath: String {
        switch self {
        case .particulier: "/vendeur-login"
        case .professionnel: "/pro-app-login"
        case .courtier: "/broker-login"
        case .artisan: "/artisan-login"
        case .diagnostiqueur: "/artisan-login"
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
        case .diagnostiqueur: "/artisan-signup"
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
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var city = ""
    @State private var postalCode = ""
    @State private var companyName = ""
    @State private var category = ""
    @State private var subcategory = ""
    @State private var description = ""
    @State private var website = ""
    @State private var professionalTitle = ""
    @State private var yearsOfExperience = ""
    @State private var professionalType = "mandataire"
    @State private var acceptedTerms = false
    @State private var isCreatingAccount = false
    let role: AccountRole
    let onSignedIn: () -> Void
    var initialProfile: [String: Any]? = nil
    var isEditing: Bool = false

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

                if isCreatingAccount {
                    Section(isEditing ? "Modifier mon profil Wix" : "Créer votre compte Wix") {
                        if !isEditing {
                            TextField("Prénom", text: $firstName)
                                .textContentType(.givenName)
                                .textInputAutocapitalization(.words)
                            TextField("Nom", text: $lastName)
                                .textContentType(.familyName)
                                .textInputAutocapitalization(.words)
                            TextField("Adresse e-mail", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            SecureField("Mot de passe (8 caractères minimum)", text: $password)
                                .textContentType(.newPassword)
                        }
                        TextField("Téléphone", text: $phone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                        roleRegistrationFields
                        if !isEditing {
                            Toggle("J’accepte les conditions générales de PartenaireFoyer et sa politique de confidentialité.", isOn: $acceptedTerms)
                            Link(destination: AppConfig.privacyURL) {
                                Label("Consulter la politique de confidentialité", systemImage: "hand.raised")
                            }
                        }
                    }
                } else {
                    Section("Connexion à votre compte") {
                    TextField("Adresse e-mail", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Mot de passe", text: $password)
                        .textContentType(.password)
                    }
                }

                if let error = auth.errorMessage {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }

                if let message = auth.infoMessage {
                    Section {
                        Label(message, systemImage: "envelope.badge")
                            .font(.footnote).foregroundStyle(.teal)
                    }
                }

                Section {
                    Button {
                        Task {
                            if isCreatingAccount {
                                let profile: [String: String] = [
                                    "firstName": firstName,
                                    "lastName": lastName,
                                    "phone": phone,
                                    "city": city,
                                    "postalCode": postalCode,
                                    "companyName": companyName,
                                    "contactName": "\(firstName) \(lastName)",
                                    "category": category,
                                    "subcategory": subcategory,
                                    "description": description,
                                    "website": website,
                                    "professionalTitle": professionalTitle,
                                    "yearsOfExperience": yearsOfExperience,
                                    "professionalType": professionalType
                                ]
                                let didComplete = await auth.signUp(
                                    email: email,
                                    password: password,
                                    firstName: firstName,
                                    lastName: lastName,
                                    role: role.rawValue,
                                    profile: profile
                                )
                                if didComplete { onSignedIn() }
                            } else {
                                await auth.signIn(email: email, password: password)
                                if auth.member != nil { onSignedIn() }
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                                    Label(isEditing ? "Enregistrer les modifications" : (isCreatingAccount ? "Créer mon compte" : "Se connecter"),
                                  systemImage: isEditing ? "checkmark.circle" : (isCreatingAccount ? "person.badge.plus" : "lock.shield"))
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!isEditing && password.isEmpty) || auth.isSigningIn || (isCreatingAccount && !isEditing && !acceptedTerms))

                    if !isEditing {
                        Button {
                            isCreatingAccount.toggle()
                            auth.errorMessage = nil
                        } label: {
                            Label(isCreatingAccount ? "J’ai déjà un compte : me connecter" : "Créer un compte", systemImage: "person.crop.circle.badge.plus")
                        }
                        .disabled(auth.isSigningIn)
                    }
                } footer: {
                    Text(isEditing
                         ? "Les informations sont mises à jour dans la fiche Wix associée à votre espace."
                         : (isCreatingAccount
                         ? "Votre compte est créé par l’authentification Wix sécurisée. Le mot de passe n’est pas conservé par l’application."
                         : "La connexion passe par l’authentification Wix sécurisée. Le mot de passe n’est pas conservé par l’application."))
                }
            }
            .navigationTitle("Accès à l’espace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
            .onAppear {
                guard let initialProfile else { return }
                isCreatingAccount = isEditing
                email = auth.member?.loginEmail ?? (initialProfile["email"] as? String ?? "")
                let profileName = (initialProfile["contactName"] as? String)
                    ?? (initialProfile["fullName"] as? String)
                    ?? (initialProfile["companyName"] as? String)
                    ?? (initialProfile["businessName"] as? String)
                    ?? ""
                let nameParts = profileName.split(separator: " ", maxSplits: 1).map(String.init)
                firstName = auth.member?.firstName ?? (initialProfile["firstName"] as? String ?? nameParts.first ?? "")
                lastName = auth.member?.lastName ?? (initialProfile["lastName"] as? String ?? nameParts.dropFirst().first ?? "")
                phone = (initialProfile["phone"] as? String) ?? (initialProfile["phoneNumber"] as? String ?? "")
                city = initialProfile["city"] as? String ?? ""
                postalCode = initialProfile["postalCode"] as? String ?? ""
                companyName = (initialProfile["companyName"] as? String)
                    ?? (initialProfile["businessName"] as? String)
                    ?? (role == .hebergeur ? (initialProfile["fullName"] as? String) : nil)
                    ?? ""
                category = initialProfile["category"] as? String ?? ""
                subcategory = initialProfile["subcategory"] as? String ?? ""
                description = (initialProfile["description"] as? String) ?? (initialProfile["biography"] as? String ?? "")
                website = (initialProfile["website"] as? String) ?? (initialProfile["websiteUrl"] as? String ?? "")
                professionalTitle = initialProfile["professionalTitle"] as? String ?? ""
                if let years = initialProfile["yearsOfExperience"] { yearsOfExperience = String(describing: years) }
                professionalType = initialProfile["professionalType"] as? String ?? "mandataire"
                acceptedTerms = true
            }
        }
    }

    @ViewBuilder
    private var roleRegistrationFields: some View {
        switch role {
        case .particulier:
            TextField("Ville (facultatif)", text: $city).textContentType(.addressCity)
            TextField("Code postal (facultatif)", text: $postalCode).keyboardType(.numberPad)
        case .professionnel:
            TextField("Société / réseau", text: $companyName)
            Picker("Profil professionnel", selection: $professionalType) {
                Text("Mandataire immobilier").tag("mandataire")
                Text("Agence immobilière").tag("agency")
            }
            TextField("Activité", text: $category)
            TextField("Ville", text: $city).textContentType(.addressCity)
            TextField("Code postal", text: $postalCode).keyboardType(.numberPad)
            TextField("Site internet (facultatif)", text: $website).keyboardType(.URL).textInputAutocapitalization(.never)
        case .courtier:
            TextField("Spécialité / titre professionnel", text: $professionalTitle)
            TextField("Ville", text: $city).textContentType(.addressCity)
            TextField("Années d’expérience (facultatif)", text: $yearsOfExperience).keyboardType(.numberPad)
            TextField("Site internet (facultatif)", text: $website).keyboardType(.URL).textInputAutocapitalization(.never)
        case .artisan, .diagnostiqueur, .prestataire:
            TextField("Entreprise", text: $companyName)
            if role == .artisan {
                TextField("Activité artisanale", text: $subcategory)
                TextField("Activité", text: $category).disabled(true).onAppear { category = "Artisan" }
            } else if role == .diagnostiqueur {
                TextField("Spécialité (DPE, amiante…)", text: $subcategory)
                TextField("Activité", text: $category).disabled(true).onAppear { category = "Diagnostiqueur" }
            } else {
                TextField("Activité", text: $category)
                TextField("Spécialité (facultatif)", text: $subcategory)
            }
            TextField("Ville", text: $city).textContentType(.addressCity)
            TextField("Code postal", text: $postalCode).keyboardType(.numberPad)
            TextField("Présentation (facultatif)", text: $description, axis: .vertical).lineLimit(3...6)
            TextField("Site internet (facultatif)", text: $website).keyboardType(.URL).textInputAutocapitalization(.never)
        case .hebergeur:
            TextField("Nom de l’hébergement / activité", text: $companyName)
            TextField("Présentation (facultatif)", text: $description, axis: .vertical).lineLimit(3...6)
        }
    }
}

private struct NativeRoleDashboardView: View {
    @StateObject private var auth = WixAuthStore.shared
    @StateObject private var referralService = ReferralService()
    @StateObject private var professionalImportService = ProfessionalImportService()
    @StateObject private var buyerSearchService = BuyerSearchService()
    @State private var selectedItem: DashboardItemSelection?
    @State private var selectedConversation: DashboardConversationSelection?
    @State private var showReferralCenter = false
    @State private var showImportCenter = false
    @State private var showBuyerSearchForm = false
    @State private var showProfileEditor = false
    let role: AccountRole
    let member: WixMember
    let onSignOut: () -> Void
    let onSwitchSpace: () -> Void

    private var sections: [(String, String, [[String: Any]])] {
        guard let data = auth.dashboardData else { return [] }
        let keys: [(String, String, String)]
        switch role {
        case .particulier:
            keys = [
                ("Mes biens", "house", "properties"),
                ("Mes petites annonces", "tag", "classifieds"),
                ("Mes favoris", "heart", "favorites"),
                ("Mes recherches", "magnifyingglass", "savedSearches"),
                ("Matchings reçus", "sparkles", "buyerMatchings")
            ]
        case .professionnel:
            keys = [("Mes biens", "house", "properties"), ("Mes matchings", "sparkles", "matchings"), ("Demandes reçues", "person.2", "demands"), ("Messages", "bubble.left.and.bubble.right", "messages")]
        case .courtier:
            keys = [("Messages", "bubble.left.and.bubble.right", "messages")]
        case .artisan:
            keys = [("Demandes d’intervention", "bubble.left.and.bubble.right", "messages")]
        case .diagnostiqueur:
            keys = [("Demandes de diagnostic", "doc.text.magnifyingglass", "messages")]
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
                    Button("Réessayer") { Task { await auth.loadDashboard(role: role.dashboardQueryRole) } }
                }
            } else if let data = auth.dashboardData {
                Section("Vue d’ensemble") {
                    DashboardOverview(data: data, role: role)
                }
                if let profile {
                    Section("Mon profil") {
                        NativeProfileShowcase(profile: profile, role: role)
                        ForEach(Array(profileKeys(for: role).filter { profile[$0.1] != nil }.enumerated()), id: \.offset) { _, field in
                            LabeledContent(field.0, value: display(profile[field.1]))
                        }
                        Button {
                            showProfileEditor = true
                        } label: {
                            Label("Modifier mon profil", systemImage: "pencil")
                        }
                    }
                }
                if role == .professionnel, let profile {
                    Section("Abonnement professionnel") {
                        let active = (profile["hasActiveSubscription"] as? Bool) == true
                        Label(active ? "Abonnement actif" : display(profile["subscriptionStatus"]),
                              systemImage: active ? "checkmark.seal.fill" : "creditcard")
                            .foregroundStyle(active ? Color.green : Color.secondary)
                        if profile["subscriptionStartDate"] != nil {
                            LabeledContent("Début", value: display(profile["subscriptionStartDate"]))
                        }
                        if profile["subscriptionEndDate"] != nil {
                            LabeledContent("Échéance", value: display(profile["subscriptionEndDate"]))
                        }
                        Text("Le statut affiché est synchronisé avec votre espace PartenaireFoyer. La gestion des paiements reste sécurisée par le service de paiement existant.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let account = data["account"] as? [String: Any],
                   account["cguAccepted"] != nil || account["cgvAccepted"] != nil {
                    Section("Documents du compte") {
                        if account["cguAccepted"] != nil {
                            LabeledContent("Conditions d’utilisation", value: display(account["cguAccepted"]))
                        }
                        if account["cgvAccepted"] != nil {
                            LabeledContent("Conditions de vente", value: display(account["cgvAccepted"]))
                        }
                    }
                }
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    Section {
                        if role == .particulier, section.0 == "Mes recherches" {
                            Button { showBuyerSearchForm = true } label: {
                                Label("Créer une recherche", systemImage: "plus.circle.fill")
                                    .font(.headline)
                            }
                            if let message = buyerSearchService.statusMessage {
                                Label(message, systemImage: "checkmark.circle.fill")
                                    .font(.footnote).foregroundStyle(.green)
                            }
                            if let error = buyerSearchService.errorMessage {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                        }
                        if section.2.isEmpty {
                            Text("Aucun élément pour le moment.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(section.2.enumerated()), id: \.offset) { index, item in
                                WixDashboardItem(item: item, fallbackTitle: "Élément \(index + 1)") {
                                        if role == .professionnel, section.0 == "Messages",
                                           let conversationID = item["conversationId"] as? String,
                                           !conversationID.isEmpty {
                                            selectedConversation = DashboardConversationSelection(id: conversationID, preview: item)
                                        } else {
                                            selectedItem = DashboardItemSelection(item: item)
                                        }
                                }
                                .swipeActions {
                                    if role == .particulier, section.0 == "Mes recherches",
                                       let searchID = (item["_id"] as? String) ?? (item["id"] as? String) {
                                        Button("Désactiver", role: .destructive) {
                                            Task { await buyerSearchService.deactivate(searchID: searchID) }
                                        }
                                    }
                                    if role == .professionnel,
                                       section.0 == "Mes matchings" || section.0 == "Demandes reçues",
                                       let itemID = (item["_id"] as? String) ?? (item["id"] as? String),
                                       item["seen"] as? Bool != true || (section.0 == "Demandes reçues" && item["isViewed"] as? Bool != true) {
                                        Button("Marquer comme vu", systemImage: "eye") {
                                            Task {
                                                await auth.markMatchingSeen(
                                                    list: section.0 == "Mes matchings" ? "matchings" : "demands",
                                                    itemID: itemID
                                                )
                                            }
                                        }
                                        .tint(.teal)
                                    }
                                    if [.courtier, .artisan, .diagnostiqueur, .prestataire].contains(role),
                                       section.0.contains("Messages") || section.0.contains("Demandes"),
                                       let messageID = (item["_id"] as? String) ?? (item["id"] as? String),
                                       item["isRead"] as? Bool != true {
                                        Button("Marquer comme lu", systemImage: "envelope.open") {
                                            Task { await auth.markInquiryRead(role: role.rawValue, messageID: messageID) }
                                        }
                                        .tint(.teal)
                                    }
                                }
                            }
                        }
                    } header: {
                        let unread = section.2.filter { $0["isRead"] as? Bool == false }.count
                        Label(unread > 0 ? "\(section.0) (\(section.2.count) · \(unread) non lus)" : "\(section.0) (\(section.2.count))",
                              systemImage: section.1)
                    }
                }
                if role == .professionnel {
                    Section("Mes annonces importées") {
                        Button { showImportCenter = true } label: {
                            Label("Gérer les imports de mon réseau", systemImage: "arrow.down.doc")
                        }
                        Text("Autorisation de republication, import automatique et visibilité des biens.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Développer mon réseau") {
                        Button {
                            showReferralCenter = true
                        } label: {
                            Label("Parrainage de mandataires", systemImage: "person.3.sequence.fill")
                        }
                        Text("Consultez les candidatures, attribuez un contact ou recommandez un futur mandataire.")
                            .font(.footnote).foregroundStyle(.secondary)
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
                Button(action: onSwitchSpace) {
                    Label("Changer d’espace", systemImage: "person.2")
                }
                Button(role: .destructive, action: onSignOut) {
                    Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Tableau de bord")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedItem) { selection in
            NavigationStack {
                DashboardItemDetailView(item: selection.item)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fermer") { selectedItem = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedConversation) { selection in
            NavigationStack {
                NativeProfessionalConversationView(
                    conversationID: selection.id,
                    preview: selection.preview,
                    professionalID: (auth.dashboardData?["profile"] as? [String: Any])?["_id"] as? String ?? ""
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer") { selectedConversation = nil }
                    }
                }
            }
        }
        .sheet(isPresented: $showReferralCenter) {
            NavigationStack {
                ReferralCenterView(service: referralService)
            }
        }
        .sheet(isPresented: $showBuyerSearchForm) {
            NavigationStack {
                NativeBuyerSearchForm(service: buyerSearchService)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showProfileEditor) {
            RoleEntryView(role: role, onSignedIn: {
                showProfileEditor = false
                Task { await auth.loadDashboard(role: role.dashboardQueryRole) }
            }, initialProfile: profile, isEditing: true)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showImportCenter) {
            NavigationStack {
                ProfessionalImportCenterView(service: professionalImportService)
            }
        }
        .refreshable { await auth.loadDashboard(role: role.dashboardQueryRole) }
        .task(id: role.rawValue) {
            await auth.loadDashboard(role: role.dashboardQueryRole)
            await auth.registerPushDevice(role: role.rawValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .partenaireFoyerFCMTokenDidChange)) { _ in
            Task { await auth.registerPushDevice(role: role.rawValue) }
        }
    }

    private func profileKeys(for role: AccountRole) -> [(String, String)] {
        switch role {
        case .particulier: [("Prénom", "firstName"), ("Nom", "lastName"), ("Ville", "city"), ("Téléphone", "phone")]
        case .professionnel: [("Société", "companyName"), ("Contact", "contactName"), ("Ville", "city"), ("Code postal", "postalCode"), ("Téléphone", "phoneNumber"), ("Type d’activité", "professionalType"), ("Catégories", "categories"), ("Visible publiquement", "isVisiblePublicly")]
        case .courtier: [("Nom", "fullName"), ("Titre", "professionalTitle"), ("Ville", "city"), ("Téléphone", "phoneNumber"), ("Expérience (ans)", "yearsOfExperience")]
        case .artisan, .diagnostiqueur, .prestataire: [("Entreprise", "businessName"), ("Activité", "category"), ("Spécialité", "subcategory"), ("Ville", "city"), ("Code postal", "postalCode"), ("Téléphone", "phone"), ("Vérifié", "verified"), ("Statut", "status")]
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

private struct DashboardConversationSelection: Identifiable {
    let id: String
    let preview: [String: Any]
}

private struct NativeProfessionalConversationView: View {
    @StateObject private var auth = WixAuthStore.shared
    @State private var messages: [[String: Any]] = []
    @State private var error: String?
    @State private var sendError: String?
    @State private var composerText = ""
    @State private var isLoading = false
    @State private var isSending = false
    let conversationID: String
    let preview: [String: Any]
    let professionalID: String

    private var contactName: String {
        [preview["senderName"] as? String, preview["senderEmail"] as? String]
            .compactMap { $0 }.first(where: { !$0.isEmpty }) ?? "Votre contact"
    }

    var body: some View {
        Group {
            if isLoading && messages.isEmpty {
                ProgressView("Chargement de la conversation…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, messages.isEmpty {
                ContentUnavailableView {
                    Label("Conversation indisponible", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                } description: {
                    Text(error)
                } actions: {
                    Button("Réessayer") { Task { await reload() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if messages.isEmpty {
                ContentUnavailableView("Aucun message", systemImage: "bubble.left.and.bubble.right")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                                let outgoing = (message["senderId"] as? String) == professionalID
                                HStack {
                                    if outgoing { Spacer(minLength: 42) }
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text((message["content"] as? String) ?? "")
                                            .font(.body).textSelection(.enabled)
                                        if let date = message["createdAt"] as? String, !date.isEmpty {
                                            Text(date).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(12)
                                    .background(outgoing ? Color.teal.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground),
                                                in: RoundedRectangle(cornerRadius: 16))
                                    if !outgoing { Spacer(minLength: 42) }
                                }
                                .id(index)
                            }
                        }
                        .padding(16)
                    }
                    .refreshable { await reload() }
                    .onChange(of: messages.count) { _, count in
                        if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Écrire un message…", text: $composerText, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityLabel("Votre message")
                    Button {
                        Task { await sendMessage() }
                    } label: {
                        if isSending { ProgressView() }
                        else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                    }
                    .disabled(isSending || composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Envoyer le message")
                }
                .padding(.horizontal).padding(.top, 8)
                if let email = preview["senderEmail"] as? String,
                   let url = URL(string: "mailto:\(email)") {
                    Link("Contacter aussi par e-mail", destination: url)
                        .font(.caption).padding(.bottom, 5)
                }
            }
            .background(.bar)
        }
        .navigationTitle(contactName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .alert("Envoi impossible", isPresented: Binding(
            get: { sendError != nil },
            set: { if !$0 { sendError = nil } }
        )) {
            Button("OK", role: .cancel) { sendError = nil }
        } message: {
            Text(sendError ?? "Réessayez dans un instant.")
        }
    }

    @MainActor
    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await auth.loadProfessionalConversation(id: conversationID)
            messages = loaded
            error = nil
            do {
                try await auth.markProfessionalConversationRead(conversationID: conversationID)
                messages = messages.map { message in
                    var updated = message
                    if (updated["receiverId"] as? String) == professionalID {
                        updated["isRead"] = true
                        updated["seen"] = true
                    }
                    return updated
                }
            } catch {
                // Keep the thread readable even if Wix declines the optional read receipt.
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func sendMessage() async {
        let content = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let sent = try await auth.sendProfessionalMessage(conversationID: conversationID, content: content)
            messages.append(sent)
            composerText = ""
        } catch {
            sendError = error.localizedDescription
        }
    }
}

private struct DashboardOverview: View {
    let data: [String: Any]
    let role: AccountRole

    private var metrics: [(String, String, String)] {
        switch role {
        case .particulier:
            [("Biens", "properties", "house.fill"), ("Petites annonces", "classifieds", "tag.fill"), ("Favoris", "favorites", "heart.fill")]
        case .professionnel:
            [("Biens", "properties", "house.fill"), ("Matchings", "matchings", "sparkles"), ("Demandes", "demands", "person.2.fill"), ("Messages", "messages", "bubble.left.and.bubble.right.fill")]
        case .courtier:
            [("Messages", "messages", "bubble.left.and.bubble.right.fill")]
        case .artisan:
            [("Demandes", "messages", "wrench.and.screwdriver.fill")]
        case .diagnostiqueur:
            [("Demandes", "messages", "doc.text.magnifyingglass")]
        case .prestataire:
            [("Contacts", "messages", "person.2.fill")]
        case .hebergeur:
            []
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
        ("category", "Catégorie"), ("subcategory", "Sous-catégorie"), ("condition", "État"), ("itemCondition", "État"), ("status", "Statut"),
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
        var values = [
            "mainImageUrl", "mainImage", "itemImage", "photo",
            "photo2", "photo3", "photo4", "photo5", "photo6", "photo7", "photo8", "photo9", "photo10",
            "photo11", "photo12", "photo13", "photo14", "photo15", "photo16", "photo17", "photo18", "photo19", "photo20",
        ]
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
