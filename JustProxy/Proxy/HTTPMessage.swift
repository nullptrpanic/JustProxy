import Foundation
import Network

enum HTTPMessageError: Error {
    case malformed
    case headerTooLarge
    case unsupported
}

private let lineEnd = Data([13, 10])
private let headEnd = Data([13, 10, 13, 10])
private let optionalWhitespace = CharacterSet(charactersIn: " \t")

struct HTTPMessageHead {
    static let limit = 32 * 1024
    private static let hopFields: Set<String> = [
        "connection", "keep-alive", "proxy-connection", "proxy-authorization",
        "proxy-authenticate", "te", "upgrade",
    ]

    struct Field {
        let name: String
        let value: String
        let line: Data

        init(_ line: Data) throws {
            guard let colon = line.firstIndex(of: 58), colon != line.startIndex,
                line[..<colon].allSatisfy(isToken),
                line[line.index(after: colon)...].allSatisfy({ $0 == 9 || ($0 >= 32 && $0 != 127) })
            else { throw HTTPMessageError.malformed }
            name = String(decoding: line[..<colon], as: UTF8.self).lowercased()
            value = String(decoding: line[line.index(after: colon)...], as: UTF8.self)
                .trimmingCharacters(in: optionalWhitespace)
            self.line = line
        }
    }

    let start: String
    let fields: [Field]

    static func read(from buffer: inout Data) throws -> Self? {
        guard let end = buffer.range(of: headEnd) else {
            if buffer.count >= limit { throw HTTPMessageError.headerTooLarge }
            return nil
        }
        guard buffer.distance(from: buffer.startIndex, to: end.upperBound) <= limit else {
            throw HTTPMessageError.headerTooLarge
        }

        let lines = buffer[..<end.lowerBound].split(separator: 10, omittingEmptySubsequences: false)
        let content = try lines.enumerated().map { index, line in
            if index == lines.count - 1 { return line }
            guard line.last == 13 else { throw HTTPMessageError.malformed }
            return line.dropLast()
        }
        guard let first = content.first, !first.isEmpty,
            first.allSatisfy({ (32...126).contains($0) })
        else { throw HTTPMessageError.malformed }

        let head = Self(start: String(decoding: first, as: UTF8.self), fields: try content.dropFirst().map(Field.init))
        buffer.removeSubrange(..<end.upperBound)
        return head
    }

    func values(for name: String) -> [String] {
        fields.filter { $0.name == name }.map(\.value)
    }

    func framing(defaultBody: HTTPBody.Framing) throws -> HTTPBody.Framing {
        let lengths = values(for: "content-length").flatMap(Self.list)
        let encodings = values(for: "transfer-encoding").flatMap(Self.list).map { $0.lowercased() }
        let options = connectionOptions
        guard !options.contains("content-length"), !options.contains("transfer-encoding") else {
            throw HTTPMessageError.malformed
        }
        if !encodings.isEmpty {
            guard lengths.isEmpty else { throw HTTPMessageError.malformed }
            guard encodings == ["chunked"] else { throw HTTPMessageError.unsupported }
            return .chunked
        }
        guard let first = lengths.first else { return defaultBody }
        guard let length = decimal(first), lengths.allSatisfy({ decimal($0) == length }) else {
            throw HTTPMessageError.malformed
        }
        return .fixed(length)
    }

    func forwarded(
        start: String,
        host: String? = nil,
        framing: HTTPBody.Framing,
        close: Bool
    ) -> Data {
        let options = connectionOptions
        var data = Data(start.utf8)
        data.append(lineEnd)
        if let host {
            data.append(Data("Host: \(host)\r\n".utf8))
        }
        for field in fields where !Self.hopFields.contains(field.name) && !options.contains(field.name) {
            switch field.name {
            case "host" where host != nil, "content-length", "transfer-encoding":
                continue
            case "trailer" where framing != .chunked:
                continue
            default:
                data.append(field.line)
                data.append(lineEnd)
            }
        }
        switch framing {
        case .fixed(let length):
            data.append(Data("Content-Length: \(length)\r\n".utf8))
        case .chunked:
            data.append(Data("Transfer-Encoding: chunked\r\n".utf8))
        case .none, .untilEOF:
            break
        }
        if close { data.append(Data("Connection: close\r\n".utf8)) }
        data.append(lineEnd)
        return data
    }

    private var connectionOptions: Set<String> {
        Set((values(for: "connection") + values(for: "proxy-connection")).flatMap(Self.list).map { $0.lowercased() })
    }

    private static func list(_ value: String) -> [String] {
        value.components(separatedBy: ",").map { $0.trimmingCharacters(in: optionalWhitespace) }
    }
}

