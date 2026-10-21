import OSLog

/// Structured loggers. Never log access tokens, signed URLs, wardrobe images, or personal data.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.grymode.stylist"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let networking = Logger(subsystem: subsystem, category: "networking")
    static let onboarding = Logger(subsystem: subsystem, category: "onboarding")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let account = Logger(subsystem: subsystem, category: "account")
    static let wardrobe = Logger(subsystem: subsystem, category: "wardrobe")
}
