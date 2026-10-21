import Foundation

/// Non-secret runtime configuration injected through xcconfig → Info.plist.
/// Provider credentials and API keys never live in the app; they stay on the backend.
/// The Supabase publishable key is public by design: it only identifies the project, and every
/// table is protected by row level security.
struct AppConfiguration: Equatable, Sendable {
    enum Environment: String, Sendable {
        case development
        case production
    }

    enum Key {
        static let apiBaseURL = "GMAPIBaseURL"
        static let environment = "GMEnvironment"
        static let supabaseURL = "GMSupabaseURL"
        static let supabasePublishableKey = "GMSupabasePublishableKey"
    }

    let environment: Environment
    let apiBaseURL: URL
    let supabaseURL: URL
    let supabasePublishableKey: String

    init(environment: Environment, apiBaseURL: URL, supabaseURL: URL, supabasePublishableKey: String) {
        self.environment = environment
        self.apiBaseURL = apiBaseURL
        self.supabaseURL = supabaseURL
        self.supabasePublishableKey = supabasePublishableKey
    }

    static func load(from bundle: Bundle = .main) throws(AppError) -> AppConfiguration {
        try load(from: bundle.infoDictionary ?? [:])
    }

    static func load(from info: [String: Any]) throws(AppError) -> AppConfiguration {
        guard let rawEnvironment = info[Key.environment] as? String,
            let environment = Environment(rawValue: rawEnvironment)
        else {
            throw .configuration("The build environment is missing or unrecognised.")
        }

        let apiBaseURL = try url(info, Key.apiBaseURL, name: "Grymode API", environment: environment)
        let supabaseURL = try url(info, Key.supabaseURL, name: "sign-in service", environment: environment)

        let publishableKey = (info[Key.supabasePublishableKey] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !publishableKey.isEmpty else {
            throw .configuration("The sign-in service key has not been set for this build.")
        }
        guard !publishableKey.hasPrefix("sb_secret_") else {
            throw .configuration("This build contains a secret key. Use the publishable key instead.")
        }

        return AppConfiguration(
            environment: environment,
            apiBaseURL: apiBaseURL,
            supabaseURL: supabaseURL,
            supabasePublishableKey: publishableKey
        )
    }

    private static func url(
        _ info: [String: Any],
        _ key: String,
        name: String,
        environment: Environment
    ) throws(AppError) -> URL {
        let rawURL = (info[key] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !rawURL.isEmpty else {
            throw .configuration("The \(name) address has not been set for this build.")
        }
        guard let url = URL(string: rawURL), let scheme = url.scheme?.lowercased(), let host = url.host() else {
            throw .configuration("The \(name) address is not a valid URL.")
        }

        let isLocalHost = host == "localhost" || host == "127.0.0.1"
        switch (environment, scheme) {
        case (_, "https"):
            return url
        case (.development, "http") where isLocalHost:
            return url
        default:
            throw .configuration("The \(name) address must use HTTPS.")
        }
    }
}