struct HTTPProxyRequest {
    let method: String
    let host: String
    let port: UInt16
    let path: String?
    let forwardHead: Data?
    let framing: HTTPBody.Framing

    init(_ head: HTTPMessageHead, localEndpoint: (address: IPv4Address, port: UInt16)? = nil) throws {
        let parts = head.start.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, parts[0].utf8.allSatisfy(isToken),
            parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0"
        else { throw HTTPMessageError.malformed }
        method = String(parts[0])
        let target = String(parts[1])
        let hosts = head.values(for: "host")
        guard hosts.count <= 1, parts[2] != "HTTP/1.1" || hosts.first?.isEmpty == false else {
            throw HTTPMessageError.malformed
        }

        framing = try head.framing(defaultBody: .none)
        if method == "CONNECT" {
            guard framing == .none || framing == .fixed(0) else { throw HTTPMessageError.malformed }
            (host, port) = try Self.destination(target, defaultPort: nil)
            path = nil
            forwardHead = nil
            return
        }

        guard head.values(for: "upgrade").isEmpty, parts[2] != "HTTP/1.0" || framing != .chunked else {
            throw HTTPMessageError.unsupported
        }
        let authority: String
        let requestPath: String
        let originForm = target.hasPrefix("/")
        if method == "OPTIONS", target == "*", let hostField = hosts.first {
            authority = hostField
            requestPath = "*"
        } else if originForm, let localEndpoint {
            guard !target.contains("#"), !target.contains("\\") else { throw HTTPMessageError.malformed }
            authority = hosts.first ?? "\(localEndpoint.address):\(localEndpoint.port)"
            requestPath = target
        } else {
            guard target.prefix(7).lowercased() == "http://", !target.contains("#"), !target.contains("\\")
            else { throw HTTPMessageError.malformed }
            let absolute = target.dropFirst(7)
            authority = String(absolute.prefix { $0 != "/" && $0 != "?" })
            let suffix = absolute.dropFirst(authority.count)
            if method == "OPTIONS", suffix.isEmpty {
                requestPath = "*"
            } else {
                requestPath = suffix.first == "/" ? String(suffix) : "/" + suffix
            }
        }
        (host, port) = try Self.destination(authority, defaultPort: 80)
        if originForm {
            guard let localEndpoint, IPv4Address(host) == localEndpoint.address, port == localEndpoint.port else {
                throw HTTPMessageError.malformed
            }
        }
        path = requestPath
        forwardHead = head.forwarded(
            start: "\(method) \(requestPath) \(parts[2])", host: authority, framing: framing, close: true)
    }

    private static func destination(_ authority: String, defaultPort: UInt16?) throws -> (String, UInt16) {
        let host: Substring
        let portText: Substring?
        if authority.first == "[", let close = authority.firstIndex(of: "]") {
            host = authority[authority.index(after: authority.startIndex)..<close]
            guard IPv6Address(String(host)) != nil else { throw HTTPMessageError.malformed }
            let suffix = authority[authority.index(after: close)...]
            guard suffix.isEmpty || suffix.first == ":" else { throw HTTPMessageError.malformed }
            portText = suffix.isEmpty ? nil : suffix.dropFirst()
        } else {
            let fields = authority.split(separator: ":", omittingEmptySubsequences: false)
            guard let first = fields.first, fields.count <= 2, !first.isEmpty,
                first.utf8.allSatisfy({ isAlphanumeric($0) || $0 == 45 || $0 == 46 || $0 == 95 })
            else { throw HTTPMessageError.malformed }
            host = first
            portText = fields.count == 2 ? fields[1] : nil
        }
        if let portText {
            guard let port = decimal(portText), let number = UInt16(exactly: port), number != 0
            else { throw HTTPMessageError.malformed }
            return (String(host), number)
        }
        guard let defaultPort else { throw HTTPMessageError.malformed }
        return (String(host), defaultPort)
    }
}

struct HTTPBody {
    enum Framing: Equatable {
        case none
        case fixed(UInt64)
        case chunked
        case untilEOF
    }

    private enum State {
        case finished
        case fixed(UInt64)
        case chunkSize
        case chunkData(UInt64)
        case chunkEnd
        case trailers
        case untilEOF
    }

    private var state: State
    private var pending = Data()
    private var trailerBytes = 0

    var finished: Bool {
        if case .finished = state { return true }
        return false
    }

    init(_ framing: Framing) {
        switch framing {
        case .none, .fixed(0): state = .finished
        case .fixed(let length): state = .fixed(length)
        case .chunked: state = .chunkSize
        case .untilEOF: state = .untilEOF
        }
    }

