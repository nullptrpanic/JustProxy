import Foundation
import Network

// The server's serial queue owns both connections and all per-client state.
final class ProxyConnection {
    enum Direction {
        case upload
        case download
    }

    private enum Rejection: String {
        case badRequest = "400 Bad Request"
        case headerTooLarge = "431 Request Header Fields Too Large"
        case unsupported = "501 Not Implemented"
        case badGateway = "502 Bad Gateway"
    }

    private let client: NWConnection
    private let queue: DispatchQueue
    private let listenAddress: IPv4Address
    private let listenPort: UInt16
    private let connected: (HTTPProxyRequest) -> Void
    private let transferred: (Direction, Int) -> Void
    private let completed: () -> Void
    private var upstream: NWConnection?
    private var buffer = Data()
    private var requestBody: HTTPBody?
    private var response: HTTPResponseStream?
    private var responseStarted = false
    private var upstreamReady = false
    private var uploadEnded = false
    private var downloadEnded = false
    private var pendingClientWrites = 0
    private var closing = false
    private var finished = false
    private var lastActivity = DispatchTime.now()

    init(
        client: NWConnection,
        queue: DispatchQueue,
        listenAddress: IPv4Address,
        listenPort: UInt16,
        connected: @escaping (HTTPProxyRequest) -> Void,
        transferred: @escaping (Direction, Int) -> Void,
        completed: @escaping () -> Void
    ) {
        self.client = client
        self.queue = queue
        self.listenAddress = listenAddress
        self.listenPort = listenPort
        self.connected = connected
        self.transferred = transferred
        self.completed = completed
    }

