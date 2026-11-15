import Foundation
import Network

enum ConnectionGuide {
    private static let template: String? = {
        guard let url = Bundle.main.url(forResource: "ConnectionGuide", withExtension: "html") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    static func response(to request: HTTPProxyRequest, address: NWEndpoint.Host, port: UInt16) -> Data {
        let status: String
        let content: String
        let type: String
        var extraHeaders = ""

        if request.method != "GET" && request.method != "HEAD" {
            status = "405 Method Not Allowed"
            content = "Use GET or HEAD to open the JustProxy connection guide.\n"
            type = "text/plain; charset=utf-8"
            extraHeaders = "Allow: GET, HEAD\r\n"
        } else if request.path?.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first != "/" {
            status = "404 Not Found"
            content = "Open / for the JustProxy connection guide.\n"
            type = "text/plain; charset=utf-8"
        } else if let template {
            status = "200 OK"
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            content = template
                .replacingOccurrences(of: "{{ENDPOINT}}", with: "\(address.httpAuthorityHost):\(port)")
                .replacingOccurrences(of: "{{HOST}}", with: String(describing: address))
                .replacingOccurrences(of: "{{PORT}}", with: String(port))
                .replacingOccurrences(of: "{{VERSION}}", with: version)
            type = "text/html; charset=utf-8"
        } else {
            status = "500 Internal Server Error"
            content = "The JustProxy connection guide is unavailable.\n"
            type = "text/plain; charset=utf-8"
        }

        let body = Data(content.utf8)
        let policy = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
        let head = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
            + "Connection: close\r\nCache-Control: no-store\r\n"
            + "X-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n"
            + "Content-Security-Policy: \(policy)\r\n\(extraHeaders)\r\n"
        var message = Data(head.utf8)
        if request.method != "HEAD" { message.append(body) }
        return message
    }
}
