import Foundation
import Network

@main
struct ProxyHarness {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        switch arguments.first {
        case "--listener-addresses":
            printListenerAddresses()
            return
        case "--cellular-selection":
            printCellularSelection()
            return
        default:
            break
        }

        let started = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        let localAddress = IPv4Address.loopback
        let interface =
            arguments.first == "--interface"
            ? arguments.dropFirst().first
            : LocalIPv4.addresses().first { $0.address == localAddress }?.interface
        let port = arguments.first.flatMap(UInt16.init) ?? 0
        let server = ProxyServer(address: localAddress, interface: interface, port: port) { event in
            switch event {
            case .ready(let port):
                write("READY \(port)")
                started.signal()
            case .traffic:
                break
            case .stopped(let traffic, let failure):
                write(
                    "STOPPED \(traffic.uploaded) \(traffic.downloaded) \(traffic.connections.count) \(failure ?? "-")")
                started.signal()
                stopped.signal()
            }
        }
        server.start()
        started.wait()
        while let command = readLine(), command == "check" {
            server.validateListener()
        }
        server.stop()
        stopped.wait()
    }

    private static func write(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private static func printListenerAddresses() {
        let wifi = LocalIPv4(interface: "en5", address: IPv4Address("192.168.42.19")!)
        let hotspot = LocalIPv4(interface: "bridge100", address: IPv4Address("192.0.0.1")!)
        let cellular = LocalIPv4(interface: "pdp_ip0", address: IPv4Address("100.64.10.3")!)
        let vpn = LocalIPv4(interface: "utun3", address: IPv4Address("10.8.0.2")!)
        let unconfiguredWiFi = LocalIPv4(interface: wifi.interface, address: .any)
        let loopback = LocalIPv4(interface: "lo0", address: .loopback)
        let networks = [
            [cellular, wifi], [wifi, hotspot, cellular], [cellular, vpn, unconfiguredWiFi], [vpn, loopback],
        ]
        for local in networks {
            let snapshot = ListenerNetworks(
                local: local, wifiInterfaces: [wifi.interface], cellularInterface: cellular.interface)
            write(snapshot.resolve(nil).map { "\($0.local.address)" } ?? "-")
        }
    }

    private static func printCellularSelection() {
        let wifi = LocalIPv4(interface: "en5", address: IPv4Address("192.168.42.19")!)
        let primary = LocalIPv4(interface: "pdp_ip2", address: IPv4Address("100.64.10.3")!)
        let secondary = LocalIPv4(interface: "pdp_ip0", address: IPv4Address("100.64.20.4")!)
        let local = [secondary, primary, wifi]
        let radios = ["first": "5G", "second": "4G"]
        let initial = ListenerNetworks(
            local: local, wifiInterfaces: [wifi.interface], cellularInterface: primary.interface,
            dataServiceID: "first", cellularGenerations: radios
        )
        let switched = ListenerNetworks(
            local: local, wifiInterfaces: [wifi.interface], cellularInterface: secondary.interface,
            dataServiceID: "second", cellularGenerations: radios
        )
        let reusedAddress = ListenerNetworks(
            local: local, cellularInterface: primary.interface, dataServiceID: "second")
        let noIPv4 = ListenerNetworks(local: local, cellularInterface: "pdp_ip8", dataServiceID: "first")
        let selectedCellular = initial.cellularAddress!
        let selectedWiFi = initial.resolve(nil)!

        write(initial.addresses.map { "\($0.local.address)" }.joined(separator: ","))
        write(initial.standbyServiceIDs.joined(separator: ","))
        write(switched.addresses.map { "\($0.local.address)" }.joined(separator: ","))
        write(switched.standbyServiceIDs.joined(separator: ","))
        write(switched.resolve(selectedCellular).map { "\($0.local.address)" } ?? "-")
        write(switched.resolve(selectedWiFi).map { "\($0.local.address)" } ?? "-")
        write(reusedAddress.resolve(selectedCellular).map { "\($0.local.address)" } ?? "-")
        write(noIPv4.resolve(nil).map { "\($0.local.address)" } ?? "-")
    }
}
