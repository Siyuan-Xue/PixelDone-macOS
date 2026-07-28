import Foundation

struct SupabaseConfiguration: Sendable {
    let baseURL: URL
    let publishableKey: String

    var realtimeURL: URL? {
        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/realtime/v1/websocket"
        return components.url
    }
}

enum AppConfiguration {
    static var current: SupabaseConfiguration? {
        guard
            let rawURL = Bundle.main.object(
                forInfoDictionaryKey: "PixelDoneSupabaseURL"
            ) as? String,
            let rawKey = Bundle.main.object(
                forInfoDictionaryKey: "PixelDoneSupabasePublishableKey"
            ) as? String
        else {
            return nil
        }

        let urlText = rawURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlText.isEmpty, !key.isEmpty, let url = URL(string: urlText) else {
            return nil
        }
        return SupabaseConfiguration(baseURL: url, publishableKey: key)
    }
}
