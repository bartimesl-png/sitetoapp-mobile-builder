Warning: truncated output (original token count: 138728)
Total output lines: 10509


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

private struct NativeSeasonalThemeResponse: Decodable {
    let activeTheme: String?
}

struct NativeSeasonalTheme {
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
    let isHome: Bool

    var body: some View {
        ZStack {
            // Floating shapes move behind the controls and never intercept touches.
            SeasonalMagicCanvas(theme: theme, stage: .ambient)
                .opacity(isHome ? 0.96 : 0.78)
                .ignoresSafeArea()
            VStack(spacing: 0) {
            LinearGradient(
                colors: [theme.accent, theme.secondary, theme.accent],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 4)
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}



// Theme-aware accents belong to the actual native cards, not just the hero.
private struct SeasonalCardOrnament: ViewModifier {
    @Environment(\.pfNativeSeasonalTheme) private var theme
    @Environment(\.pfNativeSeasonalEnabled) private var themeEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    let emphasized: Bool

    private var pair: (String, String) {
        switch theme?.id {
        case "halloween": return ("👻", "🦇")
        case "noel": return ("❄️", "🎄")
        case "nouvel-an": return ("✨", "🎆")
        case "paques": return ("🐣", "🌷")
        case "printemps": return ("🦋", "🌼")
        case "fete-des-meres": return ("💗", "💐")
        case "fete-des-peres": return ("⭐", "🎁")
        case "14-juillet": return ("✨", "🇫🇷")
        case "ete": return ("☀️", "🌴")
        case "rentree": return ("🍂", "🍁")
        case "octobre-rose": return ("🎀", "💗")
        case "armistice": return ("🕊️", "🌺")
        case "movember": return ("💙", "🎗️")
        case "saint-valentin": return ("❤️", "💌")
        case "black-friday": return ("⚡", "✨")
        default: return ("✨", "✦")
        }
    }

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if themeEnabled, let theme {
                ZStack {
                    Circle()
                        .fill(theme.secondary.opacity(emphasized ? 0.25 : 0.10))
                        .frame(width: emphasized ? 77 : 44, height: emphasized ? 77 : 44)
                        .blur(radius: emphasized ? 17 : 9)
                    Text(pair.0)
                        .font(.system(size: emphasized ? 42 : 25))
                        .shadow(color: theme.accent.opacity(0.38), radius: 4, y: 2)
                        .offset(x: emphasized ? -13 : -6, y: floating ? -9 : -2)
                    Text(pair.1)
                        .font(.system(size: emphasized ? 22 : 14))
                        .offset(x: emphasized ? 19 : 14, y: emphasized ? 21 : 14)
                }
                .frame(width: emphasized ? 90 : 53, height: emphasized ? 78 : 47)
                .opacity(emphasized ? 0.90 : 0.63)
                .offset(x: emphasized ? 9 : 1, y: emphasized ? -13 : -6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onAppear {
                    guard emphasized, !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 2.7).repeatForever(autoreverses: true)) {
                        floating = true
                    }
                }
            }
        }
    }
}

private extension View {
    func pfFestiveCard(emphasized: Bool = false) -> some View {
        modifier(SeasonalCardOrnament(emphasized: emphasized))
    }
}

private struct SeasonalPageRibbon: View {
    @Environment(\.pfNativeSeasonalTheme) private var theme
    @Environment(\.pfNativeSeasonalEnabled) private var themeEnabled
    @AppStorage("partenairefoyer.language") private var appLanguage = "fr"

    let context: String

    private var themeName: String {
        switch theme?.id {
        case "halloween": return "Halloween"
        case "noel": return "Noël"
        case "nouvel-an": return "Nouvel An"
        case "paques": return "Pâques"
        case "printemps": return "Printemps"
        case "fete-des-meres": return "Fête des mères"
        case "fete-des-peres": return "Fête des pères"
        case "14-juillet": return "14 Juillet"
        case "ete": return "Été"
        case "rentree": return "Rentrée"
        case "octobre-rose": return "Octobre rose"
        case "armistice": return "11 Novembre"
        case "movember": return "Movember"
        case "saint-valentin": return "Saint-Valentin"
        case "black-friday": return "Black Friday"
        default: return "Les moments"
        }
    }

