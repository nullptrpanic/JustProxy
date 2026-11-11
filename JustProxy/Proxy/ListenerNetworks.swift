import Network

struct ListenerAddress: Identifiable, Hashable {
    enum Kind: Hashable {
        case hotspot
        case wifi
        case cellular
    }

    let kind: Kind
    let local: LocalIPv4
    let dataServiceID: String?

    var id: Self { self }
}

struct ListenerNetworks: Equatable {
    let addresses: [ListenerAddress]
    let dataServiceID: String?
    let cellularGenerations: [String: String]

    init(
        local: [LocalIPv4] = [], wifiInterfaces: Set<String> = [], cellularInterface: String? = nil,
        dataServiceID: String? = nil, cellularGenerations: [String: String] = [:]
    ) {
        self.dataServiceID = dataServiceID
        self.cellularGenerations = cellularGenerations

        let usable = local.filter { $0.address != .any && !$0.address.isLoopback }
        // Personal Hotspot has no public interface type. Retain the known bridge checks.
        let hotspot =
            usable.first { $0.interface == "bridge100" }
            ?? usable.first {
                ($0.interface.hasPrefix("bridge") || $0.interface.hasPrefix("ap"))
                    && $0.address == IPv4Address("172.20.10.1")
            }
        var addresses = hotspot.map { [ListenerAddress(kind: .hotspot, local: $0, dataServiceID: nil)] } ?? []
        addresses += usable.filter { $0 != hotspot && wifiInterfaces.contains($0.interface) }.map {
            ListenerAddress(kind: .wifi, local: $0, dataServiceID: nil)
        }
        if let cellular = usable.first(where: { $0.interface == cellularInterface }) {
            addresses.append(ListenerAddress(kind: .cellular, local: cellular, dataServiceID: dataServiceID))
        }
        self.addresses = addresses
    }

    var cellularAddress: ListenerAddress? { addresses.first { $0.kind == .cellular } }

    var standbyServiceIDs: [String] {
        guard let dataServiceID else { return [] }
        return cellularGenerations.keys.filter { $0 != dataServiceID }.sorted()
    }

    func resolve(_ selection: ListenerAddress?) -> ListenerAddress? {
        guard let selection else { return addresses.first }
        return addresses.contains(selection) ? selection : nil
    }
}
