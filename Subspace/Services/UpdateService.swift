import Foundation
import SubspaceCore

/// The newest published release on GitHub.
struct ReleaseInfo: Sendable, Equatable {
    let version: String
    let url: URL
}

/// Manual update check against the project's public GitHub releases. Runs only when the user taps
/// "Check for updates"; the request carries no information about the user or their subscriptions.
enum UpdateService {
    static let repository = URL(string: "https://github.com/TrapNouz/Subvelle")!
    static let releases = URL(string: "https://github.com/TrapNouz/Subvelle/releases")!
    private static let latestRelease = URL(string: "https://api.github.com/repos/TrapNouz/Subvelle/releases/latest")!

    static var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static func latest() async throws -> ReleaseInfo {
        var request = URLRequest(url: latestRelease)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
            throw DataError.invalid("GitHub didn’t answer the update check. Try again later.")
        }
        struct Payload: Decodable {
            let tagName: String
            let htmlURL: URL
            enum CodingKeys: String, CodingKey { case tagName = "tag_name", htmlURL = "html_url" }
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return ReleaseInfo(version: AppVersion.normalized(payload.tagName), url: payload.htmlURL)
    }
}
