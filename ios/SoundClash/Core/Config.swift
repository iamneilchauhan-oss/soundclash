import Foundation

/// Central configuration. Fill in your own values before running on a device —
/// Xcode flags the #warning below until you do.
enum SCConfig {
    /// e.g. "https://xyzcompany.supabase.co"
    static let supabaseURL = "https://YOUR_PROJECT.supabase.co"
    /// Supabase project anon key (public, safe to ship in the app).
    static let supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY"
    /// Base URL of backend/token-service (no trailing slash).
    /// e.g. "https://soundclash-tokens.fly.dev"
    static let tokenServiceBaseURL = "https://YOUR_TOKEN_SERVICE.example.com"
}

#warning("Fill in SCConfig values (supabaseURL, supabaseAnonKey, tokenServiceBaseURL) before running on device.")

/// True inside Xcode Previews — view models use MockData instead of the network,
/// so every #Preview keeps working with zero backend configured.
enum SCPreview {
    static let isActive: Bool =
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}
