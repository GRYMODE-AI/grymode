import Foundation

/// Canonical destinations for App Review and in-app legal/support access.
enum LegalLinks {
    static let terms = URL(string: "https://grymode.ai/terms")!
    static let privacy = URL(string: "https://grymode.ai/privacy")!
    static let support = URL(string: "mailto:support@grymode.ai")!

    static let termsTitle = "Terms of Use"
    static let privacyTitle = "Privacy Policy"
    static let supportTitle = "Contact support"
}
