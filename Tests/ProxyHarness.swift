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
        case "--ipv6-selection":
            printIPv6Selection()
            return
        default:
            break
        }

        let started = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        let loopback = arguments.first == "--ipv6" ? "::1" : "127.0.0.1"
        guard let localAddress = LocalAddress.addresses().first(where: { "\($0.address)" == loopback })?.address else {
            write("UNAVAILABLE \(loopback)")
            return
        }
        let interface =
            arguments.first == "--interface"
            ? arguments.dropFirst().first
            : LocalAddress.addresses().first { $0.address == localAddress }?.interface
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
        let wifi = LocalAddress(interface: "en5", address: NWEndpoint.Host("192.168.42.19"))
        let hotspot = LocalAddress(interface: "bridge100", address: NWEndpoint.Host("192.0.0.1"))
        let cellular = LocalAddress(interface: "pdp_ip0", address: NWEndpoint.Host("100.64.10.3"))
        let vpn = LocalAddress(interface: "utun3", address: NWEndpoint.Host("10.8.0.2"))
        let unconfiguredWiFi = LocalAddress(interface: wifi.interface, address: .ipv4(.any))
        let loopback = LocalAddress(interface: "lo0", address: .ipv4(.loopback))
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
        let wifi = LocalAddress(interface: "en5", address: NWEndpoint.Host("192.168.42.19"))
        let primary = LocalAddress(interface: "pdp_ip2", address: NWEndpoint.Host("100.64.10.3"))
        let secondary = LocalAddress(interface: "pdp_ip0", address: NWEndpoint.Host("100.64.20.4"))
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

    private static func printIPv6Selection() {
        let wifi = LocalAddress(interface: "en5", address: "2001:db8:1::2")
        let ipv4 = LocalAddress(interface: "en5", address: "192.168.42.19")
        let ipv4LinkLocal = LocalAddress(interface: "en5", address: "169.254.10.2")
        let cellular = LocalAddress(interface: "pdp_ip0", address: "2001:db8:2::2")
        let hotspot = LocalAddress(interface: "bridge100", address: "fd00:1::1")
        let vpn = LocalAddress(interface: "utun3", address: "2001:db8:3::2")
        let unusable = ["::", "::1", "fe80::1", "ff02::1", "::ffff:192.0.2.1"].map {
            LocalAddress(interface: "en5", address: .ipv6(IPv6Address($0)!))
        }
        for local in [
            [vpn, cellular, wifi] + unusable,
            [wifi, ipv4, cellular],
            [ipv4LinkLocal, wifi],
            [ipv4LinkLocal],
            [cellular, hotspot, wifi],
            [vpn, cellular] + unusable,
            [vpn] + unusable,
        ] {
            let networks = ListenerNetworks(
                local: local, wifiInterfaces: [wifi.interface], cellularInterface: cellular.interface)
            write(networks.addresses.map { "\($0.local.address)" }.joined(separator: ","))
            write(networks.resolve(nil).map { "\($0.local.address.httpAuthorityHost):8080" } ?? "-")
        }
    }
}
