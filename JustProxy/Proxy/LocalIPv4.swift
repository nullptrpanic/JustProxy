import Darwin
import Foundation
import Network

struct LocalIPv4: Hashable {
    let interface: String
    let address: IPv4Address

    static func addresses() -> [LocalIPv4] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return [] }
        defer { freeifaddrs(head) }

        var result: [LocalIPv4] = []
        var current: UnsafeMutablePointer<ifaddrs>? = head
        while let entry = current?.pointee {
            current = entry.ifa_next
            guard let socketAddress = entry.ifa_addr,
                socketAddress.pointee.sa_family == UInt8(AF_INET),
                entry.ifa_flags & UInt32(IFF_UP) != 0
            else { continue }
            var address = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr
            }
            let bytes = withUnsafeBytes(of: &address) { Data($0) }
            if let ip = IPv4Address(bytes) {
                result.append(LocalIPv4(interface: String(cString: entry.ifa_name), address: ip))
            }
        }
        return result
    }

    #if os(iOS)
    static func wifiInterfaces(in local: [LocalIPv4]) -> Set<String> {
        let socket = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard socket >= 0 else { return [] }
        defer { Darwin.close(socket) }

        return Set(local.map(\.interface)).filter { name in
            name.withCString { JPIsInfrastructureWiFi(socket, $0) }
        }
    }
    #endif
}
