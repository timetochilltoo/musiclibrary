import Foundation

/// Shared bounds for user-triggered metadata and artwork requests.
///
/// URLSession's default timeout can be too long for a disconnected NAS/VPN or
/// captive network. Keeping the policy in the application target makes the Mac
/// UI and metadata provider behave consistently without changing catalogue
/// semantics.
public enum MusicNetworkRequestPolicy {
    public static let defaultTimeout: TimeInterval = 30

    public static func request(url: URL, timeout: TimeInterval = defaultTimeout) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        return request
    }
}
