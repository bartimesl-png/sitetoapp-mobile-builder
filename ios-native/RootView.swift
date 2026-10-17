Warning: truncated output (original token count: 99591)
Total output lines: 7565

Warning: truncated output (original token count: 31959)
Total output lines: 2658

import SwiftUI
import CoreFoundation
import PhotosUI
import UIKit
import SafariServices

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

            NativeListingsView(service: listingsService, classifiedAds: classifiedAdsService, professionalsService: professionalsService)
                .tabItem { Label("Annonces", systemImage: "magnifyingglass") }
                .tag(1)

            NativeSeasonalStaysView()
                .tabItem { Label("Séjours", systemImage: "bed.double") }
                .tag(2)

            NativeProfessionalsView(service: professionalsService)
                .tabItem { Label("Professionnels", systemImage: "person.2") }
                .tag(3)

            NativeFavoritesView(service: listingsService, classifiedAds: classifiedAdsService, professionalsService: professionalsService)
                .tabItem { Label("Favoris", systemImage: "heart.fill") }
                .tag(4)

            NativeSpacePickerView()
                .tabItem { Label("Menu", systemImage: "line.3.horizontal") }
                .tag(5)
        }
        .tint(Color(red: 0.02, green: 0.38, blue: 0.34))
    }
}

private struct NativeSeasonalStaysView: View {
    @State private var accommodations: [WixSeasonalAccommodation] = []
    @State private var searchText = ""
    @State private var selectedType = "Tous"
    @State private var guests = 1
    @State private var petsOnly = false
    @State private var sortByPrice = false
    @State private var minimumPrice = ""
    @State private var maximumPrice = ""
    @State private var minimumBedrooms = ""
    @State private var checkInDate: Date?
    @State private var checkOutDate: Date?
    @State private var calendarEntries: [WixSeasonalCalendarEntry] = []
    @State private var calendarWarning: String?
    @State private var isLoadingCalendar = false
    @State private var showFilters = false
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private var accommodationTypes: [String] {
        ["Tous"] + Array(Set(accommodations.compactMap { $0.accommodationType?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted()
    }

    private var filtered: [WixSeasonalAccommodation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let minPrice = Double(minimumPrice.replacingOccurrences(of: ",", with: "."))
        let maxPrice = Double(maximumPrice.replacingOccurrences(of: ",", with: "."))
        let minBeds = Int(minimumBedrooms)
        let blockedDates = blockedCalendarDatesByAccommodation
        let matches = accommodations.filter { accommodation in
            let text = [accommodation.name, accommodation.accommodationType, accommodation.city,
                        accommodation.postalCode, accommodation.department, accommodation.description,
                        accommodation.amenities].compactMap { $0 }.joined(separator: " ")
            return (query.isEmpty || text.localizedCaseInsensitiveContains(query)) &&
                (selectedType == "Tous" || accommodation.accommodationType == selectedType) &&
                ((accommodation.guestCapacity ?? guests) >= guests) &&
                (!petsOnly || accommodation.petsAllowed) &&
                (minPrice.map { min in accommodation.nightlyPrice.map { $0 >= min } ?? false } ?? true) &&
                (maxPrice.map { max in accommodation.nightlyPrice.map { $0 <= max } ?? false } ?? true) &&
                (minBeds.map { min in accommodation.bedroomCount.map { $0 >= min } ?? false } ?? true) &&
                isAvailable(accommodation.id, blockedDates: blockedDates)
        }
        return sortByPrice ? matches.sorted { ($0.nightlyPrice ?? .greatestFiniteMagnitude) < ($1.nightlyPrice ?? .greatestFiniteMagnitude) } : matches
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && accommodations.isEmpty {
                    ProgressView("Chargement des séjours…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, accommodations.isEmpty {
                    ContentUnavailableView {
                        Label("Séjours indisponibles", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Réessayer") { Task { await load() } }.buttonStyle(.borderedProminent)
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        Section {
                            if let calendarWarning {
                                Label(calendarWarning, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                            HStack {
                                Label("\(filtered.count) hébergement\(filtered.count > 1 ? "s" : "")", systemImage: "bed.double")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Spacer()
                                if isLoading { ProgressView().controlSize(.small) }
                            }
                        }
                        ForEach(filtered) { accommodation in
                            NavigationLink(value: accommodation.id) {
                                SeasonalAccommodationRow(accommodation: accommodation)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                    .navigationDestination(for: String.self) { id in
                        if let accommodation = accommodations.first(where: { $0.id == id }) {
                            NativeSeasonalAccommodationDetail(accommodation: accommodation)
                        }
                    }
                }
            }
            .navigationTitle("Séjours saisonniers")
            .searchable(text: $searchText, prompt: "Destination, ville, hébergement…")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        Image(systemName: selectedType == "Tous" && guests == 1 && !petsOnly && !sortByPrice && minimumPrice.isEmpty && maximumPrice.isEmpty && minimumBedrooms.isEmpty
                              && checkInDate == nil && checkOutDate == nil
                              ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filtrer les séjours")
                }
            }
            .sheet(isPresented: $showFilters) {
                NavigationStack {
                    Form {
                        Section("Destination et logement") {
                            Picker("Type d’hébergement", selection: $selectedType) {
                                ForEach(accommodationTypes, id: \.self) { Text($0).tag($0) }
                            }
                            Stepper("Voyageurs : \(guests)", value: $guests, in: 1...30)
                            Toggle("Animaux acceptés", isOn: $petsOnly)
                            Toggle("Trier par prix", isOn: $sortByPrice)
                        }
                        Section("Budget et chambres") {
                            TextField("Prix minimum par nuit (€)", text: $minimumPrice).keyboardType(.decimalPad)
                            TextField("Prix maximum par nuit (€)", text: $maximumPrice).keyboardType(.decimalPad)
                            TextField("Chambres minimum", text: $minimumBedrooms).keyboardType(.numberPad)
                        }
                        Section("Dates du séjour") {
                            DatePicker("Arrivée", selection: arrivalBinding, in: Calendar.current.startOfDay(for: Date())...Date.distantFuture, displayedComponents: .date)
                            DatePicker("Départ", selection: departureBinding, in: earliestDeparture...Date.distantFuture, displayedComponents: .date)
                            if checkInDate != nil || checkOutDate != nil {
                                Button("Effacer les dates", role: .destructive) {
                                    checkInDate = nil
                                    checkOutDate = nil
                                    calendarEntries = []
                                    calendarWarning = nil
                                }
                            }
                            if isLoadingCalendar {
                                HStack { ProgressView(); Text("Vérification des disponibilités…").font(.footnote).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    .navigationTitle("Filtres des séjours")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { Button("Fermer") { showFilters = false } }
                        ToolbarItem(placement: .topBarTrailing) { Button("Terminé") { showFilters = false } }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: checkInDate) { _, _ in Task { await loadAvailabilityIfSelected() } }
            .onChange(of: checkOutDate) { _, _ in Task { await loadAvailabilityIfSelected() } }
            .task { if !hasLoaded { await load() } }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false; hasLoaded = true }
        do {
            accommodations = try await WixAuthStore.shared.fetchPublicSeasonalAccommodations()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var arrivalBinding: Binding<Date> {
        Binding(
            get: { checkInDate ?? Calendar.current.startOfDay(for: Date()) },
            set: { value in
                checkInDate = value
                if let checkOutDate, checkOutDate <= value {
                    self.checkOutDate = Calendar.current.date(byAdding: .day, value: 1, to: value)
                }
            }
        )
    }

    private var earliestDeparture: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: checkInDate ?? Calendar.current.startOfDay(for: Date()))
            ?? Date().addingTimeInterval(86_400)
    }

    private var validDateRange: (Date, Date)? {
        guard let checkInDate, let checkOutDate, checkOutDate > checkInDate else { return nil }
        return (checkInDate, checkOutDate)
    }

    @MainActor
    private func loadAvailabilityIfSelected() async {
        guard validDateRange != nil else {
            calendarEntries = []
            calendarWarning = nil
            return
        }
        isLoadingCalendar = true
        defer { isLoadingCalendar = false }
        do {
            calendarEntries = try await WixAuthStore.shared.fetchPublicSeasonalCalendarEntries()
            calendarWarning = nil
        } catch {
            calendarWarning = "Les disponibilités ne se chargent pas. Confirmez les dates dans le calendrier avant toute demande."
        }
    }

    private var blockedCalendarDatesByAccommodation: [String: Set<String>] {
        let blocked = Set(["unavailable", "pending", "reserved", "booked", "blocked", "external"])
        var grouped: [String: Set<String>] = [:]
        for entry in calendarEntries where blocked.contains(entry.availabilityStatus.lowercased()) {
            if let key = localDateKey(from: entry.calendarDate) {
                grouped[entry.accommodationID, default: []].insert(key)
            }
        }
        return grouped
    }

    private func isAvailable(_ accommodationID: String, blockedDates: [String: Set<String>]) -> Bool {
        guard let (checkIn, checkOut) = validDateRange, calendarWarning == nil else { return true }
        let blockedKeys = blockedDates[accommodationID] ?? []
        var night = Calendar.current.startOfDay(for: checkIn)
        while night < checkOut {
            if blockedKeys.contains(localDateKey(for: night)) { return false }
            guard let nextNight = Calendar.current.date(byAdding: .day, value: 1, to: night) else { break }
            night = nextNight
        }
        return true
    }

    private func localDateKey(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func localDateKey(from rawDate: String) -> String? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: rawDate)
            ?? ISO8601DateFormatter().date(from: rawDate)
            ?? dateFromDayString(rawDate)
        guard let date else { return nil }
        return localDateKey(for: date)
    }

    private func dateFromDayString(_ rawDate: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(rawDate.prefix(10)))
    }
}

private struct SeasonalAccommodationRow: View {
    let accommodation: WixSeasonalAccommodation

    var body: some View {
        HStack(spacing: 14) {
            if let url = accommodation.gallery.first {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12).fill(Color.teal.opacity(0.12))
                        .overlay { Image(systemName: "house.lodge").foregroundStyle(.teal) }
                }
                .frame(width: 92, height: 92).clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12).fill(Color.teal.opacity(0.12))
                    .overlay { Image(systemName: "house.lodge").foregroundStyle(.teal) }
                    .frame(width: 92, height: 92)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(accommodation.name).font(.headline).lineLimit(2)
                if let type = accommodation.accommodationType, !type.isEmpty {
                    Text(type).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if !accommodation.locationLabel.isEmpty {
                    Label(accommodation.locationLabel, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 10) {
                    if let capacity = accommodation.guestCapacity { Label("\(capacity)", systemImage: "person.2") }
                    Text(accommodation.formattedPrice).fontWeight(.semibold).foregroundStyle(.teal)
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct NativeSeasonalAccommodationDetail: View {
    let accommodation: WixSeasonalAccommodation
    @State private var showHostedBooking = false

    private var amenities: [String] {
        guard let raw = accommodation.amenities?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return [] }
        if let data = raw.data(using: .utf8),
           let values = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return values.filter { !$0.isEmpty }
        }
        if let data = raw.data(using: .utf8),
           let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return values.filter { ($0.value as? Bool) == true }.map(\.key).sorted()
        }
        return raw.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" }).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var bookingURL: URL? {
        let slug = accommodation.slug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pathID = slug.isEmpty ? accommodation.id : slug
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard let pathComponent = pathID.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://www.partenairefoyer.com/location-saisonniere/\(pathComponent)")
    }

    var body: some View {
        List {
            if !accommodation.gallery.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(accommodation.gallery, id: \.self) { url in
                                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                                    RoundedRectangle(cornerRadius: 14).fill(Color.teal.opacity(0.12))
                                }
                                .frame(width: 280, height: 190).clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
            Section {
                Text(accommodation.name).font(.title2.bold())
                if let type = accommodation.accommodationType, !type.isEmpty {
                    Label(type, systemImage: "house.lodge").foregroundStyle(.teal)
                }
                if !accommodation.locationLabel.isEmpty {
                    Label(accommodation.locationLabel, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary)
                }
                Text(accommodation.formattedPrice).font(.headline).foregroundStyle(.teal)
            }
            Section("Le logement") {
                if let guests = accommodation.guestCapacity { LabeledContent("Capacité", value: "\(guests) voyageurs") }
                if let bedrooms = accommodation.bedroomCount { LabeledContent("Chambres", value: "\(bedrooms)") }
                if let minimumStay = accommodation.minimumStay { LabeledContent("Séjour minimum", value: "\(minimumStay) nuit\(minimumStay > 1 ? "s" : "")") }
                LabeledContent("Animaux", value: accommodation.petsAllowed ? "Acceptés" : "Non indiqué comme acceptés")
            }
            if let description = accommodation.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                Section("Description") { Text(description).textSelection(.enabled) }
            }
            if !amenities.isEmpty {
                Section("Équipements et services") {
                    ForEach(amenities, id: \.self) { Label($0, systemImage: "checkmark.circle") }
                }
            }
            if let latitude = accommodation.latitude, let longitude = accommodation.longitude,
               let url = URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)") {
                Section { Link(destination: url) { Label("Voir la zone dans Plans", systemImage: "map") } }
            }
            Section("Dates et réservation") {
                Text("Vérifiez les disponibilités et envoyez votre demande à l’hébergeur.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let bookingURL {
                    Button { showHostedBooking = true } label: {
                        Label("Ouvrir le calendrier de réservation", systemImage: "calendar.badge.clock")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .sheet(isPresented: $showHostedBooking) {
                        NavigationStack { InAppSafariView(url: bookingURL) }
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
                Text("La vérification des dates et l’envoi de la demande s’effectuent sur le parcours sécurisé du site, dans cette fenêtre.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Hébergement")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NativeProfessionalsView: View {
    @ObservedObject var service: ProfessionalsService
    @State private var searchText = ""
    @State private var selectedDirectoryType = "Tous"
    private let directoryTypes = ["Tous", "Immobilier", "Profils locaux", "Courtiers", "Importés"]

    private var filtered: [WixPublicProfessional] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return service.professionals.filter { professional in
            let matchesType: Bool
            switch selectedDirectoryType {
            case "Immobilier":
                matchesType = professional.importedCategory == "immobilier" ||
                    (professional.importedCategory == nil && !professional.isLocalProsProfile)
            case "Profils locaux":
                matchesType = professional.isLocalProsProfile ||
                    ["artisan", "diagnostiqueur"].contains(professional.importedCategory ?? "")
            case "Courtiers":
                matchesType = professional.importedCategory == "courtier"
            case "Importés":
                matchesType = professional.importedID != nil
            default:
                matchesType = true
            }
            guard matchesType else { return false }
            guard !query.isEmpty else { return true }
            return professional.resolvedName.localizedCaseInsensitiveContains(query) ||
            (professional.city ?? "").localizedCaseInsensitiveContains(query) ||
            (professional.postalCode ?? "").localizedCaseInsensitiveContains(query) ||
            (professional.resolvedActivity ?? "").localizedCaseInsensitiveContains(query) ||
            (professional.description ?? "").localizedCaseInsensitiveContains(query)
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
                } else if filtered.isEmpty, let warning = service.warningMessage {
                    VStack(spacing: 12) {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                        ContentUnavailableView.search(text: searchText)
                    }
                    .padding()
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        if let warning = service.warningMessage {
                            Section {
                                Label(warning, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Section {
                            ForEach(filtered) { professional in
                                NavigationLink(value: professional.id) {
                                    ProfessionalRow(professional: professional)
                                }
                                .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                            }
                        }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Type de professionnel", selection: $selectedDirectoryType) {
                            ForEach(directoryTypes, id: \.self) { Text($0).tag($0) }
                        }
                    } label: {
                        Image(systemName: selectedDirectoryType == "Tous" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filtrer les professionnels : \(selectedDirectoryType)")
                }
            }
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
    @ObservedObject private var auth = WixAuthStore.shared
    @State private var showImportedContact = false
    @State private var selectedMinisiteRequest: String?
    @State private var isFavorite = false
    @State private var isUpdatingFavorite = false
    @State private var favoriteError: String?

    private var favoriteRecordID: String? {
        guard !professional.isLocalProsProfile,
              professional.importedID == nil,
              professional.importedCategory != "courtier" else { return nil }
        return professional.cmsProfileID
    }

    private var favoriteType: String {
        switch professional.importedCategory {
        case "artisan": return "artisan"
        case "diagnostiqueur": return "diagnostiqueur"
        default: return "agent"
        }
    }

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

            if let favoriteRecordID {
                Section("Professionnel favori") {
                    if auth.member?.loginEmailVerified == true {
                        Button {
                            Task { await toggleFavorite(id: favoriteRecordID) }
                        } label: {
                            HStack {
                                Label(isFavorite ? "Retirer de mes favoris" : "Ajouter à mes favoris",
                                      systemImage: isFavorite ? "heart.fill" : "heart")
                                Spacer()
                                if isUpdatingFavorite { ProgressView().controlSize(.small) }
                            }
                        }
                        .disabled(isUpdatingFavorite)
                        .tint(isFavorite ? .pink : .teal)
                    } else {
                        Label("Connectez-vous depuis l’onglet Menu avec une adresse vérifiée pour enregistrer cette fiche.",
                              systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let favoriteError {
                        Text(favoriteError).font(.footnote).foregroundStyle(.red)
                    }
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
            if professional.importedCategory == "courtier" {
                Section("Profil courtier") {
                    if let years = professional.experienceYears, !years.isEmpty {
                        LabeledContent("Expérience", value: "\(years) ans")
                    }
                    if let types = professional.network, !types.isEmpty {
                        LabeledContent("Spécialités", value: types)
                    }
                    if let email = professional.professionalEmail,
                       let url = mailtoURL(email) {
                        Link(destination: url) { Label("Envoyer un e-mail", systemImage: "envelope") }
                    }
                    if let phone = professional.publicPhone {
                        let dialable = phone.filter { $0.isNumber || $0 == "+" }
                        if !dialable.isEmpty, let url = URL(string: "tel:\(dialable)") {
                            Link(destination: url) { Label("Appeler le courtier", systemImage: "phone") }
                        }
                    }
                }
            }
            if let importedID = professional.importedID,
               let category = professional.importedCategory {
                Section {
                    Button { showImportedContact = true } label: {
                        Label("Envoyer une demande de contact", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                } footer: {
                    Text("Vos coordonnées sont transmises par le formulaire sécurisé PartenaireFoyer. Les coordonnées privées de cette fiche ne sont pas exposées.")
                }
                .sheet(isPresented: $showImportedContact) {
                    NavigationStack {
                        ImportedProfessionalContactForm(proId: importedID, category: category, professionalName: professional.resolvedName)
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
            if professional.isLocalProsProfile {
                Section("Coordonnées professionnelles") {
                    if let phone = professional.publicPhone,
                       let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                        Link(destination: url) { Label("Appeler le professionnel", systemImage: "phone") }
                    }
                    if let email = professional.professionalEmail,
                       let url = URL(string: "mailto:\(email)") {
                        Link(destination: url) { Label("Envoyer un e-mail", systemImage: "envelope") }
                    }
                }
            }
            if professional.importedCategory != "courtier" && professional.importedID == nil && !professional.isLocalProsProfile {
                Section("Contacter ce professionnel") {
                    Button { selectedMinisiteRequest = "contact" } label: {
                        Label("Envoyer un message", systemImage: "message")
                    }
                    Button { selectedMinisiteRequest = "estimation" } label: {
                        Label("Demander une estimation", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    Button { selectedMinisiteRequest = "proposition" } label: {
                        Label("Proposer un bien à vendre", systemImage: "house")
                    }
                }
                .sheet(isPresented: Binding(
                    get: { selectedMinisiteRequest != nil },
                    set: { if !$0 { selectedMinisiteRequest = nil } }
                )) {
                    if let requestType = selectedMinisiteRequest {
                        NavigationStack {
                            ProfessionalMinisiteRequestForm(
                                professional: professional,
                                requestType: requestType
                            )
                        }
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Fiche professionnelle")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: auth.member?.id) { await loadFavoriteStatus() }
    }

    @MainActor
    private func loadFavoriteStatus() async {
        guard let favoriteRecordID, auth.member?.loginEmailVerified == true else {
            isFavorite = false
            favoriteError = nil
            return
        }
        do {
            isFavorite = try await auth.isProfessionalFavorite(favoriteRecordID)
            favoriteError = nil
        } catch {
            favoriteError = error.localizedDescription
        }
    }

    @MainActor
    private func toggleFavorite(id: String) async {
        isUpdatingFavorite = true
        favoriteError = nil
        defer { isUpdatingFavorite = false }
        do {
            isFavorite = try await auth.toggleProfessionalFavorite(id, professionalType: favoriteType)
        } catch {
            favoriteError = error.localizedDescription
        }
    }

    private func mailtoURL(_ email: String) -> URL? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.range(of: #"^[A-Z0-9a-z.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = trimmed
        return components.url
    }
}

private struct PrivatePropertyContactForm: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var auth = WixAuthStore.shared
    let listing: Listing
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var errorMessage: String?

    private var canSend: Bool {
        auth.member?.loginEmailVerified != false && auth.member != nil &&
        firstName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        lastName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
    }

    var body: some View {
        Form {
            Section("Annonce") {
                Text(listing.title ?? "Annonce immobilière").font(.headline)
                if !listing.locationLabel.isEmpty { Label(listing.locationLabel, systemImage: "mappin.and.ellipse") }
                Text("Votre adresse e-mail vérifiée sera utilisée pour permettre au propriétaire de vous répondre. Elle ne sera pas affichée dans l’annonce.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let member = auth.member {
                Section("Vos coordonnées") {
                    TextField("Prénom", text: $firstName).textContentType(.givenName)
                    TextField("Nom", text: $lastName).textContentType(.familyName)
                    LabeledContent("E-mail", value: member.loginEmail)
                    TextField("Téléphone (facultatif)", text: $phone)
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                }
            } else {
                Section {
                    Label("Connectez-vous depuis l’onglet Menu avec une adresse vérifiée pour envoyer un message.", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
            Section("Votre message") {
                TextField("Écrivez au propriétaire…", text: $message, axis: .vertical).lineLimit(4...8)
            }
            if let errorMessage {
                Section("Envoi impossible") { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            if didSend {
                Section { Label("Votre message a été envoyé au propriétaire.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            Section {
                Button { Task { await send() } } label: {
                    HStack { Spacer(); if isSending { ProgressView("Envoi…") } else { Label("Envoyer au propriétaire", systemImage: "paperplane.fill") }; Spacer() }
                }
                .buttonStyle(.borderedProminent).tint(.teal)
                .disabled(!canSend || isSending || didSend)
            }
        }
        .navigationTitle("Contacter le propriétaire")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(didSend ? "Terminé" : "Fermer") { dismiss() } } }
        .task {
            if let member = auth.member {
                if firstName.isEmpty { firstName = member.firstName ?? "" }
                if lastName.isEmpty { lastName = member.lastName ?? "" }
            }
        }
    }

    @MainActor private func send() async {
        guard canSend, !isSending, let id = listing.id.split(separator: "-", maxSplits: 2).last.map(String.init) else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await auth.submitPrivatePropertyContactRequest(
                listingID: id, firstName: firstName, lastName: lastName,
                phone: phone, message: message
            )
            didSend = true
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ProfessionalMinisiteRequestForm: View {
    @Environment(\.dismiss) private var dismiss
    let professional: WixPublicProfessional
    let requestType: String
    var listingContext: Listing? = nil
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var propertyType = "Maison"
    @State private var address = ""
    @State private var city = ""
    @State private var postalCode = ""
    @State private var price = ""
    @State private var livingArea = ""
    @State private var landArea = ""
    @State private var rooms = ""
    @State private var bedrooms = ""
    @State private var condition = "Bon état"
    @State private var timeline = "Dans les 3 mois"
    @State private var message = ""
    @State private var sending = false
    @State private var sent = false
    @State private var emailWarning = false
    @State private var error: String?
    @State private var propertyContactRequestID = UUID().uuidString.lowercased()
    @State private var propertyContactMessage = ""
    @State private var isRetryingPropertyContactArchive = false

    private var title: String {
        requestType == "contact" ? "Demande de contact" : requestType == "estimation" ? "Demande d’estimation" : "Proposer un bien"
    }
    private var canSend: Bool {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        lastName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && email.contains("@") &&
        (requestType == "contact" || phone.filter(\.isNumber).count >= 8) &&
        (requestType == "contact" ? message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 :
            !address.isEmpty && !city.isEmpty && postalCode.count == 5 && postalCode.allSatisfy(\.isNumber))
    }

    var body: some View {
        Form {
            Section {
                Label(
                    listingContext.map { "\(title) · \($0.title ?? "Annonce immobilière")" } ?? "\(title) auprès de \(professional.resolvedName)",
                    systemImage: "paperplane"
                )
                    .font(.headline)
                Text(listingContext == nil
                     ? "La demande sera enregistrée dans l’espace professionnel. Une notification push et un e-mail seront tentés après l’enregistrement."
                     : "Votre message sera envoyé par e-mail au professionnel et copié dans sa rubrique de contacts sur cette annonce.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Vos coordonnées") {
                TextField("Prénom", text: $firstName).textContentType(.givenName)
                TextField("Nom", text: $lastName).textContentType(.familyName)
                TextField("E-mail", text: $email).textContentType(.emailAddress)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField(requestType == "contact" ? "Téléphone (facultatif)" : "Téléphone", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
            }
            if requestType != "contact" {
                Section("Le bien") {
                    Picker("Type de bien", selection: $propertyType) {
                        ForEach(["Maison", "Appartement", "Terrain", "Immeuble", "Commerce", "Autre"], id: \.self) { Text($0) }
                    }
                    TextField("Adresse", text: $address).textContentType(.fullStreetAddress)
                    TextField("Ville", text: $city).textContentType(.addressCity)
                    TextField("Code postal", text: $postalCode).keyboardType(.numberPad)
                        .onChange(of: postalCode) { _, value in postalCode = String(value.filter(\.isNumber).prefix(5)) }
                    TextField(requestType == "proposition" ? "Prix souhaité (€)" : "Budget souhaité (€), facultatif", text: $price).keyboardType(.decimalPad)
                    TextField("Surface habitable (m²)", text: $livingArea).keyboardType(.decimalPad)
                    TextField("Surface du terrain (m²)", text: $landArea).keyboardType(.decimalPad)
                    TextField("Nombre de pièces", text: $rooms).keyboardType(.numberPad)
                    TextField("Nombre de chambres", text: $bedrooms).keyboardType(.numberPad)
                    Picker("État du bien", selection: $condition) {
                        ForEach(["Neuf", "Très bon état", "Bon état", "À rafraîchir", "À rénover"], id: \.self) { Text($0) }
                    }
                    Picker("Délai du projet", selection: $timeline) {
                        ForEach(["Au plus vite", "Dans les 3 mois", "Dans les 6 mois", "Plus tard"], id: \.self) { Text($0) }
                    }
                }
            }
            Section("Votre message") {
                TextField(requestType == "contact" ? "Votre message…" : "Précisions, facultatif…", text: $message, axis: .vertical)
                    .lineLimit(4...8)
            }
            if let error { Section("Envoi impossible") { Text(error).foregroundStyle(.red).font(.footnote) } }
            if sent {
                Section {
                    Label(listingContext == nil ? "La demande a été enregistrée." : "Votre message a été envoyé.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    if emailWarning {
                        Text(listingContext == nil
                             ? "La demande est conservée, mais l’e-mail de notification n’a pas été confirmé."
                             : "Le message est envoyé par e-mail, mais sa copie dans les contacts de l’annonce n’a pas été confirmée.")
                            .font(.footnote).foregroundStyle(.orange)
                        if let listingContext, listingContext.id.hasPrefix("wix-pro-") {
                            Button {
                                Task { await retryPropertyContactArchive(listingContext: listingContext) }
                            } label: {
                                if isRetryingPropertyContactArchive {
                                    ProgressView("Enregistrement…")
                                } else {
                                    Label("Réessayer la copie sans renvoyer l’e-mail", systemImage: "arrow.clockwise")
                                }
                            }
                            .disabled(isRetryingPropertyContactArchive)
                        }
                    }
                }
            }
            Section {
                Button { Task { await submit() } } label: {
                    HStack { Spacer(); if sending { ProgressView("Envoi…") } else { Label("Envoyer la demande", systemImage: "paperplane.fill") }; Spacer() }
                }.disabled(!canSend || sending || sent)
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(sent ? "Terminé" : "Fermer") { dismiss() } } }
    }

    private func value(_ raw: String) -> Double? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        return normalized.isEmpty ? nil : Double(normalized)
    }

    @MainActor private func submit() async {
        guard canSend, !sending else { return }
        sending = true; error = nil
        defer { sending = false }
        var property: [String: Any] = [:]
        if requestType == "contact", let listingContext {
            let propertyID: String
            if listingContext.id.hasPrefix("wix-pro-") {
                propertyID = String(listingContext.id.dropFirst("wix-pro-".count))
            } else if listingContext.id.hasPrefix("wix-private-") {
                propertyID = String(listingContext.id.dropFirst("wix-private-".count))
            } else {
                propertyID = listingContext.id
            }
            property = [
                "propertyId": propertyID,
                "propertyTitle": listingContext.title ?? "Annonce immobilière",
                "propertyCity": listingContext.city ?? "",
                "propertyPostalCode": listingContext.postalCode ?? "",
                "propertyType": listingContext.propertyType ?? "",
                "transactionType": listingContext.transactionType ?? "",
            ]
            if let price = listingContext.price { property["propertyPrice"] = price }
            if let surface = listingContext.surface { property["propertySurface"] = surface }
            if let landSurface = listingContext.landSurface { property["landArea"] = landSurface }
        }
        if requestType != "contact" {
            property = [
                "propertyType": propertyType, "location": city, "address": address, "postalCode": postalCode,
                "propertyCondition": condition, "availabilityTimeline": timeline
            ]
            if let v = value(price) { property[requestType == "proposition" ? "desiredPrice" : "minBudget"] = v }
            if let v = value(livingArea) { property["livingArea"] = v }
            if let v = value(landArea) { property["landArea"] = v }
            if let v = value(rooms) { property["numberOfRooms"] = v }
            if let v = value(bedrooms) { property["numberOfBedrooms"] = v }
        }
        var note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if requestType == "contact", let listingContext {
            let details = [
                "Bien concerné : \(listingContext.title ?? "Annonce immobilière")",
                listingContext.locationLabel.isEmpty ? nil : "Localisation : \(listingContext.locationLabel)",
                listingContext.formattedPrice,
            ].compactMap { $0 }.joined(separator: "\n")
            note = "\(details)\n\n\(note)"
        }
        if requestType != "contact" {
            let details = [
                "Bien : \(propertyType)", "Adresse : \(address)", "Ville : \(city) (\(postalCode))",
                value(price).map { "Prix / budget : \($0.formatted(.number.locale(Locale(identifier: "fr_FR")))) €" },
                value(livingArea).map { "Surface habitable : \($0) m²" },
                value(landArea).map { "Terrain : \($0) m²" },
                value(rooms).map { "Pièces : \(Int($0))" },
                value(bedrooms).map { "Chambres : \(Int($0))" },
                "État : \(condition)", "Délai : \(timeline)"
            ].compactMap { $0 }.joined(separator: "\n")
            note = note.isEmpty ? details : "\(details)\n\n\(note)"
        }
        if requestType == "estimation" && note.isEmpty {
            note = "Estimation rapide - Type: \(propertyType)"
        }
        do {
            if requestType == "contact",
               let listingContext,
               listingContext.id.hasPrefix("wix-pro-") {
                guard let recipientEmail = professional.professionalEmail,
                      recipientEmail.contains("@") else {
                    throw AuthError.api("L’e-mail du professionnel n’est pas disponible pour cette annonce.")
                }
                let listingID = String(listingContext.id.dropFirst("wix-pro-".count))
                propertyContactMessage = note
                emailWarning = !(try await WixAuthStore.shared.submitProfessionalPropertyContactRequest(
                    listingID: listingID,
                    propertyTitle: listingContext.title ?? "Annonce immobilière",
                    recipientEmail: recipientEmail,
                    recipientName: professional.resolvedName,
                    firstName: firstName,
                    lastName: lastName,
                    email: email,
                    phone: phone,
                    message: note,
                    requestID: propertyContactRequestID
                ))
                sent = true
                return
            }
            emailWarning = try await WixAuthStore.shared.submitProfessionalMinisiteRequest(
                professionalID: professional.cmsProfileID ?? professional.id, professionalName: professional.resolvedName,
                professionalEmail: professional.professionalEmail, requestType: requestType,
                firstName: firstName, lastName: lastName, email: email, phone: phone,
                message: note, propertyFields: property
            ) == false
            sent = true
        } catch { self.error = error.localizedDescription }
    }

    @MainActor private func retryPropertyContactArchive(listingContext: Listing) async {
        guard !isRetryingPropertyContactArchive,
              listingContext.id.hasPrefix("wix-pro-"),
              !propertyContactMessage.isEmpty else { return }
        isRetryingPropertyContactArchive = true
        defer { isRetryingPropertyContactArchive = false }
        let listingID = String(listingContext.id.dropFirst("wix-pro-".count))
        let archived = await WixAuthStore.shared.archiveProfessionalPropertyContactRequest(
            listingID: listingID,
            firstName: firstName,
            lastName: lastName,
            email: email,
            phone: phone,
            message: propertyContactMessage,
            requestID: propertyContactRequestID
        )
        emailWarning = !archived
    }
}

private struct ImportedProfessionalContactForm: View {
    @Environment(\.dismiss) private var dismiss
    let proId: String
    let category: String
    let professionalName: String
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var message = ""
    @State private var sending = false
    @State private var sent = false
    @State private var notificationWarning = false
    @State private var error: String?

    private var canSend: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        email.contains("@") && message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }

    var body: some View {
        Form {
            Section {
                Label("Contacter \(professionalName)", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline)
                Text("Votre demande sera transmise via le formulaire sécurisé PartenaireFoyer.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Vos coordonnées") {
                TextField("Nom et prénom", text: $name).textContentType(.name)
                TextField("Adresse e-mail", text: $email).textContentType(.emailAddress)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Téléphone (facultatif)", text: $phone).keyboardType(.phonePad)
            }
            Section("Votre message") {
                TextField("Expliquez votre demande…", text: $message, axis: .vertical).lineLimit(5...10)
            }
            if let error { Section("Envoi impossible") { Text(error).foregroundStyle(.red).font(.footnote) } }
            if sent { Section { Label("Votre message a été envoyé.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            if notificationWarning { Section { Label("La demande est enregistrée, mais l’invitation e-mail n’a pas pu être envoyée. Contactez PartenaireFoyer pour le suivi.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.footnote) } }
            Section {
                Button { Task { await submit() } } label: {
                    HStack { Spacer(); if sending { ProgressView("Envoi…") } else { Label("Envoyer le message", systemImage: "paperplane.fill") }; Spacer() }
                }.disabled(!canSend || sending || sent)
            }
        }
        .navigationTitle("Demande de contact")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(sent ? "Terminé" : "Fermer") { dismiss() } } }
    }

    @MainActor private func submit() async {
        guard canSend, !sending else { return }
        sending = true; error = nil
        defer { sending = false }
        do {
            let delivered = try await WixAuthStore.shared.contactImportedProfessional(
                id: proId, category: category, senderName: name, senderEmail: email,
                senderPhone: phone, message: message
            )
            notificationWarning = !delivered
            sent = true
        } catch { self.error = error.localizedDescription }
    }
}

private struct ImportedListingContactForm: View {
    @Environment(\.dismiss) private var dismiss
    let listing: Listing
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var message = ""
    @State private var sending = false
    @State private var sent = false
    @State private var notificationWarning = false
    @State private var error: String?

    private var canSend: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        email.contains("@") && email.split(separator: "@").last?.contains(".") == true &&
        message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
    }

    var body: some View {
        Form {
            Section {
                Label("Demande concernant \(listing.title ?? "ce bien")", systemImage: "house")
                    .font(.headline)
                Text("Vos coordonnées ne sont pas publiées. La demande est conservée dans le parcours sécurisé PartenaireFoyer et une invitation est transmise au professionnel pour la consulter dans son espace.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Vos coordonnées") {
                TextField("Nom et prénom", text: $name).textContentType(.name).textInputAutocapitalization(.words)
                TextField("Adresse e-mail", text: $email).textContentType(.emailAddress)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Téléphone (facultatif)", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
            }
            Section("Votre message") {
                TextField("Décrivez votre demande au sujet de ce bien…", text: $message, axis: .vertical).lineLimit(5...10)
            }
            if let error { Section("Envoi impossible") { Text(error).foregroundStyle(.red).font(.footnote) } }
            if sent { Section { Label("Votre demande a été enregistrée.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            if notificationWarning { Section { Label("La demande est enregistrée, mais l’invitation e-mail n’a pas pu être envoyée. Contactez PartenaireFoyer pour le suivi.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.footnote) } }
            Section {
                Button { Task { await submit() } } label: {
                    HStack { Spacer(); if sending { ProgressView("Envoi…") } else { Label("Envoyer ma demande", systemImage: "paperplane.fill") }; Spacer() }
                }
                .disabled(!canSend || sending || sent)
            }
        }
        .navigationTitle("Contacter le professionnel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(sent ? "Terminé" : "Fermer") { dismiss() } } }
    }

    @MainActor private func submit() async {
        guard canSend, !sending, listing.canContactImportedProfessional,
              let professionalID = listing.importedProId else { return }
        sending = true; error = nil
        defer { sending = false }
        do {
            let delivered = try await WixAuthStore.shared.contactImportedProfessional(
                id: professionalID,
                category: "immobilier",
                senderName: name,
                senderEmail: email,
                senderPhone: phone,
                message: message,
                listingID: listing.id
            )
            notificationWarning = !delivered
            sent = true
        } catch { self.error = error.localizedDescription }
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
    @ObservedObject var professionalsService: ProfessionalsService
    @ObservedObject private var favorites = FavoritesStore.shared
    @State private var searchText = ""
    @State private var catalogSection: NativeCatalogSection = .realEstate
    @State private var showPropertyFilters = false
    @State private var showClassifiedFilters = false
    @State private var propertyTypeFilter = "Tous"
    @State private var propertyTransactionFilter = "Tous"
    @State private var propertyMinPrice = ""
    @State private var propertyMaxPrice = ""
    @State private var propertyMinSurface = ""
    @State private var propertyMaxSurface = ""
    @State private var propertyMinLandSurface = ""
    @State private var propertyMinRooms = ""
    @State private var propertyMinBedrooms = ""
    @State private var propertyMinBathrooms = ""
    @State private var propertyCity = ""
    @State private var propertyPostalCode = ""
    @State private var propertySort = "Ordre du catalogue"
    @State private var classifiedCategory = "Toutes"
    @State private var classifiedSubcategory = "Toutes"
    @State private var classifiedListingType = "Tous"
    @State private var classifiedCondition = "Tous"
    @State private var classifiedAttributeKey = "Aucun"
    @State private var classifiedAttributeValue = ""
    @State private var classifiedCity = ""
    @State private var classifiedPostalCode = ""
    @State private var classifiedMinPrice = ""
    @State private var classifiedMaxPrice = ""
    @State private var classifiedBrand = ""
    @State private var classifiedModel = ""
    @State private var classifiedYearMin = ""
    @State private var classifiedYearMax = ""
    @State private var classifiedMileageMax = ""
    @State private var classifiedEnergy = ""
    @State private var classifiedGearbox = ""
    @State private var classifiedSort = "Ordre du catalogue"

    private var filteredListings: [Listing] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = propertyCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let postal = propertyPostalCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let minPrice = Double(propertyMinPrice.replacingOccurrences(of: ",", with: "."))
        let maxPrice = Double(propertyMaxPrice.replacingOccurrences(of: ",", with: "."))
        let minSurface = Double(propertyMinSurface.replacingOccurrences(of: ",", with: "."))
        let maxSurface = Double(propertyMaxSurface.replacingOccurrences(of: ",", with: "."))
        let minLandSurface = Double(propertyMinLandSurface.replacingOccurrences(of: ",", with: "."))
        let minRooms = Int(propertyMinRooms)
        let minBedrooms = Int(propertyMinBedrooms)
        let minBathrooms = Int(propertyMinBathrooms)
        let filtered = service.listings.filter { listing in
            let transaction = (listing.transactionType ?? "").lowercased()
            let isSale = ["sale", "vente", "sell"].contains(transaction)
            let isRent = ["rent", "location", "rental"].contains(transaction)
            return (query.isEmpty ||
                (listing.title ?? "").localizedCaseInsensitiveContains(query) ||
                (listing.propertyType ?? "").localizedCaseInsensitiveContains(query) ||
                (listing.transactionType ?? "").localizedCaseInsensitiveContains(query) ||
                (listing.city ?? "").localizedCaseInsensitiveContains(query) ||
                (listing.postalCode ?? "").localizedCaseInsensitiveContains(query) ||
                (listing.description ?? "").localizedCaseInsensitiveContains(query)) &&
                (propertyTypeFilter == "Tous" || listing.propertyType == propertyTypeFilter) &&
                (propertyTransactionFilter == "Tous" || (propertyTransactionFilter == "Vente" && isSale) || (propertyTransactionFilter == "Location" && isRent)) &&
                (city.isEmpty || (listing.city ?? "").localizedCaseInsensitiveContains(city)) &&
                (postal.isEmpty || (listing.postalCode ?? "").localizedCaseInsensitiveContains(postal)) &&
                (minPrice.map { minimum in listing.price.map { $0 >= minimum } ?? false } ?? true) &&
                (maxPrice.map { maximum in listing.price.map { $0 <= maximum } ?? false } ?? true) &&
                (minSurface.map { minimum in listing.surface.map { $0 >= minimum } ?? false } ?? true) &&
                (maxSurface.map { maximum in listing.surface.map { $0 <= maximum } ?? false } ?? true) &&
                (minLandSurface.map { minimum in listing.landSurface.map { $0 >= minimum } ?? false } ?? true) &&
                (minRooms.map { minimum in listing.rooms.map { $0 >= minimum } ?? false } ?? true) &&
                (minBedrooms.map { minimum in listing.bedrooms.map { $0 >= minimum } ?? false } ?? true) &&
                (minBathrooms.map { minimum in listing.bathrooms.map { $0 >= minimum } ?? false } ?? true)
        }
        switch propertySort {
        case "Plus récentes": return filtered.sorted {
            if $0.sortDateKey == $1.sortDateKey { return $0.id < $1.id }
            return $0.sortDateKey > $1.sortDateKey
        }
        case "Prix croissant": return filtered.sorted { ($0.price ?? .greatestFiniteMagnitude) < ($1.price ?? .greatestFiniteMagnitude) }
        case "Prix décroissant": return filtered.sorted { ($0.price ?? -.greatestFiniteMagnitude) > ($1.price ?? -.greatestFiniteMagnitude) }
        case "Surface décroissante": return filtered.sorted { ($0.surface ?? -.greatestFiniteMagnitude) > ($1.surface ?? -.greatestFiniteMagnitude) }
        default: return filtered
        }
    }

    private var activePropertyFilterCount: Int {
        [propertyTypeFilter != "Tous", propertyTransactionFilter != "Tous", !propertyMinPrice.isEmpty,
         !propertyMaxPrice.isEmpty, !propertyMinSurface.isEmpty, !propertyMaxSurface.isEmpty, !propertyMinLandSurface.isEmpty,
         !propertyMinRooms.isEmpty, !propertyMinBedrooms.isEmpty, !propertyMinBathrooms.isEmpty,
         !propertyCity.isEmpty, !propertyPostalCode.isEmpty].filter { $0 }.count
    }

    private var filteredClassifiedAds: [ClassifiedAd] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = classifiedCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let postal = classifiedPostalCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let minimum = Double(classifiedMinPrice.replacingOccurrences(of: ",", with: "."))
        let maximum = Double(classifiedMaxPrice.replacingOccurrences(of: ",", with: "."))
        let yearMinimum = Double(classifiedYearMin)
        let yearMaximum = Double(classifiedYearMax)
        let mileageMaximum = Double(classifiedMileageMax.replacingOccurrences(of: ",", with: "."))
        let usesVehicleFilters = classifiedCategory == "Auto / Moto — accessoires"
        let filtered = classifiedAds.ads.filter { ad in
            (query.isEmpty ||
             ad.title.localizedCaseInsensitiveContains(query) ||
             (ad.category ?? "").localizedCaseInsensitiveContains(query) ||
             (ad.subcategory ?? "").localizedCaseInsensitiveContains(query) ||
             (ad.listingTypeLabel ?? "").localizedCaseInsensitiveContains(query) ||
             (ad.condition ?? "").localizedCaseInsensitiveContains(query) ||
             (ad.importedAttributesJSON ?? "").localizedCaseInsensitiveContains(query) ||
             attributeValue("brand", ad: ad).localizedCaseInsensitiveContains(query) ||
             attributeValue("model", ad: ad).localizedCaseInsensitiveContains(query) ||
             (ad.city ?? "").localizedCaseInsensitiveContains(query) ||
             (ad.postalCode ?? "").localizedCaseInsensitiveContains(query) ||
             (ad.description ?? "").localizedCaseInsensitiveContains(query)) &&
            (classifiedCategory == "Toutes" || ad.category == classifiedCategory) &&
            (classifiedSubcategory == "Toutes" || ad.subcategory == classifiedSubcategory) &&
            (classifiedListingType == "Tous" || ad.listingType == classifiedListingType) &&
            (classifiedCondition == "Tous" || ad.condition == classifiedCondition) &&
            (city.isEmpty || (ad.city ?? "").localizedCaseInsensitiveContains(city)) &&
            (postal.isEmpty || (ad.postalCode ?? "").localizedCaseInsensitiveContains(postal)) &&
            (minimum.map { minimumPrice in ad.price.map { $0 >= minimumPrice } ?? false } ?? true) &&
            (maximum.map { maximumPrice in ad.price.map { $0 <= maximumPrice } ?? false } ?? true) &&
            (classifiedAttributeKey == "Aucun" || classifiedAttributeValue.isEmpty ||
                attributeValue(classifiedAttributeKey, ad: ad).localizedCaseInsensitiveContains(classifiedAttributeValue)) &&
            (!usesVehicleFilters || classifiedBrand.isEmpty || attributeValue("brand", ad: ad).localizedCaseInsensitiveContains(classifiedBrand)) &&
            (!usesVehicleFilters || classifiedModel.isEmpty || attributeValue("model", ad: ad).localizedCaseInsensitiveContains(classifiedModel)) &&
            (!usesVehicleFilters || classifiedEnergy.isEmpty || attributeValue("energy", ad: ad).localizedCaseInsensitiveContains(classifiedEnergy)) &&
            (!usesVehicleFilters || classifiedGearbox.isEmpty || attributeValue("gearbox", ad: ad).localizedCaseInsensitiveContains(classifiedGearbox)) &&
            (!usesVehicleFilters || (yearMinimum.map { minimumYear in Double(attributeValue("year", ad: ad)).map { $0 >= minimumYear } ?? false } ?? true)) &&
            (!usesVehicleFilters || (yearMaximum.map { maximumYear in Double(attributeValue("year", ad: ad)).map { $0 <= maximumYear } ?? false } ?? true)) &&
            (!usesVehicleFilters || (mileageMaximum.map { maximumMileage in Double(attributeValue("mileage", ad: ad)).map { $0 <= maximumMileage } ?? false } ?? true))
        }
        switch classifiedSort {
        case "Prix croissant": return filtered.sorted { ($0.price ?? .greatestFiniteMagnitude) < ($1.price ?? .greatestFiniteMagnitude) }
        case "Prix décroissant": return filtered.sorted { ($0.price ?? -.greatestFiniteMagnitude) > ($1.price ?? -.greatestFiniteMagnitude) }
        default: return filtered
        }
    }

    private var activeClassifiedFilterCount: Int {
        [classifiedCategory != "Toutes", classifiedSubcategory != "Toutes", classifiedListingType != "Tous", classifiedCondition != "Tous",
         !classifiedCity.isEmpty, !classifiedPostalCode.isEmpty, !classifiedMinPrice.isEmpty, !classifiedMaxPrice.isEmpty,
         classifiedAttributeKey != "Aucun" && !classifiedAttributeValue.isEmpty,
         (classifiedCategory == "Auto / Moto — accessoires" && !classifiedBrand.isEmpty),
         (classifiedCategory == "Auto / Moto — accessoires" && !classifiedModel.isEmpty),
         (classifiedCategory == "Auto / Moto — accessoires" && !classifiedYearMin.isEmpty),
         (classifiedCategory == "Auto / Moto — accessoires" && !classifiedYearMax.isEmpty),
         (classifiedCategory == "Auto / Moto — accessoires" && !classifiedMileageMax.isEmpty),
         (classifiedCategory == "Auto / Moto — accessoires" && !classifiedEnergy.isEmpty),
         (classifiedCategory == "Auto / Moto — accessoires" && !classifiedGearbox.isEmpty)]
            .filter { $0 }.count
    }

    private var classifiedAttributeKeys: [String] {
        let ads = classifiedAds.ads.filter { ad in
            (classifiedCategory == "Toutes" || ad.category == classifiedCategory) &&
                (classifiedSubcategory == "Toutes" || ad.subcategory == classifiedSubcategory)
        }
        let excluded: Set<String> = ["pfImportedVehicleListing", "importedProfessionalVehicle", "importedVehicleId", "sourceUrl", "providerProfileId", "providerSlug", "originalListingRequired", "noRepublishingConsent"]
        let keys = ads.flatMap { attributeDictionary($0).map { Array($0.keys) } ?? [] }
            .filter { !excluded.contains($0) && !$0.hasPrefix("_") && !$0.hasPrefix("classifiedOwner") }
        return Array(Set(keys)).sorted { attributeLabel($0).localizedStandardCompare(attributeLabel($1)) == .orderedAscending }
    }

    private func attributeLabel(_ key: String) -> String {
        key.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func attributeValue(_ key: String, ad: ClassifiedAd) -> String {
        guard let value = attributeDictionary(ad)?[key], !(value is NSNull) else { return "" }
        return String(describing: value)
    }

    private func attributeDictionary(_ ad: ClassifiedAd) -> [String: Any]? {
        guard let raw = ad.importedAttributesJSON?.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
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
                    Section {
                        HStack {
                            Text("\(filteredListings.count) bien\(filteredListings.count > 1 ? "s" : "")")
                                .font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                ForEach(["Ordre du catalogue", "Plus récentes", "Prix croissant", "Prix décroissant", "Surface décroissante"], id: \.self) { option in
                                    Button(option) { propertySort = option }
                                }
                            } label: {
                                Label(propertySort, systemImage: "arrow.up.arrow.down").font(.footnote)
                            }
                        }
                        Button { showPropertyFilters = true } label: {
                            Label(activePropertyFilterCount == 0 ? "Filtres immobiliers" : "Filtres immobiliers (\(activePropertyFilterCount))",
                                  systemImage: "slider.horizontal.3")
                        }
                        .sheet(isPresented: $showPropertyFilters) {
                            NavigationStack {
                                Form {
                                    Section("Bien immobilier") {
                                        Picker("Type de bien", selection: $propertyTypeFilter) {
                                            Text("Tous").tag("Tous")
                                            ForEach(Array(Set(service.listings.compactMap(\.propertyType))).sorted(), id: \.self) {
                                                Text($0).tag($0)
                                            }
                                        }
                                        Picker("Transaction", selection: $propertyTransactionFilter) {
                                            Text("Toutes").tag("Tous")
                                            Text("Vente").tag("Vente")
                                            Text("Location").tag("Location")
                                        }
                                    }
                                    Section("Prix et surface") {
                                        TextField("Pr…59591 tokens truncated…")
                    }
                    .pickerStyle(.segmented)
                }
            } else {
                EmptyView()
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
            Section {
                Button { Task { await save() } } label: {
                    HStack { Spacer(); if isSaving { ProgressView("Enregistrement…") } else { Label("Enregistrer", systemImage: "checkmark.circle.fill") }; Spacer() }
                }
                .buttonStyle(.borderedProminent).tint(.teal)
                .disabled(isSaving || !isValid)
            }
        }
        .navigationTitle(initialAccommodation == nil ? "Ajouter un hébergement" : "Modifier l’hébergement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Fermer") { dismiss() } } }
    }

    private var isValid: Bool {
        itemName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        !itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        locationAddress.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 &&
        city.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        postalCode.range(of: "^\\d{4,10}$", options: .regularExpression) != nil &&
        Double(itemPrice.replacingOccurrences(of: ",", with: ".")) != nil
    }

    @MainActor
    private func save() async {
        guard isValid, let price = Double(itemPrice.replacingOccurrences(of: ",", with: ".")) else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let coordinates = await auth.coordinates(city: city, postalCode: postalCode)
            var fields: [String: Any] = [
                "itemName": itemName, "itemDescription": itemDescription,
                "accommodationType": accommodationType, "locationAddress": locationAddress,
                "city": city, "postalCode": postalCode, "maxGuests": maxGuests,
                "numberOfBedrooms": numberOfBedrooms, "itemPrice": price,
                "amenities": amenities, "slug": slug, "checkInMode": checkInMode,
                "checkInTime": checkInTime, "checkInUntil": checkInUntil,
                "accessMethod": accessMethod, "arrivalInstructions": arrivalInstructions,
            ]
            if photosEdited {
                let uploadedPhotos = try await auth.uploadListingPhotos(newPhotos, role: "hebergeur")
                fields["photos"] = retainedPhotoURLs + uploadedPhotos
            }
            if let coordinates {
                fields["latitude"] = coordinates.latitude
                fields["longitude"] = coordinates.longitude
            }
            try await auth.saveHostAccommodation(
                accommodationID: initialAccommodation?["_id"] as? String,
                fields: fields,
                status: status
            )
            onSaved()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct NativeSeasonalCalendarEditor: View {
    @Environment(\.dismiss) private var dismiss
    let accommodations: [[String: Any]]
    let calendarEntries: [[String: Any]]
    let reservations: [[String: Any]]
    let onSave: (String, [String], String, Double?, Int?) async throws -> Void
    @State private var accommodationID = ""
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var selectedDates = Set<String>()
    @State private var status = "blocked"
    @State private var priceText = ""
    @State private var minimumStayText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private let weekdayNames = ["Lu", "Ma", "Me", "Je", "Ve", "Sa", "Di"]

    private var currentAccommodationID: String {
        if accommodations.contains(where: { String(describing: $0["_id"] ?? $0["id"] ?? "") == accommodationID }) { return accommodationID }
        return String(describing: accommodations.first?["_id"] ?? accommodations.first?["id"] ?? "")
    }

    private var monthDays: [Date] {
        guard let interval = Calendar.current.range(of: .day, in: .month, for: month),
              let first = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: month)) else { return [] }
        return interval.compactMap { Calendar.current.date(byAdding: .day, value: $0 - 1, to: first) }
    }

    private var leadingEmptyDays: Int {
        guard let first = monthDays.first else { return 0 }
        return (Calendar.current.component(.weekday, from: first) + 5) % 7
    }

    private var selectedDateList: [String] { selectedDates.sorted() }

    var body: some View {
        Form {
            Section("Hébergement") {
                Picker("Hébergement", selection: $accommodationID) {
                    ForEach(Array(accommodations.enumerated()), id: \.offset) { _, accommodation in
                        let id = String(describing: accommodation["_id"] ?? accommodation["id"] ?? "")
                        Text(String(describing: accommodation["itemName"] ?? "Hébergement")).tag(id)
                    }
                }
                .disabled(accommodations.count < 2)
            }
            Section("Calendrier") {
                HStack {
                    Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Mois précédent")
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year()).capitalized).font(.headline)
                    Spacer()
                    Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Mois suivant")
                }
                LazyVGrid(columns: columns, spacing: 7) {
                    ForEach(weekdayNames, id: \.self) { Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                    ForEach(0..<leadingEmptyDays, id: \.self) { _ in Color.clear.frame(height: 38) }
                    ForEach(monthDays, id: \.self) { date in
                        let key = Self.dateKey(date)
                        let reserved = isReserved(key)
                        let selected = selectedDates.contains(key)
                        Button {
                            guard !reserved else { return }
                            if selected { selectedDates.remove(key) } else { selectedDates.insert(key) }
                        } label: {
                            Text(String(Calendar.current.component(.day, from: date)))
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .foregroundStyle(reserved ? .secondary : selected ? .white : .primary)
                                .background(selected ? Color.teal : statusColor(key), in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(reserved ? Color.blue.opacity(0.65) : Color.clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .disabled(reserved)
                        .accessibilityLabel("\(key)\(reserved ? ", réservé" : "")\(selected ? ", sélectionné" : "")")
                    }
                }
                Text("Bleu : réservé ou demande en cours. Sélectionnez jusqu’à 31 autres dates.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Modification des dates sélectionnées (\(selectedDates.count))") {
                Picker("Disponibilité", selection: $status) {
                    Text("Disponible").tag("available")
                    Text("Bloquer").tag("blocked")
                }
                .pickerStyle(.segmented)
                TextField("Prix par nuit (€), facultatif", text: $priceText)
                    .keyboardType(.decimalPad)
                TextField("Séjour minimum (nuits), facultatif", text: $minimumStayText)
                    .keyboardType(.numberPad)
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if isSaving { ProgressView() }
                        Text(isSaving ? "Enregistrement…" : "Enregistrer les disponibilités")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(isSaving || selectedDates.isEmpty || currentAccommodationID.isEmpty)
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
        }
        .navigationTitle("Disponibilités")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Fermer") { dismiss() } }
        }
        .onAppear { if accommodationID.isEmpty { accommodationID = currentAccommodationID } }
        .onChange(of: accommodationID) { _, _ in selectedDates.removeAll() }
    }

    private func changeMonth(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: month) { month = next }
        selectedDates.removeAll()
    }

    private func isReserved(_ date: String) -> Bool {
        let calendarReserved = calendarEntries.contains { entry in
            String(describing: entry["linkedEntityId"] ?? "") == currentAccommodationID &&
            Self.dateKey(entry["calendarDate"]) == date &&
            ["reserved", "booked", "external", "pending"].contains(String(describing: entry["availabilityStatus"] ?? "").lowercased())
        }
        let reservationReserved = reservations.contains { reservation in
            guard String(describing: reservation["accommodationId"] ?? "") == currentAccommodationID,
                  String(describing: reservation["reservationStatus"] ?? "").lowercased() == "confirmed" else { return false }
            let checkIn = Self.dateKey(reservation["checkInDate"])
            let checkOut = Self.dateKey(reservation["checkOutDate"])
            return checkIn <= date && checkOut > date
        }
        return calendarReserved || reservationReserved
    }

    private func statusColor(_ date: String) -> Color {
        guard let entry = calendarEntries.first(where: {
            String(describing: $0["linkedEntityId"] ?? "") == currentAccommodationID && Self.dateKey($0["calendarDate"]) == date
        }) else { return Color(uiColor: .secondarySystemGroupedBackground) }
        return String(describing: entry["availabilityStatus"] ?? "").lowercased() == "blocked" ? Color.red.opacity(0.18) : Color.green.opacity(0.16)
    }

    @MainActor
    private func save() async {
        guard selectedDateList.count <= 31 else { errorMessage = "Sélectionnez au maximum 31 dates par enregistrement."; return }
        if !priceText.isEmpty && Double(priceText.replacingOccurrences(of: ",", with: ".")) == nil { errorMessage = "Le prix doit être un nombre valide."; return }
        if !minimumStayText.isEmpty && Int(minimumStayText) == nil { errorMessage = "Le séjour minimum doit être un nombre entier."; return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await onSave(
                currentAccommodationID, selectedDateList, status,
                priceText.isEmpty ? nil : Double(priceText.replacingOccurrences(of: ",", with: ".")),
                minimumStayText.isEmpty ? nil : Int(minimumStayText)
            )
            selectedDates.removeAll()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func dateKey(_ value: Any?) -> String {
        if let value = value as? String { return String(value.prefix(10)) }
        if let value = value as? Date { return formatter.string(from: value) }
        return ""
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
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
    var onClaim: (() async -> Void)? = nil
    var onHostBookingTransition: ((String) async -> Void)? = nil
    @State private var isClaiming = false
    @State private var isTransitioningBooking = false
    @State private var confirmBookingRejection = false

    private var matchLabel: String? {
        guard let matchType = item["matchType"] as? String else { return nil }
        switch matchType {
        case "direct": return "Code postal principal"
        case "nearby": return "Dans le rayon kilométrique"
        case "secondary": return "Code postal secondaire"
        case "department": return "Même département"
        default: return "Demande sans correspondance directe"
        }
    }

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
        ["propertyCity", "propertyPostalCode", "propertyType", "transactionType", "professionalName", "city", "postalCode", "category", "status", "matchingType", "demandType"].compactMap { item[$0] as? String }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private var detail: String? {
        ["description", "itemDescription", "message", "messageContent", "content"].compactMap { item[$0] as? String }.first
    }
    private var imageURL: URL? {
        ["propertyImage", "mainImageUrl", "mainImage", "itemImage", "photo"].compactMap { item[$0] as? String }.compactMap(WixImageSource.url).first
    }
    private var propertyLinkURL: URL? {
        guard let raw = item["propertyUrl"] as? String, !raw.isEmpty else { return nil }
        if let url = URL(string: raw), url.scheme?.lowercased() == "https" { return url }
        let path = raw.hasPrefix("/") ? raw : "/\(raw)"
        return URL(string: "https://www.partenairefoyer.com\(path)")
    }
    private var contactEmailURL: URL? {
        let candidate = ["professionalEmail", "senderEmail", "vacationerEmail", "email"]
            .compactMap { item[$0] as? String }
            .first { value in
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized.contains("@") && normalized.count <= 254 && !normalized.contains("\n")
            }
        guard let email = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              var components = URLComponents() else { return nil }
        components.scheme = "mailto"
        components.path = email
        if let subject = ["itemName", "propertyTitle", "accommodationTitle", "title"]
            .compactMap({ item[$0] as? String })
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            components.queryItems = [URLQueryItem(name: "subject", value: "Votre demande PartenaireFoyer · \(subject)")]
        }
        return components.url
    }
    private var contactPhoneURL: URL? {
        guard let phone = ["professionalPhone", "senderPhone", "vacationerPhone", "phone", "phoneNumber"]
            .compactMap({ item[$0] as? String })
            .first(where: { $0.filter { $0.isNumber }.count >= 6 }) else { return nil }
        let dialable = phone.filter { $0.isNumber || $0 == "+" }
        return URL(string: "tel:\(dialable)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        if let matchLabel { Text(matchLabel).font(.caption.weight(.medium)).foregroundStyle(.teal) }
                        if let detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                        if let price = item["propertyPrice"] ?? item["price"] ?? item["sellingPrice"] ?? item["estimatedPrice"] ?? item["itemPrice"] {
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

            if let onClaim {
                Button {
                    Task {
                        isClaiming = true
                        await onClaim()
                        isClaiming = false
                    }
                } label: {
                    HStack {
                        if isClaiming { ProgressView() }
                        Label(isClaiming ? "Acceptation en cours…" : "Accepter la demande · \(item["claimCount"] as? Int ?? 0)/3", systemImage: "hand.tap")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(isClaiming)
            }
            if let onHostBookingTransition, String(describing: item["status"] ?? "pending").lowercased() == "pending" {
                HStack {
                    Button {
                        Task {
                            isTransitioningBooking = true
                            await onHostBookingTransition("accepted")
                            isTransitioningBooking = false
                        }
                    } label: {
                        Label(isTransitioningBooking ? "Mise à jour…" : "Accepter", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(isTransitioningBooking)
                    Button(role: .destructive) { confirmBookingRejection = true } label: {
                        Label("Refuser", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTransitioningBooking)
                }
                .confirmationDialog("Refuser cette demande de réservation ?", isPresented: $confirmBookingRejection, titleVisibility: .visible) {
                    Button("Refuser la demande", role: .destructive) {
                        Task {
                            isTransitioningBooking = true
                            await onHostBookingTransition("rejected")
                            isTransitioningBooking = false
                        }
                    }
                    Button("Annuler", role: .cancel) { }
                } message: {
                    Text("La demande sera marquée comme refusée et les dates liées seront remises à disposition dans Wix.")
                }
            }
            if let url = propertyLinkURL {
                Link(destination: url) {
                    Label("Voir l’annonce", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.medium))
                }
            }
            if contactEmailURL != nil || contactPhoneURL != nil {
                HStack(spacing: 16) {
                    if let url = contactEmailURL {
                        Link(destination: url) { Label("Répondre par e-mail", systemImage: "envelope") }
                    }
                    if let url = contactPhoneURL {
                        Link(destination: url) { Label("Appeler", systemImage: "phone") }
                    }
                }
                .font(.caption.weight(.medium))
            }
        }
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
    let list: String?
}

private struct ProfessionalMiniSitePreviewView: View {
    let profile: [String: Any]
    let properties: [[String: Any]]

    private var company: String { (profile["companyName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Votre activité immobilière" }
    private var description: String { (profile["description"] as? String) ?? "Ajoutez une présentation à votre profil professionnel." }
    private var phone: String? { (profile["phoneNumber"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    private var email: String? { (profile["email"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    private var city: String { (profile["city"] as? String) ?? "" }
    private var imageURL: URL? {
        [profile["logo"] as? String, profile["photo"] as? String]
            .compactMap { $0 }
            .compactMap(WixImageSource.url)
            .first
    }
    private var publicMiniSiteURL: URL? {
        guard let slug = profile["slug"] as? String,
              slug.range(of: #"^[A-Za-z0-9-]{1,180}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://www.partenairefoyer.com/minisite/\(slug)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    if let imageURL {
                        AsyncImage(url: imageURL) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { Image(systemName: "building.2.crop.circle").resizable().scaledToFit().foregroundStyle(.teal).padding(28) }
                        }
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        Image(systemName: "building.2.crop.circle.fill").font(.system(size: 58)).foregroundStyle(.teal)
                    }
                    Text(company).font(.largeTitle.bold())
                    if let contact = profile["contactName"] as? String, !contact.isEmpty {
                        Text(contact).font(.headline).foregroundStyle(.secondary)
                    }
                    if !city.isEmpty { Label(city, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary) }
                    Text(description).font(.body).textSelection(.enabled)
                    HStack(spacing: 12) {
                        if let email, let url = URL(string: "mailto:\(email)") {
                            Link(destination: url) { Label("E-mail", systemImage: "envelope.fill") }.buttonStyle(.borderedProminent)
                        }
                        if let phone {
                            let digits = phone.filter { $0.isNumber || $0 == "+" }
                            if let url = URL(string: "tel:\(digits)") {
                                Link(destination: url) { Label("Appeler", systemImage: "phone.fill") }.buttonStyle(.bordered)
                            }
                        }
                    }
                    if let publicMiniSiteURL {
                        HStack(spacing: 12) {
                            Link(destination: publicMiniSiteURL) {
                                Label("Ouvrir mon mini-site", systemImage: "safari")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            ShareLink(item: publicMiniSiteURL) {
                                Label("Partager", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Mes biens publiés").font(.title2.bold())
                    if properties.isEmpty {
                        ContentUnavailableView("Aucun bien publié", systemImage: "house", description: Text("Les annonces immobilières actives apparaîtront ici."))
                    } else {
                        ForEach(Array(properties.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 8) {
                                if let url = WixImageSource.url((item["mainImageUrl"] as? String) ?? (item["photo1"] as? String)) {
                                    AsyncImage(url: url) { phase in
                                        if let image = phase.image { image.resizable().scaledToFill() }
                                        else { Color.teal.opacity(0.08) }
                                    }
                                    .frame(height: 170)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                                Text(item["title"] as? String ?? "Bien immobilier").font(.headline)
                                Text([item["city"] as? String, item["surface"].map { "\($0) m²" }]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                if let price = item["price"] { Text("\(price) €").font(.headline).foregroundStyle(.teal) }
                            }
                            .padding(12)
                            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Aperçu du mini-site")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NativeListingEditForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = WixAuthStore.shared
    @ObservedObject var classifiedAds: ClassifiedAdsService
    let role: String
    let list: String
    let item: [String: Any]
    let onSaved: () -> Void
    @State private var title: String
    @State private var description: String
    @State private var price: String
    @State private var propertyType: String
    @State private var transactionType: String
    @State private var address: String
    @State private var city: String
    @State private var postalCode: String
    @State private var surface: String
    @State private var landSurface: String
    @State private var rooms: String
    @State private var bedrooms: String
    @State private var bathrooms: String
    @State private var category: String
    @State private var subcategory: String
    @State private var attributes: [String: String]
    @State private var classifiedListingType: String
    @State private var rentalUnit: String
    @State private var condition: String
    @State private var isPublished: Bool
    @State private var existingPhotoURLs: [String]
    @State private var newPhotoData: [Data] = []
    @State private var photosChanged = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(role: String, list: String, item: [String: Any], classifiedAds: ClassifiedAdsService, onSaved: @escaping () -> Void) {
        self.role = role
        self.list = list
        self.item = item
        self.classifiedAds = classifiedAds
        self.onSaved = onSaved
        let isClassified = list == "classifieds"
        _title = State(initialValue: item[isClassified ? "itemName" : "title"] as? String ?? "")
        _description = State(initialValue: item[isClassified ? "itemDescription" : "description"] as? String ?? "")
        _price = State(initialValue: String(describing: item[isClassified ? "itemPrice" : role == "professionnel" ? "price" : "sellingPrice"] ?? ""))
        _propertyType = State(initialValue: item["propertyType"] as? String ?? "")
        _transactionType = State(initialValue: item["transactionType"] as? String ?? (role == "professionnel" ? "sale" : "vente"))
        _address = State(initialValue: item["address"] as? String ?? "")
        _city = State(initialValue: item["city"] as? String ?? "")
        _postalCode = State(initialValue: item["postalCode"] as? String ?? "")
        _surface = State(initialValue: String(describing: item["surface"] ?? ""))
        _landSurface = State(initialValue: String(describing: item["landSurface"] ?? ""))
        _rooms = State(initialValue: String(describing: item["rooms"] ?? ""))
        _bedrooms = State(initialValue: String(describing: item["bedrooms"] ?? ""))
        _bathrooms = State(initialValue: String(describing: item["bathrooms"] ?? ""))
        _category = State(initialValue: item["category"] as? String ?? "")
        _subcategory = State(initialValue: item["subcategory"] as? String ?? "")
        _attributes = State(initialValue: Self.attributes(from: item["attributesJSON"]))
        _classifiedListingType = State(initialValue: item["adListingType"] as? String ?? "sell")
        _rentalUnit = State(initialValue: Self.rentalUnit(from: item["attributesJSON"]))
        _condition = State(initialValue: item["itemCondition"] as? String ?? "Bon état")
        _isPublished = State(initialValue: role == "professionnel" ? (item["status"] as? String == "active") : (item["isPublic"] as? Bool == true))
        _existingPhotoURLs = State(initialValue: Self.photoURLs(from: item, list: list, role: role))
    }

    private var photoLimit: Int { role == "professionnel" ? 5 : 20 }
    private var attributeFields: [(String, String)] {
        ClassifiedCategoryOptions.attributes(
            for: category,
            observedKeys: attributes.compactMap { $0.value.isEmpty ? nil : $0.key } + ClassifiedCategoryOptions.observedKeys(category: category, subcategory: subcategory, ads: classifiedAds.ads)
        )
    }

    private static func photoURLs(from item: [String: Any], list: String, role: String) -> [String] {
        let directKeys: [String]
        if list == "classifieds" {
            directKeys = ["itemImage"] + (2...20).map { "photo\($0)" }
        } else if role == "professionnel" {
            directKeys = ["mainImageUrl"] + (1...5).map { "photo\($0)" }
        } else {
            directKeys = ["mainImage"] + (1...20).map { "photo\($0)" }
        }
        var values = directKeys.compactMap { item[$0] as? String }.filter { !$0.isEmpty }
        if let gallery = item["galleryImages"] as? String,
           let data = gallery.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) {
            values += photoValues(decoded)
        } else if let gallery = item["galleryImages"] {
            values += photoValues(gallery)
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func photoValues(_ value: Any) -> [String] {
        if let strings = value as? [String] { return strings.filter { !$0.isEmpty } }
        if let objects = value as? [[String: Any]] {
            return objects.compactMap { ($0["url"] as? String) ?? ($0["src"] as? String) }.filter { !$0.isEmpty }
        }
        return []
    }

    private static func rentalUnit(from value: Any?) -> String {
        var attributes = value as? [String: Any]
        if attributes == nil, let raw = value as? String, let data = raw.data(using: .utf8) {
            attributes = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        let unit = attributes?["rentalUnit"] as? String ?? "day"
        return ClassifiedCategoryOptions.rentalUnits.contains(where: { $0.1 == unit }) ? unit : "day"
    }

    private static func attributes(from value: Any?) -> [String: String] {
        var parsed = value as? [String: Any]
        if parsed == nil, let raw = value as? String, let data = raw.data(using: .utf8) {
            parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        var safe: [String: String] = [:]
        for key in (parsed ?? [:]).keys.sorted().prefix(80) {
            guard ClassifiedCategoryOptions.isUserAttributeKey(key),
                  let raw = parsed?[key], !(raw is NSNull) else { continue }
            safe[key] = String(describing: raw)
        }
        return safe
    }

    private var isClassified: Bool { list == "classifieds" }
    private var classifiedCategoryOptions: [String] {
        guard !category.isEmpty, !ClassifiedCategoryOptions.all.contains(category) else { return ClassifiedCategoryOptions.all }
        return [category] + ClassifiedCategoryOptions.all
    }
    private var numberPrice: Double { Double(price.replacingOccurrences(of: ",", with: ".")) ?? -1 }
    private var canSave: Bool {
        let titleLength = title.trimmingCharacters(in: .whitespacesAndNewlines).count
        let descriptionLength = description.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard titleLength >= (isClassified ? 3 : 5), descriptionLength >= (isClassified ? 10 : 20),
              numberPrice >= 0, city.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2, postalCode.count >= 4 else { return false }
        if isClassified { return category.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 }
        guard (Double(surface.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0,
              (Int(rooms) ?? 0) > 0, (Int(bedrooms) ?? -1) >= 0 else { return false }
        if role == "professionnel" {
            return address.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 &&
                (Int(bathrooms) ?? -1) >= 0 &&
                (landSurface.isEmpty || (Double(landSurface.replacingOccurrences(of: ",", with: ".")) ?? -1) >= 0)
        }
        return (Int(bathrooms) ?? -1) >= 0 && (landSurface.isEmpty || (Double(landSurface.replacingOccurrences(of: ",", with: ".")) ?? -1) >= 0)
    }

    var body: some View {
        Form {
            Section {
                Label("Modifier l’annonce", systemImage: "pencil.and.list.clipboard").font(.title3.bold())
                Text("Modifiez les photos de l’annonce. Les photos déjà publiées restent disponibles jusqu’à leur retrait.").font(.footnote).foregroundStyle(.secondary)
            }
            Section(isClassified ? "Objet" : "Présentation") {
                TextField(isClassified ? "Titre de l’objet" : "Titre de l’annonce", text: $title)
                if isClassified {
                    Picker("Vous souhaitez", selection: $classifiedListingType) {
                        Text("Je vends").tag("sell")
                        Text("Je donne").tag("give")
                        Text("J’échange").tag("exchange")
                        Text("Je loue").tag("rent")
                    }
                    Picker("Catégorie", selection: $category) {
                        ForEach(classifiedCategoryOptions, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Sous-catégorie", text: $subcategory)
                    Picker("État", selection: $condition) {
                        ForEach(["Neuf", "Comme neuf", "Très bon état", "Bon état", "État correct"], id: \.self) { Text($0).tag($0) }
                    }
                    if classifiedListingType == "rent" {
                        Picker("Périodicité du prix", selection: $rentalUnit) {
                            ForEach(Array(ClassifiedCategoryOptions.rentalUnits.enumerated()), id: \.offset) { _, option in Text(option.0).tag(option.1) }
                        }
                    }
                } else {
                    TextField("Type de bien", text: $propertyType)
                    Picker("Transaction", selection: $transactionType) {
                        Text("Vente").tag(role == "professionnel" ? "sale" : "vente")
                        Text("Location").tag(role == "professionnel" ? "rent" : "location")
                    }
                }
                TextField("Description", text: $description, axis: .vertical).lineLimit(4...10)
            }
            Section("Prix et caractéristiques") {
                TextField("Prix (€)", text: $price).keyboardType(.decimalPad)
                if isClassified {
                    ForEach(attributeFields, id: \.0) { key, label in
                        TextField(label, text: Binding(
                            get: { attributes[key, default: ""] },
                            set: { attributes[key] = $0 }
                        ))
                    }
                }
                if !isClassified {
                    TextField("Surface (m²)", text: $surface).keyboardType(.decimalPad)
                    if role == "particulier" || role == "professionnel" {
                        TextField("Terrain (m²), facultatif", text: $landSurface).keyboardType(.decimalPad)
                    }
                    TextField("Pièces", text: $rooms).keyboardType(.numberPad)
                    TextField("Chambres", text: $bedrooms).keyboardType(.numberPad)
                    if role == "particulier" || role == "professionnel" {
                        TextField("Salles de bain", text: $bathrooms).keyboardType(.numberPad)
                    }
                }
            }
            if isClassified, let loadIssue = classifiedAds.errorMessage ?? classifiedAds.warningMessage {
                Section("Champs complémentaires") {
                    Label(loadIssue, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                    Text("Les champs déjà disponibles restent modifiables.").font(.footnote).foregroundStyle(.secondary)
                    Button("Réessayer") { Task { await classifiedAds.reload() } }
                        .disabled(classifiedAds.isLoading)
                }
            }
            Section(isClassified ? "Localisation" : "Adresse et localisation") {
                if role == "professionnel" && !isClassified { TextField("Adresse", text: $address) }
                TextField("Ville", text: $city)
                TextField("Code postal", text: $postalCode).keyboardType(.numberPad)
                    .onChange(of: postalCode) { _, value in
                        postalCode = String(value.filter(\.isNumber).prefix(10))
                    }
            }
            Section("Photos (\(existingPhotoURLs.count + newPhotoData.count)/\(photoLimit))") {
                if existingPhotoURLs.isEmpty && newPhotoData.isEmpty {
                    Text("Aucune photo enregistrée.").font(.footnote).foregroundStyle(.secondary)
                }
                if !existingPhotoURLs.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(Array(existingPhotoURLs.enumerated()), id: \.offset) { index, url in
                                ZStack(alignment: .topTrailing) {
                                    AsyncImage(url: WixImageSource.url(url)) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                                            .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                                    }
                                    .frame(width: 88, height: 76).clipShape(RoundedRectangle(cornerRadius: 10))
                                    Button {
                                        existingPhotoURLs.remove(at: index)
                                        photosChanged = true
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3).symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.65))
                                    }
                                    .buttonStyle(.plain).padding(4)
                                    .accessibilityLabel("Retirer la photo \(index + 1)")
                                }
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                NativeListingPhotoPicker(photos: $newPhotoData, maxPhotos: max(0, photoLimit - existingPhotoURLs.count))
                    .onChange(of: newPhotoData) { _, _ in photosChanged = true }
            }
            if !isClassified {
                Section("Publication") {
                    Toggle("Annonce visible publiquement", isOn: $isPublished)
                }
            }
            if let errorMessage { Section("Enregistrement impossible") { Text(errorMessage).foregroundStyle(.red).font(.footnote) } }
            Section {
                Button { Task { await save() } } label: {
                    HStack { Spacer(); if isSaving { ProgressView("Enregistrement…") } else { Label("Enregistrer les changements", systemImage: "checkmark.circle.fill") }; Spacer() }
                }
                .disabled(isSaving || !canSave)
            }
        }
        .navigationTitle("Modifier l’annonce")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        .task { if isClassified { await classifiedAds.loadIfNeeded() } }
        .onChange(of: category) { _, value in
            clearUnsupportedAttributes(category: value, subcategory: subcategory)
        }
        .onChange(of: subcategory) { _, value in
            clearUnsupportedAttributes(category: category, subcategory: value)
        }
    }

    private func clearUnsupportedAttributes(category: String, subcategory: String) {
        let observed = ClassifiedCategoryOptions.observedKeys(category: category, subcategory: subcategory, ads: classifiedAds.ads)
        let current = Set(ClassifiedCategoryOptions.attributes(for: category, observedKeys: observed).map(\.0))
        for key in Array(attributes.keys) where !current.contains(key) { attributes[key] = "" }
    }

    @MainActor private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        var fields: [String: Any]
        if isClassified {
            fields = ["itemName": title, "itemDescription": description, "itemPrice": numberPrice, "category": category, "subcategory": subcategory, "adListingType": classifiedListingType, "itemCondition": condition, "city": city, "postalCode": postalCode, "attributes": attributes]
        } else if role == "professionnel" {
            fields = ["title": title, "description": description, "propertyType": propertyType, "transactionType": transactionType, "price": numberPrice, "surface": Double(surface.replacingOccurrences(of: ",", with: ".")) ?? 0, "rooms": Int(rooms) ?? 0, "bedrooms": Int(bedrooms) ?? 0, "address": address, "city": city, "postalCode": postalCode, "status": isPublished ? "active" : "inactive"]
            fields["bathrooms"] = Int(bathrooms) ?? 0
            if !landSurface.isEmpty { fields["landSurface"] = Double(landSurface.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        } else {
            fields = ["title": title, "description": description, "propertyType": propertyType, "transactionType": transactionType, "sellingPrice": numberPrice, "surface": Double(surface.replacingOccurrences(of: ",", with: ".")) ?? 0, "rooms": Int(rooms) ?? 0, "bedrooms": Int(bedrooms) ?? 0, "bathrooms": Int(bathrooms) ?? 0, "city": city, "postalCode": postalCode, "isPublic": isPublished]
            if !landSurface.isEmpty { fields["landSurface"] = Double(landSurface.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        }
        do {
            guard let itemID = (item["_id"] as? String) ?? (item["id"] as? String) else { throw AuthError.api("Identifiant d’annonce manquant.") }
            if photosChanged {
                var photos = existingPhotoURLs
                if !newPhotoData.isEmpty {
                    photos += try await auth.uploadListingPhotos(newPhotoData, role: role)
                }
                fields["photos"] = photos
            }
            if isClassified { fields["rentalUnit"] = rentalUnit }
            try await auth.updateListing(role: role, list: list, itemID: itemID, fields: fields)
            onSaved()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct DashboardItemDetailView: View {
    let item: [String: Any]
    let role: String
    let list: String?
    let onEdit: () -> Void

    private let displayFields: [(String, String)] = [
        ("description", "Description"), ("itemDescription", "Description"),
        ("projectDescription", "Description du projet"),
        ("message", "Message"), ("messageContent", "Message"), ("guestMessage", "Message du voyageur"), ("content", "Message"),
        ("searchName", "Nom de la recherche"), ("propertyTitle", "Bien correspondant"),
        ("firstName", "Prénom"), ("lastName", "Nom"), ("senderName", "Nom du contact"), ("requesterName", "Nom du demandeur"),
        ("requesterEmail", "E-mail du demandeur"), ("email", "E-mail"),
        ("city", "Ville"), ("propertyCity", "Ville du bien"), ("postalCode", "Code postal"),
        ("address", "Adresse"), ("propertyAddress", "Adresse du bien"),
        ("propertyType", "Type de bien"), ("propertyTypes", "Types recherchés"), ("transactionType", "Transaction"),
        ("propertySurface", "Surface du bien"), ("livingArea", "Surface habitable (m²)"),
        ("landArea", "Surface du terrain (m²)"), ("minSurface", "Surface minimale"), ("maxSurface", "Surface maximale"),
        ("propertyPrice", "Prix du bien"), ("desiredPrice", "Prix souhaité"),
        ("minRent", "Loyer minimum"), ("maxRent", "Loyer maximum"), ("rent", "Loyer"),
        ("minPrice", "Prix minimum"), ("maxPrice", "Prix maximum"),
        ("minBudget", "Budget minimum"), ("maxBudget", "Budget maximum"), ("budget", "Budget / prix estimé"),
        ("projectTimeline", "Délai du projet"), ("occupancyStatus", "Occupation du bien"),
        ("propertyCondition", "État du bien"), ("numberOfRooms", "Nombre de pièces"),
        ("numberOfBedrooms", "Nombre de chambres"), ("numberOfBathrooms", "Nombre de salles de bain"),
        ("radius", "Rayon (km)"), ("minRooms", "Pièces minimum"), ("minBedrooms", "Chambres minimum"),
        ("emailAlertsEnabled", "Alertes e-mail"), ("professionalName", "Professionnel"), ("professionalEmail", "E-mail du professionnel"),
        ("category", "Catégorie"), ("subcategory", "Sous-catégorie"), ("condition", "État"), ("itemCondition", "État"), ("status", "Statut"),
        ("matchingType", "Type de matching"), ("matchingScore", "Compatibilité"),
        ("demandType", "Type de demande"), ("seen", "Consulté"),
        ("senderEmail", "E-mail du contact"), ("senderPhone", "Téléphone du contact"),
        ("contactEmail", "E-mail"), ("phoneNumber", "Téléphone"),
        ("propertyId", "Bien associé"), ("acquereurId", "Acquéreur associé"),
        ("createdAt", "Reçu le"), ("notifiedAt", "Notification envoyée le"),
        ("accommodationTitle", "Hébergement"), ("accommodationType", "Type d’hébergement"),
        ("vacationerName", "Voyageur"), ("vacationerEmail", "E-mail du voyageur"),
        ("vacationerPhone", "Téléphone du voyageur"), ("checkInDate", "Arrivée"),
        ("checkOutDate", "Départ"), ("proposedCheckInDate", "Arrivée proposée"),
        ("proposedCheckOutDate", "Départ proposé"), ("numberOfNights", "Nombre de nuits"),
        ("numberOfGuests", "Nombre de voyageurs"), ("numberOfAdults", "Adultes"),
        ("numberOfChildren", "Enfants"), ("numberOfBabies", "Bébés"),
        ("petsIncluded", "Animaux inclus"), ("reservationStatus", "Statut de la réservation"),
        ("paymentStatus", "Statut du paiement"), ("totalPrice", "Montant total"),
        ("bookingDateTime", "Date de la réservation"), ("lastMessageTimestamp", "Dernier message le"),
        ("status", "Statut"), ("maxGuests", "Capacité maximale"),
        ("numberOfBedrooms", "Chambres"), ("amenities", "Équipements"),
        ("locationAddress", "Adresse"), ("calendarDate", "Date du calendrier"),
        ("availabilityStatus", "Disponibilité"), ("pricePerNight", "Prix par nuit"),
        ("minimumStay", "Séjour minimum"), ("minimumStayNights", "Séjour minimum (nuits)"),
        ("startDate", "Début"), ("endDate", "Fin"), ("sourcePlatform", "Plateforme source"),
        ("externalBookingReference", "Référence externe"), ("seasonName", "Saison"),
        ("platformName", "Plateforme"), ("lastSyncDate", "Dernière synchronisation"),
        ("syncStatus", "État de synchronisation")
    ]

    private var title: String {
        ["title", "itemName", "accommodationTitle", "businessName", "vacationerName", "senderName", "fullName"]
            .compactMap { item[$0] as? String }
            .first ?? "Détail"
    }

    private var imageURLs: [URL] {
        var values = [
            "propertyImage", "mainImageUrl", "mainImage", "itemImage", "photo", "photo1",
            "photo2", "photo3", "photo4", "photo5", "photo6", "photo7", "photo8", "photo9", "photo10",
            "photo11", "photo12", "photo13", "photo14", "photo15", "photo16", "photo17", "photo18", "photo19", "photo20",
            "photo21", "photo22", "photo23", "photo24", "photo25", "photo26", "photo27", "photo28", "photo29", "photo30",
            "galleryImage2", "galleryImage3", "galleryImage4", "galleryImage5",
        ]
            .compactMap { item[$0] as? String }
        values += item["photoUrls"] as? [String] ?? []
        values += item["galleryImages"] as? [String] ?? []
        var seen = Set<String>()
        return values.compactMap(WixImageSource.url)
            .filter { seen.insert($0.absoluteString).inserted }
    }

    private var rows: [(String, String)] {
        var seen = Set<String>()
        var rows = displayFields.compactMap { key, label in
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
        let internalFields: Set<String> = [
            "_id", "_createdDate", "_updatedDate", "id", "createdAt", "updatedAt", "seen", "seenAt",
            "isViewed", "hiddenByProfessionals", "latitude", "longitude", "hasDirectMatch", "claimCount",
            "matchingId", "matchType", "priorityBadge", "isClaimedByCurrentPro", "demandId", "proId",
            "professionalId", "memberId", "accountId", "ownerId", "department",
        ]
        for key in item.keys.sorted() where !internalFields.contains(key) && !key.hasPrefix("_") {
            guard !displayFields.contains(where: { $0.0 == key }) else { continue }
            guard let value = item[key], !(value is NSNull) else { continue }
            if let flag = value as? Bool, !flag { continue }
            let raw: String
            if let flag = value as? Bool { raw = flag ? "Oui" : "Non" }
            else if let list = value as? [String] { raw = list.joined(separator: ", ") }
            else { raw = String(describing: value) }
            guard !raw.isEmpty else { continue }
            let label = key.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            guard !seen.contains(label) else { continue }
            seen.insert(label)
            rows.append((label, raw))
        }
        return rows
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

                if let price = item["price"] ?? item["sellingPrice"] ?? item["estimatedPrice"] ?? item["itemPrice"] ?? item["totalPrice"] {
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
                if let email = ["senderEmail", "requesterEmail", "vacationerEmail", "contactEmail", "email"].compactMap({ item[$0] as? String }).first,
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
        .toolbar {
            if list != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onEdit() } label: { Label("Modifier", systemImage: "pencil") }
                }
            }
        }
    }
}
