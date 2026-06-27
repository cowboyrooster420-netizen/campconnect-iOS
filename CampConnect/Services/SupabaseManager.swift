import Foundation
import Supabase

/// Single shared Supabase client for the whole app.
final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseAnonKey
        )
    }

    var auth: AuthClient { client.auth }
    var db: PostgrestClient { client.database }
    var storage: SupabaseStorageClient { client.storage }
}