    private var icon: String {
        switch theme?.id {
        case "halloween": return "👻"
        case "noel": return "🎅"
        case "nouvel-an", "14-juillet": return "🎆"
        case "paques": return "🐰"
        case "printemps": return "🦋"
        case "fete-des-meres": return "💐"
        case "fete-des-peres": return "🎁"
        case "ete": return "☀️"
        case "rentree": return "🍁"
        case "octobre-rose": return "🎀"
        case "armistice": return "🕊️"
        case "movember": return "💙"
        case "saint-valentin": return "❤️"
        case "black-friday": return "⚡"
        default: return "✨"
        }
    }

    var body: some View {
        if themeEnabled, let theme {
            HStack(spacing: 11) {
                Text(icon)
                    .font(.system(size: 34))
                    .frame(width: 47, height: 47)
                    .background(.white.opacity(0.70), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(themeName.uppercased())
                        .font(.caption.weight(.heavy))
                        .tracking(0.9)
                    Text(appLanguage == "en" ? "A touch of magic on every page" : "La magie accompagne vos découvertes")
                        .font(.caption)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Text("✨")
                    .font(.title2)
            }
            .foregroundStyle(theme.id == "halloween" ? Color(red: 0.24, green: 0.11, blue: 0.34) : Color(red: 0.08, green: 0.23, blue: 0.23))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [theme.soft, theme.secondary.opacity(0.19), theme.soft],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.accent.opacity(0.24), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(themeName) · \(context)")
        }
    }
}

private struct HalloweenHouseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.addRect(CGRect(x: w * 0.24, y: h * 0.45, width: w * 0.58, height: h * 0.55))
        path.move(to: CGPoint(x: w * 0.15, y: h * 0.47))
        path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.12))
        path.addLine(to: CGPoint(x: w * 0.91, y: h * 0.47))
        path.closeSubpath()
        path.addRect(CGRect(x: w * 0.11, y: h * 0.28, width: w * 0.18, height: h * 0.72))
        path.move(to: CGPoint(x: w * 0.075, y: h * 0.32))
        path.addLine(to: CGPoint(x: w * 0.20, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.33, y: h * 0.32))
        path.closeSubpath()
        path.addRect(CGRect(x: w * 0.74, y: h * 0.30, width: w * 0.20, height: h * 0.70))
        path.move(to: CGPoint(x: w * 0.70, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.04))
        path.addLine(to: CGPoint(x: w * 0.98, y: h * 0.35))
        path.closeSubpath()
        path.addRect(CGRect(x: w * 0.59, y: h * 0.06, width: w * 0.055, height: h * 0.28))
        return path
    }
}

private struct SeasonalFeatureBanner: View {
    let theme: NativeSeasonalTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var floating = false
    @State private var celebrationTime: TimeInterval = -1000

    private var content: (title: String, caption: String, primary: String, secondary: String) {
        switch theme.id {
        case "halloween": return ("HALLOWEEN", "Le foyer se pare de mystère", "🎃", "👻")
        case "noel": return ("JOYEUX NOËL", "La magie des fêtes est chez vous", "🎄", "🎁")
        case "nouvel-an": return ("BONNE ANNÉE", "De nouveaux projets à célébrer", "🎆", "🥂")
        case "paques": return ("JOYEUSES PÂQUES", "Des surprises à chaque coin de maison", "🐰", "🥚")
        case "printemps": return ("LE PRINTEMPS", "Un souffle nouveau pour vos projets", "🌷", "🦋")
        case "fete-des-meres": return ("FÊTE DES MÈRES", "De belles attentions à partager", "💐", "💗")
        case "fete-des-peres": return ("FÊTE DES PÈRES", "Une journée pleine de surprises", "🎁", "🏆")
        case "14-juillet": return ("14 JUILLET", "Un air de fête partout en France", "🎆", "🇫🇷")
        case "ete": return ("BEL ÉTÉ", "Place au soleil et aux nouveaux projets", "☀️", "🌴")
        case "rentree": return ("C'EST LA RENTRÉE", "Une nouvelle saison commence", "🎒", "📚")
        case "octobre-rose": return ("OCTOBRE ROSE", "Ensemble, faisons rayonner le soutien", "🎀", "💗")
        case "armistice": return ("11 NOVEMBRE", "Un moment de mémoire et de paix", "🕊️", "🌺")
        case "movember": return ("MOVEMBER", "Un mois pour sensibiliser", "🧔", "💙")
        case "saint-valentin": return ("SAINT-VALENTIN", "Les plus belles histoires commencent ici", "❤️", "🌹")
        case "black-friday": return ("BLACK FRIDAY", "Des opportunités à découvrir", "🛍️", "⚡")
        default: return ("LES MOMENTS", "Une touche de magie dans l'application", "✨", "⭐")
        }
    }

