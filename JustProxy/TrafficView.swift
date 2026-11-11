import SwiftUI

struct TrafficView: View {
    let traffic: ProxyTraffic
    let current: Bool
    let hasSession: Bool
    let palette: ProxyPalette

    private var sessionTitle: String {
        hasSession && !current ? "上次会话" : "本次会话"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("流量")
                    .font(.title.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            summary(traffic)
            HStack {
                Text("最近连接").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(traffic.connections.count) 条")
                    .font(.footnote)
                    .foregroundStyle(palette.secondary)
            }
            .padding(.top, 4)

            if traffic.connections.isEmpty {
                Text("暂无连接记录，设备通过代理访问网络后会显示在这里。")
                    .font(.footnote)
                    .foregroundStyle(palette.secondary)
                    .padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(traffic.connections) { connection in
                        connectionRow(connection)
                        if connection.id != traffic.connections.last?.id {
                            Rectangle().fill(palette.border).frame(height: 1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 24)
    }

    private func summary(_ traffic: ProxyTraffic) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(sessionTitle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    metric("上传", icon: "arrow.up.right", bytes: traffic.uploaded)
                    Rectangle().fill(palette.border).frame(width: 1, height: 42)
                    metric("下载", icon: "arrow.down.left", bytes: traffic.downloaded)
                }
                VStack(alignment: .leading, spacing: 12) {
                    metric("上传", icon: "arrow.up.right", bytes: traffic.uploaded)
                    metric("下载", icon: "arrow.down.left", bytes: traffic.downloaded)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: .rect(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(palette.border) }
    }

    private func metric(_ title: LocalizedStringKey, icon: String, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.footnote)
                .foregroundStyle(palette.secondary)
            Text(bytes.formatted(.byteCount(style: .decimal)))
                .font(.title2.monospaced().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func connectionRow(_ connection: ProxyTraffic.Connection) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(connection.host)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("\(connection.method) · \(connection.port)")
                    .font(.caption.monospaced())
                    .foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 0)
            Text(connection.bytes.formatted(.byteCount(style: .decimal)))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
