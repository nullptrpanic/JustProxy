import CoreTelephony
import Foundation
import Network
import Observation
import UIKit

@MainActor
@Observable
final class ProxyModel {
    struct Endpoint: Equatable {
        let listener: ListenerAddress
        let port: UInt16

        var text: String { "\(listener.local.address):\(port)" }
    }

    enum State: Equatable {
        case off
        case starting
        case running(Endpoint)
        case stopping

        var title: String {
            switch self {
            case .off: "代理已关闭"
            case .starting: "正在开启"
            case .running: "代理运行中"
            case .stopping: "正在关闭"
            }
        }

        var endpoint: Endpoint? {
            if case .running(let endpoint) = self { return endpoint }
            return nil
        }

        var isBusy: Bool { self == .starting || self == .stopping }
    }

    private(set) var state: State = .off
    private(set) var traffic = ProxyTraffic()
    private(set) var hasSession = false
    private(set) var failure: String?
    private(set) var networks = ListenerNetworks()
    private(set) var selection: ListenerAddress?

    @ObservationIgnored private let cellularMonitor = NWPathMonitor(requiredInterfaceType: .cellular)
    @ObservationIgnored private let telephony = CTTelephonyNetworkInfo()
    @ObservationIgnored private let backgroundExecution: BackgroundExecution
    @ObservationIgnored private var server: ProxyServer?
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var sessionStarted = false
    @ObservationIgnored private var sessionListener: ListenerAddress?

    init() {
        let application = UIApplication.shared
        backgroundExecution = BackgroundExecution(
            beginTask: { expiration in
                let identifier = application.beginBackgroundTask(
                    withName: "JustProxy", expirationHandler: expiration)
                return identifier == .invalid ? nil : identifier.rawValue
            },
            endTask: { application.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: $0)) }
        )
        cellularMonitor.start(queue: DispatchQueue(label: "JustProxy.cellular"))
    }

    deinit {
        cellularMonitor.cancel()
    }

    func didBecomeActive() {
        refreshNetworks()
        guard state == .starting || state.endpoint != nil else { return }
        server?.validateListener()
        backgroundExecution.renew()
    }

    var isListeningOnCellular: Bool {
        (state == .starting || state.endpoint != nil) && sessionListener?.kind == .cellular
    }

    var selectionWarning: String? {
        guard let selection, networks.resolve(selection) == nil else { return nil }
        return invalidatedMessage(for: selection)
    }

    func select(_ listener: ListenerAddress?) -> Bool {
        guard state == .off else { return false }
        refreshNetworks()
        guard listener == nil || networks.resolve(listener) != nil else { return false }
        selection = listener
        failure = nil
        return true
    }

    func refreshNetworks() {
        let local = LocalIPv4.addresses()
        let cellularInterface = cellularMonitor.currentPath.availableInterfaces.first { $0.type == .cellular }?.name
        let snapshot = ListenerNetworks(
            local: local, wifiInterfaces: LocalIPv4.wifiInterfaces(in: local), cellularInterface: cellularInterface,
            dataServiceID: telephony.dataServiceIdentifier,
            cellularGenerations: (telephony.serviceCurrentRadioAccessTechnology ?? [:]).mapValues(Self.generation)
        )
        if snapshot != networks {
            networks = snapshot
        }
        if isListeningOnCellular, let sessionListener, snapshot.resolve(sessionListener) == nil {
            failure = invalidatedMessage(for: sessionListener)
            stop()
        }
    }

    func watchNetworks() async {
        while !Task.isCancelled {
            refreshNetworks()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func toggle() {
        switch state {
        case .off:
            refreshNetworks()
            guard let listener = networks.resolve(selection) else {
                failure = selectionWarning ?? "暂无可用的监听地址。请检查当前网络。"
                return
            }
            start(listener: listener)
        case .running:
            stop()
        case .starting, .stopping:
            break
        }
    }

    func stop() {
        guard let server, state != .stopping else { return }
        state = .stopping
        server.stop()
    }

    private func start(listener: ListenerAddress) {
        let id = UUID()
        sessionID = id
        sessionStarted = false
        sessionListener = listener
        failure = nil
        state = .starting
        let server = ProxyServer(address: listener.local.address, interface: listener.local.interface, port: 8080) {
            [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.receive(event, session: id, listener: listener)
            }
        }
        self.server = server
        backgroundExecution.begin()
        server.start()
    }

    private func receive(_ event: ProxyServer.Event, session: UUID, listener: ListenerAddress) {
        guard sessionID == session else { return }
        switch event {
        case .ready(let port):
            guard state == .starting else { return }
            traffic = ProxyTraffic()
            sessionStarted = true
            hasSession = true
            state = .running(Endpoint(listener: listener, port: port))
        case .traffic(let snapshot):
            if sessionStarted { traffic = snapshot }
        case .stopped(let snapshot, let failure):
            if sessionStarted { traffic = snapshot }
            backgroundExecution.end()
            server = nil
            sessionID = nil
            sessionStarted = false
            sessionListener = nil
            state = .off
            if let failure, self.failure == nil {
                refreshNetworks()
                self.failure = networks.resolve(listener) == nil ? invalidatedMessage(for: listener) : failure
            }
        }
    }

    private func invalidatedMessage(for listener: ListenerAddress) -> String {
        let address = listener.kind == .cellular ? "原蜂窝地址" : "原监听地址"
        return selection == nil ? "\(address)已失效，请重新开启代理。" : "\(address)已失效，请重新选择。"
    }

    private static func generation(_ technology: String) -> String {
        switch technology {
        case CTRadioAccessTechnologyNR, CTRadioAccessTechnologyNRNSA: "5G"
        case CTRadioAccessTechnologyLTE: "4G"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA,
            CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA,
            CTRadioAccessTechnologyCDMAEVDORevB, CTRadioAccessTechnologyeHRPD:
            "3G"
        case CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyCDMA1x: "2G"
        default: ""
        }
    }
}
