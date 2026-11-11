import Darwin
import Foundation
import Network

struct LocalAddress: Hashable {
    let interface: String
    let address: NWEndpoint.Host

    static func addresses() -> [LocalAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return [] }
        defer { freeifaddrs(head) }

        var result: [LocalAddress] = []
        var current: UnsafeMutablePointer<ifaddrs>? = head
        while let entry = current?.pointee {
            current = entry.ifa_next
            guard let socketAddress = entry.ifa_addr,
                [UInt8(AF_INET), UInt8(AF_INET6)].contains(socketAddress.pointee.sa_family),
                entry.ifa_flags & UInt32(IFF_UP) != 0
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                socketAddress, socklen_t(socketAddress.pointee.sa_len),
                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST
            ) == 0 else { continue }
            let address: NWEndpoint.Host
            if socketAddress.pointee.sa_family == UInt8(AF_INET6) {
                guard let ip = IPv6Address(String(cString: host)) else { continue }
                address = .ipv6(ip)
            } else {
                guard let ip = IPv4Address(String(cString: host)) else { continue }
                address = .ipv4(ip)
            }
            result.append(LocalAddress(interface: String(cString: entry.ifa_name), address: address))
        }
        return result
    }

    #if os(iOS)
    static func wifiInterfaces(in local: [LocalAddress]) -> Set<String> {
        let socket = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard socket >= 0 else { return [] }
        defer { Darwin.close(socket) }

        return Set(local.map(\.interface)).filter { name in
            name.withCString { JPIsInfrastructureWiFi(socket, $0) }
        }
    }
    #endif
}

extension NWEndpoint.Host {
    var ipAddress: (any IPAddress)? {
        switch self {
        case .ipv4(let address): address
        case .ipv6(let address): address
        case .name: nil
        @unknown default: nil
        }
    }

    // Brackets separate an IPv6 literal from a port in HTTP authorities and copied endpoints.
    var httpAuthorityHost: String {
        if case .ipv6(let address) = self { return "[\(address)]" }
        return "\(self)"
    }
}
