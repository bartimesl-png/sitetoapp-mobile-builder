// AppConfig.swift
import Foundation

enum AppConfig {
    static let websiteURL = URL(string: "https://www.partenairefoyer.com/")!
    static let listingsEndpoint = URL(
        string: "https://krvwwavxmuwieemubhdj.supabase.co/functions/v1/pf-imported-real-estate-listings-public"
    )!
    static let privacyURL = URL(
        string: "https://www.partenairefoyer.com/politique-de-confidentialite"
    )!
    static let supportEmail = "contact@partenairefoyer.com"
}
