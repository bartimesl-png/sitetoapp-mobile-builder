
import SwiftUI
import CoreFoundation
import PhotosUI
import UIKit
import SafariServices
import WebKit
import MapKit
import ImageIO

private enum PFTheme {
    static let brand = Color(red: 0.02, green: 0.43, blue: 0.34)
    static let deepGreen = Color(red: 0.04, green: 0.23, blue: 0.19)
    static let mint = Color(red: 0.10, green: 0.76, blue: 0.55)
    static let paleMint = Color(red: 0.91, green: 0.98, blue: 0.95)
}

struct RootView: View {
    @State private var selectedTab = 0
    @State private var selectedCatalogSection: NativeCatalogSection = .hub
    @AppStorage("partenairefoyer.activeRole") private var activeRoleRaw = ""
    @AppStorage("partenairefoyer.language") private var appLanguage = "fr"
    @StateObject private var listingsService = ListingsService()
    @StateObject private var classifiedAdsService = ClassifiedAdsService()
    @StateObject private var buyerSearchesService = PublicBuyerSearchesService()
    @StateObject private var professionalsService = ProfessionalsService()

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeDashboardView(
                selectedTab: $selectedTab,
                catalogSection: $selectedCatalogSection,
                listingsService: listingsService,
                classifiedAdsService: classifiedAdsService,
                professionalsService: professionalsService
            )
                .tabItem { Label(appLanguage == "en" ? "Home" : "Accueil", systemImage: "house.fill") }
                .tag(0)

            NativeListingsView(service: listingsService, classifiedAds: classifiedAdsService, buyerSearches: buyerSearchesService, professionalsService: professionalsService, catalogSection: $selectedCatalogSection)
                .tabItem { Label(appLanguage == "en" ? "Listings" : "Annonces", systemImage: "magnifyingglass") }
                .tag(1)

            NativeSeasonalStaysView()
                .tabItem { Label(appLanguage == "en" ? "Stays" : "Séjours", systemImage: "bed.double") }
                .tag(2)

            NativeProfessionalsView(service: professionalsService)
                .tabItem { Label(appLanguage == "en" ? "Professionals" : "Professionnels", systemImage: "person.2") }
                .tag(3)

            NativeSpacePickerView()
                .tabItem { Label(appLanguage == "en" ? "Menu" : "Menu", systemImage: "line.3.horizontal") }
                .tag(4)
        }
        .tint(PFTheme.brand)
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: appLanguage == "en" ? "en_US" : "fr_FR"))
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                AppLanguageControl(selection: $appLanguage)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(.bar)
        }
        .onReceive(NotificationCenter.default.publisher(for: .partenaireFoyerPushNotificationTapped)) { notification in
            guard let fields = notification.object as? [String: String] else { return }
            openPushDestination(fields)
        }
        .onAppear {
            if let fields = UserDefaults.standard.dictionary(forKey: "partenairefoyer.pendingPushTap.v1") as? [String: String] {
                openPushDestination(fields)
            }
        }
    }

    private func openPushDestination(_ fields: [String: String]) {
        selectedTab = 4
        let rawRole = (fields["role"] ?? fields["accountType"] ?? fields["recipientRole"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let roleByPushType: [String: String] = [
            "particulier": "particulier", "private_vendor": "particulier", "private-vendor": "particulier",
            "professionnel": "professionnel", "real_estate_agent": "professionnel", "real-estate-agent": "professionnel",
            "courtier": "courtier", "broker": "courtier",
            "artisan": "artisan", "diagnostiqueur": "diagnostiqueur", "diagnostician": "diagnostiqueur",
            "prestataire": "prestataire", "service_provider": "prestataire", "service-provider": "prestataire",
            "hebergeur": "hebergeur", "host": "hebergeur", "seasonal_host": "hebergeur",
        ]
        if let role = roleByPushType[rawRole] { activeRoleRaw = role }
        UserDefaults.standard.removeObject(forKey: "partenairefoyer.pendingPushTap.v1")
    }
}

private struct NativeSeasonalStaysView: View {
    @State private var accommodations: [WixSeasonalAccommodation] = []
    @State private var searchText = ""
    @AppStorage("partenairefoyer.searchCountryCode") private var searchCountryCode = CountryCatalog.defaultCode
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
            return accommodation.resolvedCountryCode == searchCountryCode &&
                (query.isEmpty || text.localizedCaseInsensitiveContains(query)) &&
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
                            CountryPickerRow(countryCode: $searchCountryCode, title: "Pays")
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

    private var departureBinding: Binding<Date> {
        Binding(
            get: { checkOutDate ?? earliestDeparture },
            set: { value in checkOutDate = max(value, earliestDeparture) }
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

private struct CountryPickerRow: View {
    @Binding var countryCode: String
    var title: String = "Pays"

    var body: some View {
        Picker(title, selection: $countryCode) {
            ForEach(CountryCatalog.codes, id: \.self) { code in
                Text("\(CountryCatalog.flag(code))  \(CountryCatalog.name(code))").tag(code)
            }
        }
        .pickerStyle(.menu)
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
                Section("Description") { ListingDescriptionTranslation(original: description) }
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
                        ProfessionalPortalWebView(url: bookingURL, initialToken: nil, title: "Réservation") { _ in }
                    }
                }
                Text("La vérification des dates et l’envoi de la demande s’effectuent sur le parcours sécurisé du site, dans cette fenêtre.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Hébergement")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(NativeBackButtonModifier())
    }
}

private struct NativeProfessionalsView: View {
    @ObservedObject var service: ProfessionalsService

    private let directories: [(String, String, String, String)] = [
        ("Immobilier", "building.2.fill", "Professionnels de l’immobilier", "CategoryMaison"),
        ("Courtiers", "person.text.rectangle.fill", "Courtiers", "CategoryCourtiers"),
        ("Artisans", "hammer.fill", "Artisans", "CategoryArtisans"),
        ("Diagnostiqueurs", "checkmark.seal.fill", "Diagnostiqueurs", "CategoryDiagnostics"),
        ("Prestataires", "wrench.and.screwdriver.fill", "Prestataires de services", "CategoryServices")
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choisissez un métier").font(.title2.bold()).foregroundStyle(PFTheme.deepGreen)
                    Text("Chaque métier dispose de son propre annuaire et de sa recherche.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(directories, id: \.0) { directory in
                        NavigationLink {
                            ProfessionalDirectoryListView(service: service, directoryType: directory.0, title: directory.2)
                        } label: {
                            CatalogPhotoCard(title: directory.2, subtitle: "Voir l’annuaire", image: directory.3, symbol: directory.1)
                        }.buttonStyle(.plain)
                    }
                }.padding(17)
            }
            .navigationTitle("Professionnels")
            .task { await service.loadIfNeeded() }
        }
    }
}

private struct ProfessionalDirectoryListView: View {
    @ObservedObject var service: ProfessionalsService
    let directoryType: String
    let title: String
    @State private var searchText = ""

    private var filtered: [WixPublicProfessional] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = service.professionals.filter { professional in
            let matchesType: Bool
            let activity = (professional.resolvedActivity ?? "").lowercased()
            let isDiagnostician = professional.importedCategory == "diagnostiqueur" ||
                activity.contains("diagnostic") || activity.contains("diagnostiqueur")
            switch directoryType {
            case "Immobilier":
                matchesType = professional.importedCategory == "immobilier" ||
                    (professional.importedCategory == nil && !professional.isLocalProsProfile)
            case "Courtiers":
                matchesType = professional.importedCategory == "courtier"
            case "Artisans":
                matchesType = professional.importedCategory == "artisan" ||
                    (professional.isLocalProsProfile && !isDiagnostician)
            case "Diagnostiqueurs":
                matchesType = isDiagnostician
            case "Prestataires":
                matchesType = professional.isServiceProviderProfile || professional.importedCategory == "prestataire"
            default:
                matchesType = true
            }
            guard matchesType else { return false }
            guard !query.isEmpty else { return true }
            return professional.directoryDisplayName.localizedCaseInsensitiveContains(query) ||
            professional.resolvedName.localizedCaseInsensitiveContains(query) ||
            (professional.firstName ?? "").localizedCaseInsensitiveContains(query) ||
            (professional.lastName ?? "").localizedCaseInsensitiveContains(query) ||
            (professional.city ?? "").localizedCaseInsensitiveContains(query) ||
            (professional.postalCode ?? "").localizedCaseInsensitiveContains(query) ||
            (professional.resolvedActivity ?? "").localizedCaseInsensitiveContains(query) ||
            (professional.description ?? "").localizedCaseInsensitiveContains(query)
        }
        if directoryType == "Prestataires" {
            return matches.enumerated().sorted { left, right in
                if left.element.importedID == nil && right.element.importedID != nil { return true }
                if left.element.importedID != nil && right.element.importedID == nil { return false }
                if left.element.isDirectoryFeatured != right.element.isDirectoryFeatured {
                    return left.element.isDirectoryFeatured
                }
                return left.offset < right.offset
            }.map(\.element)
        }
        return matches
    }

    var body: some View {
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
                        if service.isLoading {
                            Section { ProgressView("Chargement des autres fiches…").font(.footnote) }
                        }
                        Section {
                            ForEach(filtered) { professional in
                                NavigationLink {
                                    if let miniSiteURL = professional.miniSiteURL {
                                        InAppSafariView(url: miniSiteURL)
                                            .ignoresSafeArea()
                                            .navigationTitle(professional.directoryDisplayName)
                                            .navigationBarTitleDisplayMode(.inline)
                                    } else {
                                        ProfessionalDetailView(professional: professional)
                                    }
                                } label: {
                                    ProfessionalRow(professional: professional)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                            }
                        }
                        if let warning = service.warningMessage {
                            Section {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text("Certaines fiches n’ont pas pu être chargées.")
                                        .font(.footnote).foregroundStyle(.primary)
                                }
                                Button("Réessayer le chargement") { Task { await service.reload() } }
                            } footer: {
                                Text(warning).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await service.reload() }
                }
            }
            .navigationTitle(title)
            .searchable(text: $searchText, prompt: "Nom, métier, ville, code postal…")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await service.reload() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Actualiser l’annuaire")
                }
            }
            .task { await service.loadIfNeeded() }
    }
}

private struct ProfessionalRow: View {
    let professional: WixPublicProfessional