    private var darkColor: Color {
        switch theme.id {
        case "halloween": return Color(pfHex: 0x160B2C)
        case "noel": return Color(pfHex: 0x103F34)
        case "octobre-rose", "fete-des-meres", "saint-valentin": return Color(pfHex: 0x581632)
        case "ete", "14-juillet": return Color(pfHex: 0x0F3D60)
        default: return Color(pfHex: 0x162A35)
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [darkColor, theme.accent.opacity(0.96), theme.secondary.opacity(0.80)],
                startPoint: .leading,
                endPoint: .trailing
            )
            SeasonalScenicBackdrop(theme: theme)

            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let visualScale = min(1.75, max(0.95, width / 500))

                Circle()
                    .fill(theme.secondary.opacity(0.33))
                    .frame(width: 155 * visualScale, height: 155 * visualScale)
                    .blur(radius: 40 * visualScale)
                    .position(x: width * 0.87, y: height * 0.27)

                if theme.id == "halloween" {
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color(pfHex: 0xFFF3D0), Color(pfHex: 0xFFA650)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 60
                        ))
                        .frame(width: 108 * visualScale, height: 108 * visualScale)
                        .shadow(color: Color(pfHex: 0xFF9D45).opacity(0.66), radius: 28)
                        .position(x: width * 0.79, y: height * 0.35)
                        .scaleEffect(floating ? 1.055 : 1.0)

                    HalloweenHouseShape()
                        .fill(Color(pfHex: 0x100B1B))
                        .frame(width: 174 * visualScale, height: 119 * visualScale)
                        .position(x: width * 0.79, y: height * 0.71)

