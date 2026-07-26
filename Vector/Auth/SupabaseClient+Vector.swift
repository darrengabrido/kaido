import Foundation
import Supabase

/// Nil until `SUPABASE_HOST`/`SUPABASE_ANON_KEY` are set in `Config/Secrets.xcconfig`.
/// The app stays fully usable without them — guest mode works, sign-in surfaces an error.
///
/// The host is stored without a scheme on purpose: xcconfig treats `//` as a comment
/// marker, so a full `https://…` URL silently truncates to `https:`.
enum VectorSupabaseClient {
    static let shared: SupabaseClient? = {
        guard let host = Bundle.main.object(forInfoDictionaryKey: "SupabaseHost") as? String,
              let anonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
              !host.isEmpty, !anonKey.isEmpty,
              let url = URL(string: "https://\(host)") else {
            return nil
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }()
}
