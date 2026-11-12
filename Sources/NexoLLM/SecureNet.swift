import Foundation

/// Every network request NexoLLM makes goes through here: HTTPS only, TLS 1.2 or newer, no cookies,
/// no disk cache, and redirects only to the hosts a request is allowed to reach.
enum SecureNet {
    /// GitHub, for the update check and release downloads.
    static let githubHosts: Set<String> = ["api.github.com", "github.com", "objects.githubusercontent.com",
                                           "release-assets.githubusercontent.com"]

    /// Hugging Face and its download CDNs, for models.
    static func isHuggingFaceHost(_ host: String) -> Bool {
        host == "huggingface.co" || host.hasSuffix(".huggingface.co") || host == "hf.co" || host.hasSuffix(".hf.co")
    }

    static func isAllowed(_ url: URL?, hosts: Set<String>) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return hosts.contains(host)
    }

    static func configuration(timeout: TimeInterval = 20) -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.tlsMinimumSupportedProtocolVersion = .TLSv12
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = timeout
        return c
    }

    /// A session whose redirects may only lead to HTTPS URLs accepted by `allow`.
    static func session(timeout: TimeInterval = 20, allow: @escaping (URL) -> Bool) -> URLSession {
        URLSession(configuration: configuration(timeout: timeout), delegate: RedirectGuard(allow: allow), delegateQueue: nil)
    }
}

/// Cancels any redirect to a non-HTTPS URL or to a host the request isn't allowed to reach.
final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    private let allow: (URL) -> Bool
    init(allow: @escaping (URL) -> Bool) { self.allow = allow }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme?.lowercased() == "https", allow(url) else {
            Log.info("network: blocked a redirect to \(request.url?.host ?? "?")")
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
