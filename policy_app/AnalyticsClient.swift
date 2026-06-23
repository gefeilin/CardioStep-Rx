import Foundation

final class AnalyticsClient {
    static let shared = AnalyticsClient()

    private let projectToken = "phc_BAP6Za8fxuvrqTpVSgQTnuQwknAo3mZRYujs7c4F7Xxn"
    private let host = URL(string: "https://us.i.posthog.com")!
    private let distinctIDKey = "CardioStepRxAnalyticsDistinctID"
    private let sessionID = UUID().uuidString
    private let urlSession: URLSession

    private init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func track(_ eventName: String, properties: [String: String] = [:]) {
        guard !projectToken.isEmpty else { return }

        var eventProperties: [String: Any] = [
            "$process_person_profile": false,
            "app_name": "CardioStepRx",
            "app_version": appVersion,
            "platform": "ios",
            "session_id": sessionID
        ]
        properties.forEach { key, value in
            eventProperties[key] = value
        }

        let payload: [String: Any] = [
            "api_key": projectToken,
            "event": eventName,
            "distinct_id": distinctID,
            "properties": eventProperties
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        var request = URLRequest(url: URL(string: "/i/v0/e/", relativeTo: host)!.absoluteURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        urlSession.dataTask(with: request).resume()
    }

    private var distinctID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: distinctIDKey) {
            return existing
        }
        let generated = "ios-\(UUID().uuidString.lowercased())"
        defaults.set(generated, forKey: distinctIDKey)
        return generated
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version)-\(build)"
    }
}
