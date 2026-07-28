import Foundation
import PixelDoneSyncContract

enum AppConfiguration {
    static var supabase: SupabaseConfiguration? {
        let rawURL = Bundle.main.object(
            forInfoDictionaryKey: "PixelDoneSupabaseURL"
        ) as? String ?? ""
        let rawKey = Bundle.main.object(
            forInfoDictionaryKey: "PixelDoneSupabasePublishableKey"
        ) as? String ?? ""
        return SupabaseConfiguration(
            baseURLString: rawURL.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            publishableKey: rawKey.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )
    }
}
