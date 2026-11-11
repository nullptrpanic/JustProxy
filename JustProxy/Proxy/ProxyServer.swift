import Foundation
import Network

struct ProxyTraffic: Equatable, Sendable {
    struct Connection: Identifiable, Equatable, Sendable {
        let id: UUID
        let method: String
        let host: String
        let port: UInt16
        var bytes: Int64 = 0
    }

    var uploaded: Int64 = 0
    var downloaded: Int64 = 0
    var connections: [Connection] = []
}

// Only start() and stop() cross into this object from another queue.
final class ProxyServer: @unchecked Sendable {
    enum Event: Sendable {
        case ready(UInt16)
        case traffic(ProxyTraffic)
        case stopped(ProxyTraffic, failure: String?)
    }

    private let address: IPv4Address
    private let interface: String?
    private let port: UInt16
    private let report: @Sendable (Event) -> Void
    private let queue = DispatchQueue(label: "JustProxy.listener", qos: .userInitiated)
    private var listener: NWListener?
    private var timer: DispatchSourceTimer?
    private var peers: [UUID: ProxyConnection] = [:]
    private var traffic = ProxyTraffic()
    private var trafficChanged = false
    private var stopped = false

    init(address: IPv4Address, interface: String? = nil, port: UInt16, report: @escaping @Sendable (Event) -> Void) {
        self.address = address
        self.interface = interface
        self.port = port
        self.report = report
    }

    func start() {
        queue.async { self.listen() }
    }

    func stop() {
        queue.async { self.finish(failure: nil) }
    }

    func validateListener() {
        queue.async {
            guard !self.stopped, let listener = self.listener else { return }
            guard self.addressIsAssigned else {
                self.finish(failure: "当前网络地址已失效。")
                return
            }
            switch listener.state {
            case .ready:
                if let port = listener.port { self.report(.ready(port.rawValue)) }
            case .setup:
                break
            default:
                self.finish(failure: "代理监听已停止，请重新开启。")
            }
        }
    }

    private func listen() {
        guard !stopped, listener == nil, let port = NWEndpoint.Port(rawValue: port) else { return }
        let listenAddress: IPv4Address
        if let interface {
            guard addressIsAssigned, let scopedAddress = IPv4Address("\(address)%\(interface)") else {
                finish(failure: "当前监听地址已失效。")
                return
            }
            listenAddress = scopedAddress
        } else {
            listenAddress = address
        }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterface = listenAddress.interface
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(listenAddress), port: port)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] client in
                guard let self else {
                    client.cancel()
                    return
                }
                self.accept(client)
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener, !self.stopped else { return }
                switch state {
                case .ready:
                    guard let port = listener.port else {
                        self.finish(failure: "无法取得代理端口。")
                        return
                    }
                    self.report(.ready(port.rawValue))
                    self.startTimer()
                case .failed(let error), .waiting(let error):
                    self.finish(failure: "代理监听失败（\(error.localizedDescription)）")
                default:
                    break
                }
            }
            listener.start(queue: queue)
        } catch {
            finish(failure: "代理监听失败（\(error.localizedDescription)）")
        }
    }

    private func accept(_ client: NWConnection) {
        guard !stopped, peers.count < 128, let port = listener?.port?.rawValue else {
            client.cancel()
            return
        }
        let id = UUID()
        let peer = ProxyConnection(
            client: client, queue: queue, listenAddress: address, listenPort: port,
            connected: { [weak self] request in
                self?.record(id: id, request: request)
            },
            transferred: { [weak self] direction, count in
                self?.record(id: id, direction: direction, count: count)
            },
            completed: { [weak self] in
                self?.peers.removeValue(forKey: id)
            }
        )
        peers[id] = peer
        peer.start()
    }

    private func record(id: UUID, request: HTTPProxyRequest) {
        traffic.connections.insert(.init(id: id, method: request.method, host: request.host, port: request.port), at: 0)
        if traffic.connections.count > 50 { traffic.connections.removeLast() }
        trafficChanged = true
    }

    private func record(id: UUID, direction: ProxyConnection.Direction, count: Int) {
        let bytes = Int64(count)
        switch direction {
        case .upload: traffic.uploaded += bytes
        case .download: traffic.downloaded += bytes
        }
        if let index = traffic.connections.firstIndex(where: { $0.id == id }) {
            traffic.connections[index].bytes += bytes
        }
        trafficChanged = true
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        guard !stopped else { return }
        guard addressIsAssigned else {
            finish(failure: "当前网络地址已失效，请重新开启代理。")
            return
        }
        let now = DispatchTime.now()
        for peer in Array(peers.values) { peer.expireIfIdle(at: now) }
        if trafficChanged {
            trafficChanged = false
            report(.traffic(traffic))
        }
    }

    private var addressIsAssigned: Bool {
        LocalIPv4.addresses().contains { $0.address == address && (interface == nil || $0.interface == interface) }
    }

    private func finish(failure: String?) {
        guard !stopped else { return }
        stopped = true
        timer?.cancel()
        timer = nil
        listener?.cancel()
        listener = nil
        for peer in Array(peers.values) { peer.finish() }
        report(.stopped(traffic, failure: failure))
    }
}
