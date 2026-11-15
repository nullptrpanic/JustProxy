import SwiftUI

struct ListenerPickerView: View {
    let model: ProxyModel
    let palette: ProxyPalette

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let rowHeight: CGFloat = 49
    private let rowSpacing: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    option(title: String(localized: "Automatic"), detail: String(localized: "Hotspot, then Wi-Fi, then cellular"), icon: "sparkles")
                    ForEach(model.networks.addresses.filter { $0.kind != .cellular }) { listener in
                        option(
                            title: model.listenerTitle(listener), detail: "\(listener.local.address)",
                            icon: listener.kind.icon, listener: listener
                        )
                    }
                    cellularOptions
                    if model.networks.addresses.isEmpty {
                        Text("No listening address available")
                            .font(.footnote)
                            .foregroundStyle(palette.secondary)
                            .padding(8)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .foregroundStyle(palette.text)
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .presentationBackground(palette.surface)
        .task { await model.watchNetworks() }
    }

    private var hasCellularOptions: Bool {
        model.networks.cellularAddress != nil || model.networks.dataServiceID != nil
    }

    private var detents: Set<PresentationDetent> {
        guard !dynamicTypeSize.isAccessibilitySize else { return [.large] }
        let networks = model.networks
        let dataRowWithoutAddress = hasCellularOptions && networks.cellularAddress == nil
        let rows = 1 + networks.addresses.count + networks.standbyServiceIDs.count + (dataRowWithoutAddress ? 1 : 0)
        let cellularHeading: CGFloat = hasCellularOptions ? 26 : 0
        let footer: CGFloat = networks.addresses.isEmpty ? 48 : 0
        let height = 88 + CGFloat(rows) * (rowHeight + rowSpacing) + cellularHeading + footer
        return [.height(min(height, 420)), .large]
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Listen on")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Address clients use to connect to JustProxy")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 0)
            Button("Close") { dismiss() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.accent)
                .frame(minWidth: 44, minHeight: 44)
        }
    }

    @ViewBuilder
    private var cellularOptions: some View {
        let networks = model.networks
        let dataAddress = networks.cellularAddress
        if hasCellularOptions {
            Text("Cellular · This iPhone")
                .font(.caption)
                .foregroundStyle(palette.secondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 8)
                .padding(.horizontal, 8)
            option(
                title: model.cellularTitle(networks.dataServiceID),
                detail: dataAddress.map { "\($0.local.address)" } ?? String(localized: "No IP address available"),
                icon: ListenerAddress.Kind.cellular.icon, listener: dataAddress,
                badge: String(localized: "Data SIM"), selectable: dataAddress != nil
            )
            ForEach(networks.standbyServiceIDs, id: \.self) { serviceID in
                option(
                    title: model.cellularTitle(serviceID), detail: String(localized: "Not currently used for cellular data"),
                    icon: ListenerAddress.Kind.cellular.icon, badge: String(localized: "Standby"), selectable: false
                )
            }
        }
    }

    private func option(
        title: String, detail: String, icon: String, listener: ListenerAddress? = nil,
        badge: String? = nil, selectable: Bool = true
    ) -> some View {
        let selected = selectable && model.selection == listener
        return Button {
            if model.select(listener) { dismiss() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selectable ? palette.accent : palette.secondary)
                    .frame(width: 34, height: 34)
                    .background(palette.copySurface, in: .rect(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectable ? palette.text : palette.secondary)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(selectable ? palette.accent : palette.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(palette.copySurface, in: .rect(cornerRadius: 4))
                        }
                    }
                    Text(detail)
                        .font(listener == nil ? .caption : .caption.monospaced())
                        .foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(minHeight: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension ListenerAddress.Kind {
    var icon: String {
        switch self {
        case .hotspot: "personalhotspot"
        case .wifi: "wifi"
        case .cellular: "iphone"
        }
    }

    var connectionHint: String {
        switch self {
        case .hotspot: String(localized: "Set a manual proxy on a device connected to this hotspot")
        case .wifi: String(localized: "Set a manual proxy on a device on the same Wi-Fi network")
        case .cellular: String(localized: "Access from other devices depends on your carrier network")
        }
    }
}

extension ProxyModel {
    func listenerTitle(_ listener: ListenerAddress) -> String {
        switch listener.kind {
        case .hotspot: String(localized: "Hotspot")
        case .wifi: "Wi-Fi"
        case .cellular: cellularTitle(listener.dataServiceID)
        }
    }

    func cellularTitle(_ serviceID: String?) -> String {
        if let serviceID, let generation = networks.cellularGenerations[serviceID], !generation.isEmpty {
            return String(localized: "Cellular · \(generation)")
        }
        return String(localized: "Cellular")
    }
}
