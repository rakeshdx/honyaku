import Foundation

/// In DEBUG builds, asserts that every outbound URLSession request is a
/// user-initiated model download. In RELEASE builds this delegate is a no-op
/// (the entitlement scope provides the enforcement layer).
final class NetworkAuditDelegate: NSObject, URLSessionTaskDelegate {
    static let shared = NetworkAuditDelegate()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        audit(request: request)
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // No-op
    }

    func audit(request: URLRequest) {
        #if DEBUG
        let isModelDownload = request.value(forHTTPHeaderField: "X-Honyaku-Model-Download") == "true"
        let host = request.url?.host ?? ""
        let allowedHosts = ["huggingface.co", "cdn-lfs.huggingface.co", "cdn-lfs-us-1.huggingface.co"]
        let isAllowedHost = allowedHosts.contains(where: { host.hasSuffix($0) })

        if !isModelDownload || !isAllowedHost {
            assertionFailure("""
            [NetworkAudit] Unexpected outbound request detected!
            URL: \(request.url?.absoluteString ?? "nil")
            This violates the privacy spec: no network calls outside model downloads.
            """)
        }
        #endif
    }
}