                    HStack(spacing: 19) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(pfHex: 0xFFBF5A))
                            .frame(width: 9 * visualScale, height: 17 * visualScale)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(pfHex: 0xFFBF5A))
                            .frame(width: 9, height: 17)
                    }
                    .shadow(color: .orange.opacity(0.7), radius: 6)
                    .position(x: width * 0.83, y: height * 0.74)

                    Text("🦇")
                        .font(.system(size: 49 * visualScale))
                        .rotationEffect(.degrees(floating ? 12 : -10))
                        .position(x: width * 0.63, y: height * 0.23)
                    Text("👻")
                        .font(.system(size: 58 * visualScale))
                        .rotationEffect(.degrees(floating ? 8 : -8))
                        .position(x: width * 0.94, y: height * 0.51)
                    Text("🎃")
                        .font(.system(size: 89 * visualScale))
                        .position(x: width * 0.76, y: height * 0.94)
                } else {
                    Circle()
                        .stroke(.white.opacity(0.21), lineWidth: 1.5)
                        .frame(width: 158 * visualScale, height: 158 * visualScale)
                        .position(x: width * 0.81, y: height * 0.49)
                    Text(content.primary)
                        .font(.system(size: 110 * visualScale))
                        .rotationEffect(.degrees(floating ? 5 : -5))
                        .shadow(color: .black.opacity(0.18), radius: 15, y: 9)
                        .position(x: width * 0.78, y: height * 0.51)
                    Text(content.secondary)
                        .font(.system(size: 65 * visualScale))
                        .rotationEffect(.degrees(floating ? -9 : 8))
                        .position(x: width * 0.93, y: height * 0.77)
                }
            }

            LinearGradient(
                colors: [darkColor.opacity(0.86), darkColor.opacity(0.20), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            SeasonalMagicCanvas(theme: theme, stage: .feature, burstTime: celebrationTime)

            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .bold))
                    Text("LES MOMENTS PARTENAIREFOYER")
                        .tracking(1.0)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))

                Text(content.title)
                    .font(.system(size: horizontalSizeClass == .regular ? 43 : 31,
                                  weight: .black, design: .rounded))
                    .tracking(-0.5)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.30), radius: 7, y: 3)

                Text(content.caption)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    guard !reduceMotion else { return }
                    celebrationTime = Date().timeIntervalSinceReferenceDate
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Lancer la magie", systemImage: "sparkles")
                        .font(.system(size: horizontalSizeClass == .regular ? 15 : 13,
                                      weight: .bold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(darkColor)
                        .background(.white.opacity(0.95), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(reduceMotion)
                .accessibilityHint("Déclenche une pluie d'animations de l'événement.")
            }
            .frame(width: horizontalSizeClass == .regular ? 360 : 208, alignment: .leading)
            .padding(.leading, horizontalSizeClass == .regular ? 34 : 20)
        }
        .frame(height: horizontalSizeClass == .regular ? 290 : 258)
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(.white.opacity(0.26), lineWidth: 1)
        }
        .shadow(color: theme.accent.opacity(0.25), radius: 17, y: 8)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
    }
}

private extension Color {
    init(pfHex: UInt) {
        self.init(.sRGB, red: Double((pfHex >> 16) & 0xFF) / 255, green: Double((pfHex >> 8) & 0xFF) / 255, blue: Double(pfHex & 0xFF) / 255, opacity: 1)
    }
}

struct RootView: View {
    @State private var selectedTab = 0
    @State private var selectedCatalogSection: NativeCatalogSection = .hub
    @AppStorage("partenairefoyer.activeRole") private var activeRoleRaw = ""
    @AppStorage("partenairefoyer.language") private var appLanguage = "fr"
    @State private var seasonalTheme: NativeSeasonalTheme?
    @AppStorage("partenairefoyer.nativeSeasonalEnabled.v2") private var seasonalThemeEnabled = true
    @StateObject private var listingsService = ListingsService()
    @StateObject private var classifiedAdsService = ClassifiedAdsService()
    @StateObject private var buyerSearchesService = PublicBuyerSearchesService()
    @StateObject private var professionalsService = ProfessionalsService()

    private var visibleSeasonalTheme: NativeSeasonalTheme? {
        seasonalThemeEnabled ? seasonalTheme : nil
    }

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
        .tint(visibleSeasonalTheme?.accent ?? PFTheme.brand)
        .toolbarBackground(visibleSeasonalTheme?.soft.opacity(0.90) ?? Color(uiColor: .systemBackground), for: .tabBar)
        .toolbarBackground(visibleSeasonalTheme?.soft.opacity(0.94) ?? Color(uiColor: .systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.visible, for: .tabBar)
        .overlay {
            if let theme = visibleSeasonalTheme {
                SeasonalDecorationsLayer(theme: theme, isHome: selectedTab == 0)
            }
        }
        .environment(\.pfNativeSeasonalTheme, seasonalTheme)
        .environment(\.pfNativeSeasonalEnabled, seasonalThemeEnabled)
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: appLanguage == "en" ? "en_US" : "fr_FR"))
        .task { await loadSeasonalTheme() }
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
            // Keep the native app usable if the seasonal endpoint is unavailable.
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
                            SeasonalPageRibbon(context: "Séjours")
                                .listRowBackground(Color.clear)
                        }
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
            if blockedKeys…118728 tokens truncated…ystem(size: 58)).foregroundStyle(.teal)
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
