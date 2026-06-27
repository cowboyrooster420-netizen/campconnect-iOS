import Foundation

/// Runtime configuration. Values are read from `Secrets.plist` (git-ignored) so
/// keys never land in source control. See `Secrets.example.plist` and the README.
///
/// The Supabase anon key is safe to ship in a client app (RLS enforces access),
/// but we still keep it out of git to make key rotation and per-env config easy.
enum AppConfig {
    static let supabaseURL: URL = {
        guard let value = info("SUPABASE_URL"), let url = URL(string: value) else {
            fatalError("Missing SUPABASE_URL in Secrets.plist — copy Secrets.example.plist to Secrets.plist and fill it in.")
        }
        return url
    }()

    static let supabaseAnonKey: String = {
        guard let value = info("SUPABASE_ANON_KEY"), !value.isEmpty else {
            fatalError("Missing SUPABASE_ANON_KEY in Secrets.plist — see the README.")
        }
        return value
    }()

    private static func info(_ key: String) -> String? {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return dict[key] as? String
    }
}