    private var initials: String {
        professional.directoryDisplayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
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
                Text(professional.directoryDisplayName).font(.headline).foregroundStyle(.primary).lineLimit(2)
                if let organization = professional.directoryOrganizationName {
                    Text(organization).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
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

private struct ProfessionalPropertyRow: View {
    let listing: Listing

    var body: some View {
        HStack(spacing: 12) {
            NativeProfileImage(source: listing.gallery.first?.absoluteString ?? "", fallback: "house")
                .frame(width: 104, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(listing.title ?? "Bien immobilier")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(listing.formattedPrice)
                    .font(.subheadline.bold())
                    .foregroundStyle(PFTheme.deepGreen)
                if !listing.locationLabel.isEmpty {
                    Text(listing.locationLabel)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let surface = listing.formattedSurface { Text(surface) }
                    if let rooms = listing.rooms { Text("\(rooms) pièces") }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ProfessionalPropertyDetailView: View {
    let listing: Listing

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if listing.gallery.count > 1 {
                    TabView {
                        ForEach(Array(listing.gallery.enumerated()), id: \.offset) { image in
                            NativeProfileImage(source: image.element.absoluteString, fallback: "house")
                                .frame(maxWidth: .infinity).frame(height: 270)
                                .clipped()
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 270)
                } else {
                    NativeProfileImage(source: listing.gallery.first?.absoluteString ?? "", fallback: "house")
                        .frame(maxWidth: .infinity).frame(height: 270)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(listing.title ?? "Bien immobilier")
                        .font(.title2.bold())
                    Text(listing.formattedPrice)
                        .font(.title3.bold()).foregroundStyle(PFTheme.deepGreen)
                    if !listing.locationLabel.isEmpty {
                        Label(listing.locationLabel, systemImage: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 14) {
                        if let surface = listing.formattedSurface { Label(surface, systemImage: "square.dashed") }
                        if let rooms = listing.rooms { Label("\(rooms) pièces", systemImage: "door.left.hand.open") }
                        if let bedrooms = listing.bedrooms { Label("\(bedrooms) chambres", systemImage: "bed.double") }
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    if let description = listing.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !description.isEmpty {
                        ListingDescriptionTranslation(original: description)
                    }
                    if let rawURL = listing.sourceUrl, let url = URL(string: rawURL) {
                        Link(destination: url) {
                            Label("Voir l’annonce sur PartenaireFoyer", systemImage: "safari")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.teal)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Annonce immobilière")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(NativeBackButtonModifier())
    }
}

private struct ProfessionalDetailView: View {
    let professional: WixPublicProfessional
    @ObservedObject private var auth = WixAuthStore.shared
    @StateObject private var propertyService = ProfessionalListingsService()
    @State private var showImportedContact = false
    @State private var selectedMinisiteRequest: String?
    @State private var isFavorite = false
    @State private var isUpdatingFavorite = false
    @State private var favoriteError: String?

    private var favoriteRecordID: String? {
        guard professional.importedID == nil,
              professional.importedCategory != "courtier",
              !professional.isServiceProviderProfile else { return nil }
        return professional.cmsProfileID
    }

    private var favoriteType: String {
        switch professional.importedCategory {
        case "artisan": return "artisan"
        case "diagnostiqueur": return "diagnostiqueur"
        default: return "agent"
        }
    }

    private var showsProfessionalListings: Bool {
        professional.importedID == nil &&
            professional.importedCategory == nil &&
            !professional.isLocalProsProfile &&
            !professional.isServiceProviderProfile &&
            (professional.cmsProfileID != nil || professional.memberID != nil)
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
                    Text(professional.directoryDisplayName).font(.title2.bold())
                    if let organization = professional.directoryOrganizationName {
                        Text(organization).font(.headline).foregroundStyle(.secondary)
                    }
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
                    ListingDescriptionTranslation(original: description)
                }
            }

            if showsProfessionalListings {
                Section {
                    if propertyService.isLoading && propertyService.listings.isEmpty {
                        ProgressView("Chargement des biens…")
                    } else if let error = propertyService.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.footnote).foregroundStyle(.secondary)
                            Button("Réessayer") { Task { await propertyService.reload(for: professional) } }
                        }
                    } else if propertyService.listings.isEmpty {
                        Text("Aucun bien publié pour le moment.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(propertyService.listings) { listing in
                            NavigationLink {
                                ProfessionalPropertyDetailView(listing: listing)
                            } label: {
                                ProfessionalPropertyRow(listing: listing)
                            }
                        }
                    }
                } header: {
                    Text("Biens proposés par \(professional.directoryDisplayName)")
                } footer: {
                    if !propertyService.listings.isEmpty {
                        Text("\(propertyService.listings.count) bien\(propertyService.listings.count > 1 ? "s" : "") publié\(propertyService.listings.count > 1 ? "s" : "")")
                    }
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
            if professional.importedID == nil && professional.importedCategory != "courtier" {
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
        .modifier(NativeBackButtonModifier())
        .task(id: auth.member?.id) { await loadFavoriteStatus() }
        .task(id: professional.cmsProfileID ?? professional.memberID ?? professional.id) {
            if showsProfessionalListings {
                await propertyService.loadIfNeeded(for: professional)
            }
        }
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
                    error = "L’e-mail du professionnel n’est pas disponible pour cette annonce."
                    return
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
    case hub = "Rubriques"
    case realEstate = "Immobilier"
    case buyerSearches = "Recherches"
    case classifiedAds = "Petites annonces"
    var id: String { rawValue }
}

private struct NativeListingsView: View {
    @ObservedObject var service: ListingsService
    @ObservedObject var classifiedAds: ClassifiedAdsService
    @ObservedObject var buyerSearches: PublicBuyerSearchesService
    @ObservedObject var professionalsService: ProfessionalsService
    @Binding var catalogSection: NativeCatalogSection

    var body: some View {
        Group {
            if catalogSection == .hub {
                NavigationStack {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Trouvez ce qu’il vous faut")
                                .font(.title2.bold()).foregroundStyle(PFTheme.deepGreen)
                            Button {
                                catalogSection = .realEstate
                            } label: {
                                CatalogPhotoCard(title: "Annonces immobilières", subtitle: "Maisons, appartements et terrains", image: "CategoryMaison", symbol: "house.fill")
                            }
                            Button {
                                catalogSection = .buyerSearches
                            } label: {
                                CatalogPhotoCard(title: "Demandes de recherche", subtitle: "Les projets immobiliers des particuliers", image: "CategoryPro", symbol: "person.crop.circle.badge.magnifyingglass")
                            }
                            Button {
                                catalogSection = .classifiedAds
                            }
                            label: {
                                CatalogPhotoCard(title: "Petites annonces", subtitle: "Vendre, donner, échanger ou louer", image: "CategoryPetitesAnnonces", symbol: "tag.fill")
                            }
                            .buttonStyle(.plain)
                        }.padding(17)
                    }
                    .navigationTitle("Annonces")
                }
            } else {
                NativeCatalogContentView(service: service, classifiedAds: classifiedAds,
                                         buyerSearches: buyerSearches, professionalsService: professionalsService,
                                         catalogSection: $catalogSection)
            }
        }
    }
}

private struct NativeCatalogContentView: View {
    @ObservedObject var service: ListingsService
    @ObservedObject var classifiedAds: ClassifiedAdsService
    @ObservedObject var buyerSearches: PublicBuyerSearchesService
    @ObservedObject var professionalsService: ProfessionalsService
    @ObservedObject private var favorites = FavoritesStore.shared
    @State private var searchText = ""
    @AppStorage("partenairefoyer.searchCountryCode") private var searchCountryCode = CountryCatalog.defaultCode
    @Binding var catalogSection: NativeCatalogSection
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
    @State private var classifiedSort = "Catégorie"

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
            return listing.resolvedCountryCode == searchCountryCode &&
                (query.isEmpty ||
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
        case "Plus récentes": return filtered.sorted { left, right in
            let leftDate = left.catalogCreatedDate?.timeIntervalSince1970 ?? -.greatestFiniteMagnitude
            let rightDate = right.catalogCreatedDate?.timeIntervalSince1970 ?? -.greatestFiniteMagnitude
            if leftDate == rightDate { return left.id < right.id }
            return leftDate > rightDate
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
         !propertyCity.isEmpty, !propertyPostalCode.isEmpty,
         searchCountryCode != CountryCatalog.defaultCode].filter { $0 }.count
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
            let needsAttributes = !query.isEmpty ||
                (classifiedAttributeKey != "Aucun" && !classifiedAttributeValue.isEmpty) ||
                (usesVehicleFilters && (!classifiedBrand.isEmpty || !classifiedModel.isEmpty ||
                    !classifiedEnergy.isEmpty || !classifiedGearbox.isEmpty || yearMinimum != nil ||
                    yearMaximum != nil || mileageMaximum != nil))
            let attributes = needsAttributes ? (attributeDictionary(ad) ?? [:]) : [:]
            return ad.resolvedCountryCode == searchCountryCode &&
            (query.isEmpty ||
             ad.title.localizedCaseInsensitiveContains(query) ||
             (ad.category ?? "").localizedCaseInsensitiveContains(query) ||
             (ad.subcategory ?? "").localizedCaseInsensitiveContains(query) ||
             (ad.listingTypeLabel ?? "").localizedCaseInsensitiveContains(query) ||
             (ad.condition ?? "").localizedCaseInsensitiveContains(query) ||
             (ad.importedAttributesJSON ?? "").localizedCaseInsensitiveContains(query) ||
             attributeValue("brand", attributes: attributes).localizedCaseInsensitiveContains(query) ||
             attributeValue("model", attributes: attributes).localizedCaseInsensitiveContains(query) ||
             (ad.city ?? "").localizedCaseInsensitiveContains(query) ||
             (ad.postalCode ?? "").localizedCaseInsensitiveContains(query) ||
             (ad.description ?? "").localizedCaseInsensitiveContains(query)) &&
            (classifiedCategory == "Toutes" || ad.category == classifiedCategory) &&
            (classifiedSubcategory == "Toutes" || ad.subcategory == classifiedSubcategory) &&
            (classifiedListingType == "Tous" || ad.canonicalListingType == classifiedListingType) &&
            (classifiedCondition == "Tous" || ad.condition == classifiedCondition) &&
            (city.isEmpty || (ad.city ?? "").localizedCaseInsensitiveContains(city)) &&
            (postal.isEmpty || (ad.postalCode ?? "").localizedCaseInsensitiveContains(postal)) &&
            (minimum.map { minimumPrice in ad.price.map { $0 >= minimumPrice } ?? false } ?? true) &&
            (maximum.map { maximumPrice in ad.price.map { $0 <= maximumPrice } ?? false } ?? true) &&
            (classifiedAttributeKey == "Aucun" || classifiedAttributeValue.isEmpty ||
                attributeValue(classifiedAttributeKey, attributes: attributes).localizedCaseInsensitiveContains(classifiedAttributeValue)) &&
            (!usesVehicleFilters || classifiedBrand.isEmpty || attributeValue("brand", attributes: attributes).localizedCaseInsensitiveContains(classifiedBrand)) &&
            (!usesVehicleFilters || classifiedModel.isEmpty || attributeValue("model", attributes: attributes).localizedCaseInsensitiveContains(classifiedModel)) &&
            (!usesVehicleFilters || classifiedEnergy.isEmpty || attributeValue("energy", attributes: attributes).localizedCaseInsensitiveContains(classifiedEnergy)) &&
            (!usesVehicleFilters || classifiedGearbox.isEmpty || attributeValue("gearbox", attributes: attributes).localizedCaseInsensitiveContains(classifiedGearbox)) &&
            (!usesVehicleFilters || (yearMinimum.map { minimumYear in Double(attributeValue("year", attributes: attributes)).map { $0 >= minimumYear } ?? false } ?? true)) &&
            (!usesVehicleFilters || (yearMaximum.map { maximumYear in Double(attributeValue("year", attributes: attributes)).map { $0 <= maximumYear } ?? false } ?? true)) &&
            (!usesVehicleFilters || (mileageMaximum.map { maximumMileage in Double(attributeValue("mileage", attributes: attributes)).map { $0 <= maximumMileage } ?? false } ?? true))
        }
        switch classifiedSort {
        case "Catégorie":
            let categoryOrder = Dictionary(uniqueKeysWithValues: ClassifiedCategoryOptions.all.enumerated().map { ($1, $0) })
            return filtered.sorted { left, right in
                let leftCategory = left.category ?? "Divers"
                let rightCategory = right.category ?? "Divers"
                let leftOrder = categoryOrder[leftCategory] ?? ClassifiedCategoryOptions.all.count
                let rightOrder = categoryOrder[rightCategory] ?? ClassifiedCategoryOptions.all.count
                if leftOrder != rightOrder { return leftOrder < rightOrder }
                if leftCategory != rightCategory {
                    return leftCategory.localizedStandardCompare(rightCategory) == .orderedAscending
                }
                if left.catalogOrderDate != right.catalogOrderDate {
                    return left.catalogOrderDate > right.catalogOrderDate
                }
                return left.id < right.id
            }
        case "Prix croissant": return filtered.sorted { ($0.price ?? .greatestFiniteMagnitude) < ($1.price ?? .greatestFiniteMagnitude) }
        case "Prix décroissant": return filtered.sorted { ($0.price ?? -.greatestFiniteMagnitude) > ($1.price ?? -.greatestFiniteMagnitude) }
        default: return filtered
        }
    }

    private var filteredBuyerSearches: [WixPublicBuyerSearch] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return buyerSearches.searches }
        return buyerSearches.searches.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
                ($0.searchName ?? "").localizedCaseInsensitiveContains(query) ||
                ($0.projectDescription ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var activeClassifiedFilterCount: Int {
        [classifiedCategory != "Toutes", classifiedSubcategory != "Toutes", classifiedListingType != "Tous", classifiedCondition != "Tous",
         !classifiedCity.isEmpty, !classifiedPostalCode.isEmpty,
         searchCountryCode != CountryCatalog.defaultCode, !classifiedMinPrice.isEmpty, !classifiedMaxPrice.isEmpty,
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
        let excluded: Set<String> = [
            "pfImportedVehicleListing", "importedProfessionalVehicle", "importedVehicleId", "sourceUrl",
            "providerProfileId", "providerSlug", "originalListingRequired", "noRepublishingConsent",
            "catalogVersion", "externalDiscovery", "externalProfessionalName", "externalSellerName",
            "externalSellerUrl", "externalProfessionalUrl", "sourceId", "sourceName", "feedId",
            "feedUrl", "importedAt", "lastSyncedAt", "syncStatus", "ownerId", "accountId"
        ]
        let canonicalKey: (String) -> String = { value in
            value.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let normalizedExcluded = Set(excluded.map(canonicalKey))
        let keys = ads.flatMap { attributeDictionary($0).map { Array($0.keys) } ?? [] }
            .filter {
                let lower = $0.lowercased()
                return !normalizedExcluded.contains(canonicalKey($0)) && !$0.hasPrefix("_") && !lower.hasPrefix("classifiedowner") &&
                    !lower.hasPrefix("external") && !lower.hasPrefix("imported") &&
                    !lower.hasSuffix("id") && !lower.hasSuffix("url") && !lower.hasSuffix("slug")
            }
        return Array(Set(keys)).sorted { attributeLabel($0).localizedStandardCompare(attributeLabel($1)) == .orderedAscending }
    }

    private func attributeLabel(_ key: String) -> String {
        let normalized = key.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[_-]", with: " ", options: .regularExpression)
            .lowercased()
        let known: [String: String] = [
            "brand": "Marque", "model": "Modèle", "catalog version": "Version du catalogue",
            "color": "Couleur", "convertible": "Décapotable", "creator": "Créateur",
            "depth": "Profondeur", "edition": "Édition", "energy": "Énergie",
            "gearbox": "Boîte de vitesses", "height": "Hauteur", "length": "Longueur",
            "width": "Largeur", "weight": "Poids", "material": "Matière",
            "condition": "État", "size": "Taille", "gender": "Genre", "year": "Année",
            "mileage": "Kilométrage", "fuel": "Carburant", "power": "Puissance",
            "capacity": "Capacité", "style": "Style", "type": "Type", "manufacturer": "Fabricant",
            "rental unit": "Unité de location", "number of pieces": "Nombre de pièces",
            "storage": "Stockage", "ram": "Mémoire vive", "screen size": "Taille de l’écran",
            "battery health": "Santé de la batterie", "dual sim": "Double carte SIM",
            "unlocked": "Désimlocké", "processor": "Processeur", "connectivity": "Connectique",
            "resolution": "Résolution", "operating system": "Système d’exploitation",
            "storage type": "Type de stockage", "gpu": "Carte graphique", "format": "Format",
            "game title": "Titre du jeu", "title": "Titre", "reference": "Référence",
            "engine capacity": "Cylindrée", "fiscal power": "Puissance fiscale", "power hp": "Puissance",
            "doors": "Portes", "seats": "Places", "body type": "Carrosserie",
            "part type": "Type de pièce", "part reference": "Référence de la pièce",
            "oem reference": "Référence constructeur", "compatible make": "Marque compatible",
            "compatible model": "Modèle compatible", "compatible year from": "Année compatible dès",
            "compatible year to": "Année compatible jusqu’à", "engine code": "Code moteur",
            "external discovery": "Source de découverte", "external professional name": "Nom du professionnel",
            "external seller name": "Nom du vendeur"
        ]
        if let label = known[normalized] { return label }
        let words: [String: String] = [
            "brand": "Marque", "model": "Modèle", "catalog": "catalogue", "version": "version",
            "color": "Couleur", "convertible": "Décapotable", "creator": "Créateur", "depth": "Profondeur",
            "edition": "Édition", "energy": "Énergie", "gearbox": "Boîte", "height": "Hauteur",
            "length": "Longueur", "width": "Largeur", "weight": "Poids", "material": "Matière",
            "condition": "État", "size": "Taille", "year": "Année", "mileage": "Kilométrage",
            "fuel": "Carburant", "power": "Puissance", "capacity": "Capacité", "style": "Style",
            "type": "Type", "manufacturer": "Fabricant", "rental": "location", "unit": "unité",
            "number": "Nombre", "of": "de", "pieces": "pièces", "engine": "moteur", "doors": "portes"
        ]
        let tokens = normalized.split(separator: " ").map { token -> String in
            let word = String(token)
            return words[word] ?? word.capitalized
        }
        let label = tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return words.keys.contains(where: { normalized.split(separator: " ").contains(Substring($0)) })
            ? label
            : "Critère : \(label)"
    }

    private func attributeValue(_ key: String, attributes: [String: Any]) -> String {
        guard let value = attributes[key], !(value is NSNull) else { return "" }
        return String(describing: value)
    }

    private func attributeDictionary(_ ad: ClassifiedAd) -> [String: Any]? {
        guard let raw = ad.importedAttributesJSON?.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
    }

    var body: some View {
        // Each result set is filtered/sorted once for this render instead of
        // being recomputed for the count, empty state, and rows independently.
        let visibleListings = catalogSection == .realEstate ? filteredListings : []
        let visibleClassifiedAds = catalogSection == .classifiedAds ? filteredClassifiedAds : []
        let visibleBuyerSearches = catalogSection == .buyerSearches ? filteredBuyerSearches : []
        NavigationStack {
            List {
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
                            Text("\(visibleListings.count) bien\(visibleListings.count > 1 ? "s" : "")")
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
                                        TextField("Prix minimum (€)", text: $propertyMinPrice).keyboardType(.decimalPad)
                                        TextField("Prix maximum (€)", text: $propertyMaxPrice).keyboardType(.decimalPad)
                                        TextField("Surface minimum (m²)", text: $propertyMinSurface).keyboardType(.decimalPad)
                                        TextField("Surface maximum (m²)", text: $propertyMaxSurface).keyboardType(.decimalPad)
                                        TextField("Terrain minimum (m²)", text: $propertyMinLandSurface).keyboardType(.decimalPad)
                                    }
                                    Section("Agencement minimum") {
                                        TextField("Nombre de pièces", text: $propertyMinRooms).keyboardType(.numberPad)
                                        TextField("Nombre de chambres", text: $propertyMinBedrooms).keyboardType(.numberPad)
                                        TextField("Salles de bain", text: $propertyMinBathrooms).keyboardType(.numberPad)
                                    }
                                    Section("Localisation") {
                                        CountryPickerRow(countryCode: $searchCountryCode, title: "Pays")
                                        TextField("Ville", text: $propertyCity).textContentType(.addressCity)
                                        TextField("Code postal", text: $propertyPostalCode).keyboardType(.numberPad)
                                    }
                                    Section {
                                        Button("Effacer les filtres immobiliers", role: .destructive) {
                                            propertyTypeFilter = "Tous"
                                            propertyTransactionFilter = "Tous"
                                            propertyMinPrice = ""
                                            propertyMaxPrice = ""
                                            propertyMinSurface = ""
                                            propertyMaxSurface = ""
                                            propertyMinLandSurface = ""
                                            propertyMinRooms = ""
                                            propertyMinBedrooms = ""
                                            propertyMinBathrooms = ""
                                            propertyCity = ""
                                            propertyPostalCode = ""
                                            searchCountryCode = CountryCatalog.defaultCode
                                            propertySort = "Ordre du catalogue"
                                        }
                                    }
                                }
                                .navigationTitle("Filtres immobiliers")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) { Button("Fermer") { showPropertyFilters = false } }
                                    ToolbarItem(placement: .confirmationAction) { Button("Voir \(visibleListings.count)") { showPropertyFilters = false } }
                                }
                            }
                            .presentationDetents([.large])
                            .presentationDragIndicator(.visible)
                        }
                    }
                    if let warning = service.warningMessage {
                        Section {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote).foregroundStyle(.orange)
                            Button("Réessayer le chargement") { Task { await service.reload() } }
                        }
                    }
                    if (service.isLoading || service.isLoadingImported) && !service.listings.isEmpty {
                        Section {
                            if service.isLoading {
                                ProgressView("Chargement des biens Wix…").font(.footnote)
                            } else {
                                ProgressView().font(.footnote)
                            }
                        }
                    }
                    if (service.isLoading || service.isLoadingImported) && service.listings.isEmpty {
                        Section {
                            HStack {
                                Spacer()
                                if service.isLoading {
                                    ProgressView("Chargement des biens Wix…")
                                } else {
                                    ProgressView()
                                }
                                Spacer()
                            }
                        }
                    } else if let error = service.errorMessage, service.listings.isEmpty {
                        Section("Annonces immobilières") {
                            Label(error, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.orange)
                            Button("Réessayer") { Task { await service.reload() } }
                        }
                    } else if visibleListings.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ForEach(visibleListings) { listing in
                            NavigationLink(value: listing) {
                                ListingRow(listing: listing, isFavorite: favorites.contains(listing)) {
                                    favorites.toggle(listing)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                } else if catalogSection == .classifiedAds {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "tag.fill").foregroundStyle(.teal)
                            Text("Petites annonces Wix et annonces de véhicules importées, avec leurs critères et le lien vers le vendeur d’origine.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.teal.opacity(0.07))
                    }
                    if let warning = classifiedAds.warningMessage {
                        Section {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote).foregroundStyle(.orange)
                            Button("Réessayer le chargement") { Task { await classifiedAds.reload() } }
                        }
                    }
                    Section {
                        HStack {
                            Text("\(visibleClassifiedAds.count) annonce\(visibleClassifiedAds.count > 1 ? "s" : "")")
                                .font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                ForEach(["Catégorie", "Ordre du catalogue", "Prix croissant", "Prix décroissant"], id: \.self) { option in
                                    Button(option) { classifiedSort = option }
                                }
                            } label: {
                                Label(classifiedSort, systemImage: "arrow.up.arrow.down").font(.footnote)
                            }
                        }
                        Button { showClassifiedFilters = true } label: {
                            Label(activeClassifiedFilterCount == 0 ? "Filtres" : "Filtres (\(activeClassifiedFilterCount))",
                                  systemImage: "slider.horizontal.3")
                        }
                    }
                    if classifiedAds.isLoading && !classifiedAds.ads.isEmpty {
                        Section { ProgressView().font(.footnote) }
                    }
                    if classifiedAds.isLoading && classifiedAds.ads.isEmpty {
                        Section { HStack { Spacer(); ProgressView("Chargement des annonces Wix…"); Spacer() } }
                    } else if let error = classifiedAds.errorMessage, classifiedAds.ads.isEmpty {
                        Section("Petites annonces") {
                            Label(error, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.orange)
                            Button("Réessayer") { Task { await classifiedAds.reload() } }
                        }
                    } else if visibleClassifiedAds.isEmpty {
                        ContentUnavailableView {
                            Label("Aucune petite annonce trouvée", systemImage: "tag")
                        } description: {
                            Text(searchText.isEmpty ? "Les nouvelles annonces publiées sur PartenaireFoyer apparaîtront ici." : "Essayez une autre recherche.")
                        }
                        if classifiedAds.warningMessage != nil {
                            Section {
                                Button("Réessayer le chargement") { Task { await classifiedAds.reload() } }
                            }
                        }
                    } else {
                        ForEach(visibleClassifiedAds) { ad in
                            NavigationLink(value: ad) {
                                ClassifiedAdRow(ad: ad, isFavorite: favorites.contains(ad)) {
                                    favorites.toggle(ad)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                } else {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.magnifyingglass").foregroundStyle(.teal)
                            Text("Demandes actives de particuliers qui recherchent un bien. Les coordonnées personnelles ne sont pas affichées.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.teal.opacity(0.07))
                    }
                    Section {
                        Text("\(visibleBuyerSearches.count) demande\(visibleBuyerSearches.count > 1 ? "s" : "") active\(visibleBuyerSearches.count > 1 ? "s" : "")")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if buyerSearches.isLoading && buyerSearches.searches.isEmpty {
                        Section { HStack { Spacer(); ProgressView("Chargement des demandes…"); Spacer() } }
                    } else if let error = buyerSearches.errorMessage, buyerSearches.searches.isEmpty {
                        Section("Demandes de recherche") {
                            Label(error, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.orange)
                            Button("Réessayer") { Task { await buyerSearches.reload() } }
                        }
                    } else if visibleBuyerSearches.isEmpty {
                        ContentUnavailableView {
                            Label("Aucune demande active trouvée", systemImage: "magnifyingglass")
                        } description: {
                            Text(searchText.isEmpty ? "Les demandes actives publiées sur PartenaireFoyer apparaîtront ici." : "Essayez une autre recherche.")
                        }
                    } else {
                        ForEach(visibleBuyerSearches) { search in
                            BuyerSearchDirectoryRow(search: search)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                if catalogSection == .realEstate { await service.reload() }
                else if catalogSection == .classifiedAds { await classifiedAds.reload() }
                else { await buyerSearches.reload() }
            }
            .navigationDestination(for: Listing.self) { listing in
                ListingDetailView(listing: listing, listingsService: service, professionalsService: professionalsService)
            }
            .navigationDestination(for: ClassifiedAd.self) { ad in
                NativeClassifiedAdDetailView(ad: ad)
            }
            .navigationTitle(catalogSection.rawValue)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: catalogSection == .realEstate ? "Ville, code postal, bien…" : catalogSection == .classifiedAds ? "Article, catégorie, ville…" : "Ville, type de bien, demande…")
            .sheet(isPresented: $showClassifiedFilters) {
                NavigationStack {
                    Form {
                        Section("Annonce") {
                            Picker("Catégorie", selection: $classifiedCategory) {
                                Text("Toutes").tag("Toutes")
                                ForEach(Array(Set(classifiedAds.ads.compactMap(\.category))).sorted(), id: \.self) {
                                    Text($0).tag($0)
                                }
                            }
                            if classifiedCategory != "Toutes" {
                                Picker("Sous-catégorie", selection: $classifiedSubcategory) {
                                    Text("Toutes").tag("Toutes")
                                    ForEach(Array(Set(classifiedAds.ads.filter { $0.category == classifiedCategory }.compactMap(\.subcategory))).sorted(), id: \.self) {
                                        Text($0).tag($0)
                                    }
                                }
                            }
                            Picker("Type d’annonce", selection: $classifiedListingType) {
                                Text("Toutes").tag("Tous")
                                Text("Vendre").tag("sell")
                                Text("Donner").tag("give")
                                Text("Échanger").tag("exchange")
                                Text("Louer").tag("rent")
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel("Filtrer par type d’annonce : vendre, donner, échanger ou louer")
                            Picker("État", selection: $classifiedCondition) {
                                Text("Tous").tag("Tous")
                                ForEach(Array(Set(classifiedAds.ads.compactMap(\.condition))).sorted(), id: \.self) {
                                    Text($0).tag($0)
                                }
                            }
                        }
                        Section("Prix") {
                            TextField("Prix minimum (€)", text: $classifiedMinPrice).keyboardType(.decimalPad)
                            TextField("Prix maximum (€)", text: $classifiedMaxPrice).keyboardType(.decimalPad)
                        }
                        Section("Localisation") {
                            CountryPickerRow(countryCode: $searchCountryCode, title: "Pays")
                            TextField("Ville", text: $classifiedCity).textContentType(.addressCity)
                            TextField("Code postal", text: $classifiedPostalCode).keyboardType(.numberPad)
                        }
                        if !classifiedAttributeKeys.isEmpty {
                            Section("Caractéristiques de la catégorie") {
                                Picker("Critère", selection: $classifiedAttributeKey) {
                                    Text("Aucun").tag("Aucun")
                                    ForEach(classifiedAttributeKeys, id: \.self) { key in
                                        Text(attributeLabel(key)).tag(key)
                                    }
                                }
                                if classifiedAttributeKey != "Aucun" {
                                    TextField("Valeur à rechercher", text: $classifiedAttributeValue)
                                        .textInputAutocapitalization(.never)
                                }
                            }
                        }
                        if classifiedCategory == "Auto / Moto — accessoires" {
                            Section("Véhicules et pièces") {
                                TextField("Marque", text: $classifiedBrand)
                                TextField("Modèle", text: $classifiedModel)
                                TextField("Énergie", text: $classifiedEnergy)
                                TextField("Boîte de vitesses", text: $classifiedGearbox)
                                TextField("Année minimum", text: $classifiedYearMin).keyboardType(.numberPad)
                                TextField("Année maximum", text: $classifiedYearMax).keyboardType(.numberPad)
                                TextField("Kilométrage maximum", text: $classifiedMileageMax).keyboardType(.decimalPad)
                            }
                        }
                        Section {
                            Button("Effacer les filtres", role: .destructive) {
                                classifiedCategory = "Toutes"
                                classifiedSubcategory = "Toutes"
                                classifiedListingType = "Tous"
                                classifiedCondition = "Tous"
                                classifiedAttributeKey = "Aucun"
                                classifiedAttributeValue = ""
                                classifiedCity = ""
                                classifiedPostalCode = ""
                                searchCountryCode = CountryCatalog.defaultCode
                                classifiedMinPrice = ""
                                classifiedMaxPrice = ""
                                classifiedBrand = ""
                                classifiedModel = ""
                                classifiedYearMin = ""
                                classifiedYearMax = ""
                                classifiedMileageMax = ""
                                classifiedEnergy = ""
                                classifiedGearbox = ""
                                classifiedSort = "Ordre du catalogue"
                            }
                        }
                    }
                    .navigationTitle("Filtres des petites annonces")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Fermer") { showClassifiedFilters = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Voir \(visibleClassifiedAds.count)") { showClassifiedFilters = false } }
                    }
                }
            }
            .onChange(of: classifiedCategory) { _, value in
                classifiedSubcategory = "Toutes"
                classifiedAttributeKey = "Aucun"
                classifiedAttributeValue = ""
                if value != "Auto / Moto — accessoires" {
                    classifiedBrand = ""
                    classifiedModel = ""
                    classifiedYearMin = ""
                    classifiedYearMax = ""
                    classifiedMileageMax = ""
                    classifiedEnergy = ""
                    classifiedGearbox = ""
                }
            }
            .onChange(of: classifiedSubcategory) { _, _ in
                if classifiedAttributeKey != "Aucun" && !classifiedAttributeKeys.contains(classifiedAttributeKey) {
                    classifiedAttributeKey = "Aucun"
                    classifiedAttributeValue = ""
                }
            }
            .onChange(of: classifiedAds.ads) { _, ads in
                if classifiedSubcategory != "Toutes" && !ads.contains(where: { $0.category == classifiedCategory && $0.subcategory == classifiedSubcategory }) {
                    classifiedSubcategory = "Toutes"
                }
            }
            .task(id: catalogSection) {
                if catalogSection == .realEstate { await service.loadIfNeeded() }
                else if catalogSection == .classifiedAds { await classifiedAds.loadIfNeeded() }
                else { await buyerSearches.loadIfNeeded() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { catalogSection = .hub } label: {
                        Label("Rubriques", systemImage: "square.grid.2x2")
                    }
                }
            }
        }
    }
}

private struct BuyerSearchDirectoryRow: View {
    let search: WixPublicBuyerSearch

    private var criteria: [String] {
        var values: [String] = []
        if let budget = search.budgetLabel { values.append(budget) }
        if let area = search.minSurface, area > 0 { values.append("Surface min. : \(Int(area)) m²") }
        if let land = search.minLandSurface, land > 0 { values.append("Terrain min. : \(Int(land)) m²") }
        if let rooms = search.minRooms, rooms > 0 { values.append("\(Int(rooms)) pièces min.") }
        if let bedrooms = search.minBedrooms, bedrooms > 0 { values.append("\(Int(bedrooms)) chambres min.") }
        if let bathrooms = search.minBathrooms, bathrooms > 0 { values.append("\(Int(bathrooms)) salles de bain min.") }
        if let radius = search.radius, radius > 0 { values.append("Rayon : \(Int(radius)) km") }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(search.title).font(.headline)
            if let name = search.searchName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name != search.title {
                Text(name).font(.subheadline).foregroundStyle(.secondary)
            }
            if let location = search.locationLabel { Label(location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary) }
            if !criteria.isEmpty { Text(criteria.joined(separator: " · ")).font(.subheadline) }
            if let description = search.projectDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                Text(description).font(.footnote).foregroundStyle(.secondary).lineLimit(4)
            }
            if let createdAt = search.createdAt, !createdAt.isEmpty {
                Text("Demande publiée le \(createdAt.prefix(10))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                if let listingType = ad.listingTypeLabel {
                    Text(listingType).font(.caption.weight(.semibold)).foregroundStyle(.teal)
                }
                if ad.isImported {
                    Label("Annonce importée", systemImage: "arrow.down.doc")
                        .font(.caption2).foregroundStyle(.secondary)
                }
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
    @ObservedObject private var auth = WixAuthStore.shared
    @ObservedObject private var favorites = FavoritesStore.shared
    @State private var activeSheet: ClassifiedDetailSheet?

    private var checkoutURL: URL? {
        guard !ad.isImported, ad.id.hasPrefix("wix-classified-") else { return nil }
        let cmsID = String(ad.id.dropFirst("wix-classified-".count))
        guard cmsID.range(of: "^[A-Za-z0-9_-]{1,200}$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://www.partenairefoyer.com/petites-annonces/checkout/\(cmsID)")
    }

    private var handDeliveryCheckoutURL: URL? {
        guard let checkoutURL,
              var components = URLComponents(url: checkoutURL, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "delivery", value: "hand_delivery")]
        return components.url
    }

    private var importedFacts: [(key: String, value: String)] {
        guard let raw = ad.importedAttributesJSON?.data(using: .utf8),
              let values = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else { return [] }
        let labels: [(String, String)] = [
            ("brand", "Marque"), ("model", "Modèle"), ("year", "Année"), ("mileage", "Kilométrage"),
            ("energy", "Énergie"), ("gearbox", "Boîte"), ("bodyType", "Carrosserie"), ("engineCapacity", "Cylindrée"),
            ("fiscalPower", "Puissance fiscale"), ("powerHp", "Puissance"), ("doors", "Portes"), ("seats", "Places"),
            ("color", "Couleur"), ("partType", "Type de pièce"), ("partReference", "Référence"),
            ("oemReference", "Référence constructeur"), ("compatibleMake", "Marque compatible"),
            ("compatibleModel", "Modèle compatible"), ("compatibleYearFrom", "Année compatible dès"),
            ("compatibleYearTo", "Année compatible jusqu’à"), ("engineCode", "Code moteur"), ("dimensions", "Dimensions")
        ]
        let knownLabels = Dictionary(uniqueKeysWithValues: labels)
        let hiddenKeys: Set<String> = [
            "catalogVersion", "classifiedOwnerType", "classifiedOwnerProfileId", "classifiedOwnerAccountId",
            "classifiedOwnerDisplayName", "classifiedOwnerRoleLabel", "classifiedOwnerEmail", "classifiedOwnerPhone",
            "classifiedOwnerImage", "classifiedOwnerDashboardPath", "pfImportedVehicleListing",
            "importedProfessionalVehicle", "importedVehicleId", "sourceUrl", "providerProfileId", "providerSlug",
            "externalReference", "originalListingRequired", "noRepublishingConsent"
        ]
        return values.keys.sorted().compactMap { key in
            guard !hiddenKeys.contains(key), !key.hasPrefix("classifiedOwner"), !key.hasPrefix("pf"),
                  let value = values[key], !(value is NSNull) else { return nil }
            let text: String
            if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
                text = number.boolValue ? "Oui" : "Non"
            } else if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]),
                      let json = String(data: data, encoding: .utf8), value is [Any] || value is [String: Any] {
                text = json
            } else {
                text = String(describing: value)
            }
            let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanText.isEmpty else { return nil }
            let readableKey = key.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            let label = knownLabels[key] ?? (String(readableKey.prefix(1)).uppercased() + String(readableKey.dropFirst()))
            return (label, cleanText)
        }
    }

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
                if let listingType = ad.listingTypeLabel {
                    Label(listingType, systemImage: "tag")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.teal)
                }
                if ad.isImported {
                    Label("Annonce importée depuis un site partenaire", systemImage: "arrow.down.doc")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let category = ad.category {
                    Label([category, ad.subcategory].compactMap { $0 }.joined(separator: " · "), systemImage: "tag")
                        .font(.subheadline).foregroundStyle(.teal)
                }
                if let condition = ad.condition, !condition.isEmpty {
                    Label(condition, systemImage: "checkmark.seal")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let provider = ad.importedProviderName, ad.isImported {
                    Label(provider, systemImage: "building.2")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !importedFacts.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Caractéristiques").font(.headline)
                        ForEach(importedFacts, id: \.key) { fact in
                            HStack(alignment: .firstTextBaseline) {
                                Text(fact.key).foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                Text(fact.value).multilineTextAlignment(.trailing)
                            }.font(.subheadline)
                        }
                    }
                }
                if !ad.locationLabel.isEmpty {
                    Label(ad.locationLabel, systemImage: "mappin.and.ellipse")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let description = ad.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description").font(.headline)
                        ListingDescriptionTranslation(original: description)
                    }
                }
                if let checkoutURL {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            activeSheet = .web(InAppSafariPage(url: checkoutURL))
                        } label: {
                            Label("Acheter avec livraison", systemImage: "shippingbox")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                        if let handDeliveryCheckoutURL {
                            Button {
                                activeSheet = .web(InAppSafariPage(url: handDeliveryCheckoutURL))
                            } label: {
                                Label("Acheter avec remise en main propre", systemImage: "person.crop.rectangle")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.teal)
                        }
                        Text("Le paiement sécurisé, les offres de prix et, pour la livraison, le choix d’un Point Relais Mondial Relay sont finalisés dans le checkout PartenaireFoyer.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let wixDetailURL = ad.wixDetailURL {
                    Button {
                        activeSheet = .site(InAppSafariPage(url: wixDetailURL))
                    } label: {
                        Label("Contacter le vendeur sur PartenaireFoyer", systemImage: "message")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.teal)
                    Text("La messagerie s’ouvre dans le parcours sécurisé PartenaireFoyer et reste liée à votre compte Wix.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !ad.isImported, ad.id.hasPrefix("wix-classified-") {
                    Button {
                        activeSheet = .report(ad)
                    } label: {
                        Label("Signaler cette annonce", systemImage: "flag")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                    .tint(.red)
                }
                if let externalURL = ad.externalURL {
                    Link(destination: externalURL) {
                        Label("Voir l’annonce chez le vendeur", systemImage: "arrow.up.right.square")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                }
            }
            .padding(18)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Petite annonce")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(NativeBackButtonModifier())
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .report(let ad):
                NativeClassifiedReportSheet(ad: ad)
            case .web(let page):
                InAppSafariView(url: page.url)
                    .ignoresSafeArea()
            case .site(let page):
                ProfessionalPortalWebView(
                    url: page.url,
                    initialToken: auth.professionalPortalToken,
                    title: "Contacter le vendeur"
                ) { token in
                    auth.adoptProfessionalPortalSession(token: token, email: auth.professionalPortalEmail)
                }
            }
        }
    }
}

private enum ClassifiedDetailSheet: Identifiable {
    case report(ClassifiedAd)
    case web(InAppSafariPage)
    case site(InAppSafariPage)

    var id: String {
        switch self {
        case .report(let ad): return "report-\(ad.id)"
        case .web(let page): return "web-\(page.id.uuidString)"
        case .site(let page): return "site-\(page.id.uuidString)"
        }
    }
}

private struct InAppSafariPage: Identifiable {
    let id = UUID()
    let url: URL
}

private struct NativeClassifiedReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = WixAuthStore.shared
    @AppStorage("partenairefoyer.activeRole") private var activeRoleRaw = ""
    let ad: ClassifiedAd
    @State private var selectedReason = ""
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private let reasons: [(id: String, label: String, description: String)] = [
        ("fraud_scam", "Arnaque ou fraude", "Paiement suspect, faux vendeur, tentative de fraude ou annonce trompeuse."),
        ("prohibited_item", "Objet ou service interdit", "L’annonce semble proposer un produit ou un service interdit sur la plateforme."),
        ("sexual_explicit", "Contenu sexuel explicite", "Pornographie, service sexuel ou contenu explicitement sexuel."),
        ("drugs_restricted_medicine", "Drogues ou médicament réglementé", "Stupéfiants ou médicament soumis à prescription ou réglementation."),
        ("weapon_dangerous", "Arme ou objet dangereux interdit", "Arme, munition, explosif ou autre objet dangereux dont la vente est interdite."),
        ("counterfeit_stolen", "Contrefaçon ou objet volé", "Produit contrefait, provenance douteuse ou objet potentiellement volé."),
        ("hate_violence_harassment", "Haine, violence ou harcèlement", "Contenu haineux, menaçant, violent ou ciblant une personne ou un groupe."),
        ("personal_data", "Données personnelles sensibles", "Document d’identité, données bancaires ou informations personnelles exposées."),
        ("misleading_category", "Mauvaise catégorie ou description", "L’annonce est volontairement mal classée ou ne correspond pas à sa description."),
        ("other", "Autre problème", "Un autre motif nécessite une vérification par l’administration.")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Annonce signalée") {
                    Text(ad.title).font(.headline)
                    Text("Le signalement sera transmis à l’administration pour vérification.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Motif") {
                    ForEach(reasons, id: \.id) { reason in
                        Button {
                            selectedReason = reason.id
                            errorMessage = nil
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: selectedReason == reason.id ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(selectedReason == reason.id ? .red : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(reason.label).font(.subheadline.weight(.semibold))
                                    Text(reason.description).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Précisions facultatives") {
                    TextEditor(text: $details).frame(minHeight: 110)
                    Text("\(details.count)/2000").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .onChange(of: details) { _, value in
                    if value.count > 2000 { details = String(value.prefix(2000)) }
                }
                if auth.member == nil {
                    Section {
                        Label("Connectez-vous pour confirmer votre profil avant le signalement.", systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                } else if !hasReportIdentity {
                    Section {
                        Label("Ouvrez votre espace particulier ou professionnel avant d’envoyer un signalement.", systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                if let errorMessage {
                    Section("Signalement impossible") {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
                if let successMessage {
                    Section("Signalement envoyé") {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .font(.footnote).foregroundStyle(.green)
                    }
                }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting { ProgressView("Envoi…") }
                            else { Label("Envoyer le signalement", systemImage: "flag.fill") }
                            Spacer()
                        }
                    }
                    .disabled(isSubmitting || selectedReason.isEmpty || !hasReportIdentity || successMessage != nil)
                }
            }
            .navigationTitle("Signaler l’annonce")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(successMessage == nil ? "Annuler" : "Fermer") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
        }
    }

    private var hasReportIdentity: Bool {
        auth.member != nil && ["particulier", "professionnel", "courtier", "artisan", "diagnostiqueur", "prestataire"].contains(activeRoleRaw)
    }

    @MainActor
    private func submit() async {
        guard !selectedReason.isEmpty, let adID = cmsID else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let key = "partenairefoyer.classifiedReportClientKey"
        let clientKey = UserDefaults.standard.string(forKey: key) ?? UUID().uuidString
        UserDefaults.standard.set(clientKey, forKey: key)
        do {
            successMessage = try await auth.reportClassifiedAd(
                adID: adID,
                reason: selectedReason,
                details: details,
                clientReportKey: clientKey
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var cmsID: String? {
        guard ad.id.hasPrefix("wix-classified-") else { return nil }
        let value = String(ad.id.dropFirst("wix-classified-".count))
        return value.range(of: "^[A-Za-z0-9_-]{1,200}$", options: .regularExpression) == nil ? nil : value
    }
}

private struct NativeFavoritesView: View {
    @ObservedObject var service: ListingsService
    @ObservedObject var classifiedAds: ClassifiedAdsService
    @ObservedObject var professionalsService: ProfessionalsService
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var auth = WixAuthStore.shared
    @State private var professionalFavorites: [WixProfessionalFavorite] = []
    @State private var isLoadingProfessionalFavorites = false
    @State private var professionalFavoritesError: String?
    private var savedListings: [Listing] { service.listings.filter { favorites.contains($0) } }
    private var savedClassifiedAds: [ClassifiedAd] { classifiedAds.ads.filter { favorites.contains($0) } }
    private var savedProfessionals: [(WixProfessionalFavorite, WixPublicProfessional)] {
        professionalFavorites.compactMap { favorite in
            guard let professional = professionalsService.professionals.first(where: { $0.cmsProfileID == favorite.professionalID }) else { return nil }
            return (favorite, professional)
        }
    }

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
                Section("Professionnels") {
                    if auth.member?.loginEmailVerified != true {
                        Label("Connectez-vous depuis l’onglet Menu avec une adresse vérifiée pour voir vos professionnels favoris.", systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if isLoadingProfessionalFavorites {
                        ProgressView("Chargement de vos professionnels favoris…")
                    } else if let professionalFavoritesError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(professionalFavoritesError).font(.footnote).foregroundStyle(.red)
                            Button("Réessayer") { Task { await reloadProfessionalFavorites() } }
                        }
                    } else if savedProfessionals.isEmpty {
                        Text("Aucun professionnel favori enregistré.").foregroundStyle(.secondary)
                    } else {
                        ForEach(professionalFavorites) { favorite in
                            if let professional = professionalsService.professionals.first(where: { $0.cmsProfileID == favorite.professionalID }) {
                                NavigationLink(value: professional.id) {
                                    ProfessionalRow(professional: professional)
                                }
                                .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                                .swipeActions {
                                    Button("Retirer", systemImage: "heart.slash", role: .destructive) {
                                        Task {
                                            do {
                                                _ = try await auth.toggleProfessionalFavorite(favorite.professionalID, professionalType: favorite.professionalType)
                                                await reloadProfessionalFavorites()
                                            } catch {
                                                professionalFavoritesError = error.localizedDescription
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationDestination(for: Listing.self) { ListingDetailView(listing: $0, listingsService: service, professionalsService: professionalsService) }
            .navigationDestination(for: ClassifiedAd.self) { NativeClassifiedAdDetailView(ad: $0) }
            .navigationDestination(for: String.self) { id in
                if let professional = professionalsService.professionals.first(where: { $0.id == id }) {
                    ProfessionalDetailView(professional: professional)
                }
            }
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
            .task(id: auth.member?.id) {
                await professionalsService.loadIfNeeded()
                await reloadProfessionalFavorites()
            }
        }
    }

    @MainActor
    private func reloadProfessionalFavorites() async {
        guard auth.member?.loginEmailVerified == true else {
            professionalFavorites = []
            professionalFavoritesError = nil
            isLoadingProfessionalFavorites = false
            return
        }
        isLoadingProfessionalFavorites = true
        professionalFavoritesError = nil
        defer { isLoadingProfessionalFavorites = false }
        do {
            professionalFavorites = try await auth.fetchProfessionalFavorites()
        } catch {
            professionalFavoritesError = error.localizedDescription
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
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url) {
            thumbnail = nil
            guard let url else { return }
            if let cached = ListingThumbnailCache.image(for: url) {
                thumbnail = cached
                return
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled,
                      (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else { return }
                let decoded = await Task.detached(priority: .utility) { () -> CGImage? in
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1200
                    ]
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                }.value
                guard !Task.isCancelled, let decoded else { return }
                let image = UIImage(cgImage: decoded)
                ListingThumbnailCache.insert(image, for: url)
                thumbnail = image
            } catch {
                // Keep the light placeholder when a remote photo is unavailable.
            }
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.teal.opacity(0.09))
            .overlay(Image(systemName: "house.fill").font(.title2).foregroundStyle(.teal.opacity(0.6)))
    }
}

@MainActor
private enum ListingThumbnailCache {
    private static let storage: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 100
        return cache
    }()

    static func image(for url: URL) -> UIImage? {
        storage.object(forKey: url as NSURL)
    }

    static func insert(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        storage.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

private struct ListingDetailView: View {
    let listing: Listing
    @ObservedObject var listingsService: ListingsService
    @ObservedObject var professionalsService: ProfessionalsService
    @ObservedObject private var favorites = FavoritesStore.shared
    @State private var showImportedContact = false
    @State private var showProfessionalContact = false
    @State private var showPrivateOwnerContact = false
    @AppStorage("partenairefoyer.language") private var appLanguage = "fr"

    private var listingOwnerIDs: Set<String> {
        let values = (listing.professionalOwnerIDs ?? []) + [listing.professionalID].compactMap { $0 }
        return Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private var linkedProfessional: WixPublicProfessional? {
        if !listingOwnerIDs.isEmpty,
           let professional = professionalsService.professionals.first(where: { profile in
               let ids = [profile.memberID, profile.cmsProfileID, profile.id, "prosprofile-\(profile.id)"]
                   .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
               return ids.contains { candidate in
                   listingOwnerIDs.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
               }
           }) {
            return professional
        }
        if let importedID = listing.importedProId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !importedID.isEmpty {
            return professionalsService.professionals.first {
                $0.importedID == importedID || $0.id == importedID || $0.cmsProfileID == importedID
            }
        }
        return nil
    }

    private var professionalIdentityIDs: Set<String> {
        let values = Array(listingOwnerIDs) + [
            linkedProfessional?.memberID, linkedProfessional?.cmsProfileID, linkedProfessional?.id
        ].compactMap { $0 }
        return Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private var otherListings: [Listing] {
        listingsService.listings.filter { candidate in
            guard candidate.id != listing.id else { return false }
            let candidateOwnerIDs = (candidate.professionalOwnerIDs ?? []) + [candidate.professionalID].compactMap { $0 }
            if !professionalIdentityIDs.isEmpty {
                let isProfessional = ["professionnel", "professional"].contains(candidate.ownerType?.lowercased() ?? "")
                return isProfessional && candidateOwnerIDs.contains { candidateID in
                    professionalIdentityIDs.contains {
                        $0.caseInsensitiveCompare(candidateID.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                    }
                }
            }
            if let importedProId = listing.importedProId, !importedProId.isEmpty {
                return candidate.importedProId == importedProId
            }
            return false
        }.prefix(8).map { $0 }
    }

    private var recommendedProfessionals: [WixPublicProfessional] {
        let postalCode = (listing.postalCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let city = (listing.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard postalCode.count >= 2 || !city.isEmpty else { return [] }
        let department = String(postalCode.prefix(2))
        return professionalsService.professionals
            .filter { professional in
                if let linkedProfessional, professional.id == linkedProfessional.id { return false }
                let proPostalCode = (professional.postalCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let proCity = (professional.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let sameDepartment = department.count == 2 && proPostalCode.hasPrefix(department)
                let sameCity = !city.isEmpty && proCity.compare(city, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                return sameDepartment || sameCity
            }
            .sorted { left, right in
                let leftExact = left.postalCode == postalCode
                let rightExact = right.postalCode == postalCode
                if leftExact != rightExact { return leftExact }
                let leftCity = left.city?.compare(city, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                let rightCity = right.city?.compare(city, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                if leftCity != rightCity { return leftCity }
                return left.resolvedName.localizedCaseInsensitiveCompare(right.resolvedName) == .orderedAscending
            }
            .prefix(6)
            .map { $0 }
    }

    private var listingShareText: String {
        let title = listing.title ?? (appLanguage == "en" ? "Property listing" : "Annonce immobilière")
        var parts = [title, displayPrice, listing.locationLabel]
        if let sourceUrl = listing.sourceUrl, !sourceUrl.isEmpty { parts.append(sourceUrl) }
        else { parts.append(appLanguage == "en" ? "Find this listing in the PartenaireFoyer app." : "Retrouvez cette annonce dans l’application PartenaireFoyer.") }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private var displayPrice: String {
        guard let price = listing.price else { return appLanguage == "en" ? "Price on request" : "Prix sur demande" }
        return price.formatted(.currency(code: "EUR").locale(Locale(identifier: appLanguage == "en" ? "en_US" : "fr_FR")))
    }

    private func professionalDestination(_ professional: WixPublicProfessional) -> some View {
        Group {
            if let url = professional.miniSiteURL {
                InAppSafariView(url: url).ignoresSafeArea()
            } else {
                ProfessionalDetailView(professional: professional)
            }
        }
    }

    private var propertyTypeLabel: String? {
        guard let value = listing.propertyType?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        switch value.lowercased() {
        case "house", "maison": return appLanguage == "en" ? "House" : "Maison"
        case "apartment", "appartement": return appLanguage == "en" ? "Apartment" : "Appartement"
        case "land", "terrain": return appLanguage == "en" ? "Land" : "Terrain"
        case "building", "immeuble": return appLanguage == "en" ? "Building" : "Immeuble"
        case "commercial", "commerce": return appLanguage == "en" ? "Commercial" : "Commerce"
        case "office", "bureau": return appLanguage == "en" ? "Office" : "Bureau"
        case "garage": return "Garage"
        default: return value.capitalized
        }
    }

    private var transactionTypeLabel: String? {
        guard let value = listing.transactionType?.lowercased() else { return nil }
        if ["sale", "vente", "sell"].contains(value) { return appLanguage == "en" ? "For sale" : "À vendre" }
        if ["rent", "location", "rental"].contains(value) { return appLanguage == "en" ? "For rent" : "À louer" }
        return listing.transactionType
    }

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
                        Text(displayPrice).font(.title2.bold())
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
                    .accessibilityLabel(favorites.contains(listing)
                        ? (appLanguage == "en" ? "Remove from favorites" : "Retirer des favoris")
                        : (appLanguage == "en" ? "Add to favorites" : "Ajouter aux favoris"))
                }

                if let title = listing.title, !title.isEmpty {
                    LocalizedListingTitle(original: title, language: appLanguage)
                } else {
                    Text(appLanguage == "en" ? "Property listing" : "Annonce immobilière")
                        .font(.title3.weight(.semibold))
                }

                HStack(spacing: 12) {
                    if let propertyTypeLabel {
                        Label(propertyTypeLabel, systemImage: "house")
                    }
                    if let transactionTypeLabel {
                        Label(transactionTypeLabel, systemImage: "tag")
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.teal)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 10) {
                    if let surface = listing.formattedSurface { ListingFact(symbol: "square.dashed", text: surface) }
                    if let landSurface = listing.landSurface, landSurface > 0 {
                            ListingFact(symbol: "tree", text: "\(appLanguage == "en" ? "Land" : "Terrain") \(landSurface.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: appLanguage == "en" ? "en_US" : "fr_FR")))) m²")
                    }
                    if let rooms = listing.rooms { ListingFact(symbol: "door.left.hand.open", text: "\(rooms) \(appLanguage == "en" ? "rooms" : "pièces")") }
                    if let bedrooms = listing.bedrooms { ListingFact(symbol: "bed.double", text: "\(bedrooms) \(appLanguage == "en" ? "bedrooms" : "ch.")") }
                    if let bathrooms = listing.bathrooms { ListingFact(symbol: "shower", text: "\(bathrooms) \(appLanguage == "en" ? "bathrooms" : "SDB")") }
                }

                if let description = listing.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description").font(.headline)
                        ListingDescriptionTranslation(original: description, language: appLanguage)
                    }
                }

                PropertyCostEstimator(listing: listing, language: appLanguage)
                ListingNearbyMap(listing: listing, language: appLanguage)

                VStack(alignment: .leading, spacing: 7) {
                    Label(appLanguage == "en" ? "Stay safe during your property search" : "Restez vigilant lors de votre recherche immobilière", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                    Text(appLanguage == "en"
                         ? "Never send money before verifying the property and the identity of your contact. Use the in-app contact options when possible."
                         : "Ne versez jamais d’argent avant d’avoir vérifié le bien et l’identité de votre interlocuteur. Utilisez si possible les moyens de contact de l’application.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))

                if let source = listing.sourceUrl, let sourceURL = URL(string: source) {
                    Link(destination: sourceURL) {
                        Label(appLanguage == "en" ? "View original listing" : "Voir l’annonce d’origine", systemImage: "arrow.up.right.square")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.02, green: 0.38, blue: 0.34))
                }

                if listing.canContactImportedProfessional {
                    Button { showImportedContact = true } label: {
                        Label(appLanguage == "en" ? "Contact via PartenaireFoyer" : "Contacter via PartenaireFoyer", systemImage: "envelope.badge")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.02, green: 0.38, blue: 0.34))
                }
                if let linkedProfessional {
                    Button { showProfessionalContact = true } label: {
                        Label(appLanguage == "en" ? "Contact the professional" : "Contacter le professionnel", systemImage: "envelope.badge")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.02, green: 0.38, blue: 0.34))
                    .accessibilityHint(appLanguage == "en" ? "Sends a request to the professional's Wix account." : "Envoie une demande native dans l’espace professionnel Wix.")
                    .sheet(isPresented: $showProfessionalContact) {
                        NavigationStack {
                            ProfessionalMinisiteRequestForm(
                                professional: linkedProfessional,
                                requestType: "contact",
                                listingContext: listing
                            )
                        }
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                    }
                }
                if listing.id.hasPrefix("wix-private-") {
                    Button { showPrivateOwnerContact = true } label: {
                        Label(appLanguage == "en" ? "Contact the owner" : "Contacter le propriétaire", systemImage: "envelope.badge")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.02, green: 0.38, blue: 0.34))
                }

                if let professional = linkedProfessional {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(appLanguage == "en" ? "Listing professional" : "Professionnel de l’annonce").font(.headline)
                        HStack(spacing: 12) {
                            if let logo = professional.logo {
                                NativeProfileImage(source: logo, fallback: "building.2")
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(professional.resolvedName).font(.subheadline.bold())
                                if let activity = professional.resolvedActivity {
                                    Text(activity).font(.caption).foregroundStyle(.secondary)
                                }
                                if !professional.locationLabel.isEmpty {
                                    Text(professional.locationLabel).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        if let phone = professional.publicPhone {
                            let dialable = phone.filter { $0.isNumber || $0 == "+" }
                            if let url = URL(string: "tel:\(dialable)"), !dialable.isEmpty {
                                Link(destination: url) {
                                    Label(appLanguage == "en" ? "Call \(professional.directoryDisplayName)" : "Appeler \(professional.directoryDisplayName)", systemImage: "phone.fill")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        if let email = professional.professionalEmail {
                            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let url = URL(string: "mailto:\(trimmed)"), !trimmed.isEmpty {
                                Link(destination: url) {
                                    Label(appLanguage == "en" ? "Send an email" : "Envoyer un e-mail", systemImage: "envelope.fill")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        NavigationLink {
                            professionalDestination(professional)
                        } label: {
                            Label(appLanguage == "en" ? "View professional profile" : "Voir la fiche du professionnel", systemImage: "person.crop.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                }

                ShareLink(item: listingShareText) {
                    Label(appLanguage == "en" ? "Share this listing" : "Partager cette annonce", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.bordered)

                if !otherListings.isEmpty {
                    let professionalName = linkedProfessional?.directoryDisplayName ?? "ce professionnel"
                    VStack(alignment: .leading, spacing: 12) {
                        Text(appLanguage == "en" ? "Other properties from \(professionalName)" : "Les autres biens de \(professionalName)")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(otherListings) { other in
                                    NavigationLink(value: other) {
                                        VStack(alignment: .leading, spacing: 7) {
                                            ListingImage(url: other.gallery.first)
                                                .frame(width: 220, height: 145)
                                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                            Text(other.price.map { $0.formatted(.currency(code: "EUR").locale(Locale(identifier: appLanguage == "en" ? "en_US" : "fr_FR"))) } ?? (appLanguage == "en" ? "Price on request" : "Prix sur demande")).font(.subheadline.bold())
                                            Text(other.title ?? (appLanguage == "en" ? "Property listing" : "Annonce immobilière"))
                                                .font(.subheadline)
                                                .lineLimit(2)
                                            Text(other.locationLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        .frame(width: 220, alignment: .leading)
                                        .foregroundStyle(.primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                if !recommendedProfessionals.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(appLanguage == "en" ? "Professionals near this property" : "Professionnels suggérés près de ce bien")
                            .font(.headline)
                        ForEach(recommendedProfessionals) { professional in
                            NavigationLink {
                                professionalDestination(professional)
                            } label: {
                                ProfessionalRow(professional: professional)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding(18)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(appLanguage == "en" ? "Listing details" : "Détail de l’annonce")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(NativeBackButtonModifier())
        .sheet(isPresented: $showImportedContact) {
            NavigationStack {
                ImportedListingContactForm(listing: listing)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPrivateOwnerContact) {
            NavigationStack { PrivatePropertyContactForm(listing: listing) }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { await professionalsService.loadIfNeeded() }
    }
}

private struct AppLanguageControl: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 3) {
            languageButton("FR", code: "fr")
            languageButton("EN", code: "en")
        }
        .padding(3)
        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        .accessibilityLabel("App language")
    }

    private func languageButton(_ title: String, code: String) -> some View {
        Button { selection = code } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(selection == code ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selection == code ? PFTheme.brand : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == code ? .isSelected : [])
    }
}

private struct PropertyCostEstimator: View {
    let listing: Listing
    let language: String
    @State private var downPayment = ""
    @State private var annualRate = "3.21"
    @State private var insuranceRate = "0.30"
    @State private var durationYears = 20
    @State private var acquisitionType = "old"

    private var isEnglish: Bool { language == "en" }
    private var isRental: Bool {
        let value = listing.transactionType?.lowercased() ?? ""
        return value.contains("rent") || value.contains("location")
    }
    private var amount: Double { max(0, listing.price ?? 0) }
    private var ownContribution: Double { max(0, Double(downPayment.replacingOccurrences(of: ",", with: ".")) ?? 0) }
    private var rate: Double { max(0, Double(annualRate.replacingOccurrences(of: ",", with: ".")) ?? 3.21) }
    private var insurance: Double { max(0, Double(insuranceRate.replacingOccurrences(of: ",", with: ".")) ?? 0.30) }
    private var fees: ClosedRange<Double> {
        let ratio: (Double, Double) = acquisitionType == "new" ? (0.02, 0.03) : (0.07, 0.08)
        return (amount * ratio.0)...(amount * ratio.1)
    }
    private func payment(principal: Double) -> Double {
        let months = Double(durationYears * 12)
        let monthlyRate = rate / 1200
        let loan = max(0, principal)
        guard loan > 0 else { return 0 }
        let base = monthlyRate == 0 ? loan / months : loan * monthlyRate / (1 - pow(1 + monthlyRate, -months))
        return base + loan * insurance / 1200
    }
    private var lowerPayment: Double { payment(principal: amount + fees.lowerBound - ownContribution) }
    private var upperPayment: Double { payment(principal: amount + fees.upperBound - ownContribution) }
    private var formatter: NumberFormatter {
        let result = NumberFormatter()
        result.numberStyle = .currency
        result.currencyCode = "EUR"
        result.locale = Locale(identifier: isEnglish ? "en_US" : "fr_FR")
        result.maximumFractionDigits = 0
        return result
    }
    private func money(_ value: Double) -> String { formatter.string(from: NSNumber(value: value)) ?? "\(Int(value)) €" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isEnglish ? "Purchase cost estimate" : "Estimation du coût d’achat").font(.headline)
                    Text(isEnglish ? "Indicative estimate; confirm figures with a lender or notary." : "Estimation indicative à confirmer auprès d’un prêteur ou d’un notaire.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "percent")
                    .foregroundStyle(PFTheme.brand)
                    .padding(9).background(PFTheme.paleMint, in: Circle())
            }

            if isRental {
                if let charges = listing.monthlyCharges?.value {
                    costRow(isEnglish ? "Advertised monthly charges" : "Charges mensuelles indiquées", value: money(charges) + (isEnglish ? " / month" : " / mois"))
                }
                if let tax = listing.propertyTaxAnnual?.value {
                    costRow(isEnglish ? "Advertised property tax" : "Taxe foncière indiquée", value: money(tax) + (isEnglish ? " / year" : " / an"))
                }
                if listing.monthlyCharges?.value == nil && listing.propertyTaxAnnual?.value == nil {
                    Text(isEnglish ? "No additional cost figures were provided for this rental." : "Aucun autre montant de charges n’est renseigné pour cette location.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else if amount > 0 {
                HStack {
                    Text(isEnglish ? "Property type" : "Type de bien").font(.subheadline)
                    Spacer()
                    Picker(isEnglish ? "Property type" : "Type de bien", selection: $acquisitionType) {
                        Text(isEnglish ? "Existing" : "Ancien").tag("old")
                        Text(isEnglish ? "New build" : "Neuf").tag("new")
                        Text(isEnglish ? "Land" : "Terrain").tag("land")
                    }.labelsHidden()
                }
                HStack {
                    Text(isEnglish ? "Loan term" : "Durée du prêt").font(.subheadline)
                    Spacer()
                    Picker(isEnglish ? "Loan term" : "Durée du prêt", selection: $durationYears) {
                        ForEach([10, 15, 20, 25], id: \.self) { Text("\($0) \(isEnglish ? "years" : "ans")").tag($0) }
                    }.labelsHidden()
                }
                costInput(isEnglish ? "Down payment (€)" : "Apport (€)", value: $downPayment, keyboard: .decimalPad)
                costInput(isEnglish ? "Annual interest rate (%)" : "Taux annuel (%)", value: $annualRate, keyboard: .decimalPad)
                costInput(isEnglish ? "Loan insurance (%)" : "Assurance du prêt (%)", value: $insuranceRate, keyboard: .decimalPad)
                Divider()
                costRow(isEnglish ? "Estimated notary/acquisition fees" : "Frais d’acquisition estimés", value: "\(money(fees.lowerBound))–\(money(fees.upperBound))")
                costRow(isEnglish ? "Estimated loan amount" : "Montant emprunté estimé", value: "\(money(max(0, amount + fees.lowerBound - ownContribution)))–\(money(max(0, amount + fees.upperBound - ownContribution)))")
                HStack(alignment: .firstTextBaseline) {
                    Text(isEnglish ? "Estimated monthly payment" : "Mensualité estimée").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(money(lowerPayment))–\(money(upperPayment)) / \(isEnglish ? "mo" : "mois")")
                        .font(.subheadline.bold()).foregroundStyle(PFTheme.brand).multilineTextAlignment(.trailing)
                }
            } else {
                Text(isEnglish ? "A purchase price is not available for this listing." : "Le prix d’achat n’est pas renseigné pour cette annonce.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            if let tax = listing.propertyTaxAnnual?.value { costRow(isEnglish ? "Advertised property tax" : "Taxe foncière indiquée", value: money(tax) + (isEnglish ? " / year" : " / an")) }
            if let charges = listing.condoChargesMonthly?.value { costRow(isEnglish ? "Advertised condominium charges" : "Charges de copropriété indiquées", value: money(charges) + (isEnglish ? " / month" : " / mois")) }
            if let charges = listing.condoChargesAnnual?.value { costRow(isEnglish ? "Advertised condominium charges" : "Charges de copropriété indiquées", value: money(charges) + (isEnglish ? " / year" : " / an")) }
            if let energy = listing.annualEnergyCost?.value { costRow(isEnglish ? "Advertised energy costs" : "Dépenses énergétiques indiquées", value: money(energy) + (isEnglish ? " / year" : " / an")) }
        }
        .padding(16)
        .background(LinearGradient(colors: [PFTheme.paleMint, Color(uiColor: .secondarySystemGroupedBackground)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
        .onAppear {
            if listing.isNewBuild?.value == true { acquisitionType = "new" }
            else if (listing.propertyType ?? "").localizedCaseInsensitiveContains("terrain") { acquisitionType = "land" }
        }
    }

    private func costRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }

    private func costInput(_ title: String, value: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            TextField("0", text: value)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct ListingNearbyMap: View {
    private enum NearbyLayer: String, CaseIterable, Identifiable {
        case school, shop, transit, hospital, charging
        var id: String { rawValue }
    }
    private struct NearbyPlace: Identifiable {
        let id = UUID()
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    let listing: Listing
    let language: String
    @State private var camera: MapCameraPosition = .automatic
    @State private var propertyCoordinate: CLLocationCoordinate2D?
    @State private var nearbyPlaces: [NearbyPlace] = []
    @State private var selectedLayer: NearbyLayer?
    @State private var status: String?
    @State private var isLoading = false

    private var isEnglish: Bool { language == "en" }
    private var locationQuery: String { [listing.postalCode, listing.city, listing.resolvedCountryCode].compactMap { $0 }.joined(separator: ", ") }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(isEnglish ? "Location and nearby places" : "Localisation et lieux à proximité").font(.headline)
            Text(isEnglish ? "The map uses the city and postal code from the listing when no exact address is provided." : "Sans adresse précise, la carte se base sur la ville et le code postal de l’annonce.")
                .font(.caption).foregroundStyle(.secondary)
            if let propertyCoordinate {
                Map(position: $camera) {
                    Annotation(isEnglish ? "Property area" : "Secteur du bien", coordinate: propertyCoordinate, anchor: .bottom) {
                        Image(systemName: "house.fill").font(.caption).foregroundStyle(.white)
                            .padding(8).background(PFTheme.brand, in: Circle())
                    }
                    ForEach(nearbyPlaces) { place in
                        Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                            Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(.orange)
                        }
                    }
                }
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .mapControls { MapCompass(); MapScaleView() }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(NearbyLayer.allCases) { layer in
                            Button { selectedLayer = layer; Task { await loadNearby(layer) } } label: {
                                Text(layerTitle(layer))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 11).padding(.vertical, 8)
                                    .background(selectedLayer == layer ? PFTheme.brand : Color(uiColor: .secondarySystemBackground), in: Capsule())
                                    .foregroundStyle(selectedLayer == layer ? .white : .primary)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if isLoading { ProgressView(isEnglish ? "Searching nearby…" : "Recherche des lieux proches…").font(.caption) }
                else if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            } else if isLoading {
                ProgressView(isEnglish ? "Finding the property location…" : "Recherche de la localisation du bien…")
                    .frame(maxWidth: .infinity).frame(height: 130)
            } else {
                Text(isEnglish ? "The listing does not include a usable location." : "La localisation de cette annonce ne permet pas d’afficher la carte.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .task { await locateProperty() }
    }

    private func layerTitle(_ layer: NearbyLayer) -> String {
        switch layer {
        case .school: return isEnglish ? "Schools" : "Écoles"
        case .shop: return isEnglish ? "Shops & pharmacies" : "Commerces & pharmacies"
        case .transit: return isEnglish ? "Public transport" : "Transports"
        case .hospital: return isEnglish ? "Hospitals" : "Hôpitaux"
        case .charging: return isEnglish ? "EV charging" : "Bornes électriques"
        }
    }

    @MainActor private func locateProperty() async {
        guard !locationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        var request = MKLocalSearch.Request()
        request.naturalLanguageQuery = locationQuery
        guard let response = try? await MKLocalSearch(request: request).start(), let coordinate = response.mapItems.first?.placemark.coordinate else {
            status = isEnglish ? "The location could not be found." : "La localisation n’a pas pu être trouvée."
            return
        }
        propertyCoordinate = coordinate
        camera = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000))
    }

    @MainActor private func loadNearby(_ layer: NearbyLayer) async {
        guard let propertyCoordinate else { return }
        isLoading = true
        status = nil
        defer { isLoading = false }
        var request = MKLocalSearch.Request()
        request.naturalLanguageQuery = layerTitle(layer)
        request.region = MKCoordinateRegion(center: propertyCoordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
        let categories: [MKPointOfInterestCategory]
        switch layer {
        case .school: categories = [.school, .university]
        case .shop: categories = [.store, .pharmacy, .foodMarket]
        case .transit: categories = [.publicTransport]
        case .hospital: categories = [.hospital]
        case .charging: categories = [.evCharger]
        }
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        guard let response = try? await MKLocalSearch(request: request).start() else {
            status = isEnglish ? "Nearby places are temporarily unavailable." : "Les lieux proches sont temporairement indisponibles."
            return
        }
        nearbyPlaces = response.mapItems.prefix(30).map { item in
            NearbyPlace(name: item.name ?? layerTitle(layer), coordinate: item.placemark.coordinate)
        }
        status = nearbyPlaces.isEmpty
            ? (isEnglish ? "No results in this area." : "Aucun résultat dans ce secteur.")
            : (isEnglish ? "\(nearbyPlaces.count) places found nearby." : "\(nearbyPlaces.count) lieux trouvés à proximité.")
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

private struct LocalizedListingTitle: View {
    let original: String
    let language: String
    @State private var translated: String?

    var body: some View {
        Text(language == "en" ? (translated ?? original) : original)
            .font(.title3.weight(.semibold))
            .task(id: language) {
                guard language == "en", translated == nil else { return }
                translated = await FreePublicListingTranslator.translate(original)
            }
    }
}

private struct HomeDashboardView: View {
    @Binding var selectedTab: Int
    @Binding var catalogSection: NativeCatalogSection
    @ObservedObject var listingsService: ListingsService
    @ObservedObject var classifiedAdsService: ClassifiedAdsService
    @ObservedObject var professionalsService: ProfessionalsService
    @StateObject private var auth = WixAuthStore.shared
    @State private var showNativeEstimation = false
    @State private var showPublicDemand = false
    @State private var showFavorites = false
    @State private var showFullSite = false
    @State private var publicDemandType = "recherche_achat"

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    matchingCard
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Explorer")
                                .font(.title2.bold())
                                .foregroundStyle(PFTheme.deepGreen)
                            Text("Les services essentiels, au même endroit")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { showFavorites = true } label: {
                            Label("Favoris", systemImage: "heart.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PFTheme.brand)
                        }
                        .buttonStyle(.plain)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        homeActionCard("Biens immobiliers", subtitle: "Acheter, louer, consulter", symbol: "house.fill", image: "CategoryMaison") {
                            catalogSection = .realEstate
                            selectedTab = 1
                        }
                        homeActionCard("Petites annonces", subtitle: "Vendre, donner, échanger, louer", symbol: "tag.fill", image: "CategoryPetitesAnnonces") {
                            catalogSection = .classifiedAds
                            selectedTab = 1
                        }
                        homeActionCard("Séjours", subtitle: "Hébergements saisonniers", symbol: "bed.double.fill", image: "CategorySejours") {
                            selectedTab = 2
                        }
                        homeActionCard("Professionnels", subtitle: "Immo, courtiers, artisans, services", symbol: "person.2.fill", image: "CategoryPro") {
                            selectedTab = 3
                        }
                    }
                    Button { showFullSite = true } label: {
                        HStack(spacing: 11) {
                            Image(systemName: "safari.fill")
                                .font(.subheadline.weight(.semibold))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Site complet · Français / English")
                                    .font(.subheadline.weight(.semibold))
                                Text("Annonces, inscriptions et parcours internationaux")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(PFTheme.brand)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 13)
                        .background(PFTheme.paleMint, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Ouvre le site complet dans l’application, avec le choix de langue et les parcours internationaux.")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Votre projet")
                            .font(.title3.bold())
                            .foregroundStyle(PFTheme.deepGreen)
                        Button { showNativeEstimation = true } label: {
                            HStack(spacing: 12) {
                                Image("CategoryEstimation")
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 58, height: 54)
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Faire estimer mon bien")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(PFTheme.deepGreen)
                                    Text("Recevoir une estimation professionnelle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.right")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(PFTheme.brand)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PFTheme.paleMint, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Text("Déposer une demande")
                            .font(.headline)
                        projectCard(
                            title: "Je recherche un bien à acheter",
                            subtitle: "Envoyez une demande aux professionnels de votre secteur",
                            image: "ProjectBuy",
                            type: "recherche_achat"
                        )
                        projectCard(
                            title: "Je recherche une location",
                            subtitle: "Transmettez vos critères de recherche locative",
                            image: "ProjectRentSearch",
                            type: "recherche_location"
                        )
                        projectCard(
                            title: "Je mets un bien en location",
                            subtitle: "Proposez votre logement aux professionnels concernés",
                            image: "ProjectRentListing",
                            type: "mise_en_location"
                        )
                        Text("Ces demandes publiques sont enregistrées dans le parcours Wix des particuliers et transmises aux professionnels selon le matching du site.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
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
        .sheet(isPresented: $showPublicDemand) {
            NavigationStack { NativePublicDemandForm(demandType: publicDemandType) }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFavorites) {
            NativeFavoritesView(
                service: listingsService,
                classifiedAds: classifiedAdsService,
                professionalsService: professionalsService
            )
        }
        .sheet(isPresented: $showFullSite) {
            ProfessionalPortalWebView(
                url: URL(string: "https://www.partenairefoyer.com/")!,
                initialToken: auth.professionalPortalToken,
                title: "PartenaireFoyer"
            ) { token in
                auth.adoptProfessionalPortalSession(token: token)
            }
        }
    }

    private func homeActionCard(
        _ title: String,
        subtitle: String,
        symbol: String,
        image: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                Image(image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 164, maxHeight: 164).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.76)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: symbol).font(.caption.weight(.bold))
                            .padding(8).background(.white.opacity(0.22), in: Circle())
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
                            .padding(8).background(.white.opacity(0.22), in: Circle())
                    }
                    Spacer(minLength: 15)
                    Text(title).font(.subheadline.weight(.bold)).lineLimit(2)
                    Text(subtitle).font(.caption).lineLimit(2).opacity(0.9)
                }.foregroundStyle(.white).padding(12)
            }
            .frame(maxWidth: .infinity, minHeight: 164, maxHeight: 164)
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .shadow(color: PFTheme.deepGreen.opacity(0.14), radius: 9, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func projectCard(title: String, subtitle: String, image: String, type: String) -> some View {
        Button {
            publicDemandType = type
            showPublicDemand = true
        } label: {
            HStack(spacing: 14) {
                Image(image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var hero: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 250, height: 250)
                .offset(x: 115, y: -120)
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .frame(width: 195, height: 195)
                .offset(x: 82, y: -92)
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 92, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.12))
                .offset(x: -16, y: 91)

            VStack(alignment: .leading, spacing: 19) {
                HStack(spacing: 11) {
                    Image("BrandLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .padding(5)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 0) {
                            Text("Partenaire")
                                .foregroundStyle(.white)
                            Text("Foyer")
                                .foregroundStyle(PFTheme.mint)
                        }
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("IMMOBILIER · SERVICES · RENCONTRES")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1.15)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text("Annonces immobilières & matching intelligent")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Les bons biens, les bons projets et les bons professionnels se rencontrent.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PFTheme.deepGreen)
                    Text("Particuliers · professionnels · biens")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PFTheme.deepGreen)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(PFTheme.mint, in: Capsule())
                Button {
                    catalogSection = .realEstate
                    selectedTab = 1
                } label: {
                    HStack(spacing: 9) {
                        Text("Découvrir les annonces")
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PFTheme.deepGreen)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 286, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 286, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Image("CategoryMaison")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .overlay {
                        LinearGradient(
                            colors: [PFTheme.deepGreen.opacity(0.65), PFTheme.deepGreen.opacity(0.84)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: PFTheme.deepGreen.opacity(0.22), radius: 18, y: 9)
    }

    private var matchingCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text("AU CŒUR DE PARTENAIREFOYER")
                    .tracking(1.1)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(PFTheme.brand)

            VStack(alignment: .leading, spacing: 7) {
                Text("Le matching intelligent")
                    .font(.title3.bold())
                    .foregroundStyle(PFTheme.deepGreen)
                Text("Particuliers et professionnels sont rapprochés des biens et demandes compatibles. Les professionnels peuvent aussi être mis en relation entre eux.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 7) {
                matchingStep("Votre projet", symbol: "slider.horizontal.3")
                Image(systemName: "arrow.right").font(.caption2.bold()).foregroundStyle(PFTheme.brand.opacity(0.5))
                matchingStep("Les bons biens", symbol: "house")
                Image(systemName: "arrow.right").font(.caption2.bold()).foregroundStyle(PFTheme.brand.opacity(0.5))
                matchingStep("Mise en relation", symbol: "person.2")
            }

            Button {
                publicDemandType = "recherche_achat"
                showPublicDemand = true
            } label: {
                HStack {
                    Text("Décrire mon projet")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(PFTheme.brand, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(PFTheme.brand.opacity(0.12), lineWidth: 1))
        .shadow(color: PFTheme.brand.opacity(0.08), radius: 14, y: 6)
    }

    private func matchingStep(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption2.weight(.semibold))
            Text(title).font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(PFTheme.deepGreen)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(PFTheme.paleMint, in: Capsule())
    }
}

private struct CatalogPhotoCard: View {
    let title: String
    let subtitle: String
    let image: String
    let symbol: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [PFTheme.deepGreen, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 150, height: 150)
                .offset(x: 150, y: -34)
                .allowsHitTesting(false)
            Image(systemName: symbol)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.white.opacity(0.14))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 20)
                .padding(.bottom, 52)
                .allowsHitTesting(false)
            HStack(alignment: .bottom, spacing: 10) {
                Image(systemName: symbol).font(.headline.weight(.semibold))
                    .frame(width: 38, height: 38).background(.white.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline.weight(.bold)).lineLimit(2)
                    Text(subtitle).font(.caption).lineLimit(2).opacity(0.9)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.subheadline.bold())
            }.foregroundStyle(.white).padding(14)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: 142, maxHeight: 142)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: PFTheme.deepGreen.opacity(0.14), radius: 8, y: 3)
    }
}

private struct NativePostalLocationFields: View {
    @Binding var city: String
    @Binding var postalCode: String
    @State private var communes: [String] = []
    @State private var isLoading = false

    var body: some View {
        TextField("Code postal", text: $postalCode)
            .keyboardType(.numberPad)
            .onChange(of: postalCode) { _, value in
                let cleaned = String(value.filter(\.isNumber).prefix(5))
                if cleaned != value {
                    postalCode = cleaned
                    return
                }
                Task { await loadCommunes(for: cleaned) }
            }
        if isLoading {
            ProgressView("Recherche de la commune…")
        } else if communes.count > 1 {
            Picker("Choisissez la commune", selection: $city) {
                Text("Sélectionner une commune").tag("")
                ForEach(communes, id: \.self) { commune in
                    Text(commune).tag(commune)
                }
            }
        } else if let commune = communes.first {
            LabeledContent("Ville", value: commune)
        } else {
            TextField("Ville", text: $city)
                .textContentType(.addressCity)
        }
    }

    private func loadCommunes(for code: String) async {
        guard code.count == 5 else {
            communes = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        let results = await WixAuthStore.shared.postalCommunes(postalCode: code)
        guard postalCode == code else { return }
        communes = results
        if results.contains(where: { $0.compare(city, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return
        }
        city = results.count == 1 ? results[0] : ""
    }
}

private struct NativePublicDemandForm: View {
    @Environment(\.dismiss) private var dismiss
    let demandType: String
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var city = ""
    @State private var postalCode = ""
    @State private var propertyType = "Maison"
    @State private var minRent = ""
    @State private var minBudget = ""
    @State private var maxBudget = ""
    @State private var livingArea = ""
    @State private var maxLivingArea = ""
    @State private var landArea = ""
    @State private var maxLandArea = ""
    @State private var rooms = ""
    @State private var bedrooms = ""
    @State private var bathrooms = ""
    @State private var garage = false
    @State private var annex = false
    @State private var swimmingPool = false
    @State private var description = ""
    @State private var consent = false
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var errorMessage: String?

    private var isLandlord: Bool { demandType == "mise_en_location" }
    private var isRentSearch: Bool { demandType == "recherche_location" }
    private var title: String {
        switch demandType {
        case "recherche_location": "Recherche de location"
        case "mise_en_location": "Mise en location"
        default: "Recherche d’achat"
        }
    }
    private var canSubmit: Bool {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        lastName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        email.contains("@") && phone.filter(\.isNumber).count >= 8 &&
        !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        postalCode.count == 5 && postalCode.allSatisfy(\.isNumber) && consent &&
        (!isLandlord || (
            (number(minRent) ?? 0) > 0 &&
            (number(livingArea) ?? 0) > 0 &&
            wholeNumber(rooms) != nil &&
            wholeNumber(bedrooms) != nil &&
            wholeNumber(bathrooms) != nil
        ))
    }

    var body: some View {
        Form {
            Section {
                Label(title, systemImage: isLandlord ? "house.badge.plus" : "house.and.flag")
                    .font(.title3.bold())
                Text("Votre demande sera enregistrée dans le parcours PartenaireFoyer et orientée selon les critères de secteur du site.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Vos coordonnées") {
                TextField("Prénom", text: $firstName).textContentType(.givenName)
                TextField("Nom", text: $lastName).textContentType(.familyName)
                TextField("E-mail", text: $email).textContentType(.emailAddress)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Téléphone", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
            }
            Section(isLandlord ? "Le bien à louer" : "Votre recherche") {
                Picker("Type de bien", selection: $propertyType) {
                    ForEach(["Maison", "Appartement", "Terrain", "Immeuble", "Commerce", "Autre"], id: \.self) { Text($0) }
                }
                NativePostalLocationFields(city: $city, postalCode: $postalCode)
                if isLandlord {
                    TextField("Loyer mensuel souhaité (€)", text: $minRent).keyboardType(.decimalPad)
                    TextField("Surface habitable (m²)", text: $livingArea).keyboardType(.decimalPad)
                    TextField("Surface du terrain (m²), facultatif", text: $landArea).keyboardType(.decimalPad)
                    TextField("Nombre de pièces", text: $rooms).keyboardType(.numberPad)
                    TextField("Nombre de chambres", text: $bedrooms).keyboardType(.numberPad)
                    TextField("Nombre de salles de bain", text: $bathrooms).keyboardType(.numberPad)
                    Toggle("Garage", isOn: $garage)
                    Toggle("Annexe", isOn: $annex)
                    Toggle("Piscine", isOn: $swimmingPool)
                } else {
                    TextField(isRentSearch ? "Loyer minimum (€)" : "Budget minimum (€)", text: $minBudget).keyboardType(.decimalPad)
                    TextField(isRentSearch ? "Loyer maximum (€)" : "Budget maximum (€)", text: $maxBudget).keyboardType(.decimalPad)
                    TextField("Surface minimale (m²)", text: $livingArea).keyboardType(.decimalPad)
                    TextField("Surface maximale (m²)", text: $maxLivingArea).keyboardType(.decimalPad)
                    TextField("Terrain minimum (m²)", text: $landArea).keyboardType(.decimalPad)
                    TextField("Terrain maximum (m²)", text: $maxLandArea).keyboardType(.decimalPad)
                    TextField("Pièces minimum", text: $rooms).keyboardType(.numberPad)
                    TextField("Chambres minimum", text: $bedrooms).keyboardType(.numberPad)
                    TextField("Salles de bain minimum", text: $bathrooms).keyboardType(.numberPad)
                    Toggle("Garage", isOn: $garage)
                }
                TextField(isLandlord ? "Description du bien ou du projet" : "Précisions sur le projet", text: $description, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section {
                Toggle("J’accepte la transmission de mes coordonnées et des critères de ma demande.", isOn: $consent)
                Text("La demande sera traitée selon les règles de matching PartenaireFoyer. Les coordonnées des particuliers ne sont pas affichées aux professionnels avant attribution.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let errorMessage { Section("Envoi impossible") { Text(errorMessage).font(.footnote).foregroundStyle(.red) } }
            if didSubmit { Section { Label("Votre demande a été transmise.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            Section {
                Button { Task { await submit() } } label: {
                    HStack { Spacer(); if isSubmitting { ProgressView("Envoi…") } else { Label("Envoyer ma demande", systemImage: "paperplane.fill") }; Spacer() }
                }
                .disabled(!canSubmit || isSubmitting || didSubmit)
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(didSubmit ? "Terminé" : "Fermer") { dismiss() } } }
    }

    private func number(_ value: String) -> Double? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        return normalized.isEmpty ? nil : Double(normalized)
    }

    private func wholeNumber(_ value: String) -> Int? {
        guard let value = number(value), value > 0, value.rounded(.towardZero) == value else { return nil }
        return Int(value)
    }

    @MainActor private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true; errorMessage = nil
        defer { isSubmitting = false }
        var fields: [String: Any] = [
            "firstName": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            "lastName": lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "phone": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "city": city.trimmingCharacters(in: .whitespacesAndNewlines),
            "propertyType": propertyType,
            "projectDescription": description
        ]
        if isLandlord {
            fields["senderName"] = "\(firstName) \(lastName)"
            fields["senderEmail"] = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            fields["senderPhone"] = phone.trimmingCharacters(in: .whitespacesAndNewlines)
            fields["description"] = description
            if let value = number(minRent) { fields["rent"] = value }
            if let value = number(livingArea) { fields["livingArea"] = value }
            if let value = number(landArea) { fields["landArea"] = value }
            if let value = number(bathrooms) { fields["bathrooms"] = value }
            fields["garage"] = garage
            fields["annex"] = annex
            fields["swimmingPool"] = swimmingPool
        } else {
            fields["description"] = description
            if isRentSearch {
                if let value = number(minBudget) { fields["minRent"] = value }
                if let value = number(maxBudget) { fields["maxRent"] = value }
            } else {
                if let value = number(minBudget) { fields["minPrice"] = value }
                if let value = number(maxBudget) { fields["maxPrice"] = value }
            }
            if let value = number(livingArea) { fields["minLivingArea"] = value }
            if let value = number(maxLivingArea) { fields["maxLivingArea"] = value }
            if let value = number(landArea) { fields["minLandArea"] = value }
            if let value = number(maxLandArea) { fields["maxLandArea"] = value }
            if let value = number(bathrooms) { fields["bathrooms"] = value }
            fields["garage"] = garage
        }
        if let value = number(rooms) { fields["rooms"] = value }
        if let value = number(bedrooms) { fields["bedrooms"] = value }
        do {
            try await WixAuthStore.shared.submitPublicDemand(fields, demandType: demandType, postalCode: postalCode)
            didSubmit = true
        } catch { errorMessage = error.localizedDescription }
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
                NativePostalLocationFields(city: $city, postalCode: $postalCode)
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
    private let searchID: String?
    @State private var searchName = ""
    @State private var transactionType: String
    @State private var selectedTypes: Set<String> = []
    @State private var city = ""
    @State private var postalCode = ""
    @State private var radius = 50.0
    @State private var minBudget = "0"
    @State private var maxBudget = "1000000"
    @State private var minSurface = "0"
    @State private var maxSurface = ""
    @State private var minLandSurface = "0"
    @State private var maxLandSurface = ""
    @State private var minRooms = "0"
    @State private var minBedrooms = "0"
    @State private var minBathrooms = "0"
    @State private var singleStory = false
    @State private var garage = false
    @State private var garden = false
    @State private var terrace = false
    @State private var pool = false
    @State private var parking = false
    @State private var emailAlertsEnabled = true
    private let propertyTypes = [
        "Maison", "Appartement", "Terrain", "Immeuble", "Commerce", "Bureau", "Garage / Parking", "Autre",
        "Mobile-home", "Bien saisonnier", "Gîte", "Château", "Camping", "Mas", "Place de parking", "Pêcherie",
        "Maison de vacances", "Résidence secondaire", "Terrain de loisirs", "Terrain agricole", "Étang", "Grange",
        "Dépendance", "Corps de ferme", "Longère", "Loft", "Atelier", "Hangar", "Local professionnel",
        "Fonds de commerce", "Viager", "Colocation", "Chambre", "Studio"
    ]

    init(service: BuyerSearchService, initialTransactionType: String = "buy", initialData: [String: Any]? = nil) {
        self.service = service
        searchID = (initialData?["_id"] as? String) ?? (initialData?["id"] as? String)
        func text(_ key: String, _ fallback: String) -> String {
            guard let value = initialData?[key] else { return fallback }
            return String(describing: value)
        }
        func flag(_ key: String, _ fallback: Bool = false) -> Bool {
            (initialData?[key] as? Bool) ?? fallback
        }
        _searchName = State(initialValue: text("searchName", ""))
        _transactionType = State(initialValue: (initialData?["transactionType"] as? String) ?? initialTransactionType)
        let rawTypes = (initialData?["propertyTypes"] as? String ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        _selectedTypes = State(initialValue: Set(rawTypes))
        _city = State(initialValue: text("city", ""))
        _postalCode = State(initialValue: text("postalCode", ""))
        _radius = State(initialValue: (initialData?["radius"] as? Double) ?? 50)
        _minBudget = State(initialValue: text("minBudget", "0"))
        _maxBudget = State(initialValue: text("maxBudget", "1000000"))
        _minSurface = State(initialValue: text("minSurface", "0"))
        _maxSurface = State(initialValue: text("maxSurface", ""))
        _minLandSurface = State(initialValue: text("minLandSurface", "0"))
        _maxLandSurface = State(initialValue: text("maxLandSurface", ""))
        _minRooms = State(initialValue: text("minRooms", "0"))
        _minBedrooms = State(initialValue: text("minBedrooms", "0"))
        _minBathrooms = State(initialValue: text("minBathrooms", "0"))
        _singleStory = State(initialValue: flag("singleStory"))
        _garage = State(initialValue: flag("garage"))
        _garden = State(initialValue: flag("garden"))
        _terrace = State(initialValue: flag("terrace"))
        _pool = State(initialValue: flag("pool"))
        _parking = State(initialValue: flag("parking"))
        _emailAlertsEnabled = State(initialValue: flag("emailAlertsEnabled", true))
    }

    private var canSubmit: Bool {
        searchName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && postalCode.count == 5 &&
        !selectedTypes.isEmpty && radius >= 1 && radius <= 500 &&
        validRange(minBudget, maxBudget) && validRange(minSurface, maxSurface) &&
        validRange(minLandSurface, maxLandSurface)
    }

    var body: some View {
        Form {
            Section {
                Label(searchID == nil ? "Nouvelle recherche immobilière" : "Modifier ma recherche", systemImage: "sparkles")
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
                NativePostalLocationFields(city: $city, postalCode: $postalCode)
                Stepper("Rayon : \(Int(radius)) km", value: $radius, in: 1...500, step: 1)
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
                TextField("Terrain minimum (m²)", text: $minLandSurface).keyboardType(.decimalPad)
                TextField("Terrain maximum (m²)", text: $maxLandSurface).keyboardType(.decimalPad)
                TextField("Pièces minimum", text: $minRooms).keyboardType(.numberPad)
                TextField("Chambres minimum", text: $minBedrooms).keyboardType(.numberPad)
                TextField("Salles de bain minimum", text: $minBathrooms).keyboardType(.numberPad)
            }
            Section("Caractéristiques") {
                Toggle("Plain-pied", isOn: $singleStory)
                Toggle("Garage", isOn: $garage)
                Toggle("Jardin", isOn: $garden)
                Toggle("Terrasse", isOn: $terrace)
                Toggle("Piscine", isOn: $pool)
                Toggle("Parking", isOn: $parking)
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
                        else { Label(searchID == nil ? "Créer ma recherche" : "Enregistrer les modifications", systemImage: "checkmark.circle.fill").font(.headline) }
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
        let coordinate = await WixAuthStore.shared.coordinates(city: city, postalCode: postalCode)
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
            minLandSurface: number(minLandSurface),
            maxLandSurface: optionalNumber(maxLandSurface),
            minRooms: number(minRooms),
            minBedrooms: number(minBedrooms),
            minBathrooms: number(minBathrooms),
            singleStory: singleStory,
            garage: garage,
            garden: garden,
            terrace: terrace,
            pool: pool,
            parking: parking,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            emailAlertsEnabled: emailAlertsEnabled,
            searchID: searchID
        )
        if success { dismiss() }
    }
}

private struct NativeListingPhotoPicker: View {
    @Binding var photos: [Data]
    let maxPhotos: Int
    @State private var selection: [PhotosPickerItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(selection: $selection, maxSelectionCount: max(1, maxPhotos), matching: .images) {
                Label(photos.isEmpty ? "Choisir des photos" : "Modifier les photos", systemImage: "photo.badge.plus")
            }
            .disabled(isLoading || maxPhotos == 0)
            if isLoading {
                ProgressView("Préparation des photos…")
                    .font(.footnote)
            }
            if !photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                            if let image = UIImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable().scaledToFill()
                                        .frame(width: 84, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Button {
                                        photos.remove(at: index)
                                        errorMessage = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3).symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                    .accessibilityLabel("Supprimer la photo \(index + 1)")
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Text("Jusqu’à \(maxPhotos) photos. Elles sont redimensionnées avant l’envoi pour limiter les données utilisées.")
                .font(.footnote).foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.orange)
            }
        }
        .onChange(of: selection) { _, items in
            Task { await loadPhotos(items) }
        }
    }

    @MainActor
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { photos = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        var prepared: [Data] = []
        for item in items.prefix(maxPhotos) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            let maxDimension = max(image.size.width, image.size.height)
            let scale = min(1, 1600 / max(maxDimension, 1))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            if let jpeg = resized.jpegData(compressionQuality: 0.78), jpeg.count <= 3 * 1024 * 1024 {
                prepared.append(jpeg)
            }
        }
        photos = prepared
        if prepared.isEmpty {
            errorMessage = "Aucune photo compatible n’a pu être préparée. Choisissez des images JPEG, PNG ou HEIC."
        } else if prepared.count < items.count {
            errorMessage = "Certaines photos n’ont pas pu être préparées et n’ont pas été ajoutées."
        }
    }

    init(photos: Binding<[Data]>, maxPhotos: Int = 12) {
        _photos = photos
        self.maxPhotos = max(0, maxPhotos)
    }
}

private struct NativePrivatePropertyForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = WixAuthStore.shared
    let onCreated: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var propertyType = "maison"
    @State private var transactionType = "vente"
    @State private var price = ""
    @State private var surface = ""
    @State private var landSurface = ""
    @State private var rooms = 3
    @State private var bedrooms = 2
    @State private var bathrooms = 1
    @State private var hasGarage = false
    @State private var hasSwimmingPool = false
    @State private var hasAnnex = false
    @State private var city = ""
    @State private var postalCode = ""
    @State private var publishImmediately = false
    @State private var photos: [Data] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 &&
        description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 &&
        propertyType.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        city.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        postalCode.count >= 4 && number(price) >= 0 && number(surface) > 0 && rooms > 0 &&
        !photos.isEmpty && (landSurface.isEmpty || optionalNumber(landSurface) != nil)
    }

    var body: some View {
        Form {
            Section {
                Label("Nouveau bien immobilier", systemImage: "house.badge.plus").font(.title3.bold())
                Text("Le bien est enregistré dans votre compte Wix. Vous pouvez le garder privé et ajouter une galerie depuis votre iPhone.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Présentation") {
                TextField("Titre de l’annonce", text: $title).textInputAutocapitalization(.sentences)
                TextField("Type de bien (maison, appartement…)", text: $propertyType).textInputAutocapitalization(.never)
                Picker("Transaction", selection: $transactionType) {
                    Text("Vente").tag("vente")
                    Text("Location").tag("location")
                }
                TextField("Description", text: $description, axis: .vertical).lineLimit(5...12)
            }
            Section("Caractéristiques") {
                TextField("Prix (€)", text: $price).keyboardType(.decimalPad)
                TextField("Surface habitable (m²)", text: $surface).keyboardType(.decimalPad)
                TextField("Surface du terrain (facultatif)", text: $landSurface).keyboardType(.decimalPad)
                Stepper("Pièces : \(rooms)", value: $rooms, in: 1...30)
                Stepper("Chambres : \(bedrooms)", value: $bedrooms, in: 0...20)
                Stepper("Salles de bain : \(bathrooms)", value: $bathrooms, in: 0...20)
            }
            Section("Équipements") {
                Toggle("Garage ou parking", isOn: $hasGarage)
                Toggle("Piscine", isOn: $hasSwimmingPool)
                Toggle("Annexe", isOn: $hasAnnex)
            }
            Section("Localisation") {
                TextField("Ville", text: $city).textContentType(.addressCity)
                TextField("Code postal", text: $postalCode).keyboardType(.numberPad)
                    .onChange(of: postalCode) { _, value in postalCode = String(value.filter(\.isNumber).prefix(10)) }
            }
            Section("Photos") { NativeListingPhotoPicker(photos: $photos) }
            Section("Publication") {
                Toggle("Publier dans les annonces publiques", isOn: $publishImmediately)
                Text(publishImmediately ? "Le bien sera visible après synchronisation des annonces." : "Le bien restera dans votre espace, sans être affiché publiquement.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let errorMessage { Section("Enregistrement impossible") { Text(errorMessage).font(.footnote).foregroundStyle(.red) } }
            Section {
                Button { Task { await submit() } } label: {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView("Enregistrement…") }
                        else { Label("Enregistrer le bien", systemImage: "checkmark.circle.fill").font(.headline) }
                        Spacer()
                    }
                }
                .disabled(!canSubmit || isSaving)
            } footer: {
                Text("Ajoutez au moins une photo. Le stockage dédié à l’application ne change pas la configuration Wix.")
            }
        }
        .navigationTitle("Nouveau bien")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
    }

    private func number(_ value: String) -> Double {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")) ?? -1
    }
    private func optionalNumber(_ value: String) -> Double? {
        let result = number(value)
        return result >= 0 ? result : nil
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let coordinates = await auth.coordinates(city: city, postalCode: postalCode)
            let imageURLs = try await auth.uploadListingPhotos(photos, role: "particulier")
            try await auth.createPrivateProperty(
                title: title, description: description, propertyType: propertyType,
                transactionType: transactionType, price: number(price), surface: number(surface),
                landSurface: optionalNumber(landSurface), rooms: rooms, bedrooms: bedrooms,
                bathrooms: bathrooms, hasGarage: hasGarage, hasSwimmingPool: hasSwimmingPool,
                hasAnnex: hasAnnex, city: city, postalCode: postalCode,
                latitude: coordinates?.latitude, longitude: coordinates?.longitude, photos: imageURLs,
                publishImmediately: publishImmediately
            )
            onCreated()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private enum ClassifiedCategoryOptions {
    static let rentalUnits = [("À l’heure", "hour"), ("À la journée", "day"), ("Au week-end", "weekend"), ("À la semaine", "week"), ("Au mois", "month")]
    static let commonAttributes: [(String, String)] = [
        ("brand", "Marque"), ("model", "Modèle"), ("color", "Couleur"), ("size", "Taille / dimensions"),
        ("material", "Matière"), ("dimensions", "Dimensions"), ("capacity", "Capacité"),
    ]
    static let vehicleAttributes: [(String, String)] = [
        ("year", "Année"), ("mileage", "Kilométrage"), ("energy", "Énergie"), ("gearbox", "Boîte de vitesses"),
        ("bodyType", "Carrosserie"), ("engineCapacity", "Cylindrée"), ("fiscalPower", "Puissance fiscale"),
        ("powerHp", "Puissance (ch)"), ("doors", "Nombre de portes"), ("seats", "Nombre de places"),
        ("engineCode", "Code moteur"), ("partType", "Type de pièce"), ("partReference", "Référence de pièce"),
        ("oemReference", "Référence constructeur"), ("compatibleMake", "Marque compatible"),
        ("compatibleModel", "Modèle compatible"), ("compatibleYearFrom", "Année compatible dès"),
        ("compatibleYearTo", "Année compatible jusqu’à"),
    ]
    static let allAttributes = commonAttributes + vehicleAttributes
    static func isUserAttributeKey(_ key: String) -> Bool {
        key.range(of: "^[A-Za-z][A-Za-z0-9_]{0,63}$", options: .regularExpression) != nil &&
            key.range(of: "^(?:_?id|ownerId|accountId|memberId|professionalId|hostId|rentalUnit|createdAt|updatedAt|status|isPublic|isActive|slug|attributesJSON|catalogVersion|classifiedOwner.*|pf.*|imported.*|source.*|stripe.*|payment.*|order.*|purchase.*)$", options: [.regularExpression, .caseInsensitive]) == nil
    }

    static func label(for key: String) -> String {
        key.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    static func observedKeys(category: String, subcategory: String, ads: [ClassifiedAd]) -> [String] {
        func normalize(_ value: String?) -> String {
            (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        }
        let wantedCategory = normalize(category)
        let wantedSubcategory = normalize(subcategory)
        var keys = Set<String>()
        for ad in ads {
            guard !ad.isImported,
                  normalize(ad.category) == wantedCategory,
                  wantedSubcategory.isEmpty || normalize(ad.subcategory) == wantedSubcategory,
                  let raw = ad.importedAttributesJSON,
                  let data = raw.data(using: .utf8),
                  let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            keys.formUnion(values.keys.filter(isUserAttributeKey))
        }
        return keys.sorted()
    }

    static func attributes(for category: String, observedKeys: [String] = []) -> [(String, String)] {
        var fields = category == "Auto / Moto — accessoires" ? allAttributes : commonAttributes
        var seen = Set(fields.map(\.0))
        for key in observedKeys where isUserAttributeKey(key) && seen.insert(key).inserted {
            fields.append((key, label(for: key)))
        }
        return Array(fields.prefix(80))
    }
    static let all = [
        "Maison & décoration", "Meubles", "Brocante, vintage & antiquités", "Jardin", "Bricolage",
        "Bois, chauffage & combustibles", "Électroménager", "Informatique", "Téléphonie", "TV / Son / Photo",
        "Jeux vidéo", "Jeux de société & loisirs", "Fête, événementiel & réception", "Ésotérisme & spiritualité",
        "Art & loisirs créatifs", "Mode & accessoires", "Beauté & bien-être", "Bébé & enfant", "Sports & loisirs",
        "Camping, caravaning & plein air", "Vélo & mobilité", "Culture", "Collections", "Instruments de musique",
        "Auto / Moto — accessoires", "Nautisme", "Matériel professionnel", "BTP, chantier & industrie",
        "Agriculture & élevage", "Restauration & métiers de bouche", "Bureau & entreprise",
        "Sécurité, domotique & énergie", "Santé, mobilité & autonomie", "Animaux & accessoires", "Divers"
    ]
}

private struct NativeClassifiedAdForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = WixAuthStore.shared
    @ObservedObject var classifiedAds: ClassifiedAdsService
    let onCreated: () -> Void

    @State private var itemName = ""
    @State private var itemDescription = ""
    @State private var itemPrice = ""
    @State private var listingType = "sell"
    @State private var rentalUnit = "day"
    @State private var category = "Maison & décoration"
    @State private var subcategory = ""
    @State private var attributes: [String: String] = [:]
    @State private var itemCondition = "Bon état"
    @State private var city = ""
    @State private var postalCode = ""
    @State private var photos: [Data] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let conditions = ["Neuf", "Comme neuf", "Très bon état", "Bon état", "État correct"]
    private var attributeFields: [(String, String)] {
        ClassifiedCategoryOptions.attributes(
            for: category,
            observedKeys: ClassifiedCategoryOptions.observedKeys(category: category, subcategory: subcategory, ads: classifiedAds.ads)
        )
    }
    private var canSubmit: Bool {
        itemName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 &&
        itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 &&
        category.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        city.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && postalCode.count >= 4 && number(itemPrice) >= 0 && !photos.isEmpty
    }

    var body: some View {
        Form {
            Section("Objet") {
                Picker("Vous souhaitez", selection: $listingType) {
                    Text("Je vends").tag("sell")
                    Text("Je donne").tag("give")
                    Text("J’échange").tag("exchange")
                    Text("Je loue").tag("rent")
                }
                TextField("Titre", text: $itemName).textInputAutocapitalization(.sentences)
                TextField("Description", text: $itemDescription, axis: .vertical).lineLimit(4...10)
                Picker("Catégorie", selection: $category) {
                    ForEach(ClassifiedCategoryOptions.all, id: \.self) { Text($0).tag($0) }
                }
                TextField("Sous-catégorie (facultatif)", text: $subcategory)
                Picker("État", selection: $itemCondition) {
                    ForEach(conditions, id: \.self) { Text($0).tag($0) }
                }
                TextField("Prix (€)", text: $itemPrice).keyboardType(.decimalPad)
                if listingType == "rent" {
                    Picker("Périodicité du prix", selection: $rentalUnit) {
                        ForEach(Array(ClassifiedCategoryOptions.rentalUnits.enumerated()), id: \.offset) { _, option in Text(option.0).tag(option.1) }
                    }
                }
            }
            if !attributeFields.isEmpty {
                Section("Caractéristiques complémentaires") {
                    ForEach(attributeFields, id: \.0) { key, label in
                        TextField(label, text: Binding(
                            get: { attributes[key, default: ""] },
                            set: { attributes[key] = $0 }
                        ))
                        .keyboardType(["year", "mileage", "engineCapacity", "fiscalPower", "powerHp", "doors", "seats", "capacity"].contains(key) ? .numbersAndPunctuation : .default)
                    }
                }
            }
            if let loadIssue = classifiedAds.errorMessage ?? classifiedAds.warningMessage {
                Section("Champs complémentaires") {
                    Label(loadIssue, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                    Text("Les champs déjà disponibles restent modifiables.").font(.footnote).foregroundStyle(.secondary)
                    Button("Réessayer") { Task { await classifiedAds.reload() } }
                        .disabled(classifiedAds.isLoading)
                }
            }
            Section("Localisation") {
                TextField("Ville", text: $city).textContentType(.addressCity)
                TextField("Code postal", text: $postalCode).keyboardType(.numberPad)
                    .onChange(of: postalCode) { _, value in postalCode = String(value.filter(\.isNumber).prefix(10)) }
            }
            Section("Photos") { NativeListingPhotoPicker(photos: $photos) }
            if let errorMessage { Section("Publication impossible") { Text(errorMessage).font(.footnote).foregroundStyle(.red) } }
            Section {
                Button { Task { await submit() } } label: {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView("Publication…") }
                        else { Label("Publier la petite annonce", systemImage: "tag.fill").font(.headline) }
                        Spacer()
                    }
                }
                .disabled(!canSubmit || isSaving)
            } footer: {
                Text("Ajoutez au moins une photo. Votre annonce sera publiée dans la collection Wix des petites annonces.")
            }
        }
        .navigationTitle("Petite annonce")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        .task { await classifiedAds.loadIfNeeded() }
        .onChange(of: category) { _, value in
            clearUnsupportedAttributes(category: value, subcategory: subcategory)
        }
        .onChange(of: subcategory) { _, value in
            clearUnsupportedAttributes(category: category, subcategory: value)
        }
    }

    private func clearUnsupportedAttributes(category: String, subcategory: String) {
        let current = Set(ClassifiedCategoryOptions.attributes(
            for: category,
            observedKeys: ClassifiedCategoryOptions.observedKeys(category: category, subcategory: subcategory, ads: classifiedAds.ads)
        ).map(\.0))
        for key in Array(attributes.keys) where !current.contains(key) { attributes[key] = "" }
    }

    private func number(_ value: String) -> Double {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")) ?? -1
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let imageURLs = try await auth.uploadListingPhotos(photos, role: "particulier")
            try await auth.createClassifiedAd(
                itemName: itemName, itemDescription: itemDescription, itemPrice: number(itemPrice),
                category: category, subcategory: subcategory, listingType: listingType, rentalUnit: rentalUnit, itemCondition: itemCondition,
                city: city, postalCode: postalCode, photos: imageURLs, attributes: attributes
            )
            onCreated()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct NativeProfessionalPropertyForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = WixAuthStore.shared
    let onCreated: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var propertyType = "house"
    @State private var transactionType = "sale"
    @State private var price = ""
    @State private var surface = ""
    @State private var landSurface = ""
    @State private var rooms = 3
    @State private var bedrooms = 2
    @State private var bathrooms = 1
    @State private var hasGarage = false
    @State private var hasSwimmingPool = false
    @State private var hasAnnex = false
    @State private var address = ""
    @State private var city = ""
    @State private var postalCode = ""
    @State private var publishImmediately = false
    @State private var photos: [Data] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let propertyTypes = [
        ("Maison", "house"), ("Appartement", "apartment"), ("Maison (autre)", "maison"),
        ("Appartement (autre)", "appartement"), ("Commerce", "commercial"),
        ("Terrain", "land"), ("Immeuble", "building"), ("Bureau", "office"),
        ("Garage", "garage"), ("Autre", "other")
    ]

    private var canSubmit: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 &&
        description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 &&
        address.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 &&
        city.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        postalCode.count >= 4 && number(price) >= 0 && number(surface) > 0 && rooms > 0 &&
        bathrooms >= 0 && (landSurface.isEmpty || number(landSurface) >= 0) && !photos.isEmpty
    }

    var body: some View {
        Form {
            Section {
                Label("Nouvelle annonce immobilière", systemImage: "house.badge.plus")
                    .font(.title3.bold())
                Text("Le bien et sa galerie seront enregistrés pour votre espace Wix. Par défaut, l’annonce reste masquée.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Présentation") {
                TextField("Titre de l’annonce", text: $title).textInputAutocapitalization(.sentences)
                Picker("Type de bien", selection: $propertyType) {
                    ForEach(Array(propertyTypes.enumerated()), id: \.offset) { _, option in
                        Text(option.0).tag(option.1)
                    }
                }
                Picker("Transaction", selection: $transactionType) {
                    Text("Vente").tag("sale")
                    Text("Location").tag("rent")
                }
                TextField("Description du bien", text: $description, axis: .vertical).lineLimit(5...12)
            }
            Section("Caractéristiques") {
                TextField("Prix (€)", text: $price).keyboardType(.decimalPad)
                TextField("Surface (m²)", text: $surface).keyboardType(.decimalPad)
                TextField("Surface du terrain (m²), facultative", text: $landSurface).keyboardType(.decimalPad)
                Stepper("Pièces : \(rooms)", value: $rooms, in: 1...30)
                Stepper("Chambres : \(bedrooms)", value: $bedrooms, in: 0...20)
                Stepper("Salles de bain : \(bathrooms)", value: $bathrooms, in: 0...20)
            }
            Section("Équipements pour le matching") {
                Toggle("Garage ou parking", isOn: $hasGarage)
                Toggle("Piscine", isOn: $hasSwimmingPool)
                Toggle("Annexe", isOn: $hasAnnex)
                Text("Ces critères sont enregistrés avec le bien et utilisés pour rapprocher les recherches compatibles.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Adresse") {
                TextField("Adresse", text: $address).textContentType(.streetAddressLine1)
                TextField("Ville", text: $city).textContentType(.addressCity)
                TextField("Code postal", text: $postalCode)
                    .keyboardType(.numberPad)
                    .onChange(of: postalCode) { _, value in postalCode = String(value.filter(\.isNumber).prefix(10)) }
            }
            Section("Photos") { NativeListingPhotoPicker(photos: $photos) }
            Section("Publication") {
                Toggle("Publier dès l’enregistrement", isOn: $publishImmediately)
                Text(publishImmediately
                     ? "L’annonce sera créée avec le statut actif dans Wix et pourra apparaître dans l’application."
                     : "L’annonce sera créée comme inactive et ne sera pas affichée publiquement.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Section("Enregistrement impossible") { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView("Enregistrement…") }
                        else { Label(publishImmediately ? "Créer et publier" : "Enregistrer comme masquée", systemImage: "checkmark.circle.fill").font(.headline) }
                        Spacer()
                    }
                }
                .disabled(!canSubmit || isSaving)
            }
        }
        .navigationTitle("Nouvelle annonce")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
    }

    private func number(_ value: String) -> Double {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")) ?? -1
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let coordinates = await auth.coordinates(city: city, postalCode: postalCode)
            try await auth.createProfessionalProperty(
                title: title,
                description: description,
                propertyType: propertyType,
                transactionType: transactionType,
                price: number(price),
                surface: number(surface),
                landSurface: landSurface.isEmpty ? nil : number(landSurface),
                rooms: rooms,
                bedrooms: bedrooms,
                bathrooms: bathrooms,
                hasGarage: hasGarage,
                hasSwimmingPool: hasSwimmingPool,
                hasAnnex: hasAnnex,
                address: address,
                city: city,
                postalCode: postalCode,
                latitude: coordinates?.latitude,
                longitude: coordinates?.longitude,
                photos: try await auth.uploadListingPhotos(photos, role: "professionnel"),
                publishImmediately: publishImmediately
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NativeSeasonalRateForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var accommodationID: String
    @State private var seasonName: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var pricePerNight: String
    @State private var minimumStayNights: Int
    @State private var isSaving = false
    @State private var errorMessage: String?

    let accommodations: [[String: Any]]
    let initialRate: [String: Any]?
    let onSaved: () -> Void

    init(accommodations: [[String: Any]], initialRate: [String: Any]?, onSaved: @escaping () -> Void) {
        self.accommodations = accommodations
        self.initialRate = initialRate
        self.onSaved = onSaved
        let firstID = (accommodations.first?["_id"] as? String) ?? (accommodations.first?["id"] as? String) ?? ""
        _accommodationID = State(initialValue: (initialRate?["accommodationId"] as? String) ?? firstID)
        _seasonName = State(initialValue: (initialRate?["seasonName"] as? String) ?? "")
        _startDate = State(initialValue: Self.parseDate(initialRate?["startDate"] as? String) ?? Calendar.current.startOfDay(for: .now))
        _endDate = State(initialValue: Self.parseDate(initialRate?["endDate"] as? String) ?? Calendar.current.date(byAdding: .month, value: 3, to: Calendar.current.startOfDay(for: .now)) ?? .now)
        let existingPrice = initialRate?["pricePerNight"].map { String(describing: $0) } ?? ""
        _pricePerNight = State(initialValue: existingPrice)
        _minimumStayNights = State(initialValue: (initialRate?["minimumStayNights"] as? Int) ?? 1)
    }

    private var title: String { initialRate == nil ? "Nouveau tarif saisonnier" : "Modifier le tarif" }
    private var parsedPrice: Double? {
        Double(pricePerNight.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }
    private var canSave: Bool {
        !accommodationID.isEmpty && seasonName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        startDate <= endDate && (parsedPrice ?? 0) > 0 && (parsedPrice ?? .infinity) <= 100_000
    }

    var body: some View {
        Form {
            Section {
                Label(title, systemImage: "eurosign.circle")
                    .font(.title3.bold())
                Text("Définissez la période et les conditions de séjour pour un de vos hébergements.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Hébergement et saison") {
                if accommodations.isEmpty {
                    ContentUnavailableView("Aucun hébergement", systemImage: "house", description: Text("Créez d’abord un hébergement dans votre espace."))
                } else {
                    Picker("Hébergement", selection: $accommodationID) {
                        ForEach(Array(accommodations.enumerated()), id: \.offset) { _, item in
                            let id = (item["_id"] as? String) ?? (item["id"] as? String) ?? ""
                            Text((item["itemName"] as? String) ?? "Hébergement").tag(id)
                        }
                    }
                    .disabled(initialRate != nil)
                    TextField("Nom de la saison", text: $seasonName)
                        .textInputAutocapitalization(.words)
                }
            }
            Section("Période") {
                DatePicker("Du", selection: $startDate, displayedComponents: .date)
                DatePicker("Au", selection: $endDate, in: startDate..., displayedComponents: .date)
                    .onChange(of: startDate) { _, newStartDate in
                        if endDate < newStartDate { endDate = newStartDate }
                    }
            }
            Section("Conditions") {
                TextField("Prix par nuit (€)", text: $pricePerNight).keyboardType(.decimalPad)
                Stepper("Séjour minimum : \(minimumStayNights) nuit\(minimumStayNights > 1 ? "s" : "")", value: $minimumStayNights, in: 1...365)
            }
            if let errorMessage {
                Section("Enregistrement impossible") {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView("Enregistrement…") }
                        else { Label("Enregistrer le tarif", systemImage: "checkmark.circle.fill") }
                        Spacer()
                    }
                }
                .disabled(!canSave || isSaving || accommodations.isEmpty)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(value.prefix(10)))
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    @MainActor private func save() async {
        guard canSave, let parsedPrice else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await WixAuthStore.shared.saveSeasonalRate(
                rateID: (initialRate?["_id"] as? String) ?? (initialRate?["id"] as? String),
                accommodationID: accommodationID,
                seasonName: seasonName,
                startDate: formattedDate(startDate),
                endDate: formattedDate(endDate),
                pricePerNight: parsedPrice,
                minimumStayNights: minimumStayNights
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NativeSpacePickerView: View {
    @State private var selectedRole: AccountRole?
    @State private var showTravelerPortal = false
    @State private var showFullSite = false
    @StateObject private var auth = WixAuthStore.shared
    @AppStorage("partenairefoyer.activeRole") private var activeRoleRaw = ""

    var body: some View {
        NavigationStack {
            Group {
                if activeRoleRaw == AccountRole.professionnel.rawValue,
                   let token = auth.professionalPortalToken {
                    ProfessionalPortalDashboardView(token: token) {
                        signOutEverywhere()
                    }
                } else if let role = AccountRole(rawValue: activeRoleRaw), role != .professionnel,
                          auth.member == nil {
                    WebsiteRoleDashboardView(role: role) {
                        signOutEverywhere()
                    }
                } else if let member = auth.member, let role = AccountRole(rawValue: activeRoleRaw) {
                    NativeRoleDashboardView(role: role, member: member) {
                        signOutEverywhere()
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
            .sheet(isPresented: $showTravelerPortal) {
                ProfessionalPortalWebView(
                    url: URL(string: "https://www.partenairefoyer.com/vacancier-connexion")!,
                    initialToken: nil,
                    title: "Espace voyageur"
                ) { _ in }
            }
            .sheet(isPresented: $showFullSite) {
                ProfessionalPortalWebView(
                    url: URL(string: "https://www.partenairefoyer.com/")!,
                    initialToken: auth.professionalPortalToken,
                    title: "PartenaireFoyer"
                ) { token in
                    auth.adoptProfessionalPortalSession(token: token)
                }
            }
        }
    }

    private var rolePicker: some View {
        List {
                Section {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Vous êtes… ?")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text("Choisissez votre profil. Chaque espace reste séparé ; les fonctions d’un compte ne s’affichent qu’après connexion à cet espace.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
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
                } header: {
                    Text("Choisir un espace").foregroundStyle(PFTheme.mint)
                }
                Section {
                    Button { showTravelerPortal = true } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "airplane")
                                .font(.title3)
                                .foregroundStyle(PFTheme.brand)
                                .frame(width: 42, height: 42)
                                .background(PFTheme.paleMint, in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Voyageur / vacancier").font(.headline).foregroundStyle(PFTheme.deepGreen)
                                Text("Connexion, réservations, favoris et messages").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Voyageurs").foregroundStyle(PFTheme.mint)
                }
                Section {
                    Button { showFullSite = true } label: {
                        Label("Parcourir tout PartenaireFoyer", systemImage: "safari")
                            .font(.headline)
                            .foregroundStyle(PFTheme.brand)
                    }
                    Text("Retrouvez les pages, démarches et services du site dans l’app.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                } header: {
                    Text("Accès complet").foregroundStyle(PFTheme.mint)
                }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PFTheme.deepGreen)
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
        if role == .professionnel, auth.professionalPortalToken != nil {
            auth.resetDashboard()
            activeRoleRaw = role.rawValue
            selectedRole = nil
        } else if auth.member != nil {
            auth.resetDashboard()
            activeRoleRaw = role.rawValue
            selectedRole = nil
        } else {
            selectedRole = role
        }
    }

    private func signOutEverywhere() {
        ProfessionalPortalWebView.clearStoredWebsiteSession {
            DispatchQueue.main.async {
                auth.signOut()
                activeRoleRaw = ""
            }
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
    var recoveryURL: URL {
        URL(string: "https://www.partenairefoyer.com\(recoveryPath)")!
    }
    var activationURL: URL {
        URL(string: "https://www.partenairefoyer.com\(activationPath)")!
    }
    var dashboardURL: URL {
        URL(string: "https://www.partenairefoyer.com\(dashboardPath)")!
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
        case .professionnel: "/pro-app-login?mode=signup"
        case .courtier: "/broker-signup"
        case .artisan: "/artisan-signup"
        case .diagnostiqueur: "/artisan-signup"
        case .prestataire: "/inscription-prestataire"
        case .hebergeur: "/hebergeur-inscription"
        }
    }
    private var recoveryPath: String {
        switch self {
        case .particulier: "/vendeur-forgot-password"
        // Password recovery is currently offered by the professional portal's
        // login screen; activation remains its own explicit route.
        case .professionnel: "/pro-app-login"
        case .courtier: "/broker-forgot-password"
        case .artisan, .diagnostiqueur: "/artisan-forgot-password"
        case .prestataire: "/mot-de-passe-oublie-prestataire"
        case .hebergeur: "/hebergeur-mot-de-passe-oublie"
        }
    }
    private var activationPath: String {
        switch self {
        case .professionnel: "/pro-app-login?mode=activate"
        default: loginPath
        }
    }
    private var dashboardPath: String {
        switch self {
        case .particulier: "/vendeur-dashboard"
        case .professionnel: "/pro/dashboard"
        case .courtier: "/broker-dashboard"
        case .artisan, .diagnostiqueur: "/artisan-dashboard"
        case .prestataire: "/espace-prestataire"
        case .hebergeur: "/hebergeur-dashboard"
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
    @State private var isVisiblePublicly = false
    @State private var professionalTitle = ""
    @State private var yearsOfExperience = ""
    @State private var professionalType = "mandataire"
    @State private var showLegalAcceptance = false
    @State private var showAccountRecovery = false
    @State private var showSiteLogin = false
    @State private var showSiteSignup = false
    @State private var showSignupCountryPicker = false
    @AppStorage("partenairefoyer.accountCountryCode") private var accountCountryCode = CountryCatalog.defaultCode
    @State private var showSiteActivation = false
    @State private var showSiteDashboard = false
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
                    }
                } else if role == .professionnel {
                    Section("Compte professionnel partagé") {
                        Text("Utilisez les mêmes identifiants que sur le portail professionnel PartenaireFoyer.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Adresse e-mail professionnelle", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Mot de passe", text: $password)
                            .textContentType(.password)
                            .onSubmit { Task { await signInProfessionalPortal() } }
                        Button("Mot de passe oublié ?") {
                            auth.errorMessage = nil
                            showAccountRecovery = true
                        }
                        .font(.footnote)
                        Button("Ouvrir la connexion du site") {
                            auth.errorMessage = nil
                            showSiteLogin = true
                        }
                        .font(.footnote)
                    }
                } else {
                    Section("Compte PartenaireFoyer") {
                        Text("La connexion, la création de compte et la récupération du mot de passe passent par le parcours officiel de votre espace. Vos identifiants et vos données restent ceux utilisés sur le site.")
                            .font(.subheadline)
                        Label("Même compte et mêmes données que sur le site", systemImage: "checkmark.shield.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.teal)
                        Text("Sur chaque appareil, reconnectez-vous avec les identifiants de ce compte. Les données sont rattachées au compte ; le jeton de session reste propre à l’appareil utilisé.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Mot de passe oublié ?") {
                            auth.errorMessage = nil
                            showAccountRecovery = true
                        }
                        .font(.subheadline)
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
                        if isEditing {
                            Task { await updateExistingProfile() }
                        } else if isCreatingAccount {
                            showSignupCountryPicker = true
                        } else if role == .professionnel {
                            Task { await signInProfessionalPortal() }
                        } else {
                            showSiteLogin = true
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label(
                                isEditing ? "Enregistrer les modifications" :
                                    (isCreatingAccount ? "Continuer l’inscription PartenaireFoyer" : "Se connecter à mon espace PartenaireFoyer"),
                                systemImage: isEditing ? "checkmark.circle" : (isCreatingAccount ? "person.badge.plus" : "lock.shield")
                            )
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(auth.isSigningIn)

                    if !isEditing {
                        Button {
                            auth.errorMessage = nil
                            showSignupCountryPicker = true
                        } label: {
                            Label("Créer un compte PartenaireFoyer", systemImage: "person.crop.circle.badge.plus")
                        }
                        .disabled(auth.isSigningIn)
                        if role == .professionnel {
                            Button {
                                showSiteActivation = true
                            } label: {
                                Label("Activer mon accès professionnel existant", systemImage: "key.horizontal")
                            }
                            .disabled(auth.isSigningIn)
                        }
                        Button {
                            showSiteDashboard = true
                        } label: {
                            Label("Ouvrir mon tableau de bord sur le site", systemImage: "rectangle.portrait.and.arrow.forward")
                        }
                    }
                } footer: {
                    Text(isEditing
                         ? "Les informations sont mises à jour dans la fiche Wix associée à votre espace."
                         : "Les identifiants et l’espace métier sont gérés par le parcours officiel PartenaireFoyer, comme sur PC et Android.")
                }
            }
            .navigationTitle("Accès à l’espace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
            .sheet(isPresented: $showLegalAcceptance) {
                LegalAcceptanceSheet(role: role) {
                    showLegalAcceptance = false
                    Task { await createAccountAfterLegalAcceptance() }
                }
            }
            .sheet(isPresented: $showAccountRecovery) {
                siteFlow(url: role.recoveryURL, title: "Récupérer mon accès")
            }
            .sheet(isPresented: $showSiteLogin) {
                siteFlow(url: role.loginURL, title: "Connexion à mon espace")
            }
            .sheet(isPresented: $showSignupCountryPicker) {
                NavigationStack {
                    Form {
                        Section("Votre pays") {
                            CountryPickerRow(countryCode: $accountCountryCode, title: "Pays de résidence")
                            Text("La France est sélectionnée par défaut. Ce choix sera transmis au parcours d’inscription PartenaireFoyer.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Section {
                            Button {
                                UserDefaults.standard.set(accountCountryCode, forKey: "partenairefoyer.searchCountryCode")
                                showSignupCountryPicker = false
                                showSiteSignup = true
                            } label: {
                                Label("Continuer l’inscription", systemImage: "arrow.right.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .navigationTitle("Pays d’inscription")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fermer") { showSignupCountryPicker = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showSiteSignup) {
                siteFlow(url: signupURLWithCountry, title: "Créer mon compte")
            }
            .sheet(isPresented: $showSiteActivation) {
                siteFlow(url: role.activationURL, title: "Activer mon accès")
            }
            .sheet(isPresented: $showSiteDashboard) {
                siteFlow(url: role.dashboardURL, title: "Mon tableau de bord")
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
                firstName = (initialProfile["firstName"] as? String) ?? auth.member?.firstName ?? nameParts.first ?? ""
                lastName = (initialProfile["lastName"] as? String) ?? auth.member?.lastName ?? nameParts.dropFirst().first ?? ""
                phone = (initialProfile["phone"] as? String) ?? (initialProfile["phoneNumber"] as? String ?? "")
                city = initialProfile["city"] as? String ?? ""
                postalCode = initialProfile["postalCode"] as? String ?? ""
                companyName = (initialProfile["companyName"] as? String)
                    ?? (initialProfile["businessName"] as? String)
                    ?? (role == .hebergeur ? (initialProfile["fullName"] as? String) : nil)
                    ?? ""
                category = initialProfile["category"] as? String ?? ""
                subcategory = (initialProfile["subcategory"] as? String) ?? Self.primarySubcategory(from: initialProfile["categories"])
                description = (initialProfile["description"] as? String) ?? (initialProfile["biography"] as? String ?? "")
                website = (initialProfile["website"] as? String) ?? (initialProfile["websiteUrl"] as? String ?? "")
                professionalTitle = initialProfile["professionalTitle"] as? String ?? ""
                if let years = initialProfile["yearsOfExperience"] { yearsOfExperience = String(describing: years) }
                professionalType = initialProfile["professionalType"] as? String ?? "mandataire"
                isVisiblePublicly = initialProfile["isVisiblePublicly"] as? Bool ?? false
            }
        }
    }

    private static func primarySubcategory(from value: Any?) -> String {
        var decoded = value
        if let raw = decoded as? String, let data = raw.data(using: .utf8) {
            decoded = try? JSONSerialization.jsonObject(with: data)
        }
        if let entries = decoded as? [[String: Any]],
           let subcategories = entries.first?["subCategories"] as? [String] {
            return subcategories.first ?? ""
        }
        if let entries = decoded as? [[String: Any]],
           let subcategories = entries.first?["subcategories"] as? [String] {
            return subcategories.first ?? ""
        }
        return ""
    }

    @MainActor
    private func createAccountAfterLegalAcceptance() async {
        let profile: [String: String] = [
            "firstName": firstName,
            "lastName": lastName,
            "phone": phone,
            "city": city,
            "postalCode": postalCode,
            "countryCode": accountCountryCode,
            "companyName": companyName,
            "contactName": "\(firstName) \(lastName)",
            "category": category,
            "subcategory": subcategory,
            "description": description,
            "website": website,
            "isVisiblePublicly": isVisiblePublicly ? "true" : "false",
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
            profile: profile,
            acceptedCGU: true,
            acceptedCGV: true
        )
        if didComplete { onSignedIn() }
    }

    private var signupURLWithCountry: URL {
        var components = URLComponents(url: role.signupURL, resolvingAgainstBaseURL: false)!
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "countryCode" }
        items.append(URLQueryItem(name: "countryCode", value: accountCountryCode))
        components.queryItems = items
        return components.url ?? role.signupURL
    }

    private func siteFlow(url: URL, title: String) -> some View {
        ProfessionalPortalWebView(
            url: url,
            initialToken: role == .professionnel ? auth.professionalPortalToken : nil,
            title: title,
            expectedDashboardRole: role,
            onDashboardReached: { reachedRole in
                guard reachedRole == role else { return }
                onSignedIn()
            }
        ) { token in
            guard role == .professionnel else { return }
            handleProfessionalPortalSession(token)
        }
    }

    @MainActor
    private func signInProfessionalPortal() async {
        guard await auth.signInProfessionalPortal(email: email, password: password) else { return }
        password = ""
        onSignedIn()
    }

    @MainActor
    private func handleProfessionalPortalSession(_ token: String) {
        auth.adoptProfessionalPortalSession(token: token, email: email)
        guard !token.isEmpty else { return }
        password = ""
        showAccountRecovery = false
        showSiteLogin = false
        showSiteSignup = false
        showSiteActivation = false
        showSiteDashboard = false
        onSignedIn()
    }

    @MainActor
    private func updateExistingProfile() async {
        guard let profileID = initialProfile?["_id"] as? String, !profileID.isEmpty else {
            auth.errorMessage = "Identifiant de profil manquant. Rechargez votre espace puis réessayez."
            return
        }
        auth.errorMessage = nil
        var fields: [String: Any] = [
            "firstName": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            "lastName": lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            "phone": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "city": city.trimmingCharacters(in: .whitespacesAndNewlines),
            "postalCode": postalCode.trimmingCharacters(in: .whitespacesAndNewlines),
            "companyName": companyName.trimmingCharacters(in: .whitespacesAndNewlines),
            "contactName": "\(firstName.trimmingCharacters(in: .whitespacesAndNewlines)) \(lastName.trimmingCharacters(in: .whitespacesAndNewlines))".trimmingCharacters(in: .whitespaces),
            "category": category.trimmingCharacters(in: .whitespacesAndNewlines),
            "subcategory": subcategory.trimmingCharacters(in: .whitespacesAndNewlines),
            "description": description.trimmingCharacters(in: .whitespacesAndNewlines),
            "website": website.trimmingCharacters(in: .whitespacesAndNewlines),
            "isVisiblePublicly": isVisiblePublicly,
            "professionalTitle": professionalTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            "yearsOfExperience": yearsOfExperience.trimmingCharacters(in: .whitespacesAndNewlines),
            "professionalType": professionalType,
        ]
        if role == .particulier { fields["phoneNumber"] = fields["phone"] }
        if role == .courtier {
            fields["bio"] = fields["description"]
            fields["websiteUrl"] = fields["website"]
        }
        if role == .hebergeur {
            fields["fullName"] = fields["companyName"]
            fields["biography"] = fields["description"]
            fields["phoneNumber"] = fields["phone"]
        }
        do {
            try await auth.updateRoleProfile(role: role.rawValue, profileID: profileID, fields: fields)
            onSignedIn()
        } catch {
            auth.errorMessage = error.localizedDescription
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
            TextField("Présentation de votre activité", text: $description, axis: .vertical).lineLimit(3...8)
            TextField("Ville", text: $city).textContentType(.addressCity)
            TextField("Code postal", text: $postalCode).keyboardType(.numberPad)
            TextField("Site internet (facultatif)", text: $website).keyboardType(.URL).textInputAutocapitalization(.never)
            Toggle("Afficher mon mini-site professionnel", isOn: $isVisiblePublicly)
        case .courtier:
            TextField("Spécialité / titre professionnel", text: $professionalTitle)
            TextField("Présentation professionnelle", text: $description, axis: .vertical).lineLimit(3...8)
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

private enum LegalDocument: String, Identifiable, Equatable {
    case cgu
    case cgv
    var id: String { rawValue }
}

private struct LegalAcceptanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let role: AccountRole
    let onAccept: () -> Void
    @State private var cguOpened = false
    @State private var cgvOpened = false
    @State private var cguAccepted = false
    @State private var cgvAccepted = false
    @State private var selectedDocument: LegalDocument?
    @State private var lastOpenedDocument: LegalDocument?

    private var documentPaths: (cgu: String, cgv: String) {
        switch role {
        case .particulier: ("/cgu-particuliers", "/cgv-particuliers")
        case .hebergeur: ("/cgu", "/cgv")
        case .professionnel: ("/pro-cgu", "/pro-cgv")
        case .courtier: ("/broker-cgu", "/broker-cgv")
        case .artisan, .diagnostiqueur: ("/artisan-cgu", "/artisan-cgv")
        case .prestataire: ("/prestataire-cgu", "/prestataire-cgv")
        }
    }

    private var roleLabel: String {
        switch role {
        case .particulier: "Particuliers"
        case .professionnel: "Professionnels de l’immobilier"
        case .courtier: "Courtiers"
        case .artisan, .diagnostiqueur: "Artisans et diagnostiqueurs"
        case .prestataire: "Prestataires"
        case .hebergeur: "Hébergeurs"
        }
    }

    private var canAccept: Bool { cguOpened && cgvOpened && cguAccepted && cgvAccepted }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Avant de créer votre espace \(roleLabel.lowercased()), consultez et acceptez les Conditions Générales d’Utilisation et les Conditions Générales de Vente applicables à votre compte.")
                    Text("Vous pouvez lire chaque document avant de donner votre accord.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("Acceptation des conditions légales")
                }

                Section("Conditions Générales d’Utilisation") {
                    Button {
                        lastOpenedDocument = .cgu
                        selectedDocument = .cgu
                    } label: {
                        Label(cguOpened ? "CGU consultées · Relire" : "Lire les CGU \(roleLabel)", systemImage: cguOpened ? "checkmark.circle.fill" : "doc.text")
                    }
                    Toggle("J’accepte les CGU \(roleLabel)", isOn: $cguAccepted)
                        .disabled(!cguOpened)
                }

                Section("Conditions Générales de Vente") {
                    Button {
                        lastOpenedDocument = .cgv
                        selectedDocument = .cgv
                    } label: {
                        Label(cgvOpened ? "CGV consultées · Relire" : "Lire les CGV \(roleLabel)", systemImage: cgvOpened ? "checkmark.circle.fill" : "doc.text")
                    }
                    Toggle("J’accepte les CGV \(roleLabel)", isOn: $cgvAccepted)
                        .disabled(!cgvOpened)
                }

                if !canAccept {
                    Section {
                        Label("Consultez les deux documents et cochez les deux accords pour continuer.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Link(destination: AppConfig.privacyURL) {
                        Label("Lire la politique de confidentialité", systemImage: "hand.raised")
                    }
                    Button("Refuser et quitter", role: .destructive) { dismiss() }
                }

                Section {
                    Button {
                        guard canAccept else { return }
                        onAccept()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Accepter et continuer", systemImage: "checkmark.circle.fill").font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(!canAccept)
                }
            }
            .navigationTitle("Conditions légales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
            .sheet(item: $selectedDocument, onDismiss: {
                if lastOpenedDocument == .cgu { cguOpened = true }
                if lastOpenedDocument == .cgv { cgvOpened = true }
                lastOpenedDocument = nil
            }) { document in
                let path = document == .cgu ? documentPaths.cgu : documentPaths.cgv
                InAppSafariView(url: URL(string: "https://www.partenairefoyer.com\(path)")!)
                    .ignoresSafeArea()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            cguOpened = false
            cgvOpened = false
            cguAccepted = false
            cgvAccepted = false
            selectedDocument = nil
            lastOpenedDocument = nil
        }
    }
}

private struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

private struct ProfessionalPortalDashboardView: View {
    let token: String
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            ProfessionalPortalWebViewRepresentable(
                url: URL(string: "https://www.partenairefoyer.com/pro/dashboard")!,
                initialToken: token,
                onSessionToken: { _ in }
            )
                .ignoresSafeArea(edges: .bottom)
                .task(id: token) {
                    await WixAuthStore.shared.registerPushDevice(role: "professionnel")
                }
                .onReceive(NotificationCenter.default.publisher(for: .partenaireFoyerFCMTokenDidChange)) { _ in
                    Task { await WixAuthStore.shared.registerPushDevice(role: "professionnel") }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("Espace professionnel").font(.headline) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Déconnexion", systemImage: "rectangle.portrait.and.arrow.right") {
                            onSignOut()
                        }
                    }
                }
        }
    }
}

/// Keeps non-real-estate Wix role sessions in the same persistent website store
/// used for login, signup and password recovery. This is the session authority
/// for these legacy role portals until their Wix authentication is bridged to
/// the native APIs.
private struct WebsiteRoleDashboardView: View {
    @State private var isLoading = true
    let role: AccountRole
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            ProfessionalPortalWebViewRepresentable(
                url: role.dashboardURL,
                initialToken: nil,
                onSessionToken: { _ in },
                onDashboardReached: nil,
                onLoadingChanged: { isLoading = $0 }
            )
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if isLoading {
                        ProgressView("Chargement de votre espace…")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.top, 8)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) { Text(role.title).font(.headline) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Déconnexion", systemImage: "rectangle.portrait.and.arrow.right", action: onSignOut)
                    }
                }
        }
    }
}

private struct ProfessionalPortalWebView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var portalWebView: WKWebView?
    @State private var isLoading = true
    let url: URL
    let initialToken: String?
    var title = "Accès au portail"
    var expectedDashboardRole: AccountRole? = nil
    var onDashboardReached: ((AccountRole) -> Void)? = nil
    let onSessionToken: (String) -> Void

    var body: some View {
        NavigationStack {
            ProfessionalPortalWebViewRepresentable(
                url: url,
                initialToken: initialToken,
                onSessionToken: onSessionToken,
                expectedDashboardRole: expectedDashboardRole,
                onDashboardReached: onDashboardReached,
                onLoadingChanged: { isLoading = $0 },
                onWebViewCreated: { portalWebView = $0 }
            )
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if isLoading {
                        ProgressView("Chargement sécurisé…")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.top, 8)
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { portalWebView?.goBack() } label: {
                            Image(systemName: "chevron.left").accessibilityLabel("Retour")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack {
                            Button { portalWebView?.reload() } label: {
                                Image(systemName: "arrow.clockwise").accessibilityLabel("Actualiser")
                            }
                            Button("Fermer") { dismiss() }
                        }
                    }
                }
        }
    }

    static func clearStoredWebsiteSession(completion: @escaping () -> Void) {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let websiteRecords = records.filter { $0.displayName.contains("partenairefoyer.com") }
            guard !websiteRecords.isEmpty else { completion(); return }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: websiteRecords, completionHandler: completion)
        }
    }
}

private struct ProfessionalPortalWebViewRepresentable: UIViewRepresentable {
    @AppStorage("partenairefoyer.language") private var appLanguage = "fr"
    let url: URL
    let initialToken: String?
    let onSessionToken: (String) -> Void
    var expectedDashboardRole: AccountRole? = nil
    var onDashboardReached: ((AccountRole) -> Void)? = nil
    var onLoadingChanged: ((Bool) -> Void)? = nil
    var onWebViewCreated: (WKWebView) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSessionToken: onSessionToken, expectedDashboardRole: expectedDashboardRole,
                    onDashboardReached: onDashboardReached, onLoadingChanged: onLoadingChanged)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(context.coordinator, name: "pfProSession")
        let injectedToken: String
        if let initialToken, !initialToken.isEmpty,
           let encoded = try? JSONEncoder().encode(initialToken),
           let jsonToken = String(data: encoded, encoding: .utf8) {
            injectedToken = "localStorage.setItem('pf_pro_app_session_token', \(jsonToken));"
        } else {
            injectedToken = ""
        }
        let sessionBridge = """
        if (location.hostname === 'www.partenairefoyer.com' || location.hostname === 'partenairefoyer.com') {
          localStorage.setItem('language', '\(appLanguage == "en" ? "en" : "fr")');
          \(injectedToken)
          (function () {
            const key = 'pf_pro_app_session_token';
            const originalSetItem = Storage.prototype.setItem;
            Storage.prototype.setItem = function (name, value) {
              originalSetItem.call(this, name, value);
              if (name === key && this === localStorage) window.webkit.messageHandlers.pfProSession.postMessage('set:' + String(value));
            };
            const originalRemoveItem = Storage.prototype.removeItem;
            Storage.prototype.removeItem = function (name) {
              originalRemoveItem.call(this, name);
              if (name === key && this === localStorage) window.webkit.messageHandlers.pfProSession.postMessage('clear');
            };
            const originalClear = Storage.prototype.clear;
            Storage.prototype.clear = function () {
              originalClear.call(this);
              if (this === localStorage) window.webkit.messageHandlers.pfProSession.postMessage('clear');
            };
          })();
        }
        """
        configuration.userContentController.addUserScript(WKUserScript(source: sessionBridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        DispatchQueue.main.async { onWebViewCreated(webView) }
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let language = appLanguage == "en" ? "en" : "fr"
        let script = "localStorage.setItem('language', '\(language)'); window.dispatchEvent(new CustomEvent('pf:language-change', { detail: { language: '\(language)' } }));"
        webView.evaluateJavaScript(script)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let onSessionToken: (String) -> Void
        private let expectedDashboardRole: AccountRole?
        private let onDashboardReached: ((AccountRole) -> Void)?
        private let onLoadingChanged: ((Bool) -> Void)?
        private var lastCapturedToken: String?
        private var didReportDashboard = false

        init(onSessionToken: @escaping (String) -> Void, expectedDashboardRole: AccountRole?,
             onDashboardReached: ((AccountRole) -> Void)?, onLoadingChanged: ((Bool) -> Void)?) {
            self.onSessionToken = onSessionToken
            self.expectedDashboardRole = expectedDashboardRole
            self.onDashboardReached = onDashboardReached
            self.onLoadingChanged = onLoadingChanged
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.onLoadingChanged?(true) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.onLoadingChanged?(false) }
            reportDashboardIfReached(in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.onLoadingChanged?(false) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.onLoadingChanged?(false) }
        }

        private func reportDashboardIfReached(in webView: WKWebView) {
            guard !didReportDashboard, let expectedDashboardRole,
                  let url = webView.url,
                  let host = url.host?.lowercased(),
                  host == "www.partenairefoyer.com" || host == "partenairefoyer.com",
                  expectedDashboardRole != .professionnel,
                  url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
                    == expectedDashboardRole.dashboardURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            else { return }
            didReportDashboard = true
            DispatchQueue.main.async { self.onDashboardReached?(expectedDashboardRole) }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "pfProSession", let value = message.body as? String else { return }
            if value == "clear" {
                lastCapturedToken = nil
                DispatchQueue.main.async { self.onSessionToken("") }
                return
            }
            guard value.hasPrefix("set:") else { return }
            let token = String(value.dropFirst(4))
            guard !token.isEmpty, token != lastCapturedToken else { return }
            lastCapturedToken = token
            DispatchQueue.main.async { self.onSessionToken(token) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let destination = navigationAction.request.url,
                  let scheme = destination.scheme?.lowercased() else { decisionHandler(.cancel); return }
            if scheme == "https" || scheme == "http" {
                decisionHandler(.allow)
            } else {
                openExternalAction(destination, scheme: scheme)
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil,
                  let destination = navigationAction.request.url,
                  let scheme = destination.scheme?.lowercased() else { return nil }
            if scheme == "https" || scheme == "http" {
                webView.load(navigationAction.request)
            } else {
                openExternalAction(destination, scheme: scheme)
            }
            return nil
        }

        private func openExternalAction(_ url: URL, scheme: String) {
            guard ["mailto", "tel", "sms"].contains(scheme) else { return }
            UIApplication.shared.open(url)
        }
    }
}

private struct NativeRoleDashboardView: View {
    @StateObject private var auth = WixAuthStore.shared
    @StateObject private var referralService = ReferralService()
    @StateObject private var professionalImportService = ProfessionalImportService()
    @StateObject private var buyerSearchService = BuyerSearchService()
    @StateObject private var classifiedAdsService = ClassifiedAdsService()
    @State private var selectedItem: DashboardItemSelection?
    @State private var isEditingSelectedListing = false
    @State private var selectedConversation: DashboardConversationSelection?
    @State private var showReferralCenter = false
    @State private var showImportCenter = false
    @State private var showBuyerSearchForm = false
    @State private var showProfessionalPropertyForm = false
    @State private var showPrivatePropertyForm = false
    @State private var showClassifiedAdForm = false
    @State private var showSeasonalRateForm = false
    @State private var editingSeasonalRate: [String: Any]?
    @State private var showSeasonalCalendarEditor = false
    @State private var showSeasonalAccommodationForm = false
    @State private var editingSeasonalAccommodation: [String: Any]?
    @State private var pendingAccommodationDeletion: String?
    @State private var showAccommodationDeletionConfirmation = false
    @State private var pendingSeasonalRateDeletion: String?
    @State private var showSeasonalRateDeletionConfirmation = false
    @State private var showProfileEditor = false
    @State private var showMiniSitePreview = false
    @State private var showWebsiteDashboard = false
    @State private var websitePageURL: URL?
    @State private var websitePageTitle = "Mon espace"
    @State private var selectedBillingPage: InAppSafariPage?
    @State private var editingBuyerSearch: [String: Any]?
    @State private var pendingBuyerSearchDeletion: String?
    @State private var showBuyerSearchDeletionConfirmation = false
    @State private var pendingMinisiteDeletion: String?
    @State private var showMinisiteDeletionConfirmation = false
    @State private var pendingProfessionalMatchingDeletion: String?
    @State private var showProfessionalMatchingDeletionConfirmation = false
    @State private var pendingHostBookingRequest: String?
    @State private var showHostBookingHideConfirmation = false
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
                ("Matchings reçus", "sparkles", "buyerMatchings"),
                ("Professionnels intéressés par mes biens", "person.2", "vendorMatchings")
            ]
        case .professionnel:
            keys = [
                ("Mes biens", "house", "properties"),
                ("Opportunités réseau", "sparkles.rectangle.stack", "opportunities"),
                ("Mes matchings", "sparkles", "matchingsMy"),
                ("Matchings réseau", "person.2", "matchingsNetwork"),
                ("Biens de particuliers correspondants", "house", "privatePropertyMatchings"),
                ("Conversations réseau", "bubble.left.and.bubble.right", "conversations"),
                ("Demandes disponibles", "bolt.horizontal.circle", "availableDemands"),
                ("Demandes acceptées", "person.2", "demands"),
                ("Demandes du mini-site", "globe", "minisiteRequests"),
                ("Estimations reçues", "chart.line.uptrend.xyaxis", "estimationRequests"),
                ("Contacts sur mes annonces", "bubble.left", "propertyRequests"),
                ("Messages", "bubble.left.and.bubble.right", "messages")
            ]
        case .courtier:
            keys = [("Messages", "bubble.left.and.bubble.right", "messages")]
        case .artisan:
            keys = [("Demandes d’intervention", "bubble.left.and.bubble.right", "messages")]
        case .diagnostiqueur:
            keys = [("Demandes de diagnostic", "doc.text.magnifyingglass", "messages")]
        case .prestataire:
            keys = [("Demandes et messages", "bubble.left.and.bubble.right", "messages")]
        case .hebergeur:
            keys = [
                ("Mes hébergements", "house", "accommodations"),
                ("Demandes de réservation", "calendar.badge.clock", "bookingRequests"),
                ("Réservations", "calendar", "reservations"),
                ("Conversations", "bubble.left.and.bubble.right", "conversations"),
                ("Calendrier des disponibilités", "calendar.badge.checkmark", "calendar"),
                ("Réservations externes", "calendar.badge.exclamationmark", "externalBookings"),
                ("Tarifs saisonniers", "eurosign.circle", "seasonalRates"),
                ("Calendriers connectés", "arrow.triangle.2.circlepath.icloud", "calendarConnections")
            ]
        }
        return keys.compactMap { title, icon, key in
            if key == "matchingsMy" || key == "matchingsNetwork" {
                let allMatchings = data["matchings"] as? [[String: Any]] ?? []
                let expectedType = key == "matchingsNetwork" ? "reseau" : "my"
                let items = allMatchings.filter { ($0["matchingType"] as? String)?.lowercased() == expectedType }
                return (title, icon, items)
            }
            guard let items = data[key] as? [[String: Any]] else { return nil }
            return (title, icon, items)
        }
    }

    private var profile: [String: Any]? { auth.dashboardData?["profile"] as? [String: Any] }

    private func openWebsiteRoute(_ route: String, title: String) {
        guard let url = URL(string: "https://www.partenairefoyer.com\(route)") else { return }
        websitePageURL = url
        websitePageTitle = title
        showWebsiteDashboard = true
    }

    private func artisanPaymentURL(plan: String) -> URL? {
        guard let profile,
              let profileID = profile["_id"] as? String, !profileID.isEmpty else { return nil }
        let base = plan == "monthly"
            ? "https://buy.stripe.com/cNi14ofrZ3X9cMva476Vq05"
            : "https://buy.stripe.com/eVq9AU6Vt9ht27Rccf6Vq06"
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "client_reference_id", value: "artisan:\(profileID):\(plan)"),
            URLQueryItem(name: "prefilled_email", value: member.loginEmail),
        ]
        return components.url
    }

    var body: some View {
        List {
            Section {
                Label(role.title, systemImage: role.symbol)
                    .font(.title3.bold())
                LabeledContent("Compte connecté", value: member.loginEmail)
                if let message = auth.infoMessage {
                    Label(message, systemImage: "envelope.badge")
                        .font(.footnote).foregroundStyle(.orange)
                }
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
                    Button {
                        websitePageURL = role.dashboardURL
                        websitePageTitle = "Mon tableau de bord"
                        showWebsiteDashboard = true
                    } label: {
                        Label("Ouvrir mon espace complet sur le site", systemImage: "safari")
                    }
                }
            } else if let data = auth.dashboardData {
                if let error = auth.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                Section("Vue d’ensemble") {
                    DashboardOverview(data: data, role: role)
                }
                if let profile {
                    Section("Mon profil") {
                        NativeProfileShowcase(profile: profile, role: role)
                        ForEach(Array(profileKeys(for: role).filter { profile[$0.1] != nil }.enumerated()), id: \.offset) { _, field in
                            LabeledContent(field.0, value: field.1 == "categories" ? displayCategories(profile[field.1]) : display(profile[field.1]))
                        }
                        Button {
                            showProfileEditor = true
                        } label: {
                            Label("Modifier mon profil", systemImage: "pencil")
                        }
                    }
                }
                if role == .professionnel, let profile {
                    Section("Mon mini-site professionnel") {
                        Label((profile["isVisiblePublicly"] as? Bool) == true ? "Présentation publique activée" : "Présentation publique masquée",
                              systemImage: (profile["isVisiblePublicly"] as? Bool) == true ? "eye.fill" : "eye.slash")
                            .foregroundStyle((profile["isVisiblePublicly"] as? Bool) == true ? .green : .secondary)
                        Text("Cette présentation reprend vos coordonnées, votre description et vos biens publiés. Vous pouvez la prévisualiser et régler sa visibilité dans la modification du profil.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button { showMiniSitePreview = true } label: {
                            Label("Prévisualiser mon mini-site", systemImage: "safari")
                        }
                        Button { showProfileEditor = true } label: {
                            Label("Modifier la présentation et la visibilité", systemImage: "pencil")
                        }
                    }
                    Section("Abonnement professionnel") {
                        let active = (profile["hasActiveSubscription"] as? Bool) == true
                        let subscriptionStatus = (profile["subscriptionStatus"] as? String ?? "").lowercased()
                        let freeAccessEnd = ISO8601DateFormatter().date(from: "2027-01-01T00:00:00+01:00")!
                        let freeAccessActive = Date() < freeAccessEnd
                        let statusLabel = freeAccessActive
                            ? "Accès gratuit jusqu’au 31 décembre 2026"
                            : (subscriptionStatus == "trialing" ? "Essai gratuit en cours" : (active ? "Abonnement actif" : display(profile["subscriptionStatus"])))
                        Label(statusLabel,
                              systemImage: freeAccessActive ? "gift.fill" : (active ? "checkmark.seal.fill" : "creditcard"))
                            .foregroundStyle(freeAccessActive || active || subscriptionStatus == "trialing" ? Color.green : Color.secondary)
                        if profile["subscriptionStartDate"] != nil {
                            LabeledContent("Début", value: display(profile["subscriptionStartDate"]))
                        }
                        if profile["subscriptionEndDate"] != nil {
                            LabeledContent("Échéance", value: display(profile["subscriptionEndDate"]))
                        }
                        Text("Le statut affiché est synchronisé avec votre espace PartenaireFoyer. La gestion des paiements reste sécurisée par le service de paiement existant.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button {
                            websitePageURL = URL(string: "https://www.partenairefoyer.com/pro/abonnement")
                            websitePageTitle = "Abonnement professionnel"
                            showWebsiteDashboard = true
                        } label: {
                            Label("Voir mon offre et gérer l’abonnement", systemImage: "creditcard")
                        }
                    }
                }
                if [.artisan, .diagnostiqueur].contains(role), let profile {
                    let subscription = data["subscription"] as? [String: Any] ?? [:]
                    let status = (subscription["subscriptionStatus"] as? String ?? "").lowercased()
                    let hasPaidAccess = subscription["accessEnabled"] as? Bool == true && ["active", "trialing"].contains(status)
                    let freeAccessEnd = ISO8601DateFormatter().date(from: "2027-01-01T00:00:00+01:00")!
                    Section("Activité de ma fiche") {
                        LabeledContent("Vues du profil", value: display(profile["profileViews"] ?? 0))
                        LabeledContent("Demandes de contact", value: display(profile["contactRequestsCount"] ?? 0))
                    }
                    Section("Abonnement artisan / diagnostiqueur") {
                        Label(
                            hasPaidAccess ? "Abonnement actif" : (Date() < freeAccessEnd ? "Accès gratuit jusqu’au 31 décembre 2026" : "Abonnement inactif"),
                            systemImage: hasPaidAccess ? "checkmark.seal.fill" : "creditcard"
                        )
                        .foregroundStyle(hasPaidAccess ? Color.green : Color.secondary)
                        if let start = subscription["subscriptionStartDate"] {
                            LabeledContent("Début", value: display(start))
                        }
                        if let end = subscription["subscriptionEndDate"] {
                            LabeledContent("Échéance", value: display(end))
                        }
                        if let monthly = artisanPaymentURL(plan: "monthly") {
                            Button {
                                selectedBillingPage = InAppSafariPage(url: monthly)
                            } label: {
                                Label("Choisir la formule mensuelle", systemImage: "creditcard")
                            }
                        }
                        if let annual = artisanPaymentURL(plan: "annual") {
                            Button {
                                selectedBillingPage = InAppSafariPage(url: annual)
                            } label: {
                                Label("Choisir la formule annuelle", systemImage: "calendar")
                            }
                        }
                        Button {
                            selectedBillingPage = InAppSafariPage(url: URL(string: "https://billing.stripe.com/p/login/7sY4gAenV3X95k32BF6Vq00")!)
                        } label: {
                            Label("Gérer mon abonnement Stripe", systemImage: "arrow.up.right.square")
                        }
                        Text("Le paiement et le statut d’abonnement restent gérés par les services Stripe et Wix du site.")
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
                        if role == .particulier, section.0 == "Mes biens" {
                            Button { showPrivatePropertyForm = true } label: {
                                Label("Déposer un bien immobilier", systemImage: "house.badge.plus").font(.headline)
                            }
                        }
                        if role == .particulier, section.0 == "Mes petites annonces" {
                            Button { showClassifiedAdForm = true } label: {
                                Label("Déposer une petite annonce", systemImage: "tag.badge.plus").font(.headline)
                            }
                            Button {
                                openWebsiteRoute("/vendeur-petites-annonces", title: "Mes annonces et ventes")
                            } label: {
                                Label("Gérer mes annonces, ventes et paiements", systemImage: "shippingbox")
                            }
                            Text("La gestion des ventes et des paiements s’ouvre dans votre espace sécurisé PartenaireFoyer.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
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
                        if role == .hebergeur, section.0 == "Tarifs saisonniers" {
                            Button {
                                editingSeasonalRate = nil
                                showSeasonalRateForm = true
                            } label: {
                                Label("Ajouter un tarif saisonnier", systemImage: "plus.circle.fill")
                                    .font(.headline)
                            }
                        }
                        if role == .hebergeur, section.0 == "Mes hébergements" {
                            Button {
                                editingSeasonalAccommodation = nil
                                showSeasonalAccommodationForm = true
                            } label: {
                                Label("Ajouter un hébergement", systemImage: "plus.circle.fill")
                                    .font(.headline)
                            }
                        }
                        if role == .hebergeur, section.0 == "Calendrier des disponibilités" {
                            Button { showSeasonalCalendarEditor = true } label: {
                                Label("Gérer les disponibilités", systemImage: "calendar.badge.checkmark")
                                    .font(.headline)
                            }
                        }
                        if section.2.isEmpty {
                            Text("Aucun élément pour le moment.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(section.2.enumerated()), id: \.offset) { index, item in
                                WixDashboardItem(item: item, fallbackTitle: "Élément \(index + 1)", onOpen: {
                                        if role == .particulier, section.0 == "Mes recherches" {
                                            editingBuyerSearch = item
                                            showBuyerSearchForm = true
                                        } else if role == .professionnel, section.0 == "Messages",
                                           let conversationID = item["conversationId"] as? String,
                                           !conversationID.isEmpty {
                                            selectedConversation = DashboardConversationSelection(id: conversationID, preview: item)
                                        } else if role == .professionnel, section.0 == "Conversations réseau",
                                                  let conversationID = (item["conversationId"] as? String) ?? (item["_id"] as? String),
                                                  !conversationID.isEmpty {
                                            selectedConversation = DashboardConversationSelection(id: conversationID, preview: item)
                                        } else if role == .hebergeur, section.0 == "Conversations",
                                                  let conversationID = (item["_id"] as? String) ?? (item["id"] as? String),
                                                  !conversationID.isEmpty {
                                            selectedConversation = DashboardConversationSelection(id: conversationID, preview: item)
                                        } else if role == .hebergeur, section.0 == "Tarifs saisonniers" {
                                            editingSeasonalRate = item
                                            showSeasonalRateForm = true
                                        } else if role == .hebergeur, section.0 == "Mes hébergements" {
                                            editingSeasonalAccommodation = item
                                            showSeasonalAccommodationForm = true
                                        } else {
                                            let list: String?
                                            if section.0 == "Mes biens" && [.particulier, .professionnel].contains(role) {
                                                list = "properties"
                                            } else if role == .particulier && section.0 == "Mes petites annonces" {
                                                list = "classifieds"
                                            } else {
                                                list = nil
                                            }
                                            selectedItem = DashboardItemSelection(item: item, list: list)
                                        }
                                }, onClaim: role == .professionnel && section.0 == "Demandes disponibles" ? {
                                    if let demandID = item["_id"] as? String {
                                        await auth.claimDemand(demandID: demandID)
                                    }
                                } : nil, onOpportunityAccept: role == .professionnel && section.0 == "Opportunités réseau" && String(describing: item["status"] ?? "").lowercased() == "pending" ? {
                                    if let opportunityID = (item["_id"] as? String) ?? (item["id"] as? String) {
                                        await auth.acceptNetworkOpportunity(opportunityID: opportunityID)
                                    }
                                } : nil, onHostBookingTransition: role == .hebergeur && section.0 == "Demandes de réservation" ? { status in
                                    guard let requestID = (item["_id"] as? String) ?? (item["id"] as? String) else { return }
                                    await auth.transitionHostBookingRequest(requestID: requestID, status: status)
                                } : nil)
                                .swipeActions {
                                    if (role == .particulier && ["Mes biens", "Mes petites annonces"].contains(section.0)) ||
                                        (role == .professionnel && section.0 == "Mes biens"),
                                       let itemID = (item["_id"] as? String) ?? (item["id"] as? String) {
                                        Button("Archiver", systemImage: "archivebox", role: .destructive) {
                                            let list = section.0 == "Mes petites annonces" ? "classifieds" : "properties"
                                            Task { await auth.archiveListing(role: role.rawValue, list: list, itemID: itemID) }
                                        }
                                    }
                                    if role == .particulier, section.0 == "Mes recherches",
                                       let searchID = (item["_id"] as? String) ?? (item["id"] as? String) {
                                        Button("Modifier", systemImage: "pencil") {
                                            editingBuyerSearch = item
                                            showBuyerSearchForm = true
                                        }
                                        .tint(.blue)
                                        Button("Alertes", systemImage: (item["emailAlertsEnabled"] as? Bool == true) ? "bell.slash" : "bell") {
                                            Task {
                                                _ = await buyerSearchService.setEmailAlerts(searchID: searchID, enabled: item["emailAlertsEnabled"] as? Bool != true)
                                            }
                                        }
                                        .tint(.orange)
                                        Button(item["isActive"] as? Bool == false ? "Activer" : "Désactiver",
                                               systemImage: item["isActive"] as? Bool == false ? "play.circle" : "pause.circle",
                                               role: item["isActive"] as? Bool == false ? nil : .destructive) {
                                            Task {
                                                if item["isActive"] as? Bool == false {
                                                    _ = await buyerSearchService.activate(searchID: searchID)
                                                } else {
                                                    await buyerSearchService.deactivate(searchID: searchID)
                                                }
                                            }
                                        }
                                        Button("Supprimer", systemImage: "trash", role: .destructive) {
                                            pendingBuyerSearchDeletion = searchID
                                            showBuyerSearchDeletionConfirmation = true
                                        }
                                    }
                                    if role == .particulier, section.0 == "Matchings reçus",
                                       let matchingID = (item["_id"] as? String) ?? (item["id"] as? String) {
                                        Button("Masquer", systemImage: "eye.slash", role: .destructive) {
                                            Task { _ = await buyerSearchService.dismissMatching(matchingID: matchingID) }
                                        }
                                    }
                                    if role == .particulier, section.0 == "Professionnels intéressés par mes biens",
                                       let matchingID = (item["_id"] as? String) ?? (item["id"] as? String) {
                                        Button("Retirer le rapprochement", systemImage: "eye.slash", role: .destructive) {
                                            Task { await auth.hidePrivatePropertyMatching(role: role.rawValue, matchingID: matchingID) }
                                        }
                                    }
                                    if role == .professionnel, section.0 == "Biens de particuliers correspondants",
                                       let matchingID = (item["_id"] as? String) ?? (item["id"] as? String) {
                                        Button("Retirer le rapprochement", systemImage: "eye.slash", role: .destructive) {
                                            Task { await auth.hidePrivatePropertyMatching(role: role.rawValue, matchingID: matchingID) }
                                        }
                                    }
                                    if role == .professionnel,
                                       ["Mes matchings", "Matchings réseau"].contains(section.0),
                                       let matchingID = (item["_id"] as? String) ?? (item["id"] as? String) {
                                        Button("Supprimer le matching", systemImage: "trash", role: .destructive) {
                                            pendingProfessionalMatchingDeletion = matchingID
                                            showProfessionalMatchingDeletionConfirmation = true
                                        }
                                    }
                                    if role == .professionnel,
                                       ["Mes matchings", "Matchings réseau", "Demandes acceptées"].contains(section.0),
                                       let itemID = (item["_id"] as? String) ?? (item["id"] as? String),
                                       item["seen"] as? Bool != true || (section.0 == "Demandes acceptées" && item["isViewed"] as? Bool != true) {
                                        Button("Marquer comme vu", systemImage: "eye") {
                                            Task {
                                                await auth.markMatchingSeen(
                                                    list: ["Mes matchings", "Matchings réseau"].contains(section.0) ? "matchings" : "demands",
                                                    itemID: itemID
                                                )
                                            }
                                        }
                                        .tint(.teal)
                                    }
                                    if role == .professionnel, section.0 == "Demandes du mini-site",
                                       item["status"] as? String != "processed",
                                       let requestID = (item["_id"] as? String) ?? (item["id"] as? String) {
                                        Button("Marquer comme traité", systemImage: "checkmark.circle") {
                                            Task { await auth.markMinisiteRequestProcessed(requestID: requestID) }
                                        }
                                        .tint(.green)
                                    }
                                    if role == .professionnel, section.0 == "Demandes du mini-site",
                                       let requestID = (item["_id"] as? String) ?? (item["id"] as? String) {
                                        Button("Supprimer", systemImage: "trash", role: .destructive) {
                                            pendingMinisiteDeletion = requestID
                                            showMinisiteDeletionConfirmation = true
                                        }
                                    }
                                    if role == .hebergeur, section.0 == "Demandes de réservation",
                                       item["hiddenByHost"] as? Bool != true,
                                       let requestID = (item["_id"] as? String) ?? (item["id"] as? String) {
                                        Button("Masquer", systemImage: "eye.slash", role: .destructive) {
                                            pendingHostBookingRequest = requestID
                                            showHostBookingHideConfirmation = true
                                        }
                                    }
                                    if role == .hebergeur, section.0 == "Tarifs saisonniers" {
                                        Button("Modifier", systemImage: "pencil") {
                                            editingSeasonalRate = item
                                            showSeasonalRateForm = true
                                        }
                                        .tint(.blue)
                                        if let rateID = (item["_id"] as? String) ?? (item["id"] as? String) {
                                            Button("Supprimer", systemImage: "trash", role: .destructive) {
                                                pendingSeasonalRateDeletion = rateID
                                                showSeasonalRateDeletionConfirmation = true
                                            }
                                        }
                                    }
                                    if role == .hebergeur, section.0 == "Mes hébergements",
                                       let accommodationID = (item["_id"] as? String) ?? (item["id"] as? String) {
                                        Button("Modifier", systemImage: "pencil") {
                                            editingSeasonalAccommodation = item
                                            showSeasonalAccommodationForm = true
                                        }
                                        .tint(.blue)
                                        Button("Supprimer", systemImage: "trash", role: .destructive) {
                                            pendingAccommodationDeletion = accommodationID
                                            showAccommodationDeletionConfirmation = true
                                        }
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
                    Section("Mes biens") {
                        Button { showProfessionalPropertyForm = true } label: {
                            Label("Créer une annonce immobilière", systemImage: "house.badge.plus")
                        }
                        Text("Créez un bien dans la collection Wix de votre compte. Vous choisissez s’il reste masqué ou s’il est publié immédiatement.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("Balayez une annonce vers la gauche pour l’archiver. Les annonces archivées ne sont plus publiées.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
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
                        Button {
                            openWebsiteRoute("/pro/parrainage", title: "Programme Ambassadeurs")
                        } label: {
                            Label("Programme Ambassadeurs et commissions", systemImage: "gift")
                        }
                    }
                }
                if role == .particulier {
                    Section("Parrainage et récompenses") {
                        Text("Retrouvez votre code, vos parrainages, vos points et les campagnes du programme sur votre compte PartenaireFoyer.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button {
                            openWebsiteRoute("/parrainage", title: "Parrainage et récompenses")
                        } label: {
                            Label("Ouvrir mon programme de parrainage", systemImage: "person.2.badge.plus")
                        }
                    }
                }
                if role == .hebergeur {
                    Section("Mon activité") {
                        Text("Hébergements et réservations chargés depuis vos collections Wix. Les demandes masquées dans Wix ne sont pas affichées ici.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let subscription = data["subscription"] as? [String: Any] {
                            LabeledContent("Abonnement", value: display(subscription["subscriptionTier"] ?? subscription["status"] ?? "Statut indisponible"))
                            LabeledContent("Statut", value: display(subscription["status"] ?? "Inconnu"))
                            if subscription["endDate"] != nil {
                                LabeledContent("Fin de période", value: display(subscription["endDate"]))
                            }
                            if subscription["renewalDate"] != nil {
                                LabeledContent("Prochain renouvellement", value: display(subscription["renewalDate"]))
                            }
                        } else {
                            Label("Aucun abonnement saisonnier associé à ce profil.", systemImage: "info.circle")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button {
                            websitePageURL = URL(string: "https://www.partenairefoyer.com/hebergeur-abonnement")
                            websitePageTitle = "Abonnement hébergeur"
                            showWebsiteDashboard = true
                        } label: {
                            Label("Gérer l’abonnement et le paiement", systemImage: "creditcard")
                        }
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
        .confirmationDialog(
            "Supprimer définitivement cette demande ?",
            isPresented: $showMinisiteDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer définitivement", role: .destructive) {
                guard let requestID = pendingMinisiteDeletion else { return }
                Task { await auth.deleteMinisiteRequest(requestID: requestID) }
                pendingMinisiteDeletion = nil
            }
            Button("Annuler", role: .cancel) { pendingMinisiteDeletion = nil }
        } message: {
            Text("La demande sera supprimée du CMS Wix et ne pourra pas être restaurée.")
        }
        .confirmationDialog(
            "Supprimer ce matching professionnel ?",
            isPresented: $showProfessionalMatchingDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer définitivement", role: .destructive) {
                guard let matchingID = pendingProfessionalMatchingDeletion else { return }
                Task { await auth.deleteProfessionalMatching(matchingID: matchingID) }
                pendingProfessionalMatchingDeletion = nil
            }
            Button("Annuler", role: .cancel) { pendingProfessionalMatchingDeletion = nil }
        } message: {
            Text("Le matching sera supprimé de Wix, comme dans votre espace professionnel sur le site.")
        }
        .confirmationDialog(
            "Supprimer cette recherche ?",
            isPresented: $showBuyerSearchDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer définitivement", role: .destructive) {
                guard let searchID = pendingBuyerSearchDeletion else { return }
                Task { _ = await buyerSearchService.delete(searchID: searchID) }
                pendingBuyerSearchDeletion = nil
            }
            Button("Annuler", role: .cancel) { pendingBuyerSearchDeletion = nil }
        } message: {
            Text("Cette recherche sera supprimée de votre espace Wix.")
        }
        .confirmationDialog(
            "Masquer cette demande de réservation ?",
            isPresented: $showHostBookingHideConfirmation,
            titleVisibility: .visible
        ) {
            Button("Masquer la demande", role: .destructive) {
                guard let requestID = pendingHostBookingRequest else { return }
                Task { await auth.hideHostBookingRequest(requestID: requestID) }
                pendingHostBookingRequest = nil
            }
            Button("Annuler", role: .cancel) { pendingHostBookingRequest = nil }
        } message: {
            Text("La demande sera masquée dans votre espace et dans Wix. Elle restera enregistrée pour le suivi de la réservation.")
        }
        .confirmationDialog(
            "Supprimer ce tarif saisonnier ?",
            isPresented: $showSeasonalRateDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer le tarif", role: .destructive) {
                guard let rateID = pendingSeasonalRateDeletion else { return }
                Task {
                    do { try await auth.deleteSeasonalRate(rateID: rateID) }
                    catch { auth.errorMessage = error.localizedDescription }
                }
                pendingSeasonalRateDeletion = nil
            }
            Button("Annuler", role: .cancel) { pendingSeasonalRateDeletion = nil }
        } message: {
            Text("Ce tarif sera supprimé de Wix et ne pourra pas être restauré.")
        }
        .confirmationDialog(
            "Supprimer cet hébergement ?",
            isPresented: $showAccommodationDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer l’hébergement", role: .destructive) {
                guard let accommodationID = pendingAccommodationDeletion else { return }
                Task {
                    do { try await auth.deleteHostAccommodation(accommodationID: accommodationID) }
                    catch { auth.errorMessage = error.localizedDescription }
                }
                pendingAccommodationDeletion = nil
            }
            Button("Annuler", role: .cancel) { pendingAccommodationDeletion = nil }
        } message: {
            Text("La suppression est possible seulement si cet hébergement n’a aucune demande, réservation, période tarifaire ou entrée de calendrier liée.")
        }
        .navigationTitle("Tableau de bord")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedItem) { selection in
            NavigationStack {
                if isEditingSelectedListing, let list = selection.list {
                    NativeListingEditForm(role: role.rawValue, list: list, item: selection.item, classifiedAds: classifiedAdsService) {
                        Task { await auth.loadDashboard(role: role.dashboardQueryRole) }
                        selectedItem = nil
                        isEditingSelectedListing = false
                    }
                } else {
                    DashboardItemDetailView(item: selection.item, role: role.rawValue, list: selection.list) {
                        isEditingSelectedListing = true
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fermer") { selectedItem = nil; isEditingSelectedListing = false }
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedConversation) { selection in
            NavigationStack {
                Group {
                    if role == .hebergeur {
                        NativeHostConversationView(conversationID: selection.id, preview: selection.preview)
                    } else {
                        NativeProfessionalConversationView(
                            conversationID: selection.id,
                            preview: selection.preview,
                            professionalID: member.id
                        )
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer") { selectedConversation = nil }
                    }
                }
            }
        }
        .sheet(isPresented: $showWebsiteDashboard) {
            ProfessionalPortalWebView(
                url: websitePageURL ?? role.dashboardURL,
                initialToken: auth.professionalPortalToken,
                title: websitePageTitle
            ) { token in
                if role == .professionnel {
                    auth.adoptProfessionalPortalSession(token: token)
                }
            }
        }
        .sheet(item: $selectedBillingPage) { page in
            NavigationStack {
                InAppSafariView(url: page.url)
                    .ignoresSafeArea()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fermer") { selectedBillingPage = nil }
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
                NativeBuyerSearchForm(service: buyerSearchService, initialData: editingBuyerSearch)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .onDisappear { editingBuyerSearch = nil }
        }
        .sheet(isPresented: $showProfessionalPropertyForm) {
            NavigationStack {
                NativeProfessionalPropertyForm {
                    Task { await auth.loadDashboard(role: role.dashboardQueryRole) }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPrivatePropertyForm) {
            NavigationStack {
                NativePrivatePropertyForm {
                    Task { await auth.loadDashboard(role: role.dashboardQueryRole) }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showClassifiedAdForm) {
            NavigationStack {
                NativeClassifiedAdForm(classifiedAds: classifiedAdsService) {
                    Task { await auth.loadDashboard(role: role.dashboardQueryRole) }
                }
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
        .sheet(isPresented: $showMiniSitePreview) {
            NavigationStack {
                ProfessionalMiniSitePreviewView(
                    profile: profile ?? [:],
                    properties: (auth.dashboardData?["properties"] as? [[String: Any]] ?? [])
                        .filter { $0["status"] as? String == "active" }
                )
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { showMiniSitePreview = false } } }
            }
        }
        .sheet(isPresented: $showImportCenter) {
            NavigationStack {
                ProfessionalImportCenterView(service: professionalImportService)
            }
        }
        .sheet(isPresented: $showSeasonalRateForm) {
            NavigationStack {
                NativeSeasonalRateForm(
                    accommodations: auth.dashboardData?["accommodations"] as? [[String: Any]] ?? [],
                    initialRate: editingSeasonalRate
                ) {
                    showSeasonalRateForm = false
                    editingSeasonalRate = nil
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSeasonalCalendarEditor) {
            NavigationStack {
                NativeSeasonalCalendarEditor(
                    accommodations: auth.dashboardData?["accommodations"] as? [[String: Any]] ?? [],
                    calendarEntries: auth.dashboardData?["calendar"] as? [[String: Any]] ?? [],
                    reservations: auth.dashboardData?["reservations"] as? [[String: Any]] ?? [],
                    onSave: { accommodationID, dates, status, price, minimumStay in
                        try await auth.saveSeasonalCalendarDates(
                            accommodationID: accommodationID, dates: dates,
                            availabilityStatus: status, pricePerNight: price, minimumStay: minimumStay
                        )
                    }
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSeasonalAccommodationForm) {
            NavigationStack {
                NativeSeasonalAccommodationForm(initialAccommodation: editingSeasonalAccommodation) {
                    showSeasonalAccommodationForm = false
                    editingSeasonalAccommodation = nil
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
        case .artisan, .diagnostiqueur: [("Entreprise", "companyName"), ("Contact", "contactName"), ("Activité", "category"), ("Spécialités", "categories"), ("Ville", "city"), ("Code postal", "postalCode"), ("Téléphone", "phoneNumber"), ("Site internet", "website"), ("Fiche visible", "isVisiblePublicly")]
        case .prestataire: [("Entreprise", "businessName"), ("Activité", "category"), ("Spécialité", "subcategory"), ("Ville", "city"), ("Code postal", "postalCode"), ("Téléphone", "phone"), ("Vérifié", "verified"), ("Statut", "status")]
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

    private func displayCategories(_ value: Any?) -> String {
        guard let value else { return "—" }
        let rows: [[String: Any]]
        if let string = value as? String, let data = string.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            rows = parsed
        } else if let parsed = value as? [[String: Any]] {
            rows = parsed
        } else {
            return display(value)
        }
        let names = rows.flatMap { $0["subCategories"] as? [String] ?? [] }
        return names.isEmpty ? display(value) : names.joined(separator: ", ")
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

private struct NativeHostConversationView: View {
    @StateObject private var auth = WixAuthStore.shared
    @State private var messages: [[String: Any]] = []
    @State private var hostID = ""
    @State private var error: String?
    @State private var sendError: String?
    @State private var composerText = ""
    @State private var isLoading = false
    @State private var isSending = false
    let conversationID: String
    let preview: [String: Any]

    private var title: String {
        if let name = preview["vacationerName"] as? String, !name.isEmpty { return name }
        return "Conversation hébergement"
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
                                let outgoing = (message["senderId"] as? String) == hostID
                                HStack {
                                    if outgoing { Spacer(minLength: 42) }
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text((message["messageContent"] as? String) ?? "")
                                            .font(.body).textSelection(.enabled)
                                        if let date = message["sentAt"] as? String, !date.isEmpty {
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
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Écrire un message…", text: $composerText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityLabel("Votre message")
                Button { Task { await sendMessage() } } label: {
                    if isSending { ProgressView() }
                    else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                }
                .disabled(isSending || composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Envoyer le message")
            }
            .padding(.horizontal).padding(.vertical, 8).background(.bar)
        }
        .navigationTitle(title)
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
            let loaded = try await auth.loadHostConversation(id: conversationID)
            hostID = loaded.hostID
            messages = loaded.messages
            error = nil
            try await auth.markHostConversationRead(conversationID: conversationID)
            messages = messages.map { message in
                var updated = message
                if (updated["receiverId"] as? String) == hostID { updated["isRead"] = true }
                return updated
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
            let sent = try await auth.sendHostMessage(conversationID: conversationID, content: content)
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
            [
                ("Hébergements", "accommodations", "house.fill"),
                ("Demandes", "bookingRequests", "calendar.badge.clock"),
                ("Réservations", "reservations", "calendar"),
                ("Conversations", "conversations", "bubble.left.and.bubble.right.fill"),
                ("Disponibilités", "calendar", "calendar.badge.checkmark"),
                ("Imports externes", "externalBookings", "calendar.badge.exclamationmark"),
                ("Tarifs", "seasonalRates", "eurosign.circle"),
                ("iCal", "calendarConnections", "arrow.triangle.2.circlepath.icloud")
            ]
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
                        let unread = items.reduce(into: 0) { count, item in
                            let isUnread = item["isRead"] as? Bool == false || item["seen"] as? Bool == false
                            if isUnread { count += 1 }
                        }
                        Text(unread == 0 ? "À jour" : "\(unread) non lu(s)")
                            .font(.caption2).foregroundStyle(unread == 0 ? Color.secondary : Color.orange)
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

private struct NativeSeasonalAccommodationForm: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var auth = WixAuthStore.shared
    @State private var itemName: String
    @State private var itemDescription: String
    @State private var accommodationType: String
    @State private var locationAddress: String
    @State private var city: String
    @State private var postalCode: String
    @State private var maxGuests: Int
    @State private var numberOfBedrooms: Int
    @State private var itemPrice: String
    @State private var amenities: String
    @State private var slug: String
    @State private var checkInMode: String
    @State private var checkInTime: String
    @State private var checkInUntil: String
    @State private var accessMethod: String
    @State private var arrivalInstructions: String
    @State private var status: String
    @State private var retainedPhotoURLs: [String]
    @State private var newPhotos: [Data] = []
    @State private var photosEdited = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    let initialAccommodation: [String: Any]?
    let onSaved: () -> Void

    init(initialAccommodation: [String: Any]?, onSaved: @escaping () -> Void) {
        self.initialAccommodation = initialAccommodation
        self.onSaved = onSaved
        let photoKeys = ["itemImage"] + (1...30).map { "photo\($0)" } + ["galleryImage2", "galleryImage3", "galleryImage4", "galleryImage5"]
        var seenPhotos = Set<String>()
        let existingPhotos = photoKeys.compactMap { initialAccommodation?[$0] as? String }
            .filter { !$0.isEmpty && seenPhotos.insert($0).inserted }
        _retainedPhotoURLs = State(initialValue: existingPhotos)
        _itemName = State(initialValue: initialAccommodation?["itemName"] as? String ?? "")
        _itemDescription = State(initialValue: initialAccommodation?["itemDescription"] as? String ?? "")
        _accommodationType = State(initialValue: initialAccommodation?["accommodationType"] as? String ?? "apartment")
        _locationAddress = State(initialValue: initialAccommodation?["locationAddress"] as? String ?? "")
        _city = State(initialValue: initialAccommodation?["city"] as? String ?? "")
        _postalCode = State(initialValue: initialAccommodation?["postalCode"] as? String ?? "")
        _maxGuests = State(initialValue: (initialAccommodation?["maxGuests"] as? Int) ?? 2)
        _numberOfBedrooms = State(initialValue: (initialAccommodation?["numberOfBedrooms"] as? Int) ?? 1)
        _itemPrice = State(initialValue: initialAccommodation?["itemPrice"].map { String(describing: $0) } ?? "")
        _amenities = State(initialValue: initialAccommodation?["amenities"] as? String ?? "")
        _slug = State(initialValue: initialAccommodation?["slug"] as? String ?? "")
        _checkInMode = State(initialValue: initialAccommodation?["checkInMode"] as? String ?? "FLEXIBLE")
        _checkInTime = State(initialValue: initialAccommodation?["checkInTime"] as? String ?? "15:00")
        _checkInUntil = State(initialValue: initialAccommodation?["checkInUntil"] as? String ?? "20:00")
        _accessMethod = State(initialValue: initialAccommodation?["accessMethod"] as? String ?? "HOST")
        _arrivalInstructions = State(initialValue: initialAccommodation?["arrivalInstructions"] as? String ?? "")
        _status = State(initialValue: "draft")
    }

    private var accommodationTypes: [(String, String)] {
        [("apartment", "Appartement"), ("house", "Maison"), ("villa", "Villa"), ("cottage", "Cottage"), ("studio", "Studio"), ("room", "Chambre")]
    }
    private var checkInModes: [(String, String)] {
        [("FLEXIBLE", "Arrivée libre"), ("FROM_TIME", "À partir d’une heure"), ("TIME_WINDOW", "Entre deux horaires"), ("BY_AGREEMENT", "À convenir")]
    }
    private var accessMethods: [(String, String)] {
        [("HOST", "Remise par l’hébergeur"), ("LOCKBOX", "Boîte à clés"), ("SMART_LOCK", "Serrure connectée"), ("RECEPTION", "Accueil ou réception"), ("KEY_PICKUP", "Retrait ailleurs"), ("OTHER", "Autre")]
    }

    var body: some View {
        Form {
            Section(initialAccommodation == nil ? "Nouvel hébergement" : "Modifier l’hébergement") {
                TextField("Nom de l’établissement", text: $itemName)
                Picker("Type", selection: $accommodationType) {
                    ForEach(accommodationTypes, id: \.0) { Text($0.1).tag($0.0) }
                }
                TextField("Adresse", text: $locationAddress)
                TextField("Ville", text: $city)
                TextField("Code postal", text: $postalCode).keyboardType(.numberPad)
                TextField("URL personnalisée", text: $slug)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Description", text: $itemDescription, axis: .vertical).lineLimit(4...9)
            }
            Section("Capacité et tarif") {
                Stepper("Voyageurs maximum : \(maxGuests)", value: $maxGuests, in: 1...100)
                Stepper("Chambres : \(numberOfBedrooms)", value: $numberOfBedrooms, in: 1...100)
                TextField("Prix par nuit (€)", text: $itemPrice).keyboardType(.decimalPad)
            }
            Section("Équipements et arrivée") {
                TextField("Équipements (séparés par des virgules)", text: $amenities, axis: .vertical).lineLimit(2...4)
                Picker("Modalité d’arrivée", selection: $checkInMode) {
                    ForEach(checkInModes, id: \.0) { Text($0.1).tag($0.0) }
                }
                if ["FROM_TIME", "TIME_WINDOW"].contains(checkInMode) {
                    TextField("Arrivée à partir de (HH:mm)", text: $checkInTime)
                    if checkInMode == "TIME_WINDOW" { TextField("Arrivée jusqu’à (HH:mm)", text: $checkInUntil) }
                }
                Picker("Accès au logement", selection: $accessMethod) {
                    ForEach(accessMethods, id: \.0) { Text($0.1).tag($0.0) }
                }
                TextField("Consignes d’arrivée (sans code confidentiel)", text: $arrivalInstructions, axis: .vertical).lineLimit(3...6)
            }
            Section("Photos de l’hébergement") {
                if retainedPhotoURLs.isEmpty && newPhotos.isEmpty {
                    Text("Aucune photo ajoutée.").foregroundStyle(.secondary)
                }
                if !retainedPhotoURLs.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(Array(retainedPhotoURLs.enumerated()), id: \.offset) { index, source in
                                ZStack(alignment: .topTrailing) {
                                    AsyncImage(url: WixImageSource.url(source)) { phase in
                                        if let image = phase.image { image.resizable().scaledToFill() }
                                        else { Image(systemName: "house.fill").foregroundStyle(.teal).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.teal.opacity(0.1)) }
                                    }
                                    .frame(width: 84, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Button(role: .destructive) {
                                        retainedPhotoURLs.remove(at: index)
                                        photosEdited = true
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3).symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain).padding(4)
                                    .accessibilityLabel("Supprimer la photo existante \(index + 1)")
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                NativeListingPhotoPicker(photos: $newPhotos, maxPhotos: max(0, 35 - retainedPhotoURLs.count))
                    .onChange(of: newPhotos) { _, _ in photosEdited = true }
                Text("Vous pouvez ajouter ou retirer jusqu’à 35 photos. Les changements sont enregistrés dans l’hébergement Wix.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if initialAccommodation == nil {
                Section("Statut") {
                    Picker("Publication", selection: $status) {
                        Text("Brouillon").tag("draft")
                        Text("À valider").tag("pending")
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
                        let dayNumber = Calendar.current.component(.day, from: date)
                        let reserved = isReserved(key)
                        let selected = selectedDates.contains(key)
                        let foregroundColor: Color = reserved ? Color.secondary : (selected ? Color.white : Color.primary)
                        let backgroundColor: Color = selected ? Color.teal : statusColor(key)
                        let borderColor: Color = reserved ? Color.blue.opacity(0.65) : Color.clear
                        Button {
                            guard !reserved else { return }
                            if selected { selectedDates.remove(key) } else { selectedDates.insert(key) }
                        } label: {
                            Text(dayNumber.formatted())
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .foregroundStyle(foregroundColor)
                                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(borderColor, lineWidth: 1.5))
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

private struct NativeBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Label("Retour", systemImage: "chevron.left")
                    }
                    .accessibilityLabel("Retour")
                }
            }
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
    var onOpportunityAccept: (() async -> Void)? = nil
    var onHostBookingTransition: ((String) async -> Void)? = nil
    @State private var isClaiming = false
    @State private var isAcceptingOpportunity = false
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
        if let label = item["matchingLabel"] as? String, !label.isEmpty {
            if let score = item["matchingScore"] {
                return "\(label) · \(String(describing: score)) %"
            }
            return label
        }
        if let score = item["matchingScore"] {
            let isNetwork = (item["matchingType"] as? String)?.lowercased() == "reseau"
            return "Matching \(isNetwork ? "réseau" : "immobilier") · \(String(describing: score)) %"
        }
        if let demand = item["demandType"] as? String, !demand.isEmpty {
            return "Demande · \(demand)"
        }
        return ["title", "itemName", "propertyTitle", "searchName", "businessName", "professionalName", "senderName", "fullName"]
            .compactMap { item[$0] as? String }.first ?? fallbackTitle
    }
    private var subtitle: String {
        var values = ["propertyCity", "propertyPostalCode", "propertyType", "transactionType", "propertyReferenceCode", "buyerCity", "buyerReferenceCode", "otherProfessionalName", "otherProfessionalCompany", "otherProfessionalCity", "professionalName", "city", "postalCode", "category", "matchingType", "demandType"].compactMap { item[$0] as? String }.filter { !$0.isEmpty }
        if let status = item["status"] as? String {
            switch status.lowercased() {
            case "pending": values.append("À examiner")
            case "accepted": values.append("Acceptée")
            case "converted": values.append("Sélectionnée")
            default: break
            }
        }
        return values.joined(separator: " · ")
    }
    private var detail: String? {
        let text = ["description", "itemDescription", "message", "messageContent", "content"].compactMap { item[$0] as? String }.first
        var criteria: [String] = []
        if let reference = item["buyerReferenceCode"] as? String, !reference.isEmpty {
            criteria.append("Acquéreur · réf. \(reference)")
        }
        if let value = item["buyerBudgetMin"] { criteria.append("Budget dès \(value) €") }
        if let value = item["buyerBudgetMax"] { criteria.append("Budget jusqu’à \(value) €") }
        if let value = item["buyerMinRooms"] { criteria.append("\(value) pièces min.") }
        if let value = item["buyerSurfaceMin"] { criteria.append("\(value) m² min.") }
        if let value = item["buyerSearchRadiusKm"] { criteria.append("Rayon \(value) km") }
        if let features = item["buyerMandatoryFeatures"] as? String, !features.isEmpty {
            criteria.append("Critères : \(features.replacingOccurrences(of: ",", with: " · "))")
        }
        if let style = item["buyerPropertyStylePreferences"] as? String, !style.isEmpty {
            criteria.append("Style : \(style.replacingOccurrences(of: ",", with: " · "))")
        }
        if let value = item["propertyRooms"] { criteria.append("\(value) pièces") }
        if let value = item["propertyBedrooms"] { criteria.append("\(value) chambres") }
        if let value = item["propertyBathrooms"] { criteria.append("\(value) salles de bain") }
        return ([text].compactMap { $0 } + criteria).joined(separator: " · ")
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
        let candidate = ["otherProfessionalEmail", "professionalEmail", "senderEmail", "vacationerEmail", "email"]
            .compactMap { item[$0] as? String }
            .first { value in
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized.contains("@") && normalized.count <= 254 && !normalized.contains("\n")
            }
        guard let email = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        var components = URLComponents()
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
        guard let phone = ["otherProfessionalPhone", "professionalPhone", "senderPhone", "vacationerPhone", "phone", "phoneNumber"]
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
            if let onOpportunityAccept {
                Button {
                    Task {
                        isAcceptingOpportunity = true
                        await onOpportunityAccept()
                        isAcceptingOpportunity = false
                    }
                } label: {
                    Label(isAcceptingOpportunity ? "Création de la collaboration…" : "Accepter cette opportunité", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(isAcceptingOpportunity)
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
                let places = candidate["placesRemaining"] as? Int ?? 0
                Text("\(places) place\(places == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold)).foregroundStyle(.teal)
            }
            Text([text("postalCode"), text("experience"), text("project")].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondary)
            if candidate["mine"] as? Bool == true {
                Text([text("firstName"), text("lastName")].filter { !$0.isEmpty }.joined(separator: " "))
                    .font(.subheadline.weight(.semibold))
                if !text("email").isEmpty { Label("E-mail : \(text("email"))", systemImage: "envelope").font(.caption) }
                if !text("phone").isEmpty { Label("Téléphone : \(text("phone"))", systemImage: "phone").font(.caption) }
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
                                if let rawImage = (item["mainImageUrl"] as? String) ?? (item["photo1"] as? String),
                                   let url = WixImageSource.url(rawImage) {
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
        guard let itemID = (item["_id"] as? String) ?? (item["id"] as? String) else {
            errorMessage = "Identifiant d’annonce manquant."
            return
        }
        do {
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
        var rows: [(String, String)] = []
        for (key, label) in displayFields {
            guard let value = item[key], !(value is NSNull), !seen.contains(label) else { continue }
            let text: String
            if let flag = value as? Bool {
                text = flag ? "Oui" : "Non"
            } else if let values = value as? [String] {
                text = values.joined(separator: ", ")
            } else {
                text = String(describing: value)
            }
            guard !text.isEmpty else { continue }
            seen.insert(label)
            rows.append((label, text))
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

/// Translates a public listing description only after the reader requests English.
/// The French source stays in its original record and remains the fallback.
private struct ListingDescriptionTranslation: View {
    let original: String
    var language: String = "fr"
    @State private var translatedText: String?
    @State private var showingEnglish = false
    @State private var isTranslating = false
    @State private var translationFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(showingEnglish ? (translatedText ?? original) : original)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if language != "en" {
                Button {
                    if translatedText != nil { showingEnglish.toggle() }
                    else { Task { await translateDescription() } }
                } label: {
                HStack(spacing: 7) {
                    if isTranslating {
                        ProgressView().controlSize(.small)
                        Text(language == "en" ? "Translating…" : "Traduction en cours…")
                    } else {
                        Label(
                            translatedText != nil && showingEnglish
                                ? "Afficher le français"
                                : "Traduire en anglais (gratuit)",
                            systemImage: "translate"
                        )
                    }
                }
                .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(isTranslating)
            }

            Text(language == "en"
                 ? "The public description is translated using a free translation service. The original text is preserved."
                 : "La description publique est envoyée à un service de traduction gratuit. Le texte français reste inchangé.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if translationFailed {
                Text(language == "en" ? "Translation is unavailable right now; the original text is shown." : "Traduction indisponible pour le moment ; le texte original est conservé.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: language) {
            if language == "en" { await translateDescription() }
            else { showingEnglish = false }
        }
    }

    @MainActor private func translateDescription() async {
        guard !isTranslating else { return }
        if let translatedText { showingEnglish = true; return }
        isTranslating = true
        translationFailed = false
        let result = await FreePublicListingTranslator.translate(original)
        isTranslating = false
        if let result, !result.isEmpty {
            translatedText = result
            showingEnglish = true
        } else {
            translationFailed = true
        }
    }
}

private enum FreePublicListingTranslator {
    private struct Response: Decodable {
        let translatedText: String
    }

    private static let endpoints = [
        "https://translate.cutie.dating/translate",
        "https://translate.fedilab.app/translate"
    ]

    static func translate(_ text: String) async -> String? {
        let chunks = split(text, maximumLength: 1800)
        guard !chunks.isEmpty else { return nil }

        for endpoint in endpoints {
            var translated: [String] = []
            var endpointSucceeded = true
            for chunk in chunks {
                guard let result = await translate(chunk, endpoint: endpoint) else {
                    endpointSucceeded = false
                    break
                }
                translated.append(result)
            }
            if endpointSucceeded { return translated.joined(separator: " ") }
        }
        return nil
    }

    private static func translate(_ text: String, endpoint: String) async -> String? {
        guard let url = URL(string: endpoint),
              let body = try? JSONSerialization.data(withJSONObject: [
                "q": text,
                "source": "auto",
                "target": "en",
                "format": "text"
              ]) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            return nil
        }
        return decoded.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func split(_ text: String, maximumLength: Int) -> [String] {
        var remaining = text[...]
        var chunks: [String] = []
        while !remaining.isEmpty {
            let count = min(maximumLength, remaining.count)
            var end = remaining.index(remaining.startIndex, offsetBy: count)
            if end < remaining.endIndex,
               let boundary = remaining[..<end].lastIndex(where: { $0.isWhitespace }) {
                end = remaining.index(after: boundary)
            }
            let chunk = String(remaining[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty { chunks.append(chunk) }
            remaining = remaining[end...]
        }
        return chunks
    }
}