    func start() {
        client.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.readHeader()
            case .failed, .cancelled:
                self.finish()
            default:
                break
            }
        }
        client.start(queue: queue)
    }

    func finish() {
        guard !finished else { return }
        finished = true
        client.cancel()
        upstream?.cancel()
        completed()
    }

    func expireIfIdle(at now: DispatchTime) {
        let seconds: UInt64 = upstreamReady ? 180 : 20
        if now.uptimeNanoseconds - lastActivity.uptimeNanoseconds >= seconds * 1_000_000_000 {
            finish()
        }
    }

    private func readHeader() {
        read(from: client) { [weak self] data, eof in
            guard let self else { return }
            self.buffer.append(data)
            do {
                if let head = try HTTPMessageHead.read(from: &self.buffer) {
                    let request = try HTTPProxyRequest(head, localEndpoint: (self.listenAddress, self.listenPort))
                    try self.connect(request, eof: eof)
                } else if eof {
                    if self.buffer.isEmpty { self.finish() } else { self.reject(.badRequest) }
                } else {
                    self.readHeader()
                }
            } catch HTTPMessageError.headerTooLarge {
                self.reject(.headerTooLarge)
            } catch HTTPMessageError.unsupported {
                self.reject(.unsupported)
            } catch {
                self.reject(.badRequest)
            }
        }
    }

    private func connect(_ request: HTTPProxyRequest, eof: Bool) throws {
        if IPv4Address(request.host) == listenAddress, request.port == listenPort {
            guard request.path != nil else { throw HTTPMessageError.malformed }
            if request.method == "GET" || request.method == "HEAD" {
                guard request.framing == .none || request.framing == .fixed(0) else {
                    throw HTTPMessageError.malformed
                }
            }
            buffer.removeAll()
            closing = true
            let reply = ConnectionGuide.response(to: request, address: listenAddress, port: listenPort)
            write(reply, to: client, final: true) { [weak self] in self?.finish() }
            return
        }
        guard let port = NWEndpoint.Port(rawValue: request.port) else { throw HTTPMessageError.malformed }

        let initialData = buffer
        buffer.removeAll()
        let destination = NWConnection(host: NWEndpoint.Host(request.host), port: port, using: .tcp)
        upstream = destination
        destination.stateUpdateHandler = { [weak self, weak destination] state in
            guard let self, let destination, !self.finished, !self.closing else { return }
            switch state {
            case .ready where !self.upstreamReady:
                self.upstreamReady = true
                self.lastActivity = .now()
                self.connected(request)
                if let head = request.forwardHead {
                    self.startHTTP(request, head: head, initialData: initialData, eof: eof, upstream: destination)
                } else {
                    self.startTunnel(initialData, eof: eof, upstream: destination)
                }
            case .waiting, .failed:
                self.upstreamFailed()
            default:
                break
            }
        }
        destination.start(queue: queue)
    }

    private func startTunnel(_ initialData: Data, eof: Bool, upstream: NWConnection) {
        responseStarted = true
        write(Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), to: client) { [weak self] in
            guard let self else { return }
            self.readTunnel(from: upstream, to: self.client, direction: .download)
            self.forwardTunnel(initialData, eof: eof, from: self.client, to: upstream, direction: .upload)
        }
    }

    private func readTunnel(from source: NWConnection, to destination: NWConnection, direction: Direction) {
        read(from: source) { [weak self] data, eof in
            self?.forwardTunnel(data, eof: eof, from: source, to: destination, direction: direction)
        }
    }

    private func forwardTunnel(
        _ data: Data, eof: Bool, from source: NWConnection, to destination: NWConnection, direction: Direction
    ) {
        write(data, to: destination, direction: direction, final: eof) { [weak self] in
            guard let self else { return }
            if eof {
                switch direction {
                case .upload: self.uploadEnded = true
                case .download: self.downloadEnded = true
                }
                if self.uploadEnded, self.downloadEnded { self.finish() }
            } else {
                self.readTunnel(from: source, to: destination, direction: direction)
            }
        }
    }

    private func startHTTP(
        _ request: HTTPProxyRequest, head: Data, initialData: Data, eof: Bool, upstream: NWConnection
    ) {
        requestBody = HTTPBody(request.framing)
        response = HTTPResponseStream(requestMethod: request.method)
        do {
            var message = head
            message.append(try requestBody!.consume(initialData, eof: eof))
            write(message, to: upstream, direction: .upload) { [weak self] in
                self?.readResponse(from: upstream)
                self?.readRequestBody(to: upstream)
            }
        } catch {
            reject(.badRequest)
        }
    }

    private func readRequestBody(to upstream: NWConnection) {
        guard requestBody?.finished == false else { return }
        read(from: client) { [weak self] data, eof in
            guard let self else { return }
            do {
                let body = try self.requestBody!.consume(data, eof: eof)
                self.write(body, to: upstream, direction: .upload) { [weak self] in
                    self?.readRequestBody(to: upstream)
                }
            } catch {
                if self.responseStarted { self.finish() } else { self.reject(.badRequest) }
            }
        }
    }

    private func readResponse(from upstream: NWConnection) {
        read(from: upstream) { [weak self] data, eof in
            guard let self else { return }
            do {
                let output = try self.response!.consume(data, eof: eof)
                let final = self.response!.finished
                if !output.isEmpty { self.responseStarted = true }
                self.write(output, to: self.client, direction: .download, final: final) { [weak self] in
                    if final { self?.finish() } else { self?.readResponse(from: upstream) }
                }
            } catch {
                self.upstreamFailed()
            }
        }
    }

    private func read(from connection: NWConnection, completion: @escaping (Data, Bool) -> Void) {
        guard !finished, !closing else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, eof, error in
            guard let self, !self.finished, !self.closing else { return }
            if error != nil {
                if connection === self.client { self.finish() } else { self.upstreamFailed() }
                return
            }
            if data?.isEmpty == false { self.lastActivity = .now() }
            completion(data ?? Data(), eof)
        }
    }

    private func write(
        _ data: Data,
        to connection: NWConnection,
        direction: Direction? = nil,
        final: Bool = false,
        completion: @escaping () -> Void
    ) {
        guard !finished else { return }
        if data.isEmpty, !final {
            completion()
            return
        }
        if connection === client { pendingClientWrites += 1 }
        connection.send(
            content: data.isEmpty ? nil : data,
            contentContext: final ? .finalMessage : .defaultMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                guard let self, !self.finished else { return }
                if connection === self.client { self.pendingClientWrites -= 1 }
                if error != nil {
                    if connection === self.client { self.finish() } else { self.upstreamFailed() }
                    return
                }
                if !data.isEmpty, let direction {
                    self.lastActivity = .now()
                    self.transferred(direction, data.count)
                }
                if self.closing {
                    if self.pendingClientWrites == 0 { self.finish() }
                    return
                }
                completion()
            }
        )
    }

    private func upstreamFailed() {
        guard !closing else { return }
        if responseStarted {
            closing = true
            upstream?.cancel()
            // Preserve response bytes already queued for the client, including their traffic counts.
            if pendingClientWrites == 0 { finish() }
        } else {
            reject(.badGateway)
        }
    }

    private func reject(_ status: Rejection) {
        guard !finished, !closing else { return }
        closing = true
        upstream?.cancel()
        let message = "HTTP/1.1 \(status.rawValue)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        write(Data(message.utf8), to: client, final: true) { [weak self] in
            self?.finish()
        }
    }
}