    mutating func consume(_ input: Data, eof: Bool) throws -> Data {
        if finished { return Data() }
        if case .untilEOF = state {
            if eof { state = .finished }
            return input
        }

        pending.append(input)
        var output = Data()
        parse: while !pending.isEmpty {
            switch state {
            case .finished:
                pending.removeAll()
            case .fixed(let remaining), .chunkData(let remaining):
                let count = Int(min(remaining, UInt64(pending.count)))
                output.append(pending.prefix(count))
                pending.removeFirst(count)
                let left = remaining - UInt64(count)
                if case .fixed = state {
                    state = left == 0 ? .finished : .fixed(left)
                } else {
                    state = left == 0 ? .chunkEnd : .chunkData(left)
                }
            case .chunkSize:
                guard let line = try takeLine() else { break parse }
                let size = String(decoding: line.prefix { $0 != 59 }, as: UTF8.self)
                    .trimmingCharacters(in: optionalWhitespace)
                guard !size.isEmpty, size.utf8.allSatisfy(isHex), let count = UInt64(size, radix: 16),
                    line.allSatisfy({ $0 == 9 || ($0 >= 32 && $0 != 127) })
                else { throw HTTPMessageError.malformed }
                output.append(line)
                output.append(lineEnd)
                state = count == 0 ? .trailers : .chunkData(count)
            case .chunkEnd:
                guard pending.count >= lineEnd.count else { break parse }
                guard pending.starts(with: lineEnd) else { throw HTTPMessageError.malformed }
                output.append(lineEnd)
                pending.removeFirst(lineEnd.count)
                state = .chunkSize
            case .trailers:
                guard let line = try takeLine() else { break parse }
                trailerBytes += line.count + lineEnd.count
                guard trailerBytes <= HTTPMessageHead.limit else { throw HTTPMessageError.headerTooLarge }
                if line.isEmpty {
                    state = .finished
                } else {
                    let field = try HTTPMessageHead.Field(line)
                    guard
                        ![
                            "content-length", "transfer-encoding", "host", "connection",
                            "proxy-authorization", "proxy-authenticate",
                        ].contains(field.name)
                    else { throw HTTPMessageError.malformed }
                    output.append(line)
                }
                output.append(lineEnd)
            case .untilEOF:
                break parse
            }
        }
        if eof, !finished { throw HTTPMessageError.malformed }
        return output
    }

    private mutating func takeLine() throws -> Data? {
        let limit = 8 * 1024
        guard let range = pending.range(of: lineEnd) else {
            if pending.count > limit { throw HTTPMessageError.headerTooLarge }
            return nil
        }
        let line = pending[..<range.lowerBound]
        guard line.count <= limit else { throw HTTPMessageError.headerTooLarge }
        pending.removeSubrange(..<range.upperBound)
        return line
    }
}

struct HTTPResponseStream {
    let requestMethod: String
    private var pending = Data()
    private var body: HTTPBody?

    init(requestMethod: String) {
        self.requestMethod = requestMethod
    }

    var finished: Bool { body?.finished == true }

    mutating func consume(_ input: Data, eof: Bool) throws -> Data {
        if body != nil {
            return try body!.consume(input, eof: eof)
        }
        pending.append(input)
        var output = Data()
        while let head = try HTTPMessageHead.read(from: &pending) {
            let parts = head.start.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2, parts[0] == "HTTP/1.1" || parts[0] == "HTTP/1.0",
                parts[1].count == 3, let status = decimal(parts[1]), (100...599).contains(status)
            else { throw HTTPMessageError.malformed }
            if status == 101 { throw HTTPMessageError.unsupported }
            if status < 200 {
                output.append(head.forwarded(start: head.start, framing: .none, close: false))
                continue
            }

            let framing = try head.framing(defaultBody: .untilEOF)
            let hasBody = requestMethod != "HEAD" && status != 204 && status != 304
            let headFraming: HTTPBody.Framing
            if hasBody {
                headFraming = framing
            } else if case .fixed = framing, status != 204 {
                headFraming = framing
            } else {
                headFraming = .none
            }
            output.append(head.forwarded(start: head.start, framing: headFraming, close: true))
            var responseBody = HTTPBody(hasBody ? framing : .none)
            output.append(try responseBody.consume(pending, eof: eof))
            pending.removeAll()
            body = responseBody
            return output
        }
        if eof { throw HTTPMessageError.malformed }
        return output
    }
}

private func decimal<S: StringProtocol>(_ value: S) -> UInt64? {
    guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
    return UInt64(value)
}

private func isAlphanumeric(_ byte: UInt8) -> Bool {
    (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
}

private func isHex(_ byte: UInt8) -> Bool {
    (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
}

private func isToken(_ byte: UInt8) -> Bool {
    isAlphanumeric(byte) || "!#$%&'*+-.^_`|~".utf8.contains(byte)
}
