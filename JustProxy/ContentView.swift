import SwiftUI
import UIKit

struct ContentView: View {
    private enum Page {
        case proxy
        case traffic
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var model = ProxyModel()
    @State private var page = Page.proxy
    @State private var showingPrivacy = false

    private var palette: ProxyPalette { ProxyPalette(dark: colorScheme == .dark) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                switch page {
                case .proxy:
                    ProxyHomeView(model: model, palette: palette)
                case .traffic:
                    TrafficView(
                        traffic: model.traffic,
                        current: model.state.endpoint != nil,
                        hasSession: model.hasSession,
                        palette: palette
                    )
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            tabBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(palette.text)
        .background {
            EllipticalGradient(
                colors: [palette.highlight, palette.background],
                center: UnitPoint(x: 0.50, y: 0.22),
                endRadiusFraction: 0.66
            )
            .ignoresSafeArea()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { model.didBecomeActive() }
        }
        .task(id: model.isListeningOnCellular) {
            if model.isListeningOnCellular { await model.watchNetworks() }
        }
        .sheet(isPresented: $showingPrivacy) {
            PrivacyView(palette: palette)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("BrandMark")
                .resizable()
                .frame(width: 42, height: 42)
                .clipShape(.rect(cornerRadius: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("JustProxy")
                    .font(.title2.weight(.bold))
                    .tracking(-1)
                    .accessibilityAddTraits(.isHeader)
                Text("HTTP 代理")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 0)
            Button {
                showingPrivacy = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("隐私说明")
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 15)
    }

    private var tabBar: some View {
        HStack(spacing: 10) {
            tab(.proxy, title: "代理")
            tab(.traffic, title: "流量")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 3)
        .background(alignment: .top) {
            palette.surface.ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
        }
    }

    private func tab(_ target: Page, title: LocalizedStringKey) -> some View {
        Button {
            page = target
        } label: {
            VStack(spacing: 3) {
                Group {
                    if target == .proxy {
                        PowerGlyph().stroke(style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                            .frame(width: 15, height: 17)
                    } else {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                .frame(width: 22, height: 21)
                .accessibilityHidden(true)
                Text(title).font(.caption2.weight(page == target ? .semibold : .medium))
            }
            .foregroundStyle(page == target ? palette.accent : palette.secondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if page == target {
                    Capsule().fill(palette.accent).frame(width: 20, height: 2)
                        .offset(y: -6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(page == target ? .isSelected : [])
    }
}

struct ProxyPalette {
    let dark: Bool

    var background: Color { tone(0xF4F5F7, 0x111317) }
    var highlight: Color { tone(0xFFFFFF, 0x20242C) }
    var surface: Color { tone(0xFCFCFD, 0x171A20) }
    var text: Color { tone(0x171C24, 0xEDF0F5) }
    var secondary: Color { tone(0x586474, 0xA5AEBB) }
    var border: Color { tone(0xDCE0E7, 0x2B303A) }
    var accent: Color { tone(0x315CAA, 0x9CBAFF) }
    var running: Color { tone(0x188653, 0x78DFA5) }
    var copySurface: Color { tone(0xEEF0F4, 0x242A35) }
    var error: Color { tone(0x9D342C, 0xF3AAA0) }

    private func tone(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(rgb: self.dark ? dark : light)
    }
}

extension Color {
    fileprivate init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

private struct ProxyHomeView: View {
    let model: ProxyModel
    let palette: ProxyPalette
    @State private var copied = false
    @State private var showingListenerPicker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var running: Bool { model.state.endpoint != nil }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: model.toggle) {
                powerDial
            }
            .buttonStyle(.plain)
            .disabled(model.state.isBusy || (!running && model.selectionWarning != nil))
            .accessibilityLabel(running ? "关闭代理" : "开启代理")
            .accessibilityValue(model.state.title)

            HStack(spacing: 8) {
                Circle()
                    .fill(running ? palette.running : palette.secondary)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(model.state.title)
                    .font(.title3.weight(.semibold))
                    .tracking(-0.5)
            }
            .padding(.top, 19)

            if let endpoint = model.state.endpoint {
                addressCard(endpoint)
                    .padding(.top, 25)
            } else if model.state == .off {
                listenerPickerButton
                    .padding(.top, 25)
                if let failure = model.selectionWarning ?? model.failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(palette.error)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                }
            }
        }
        .frame(maxWidth: 322)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 42)
        .padding(.bottom, 18)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: running)
        .onChange(of: model.state.endpoint) { _, _ in copied = false }
        .sheet(isPresented: $showingListenerPicker) {
            ListenerPickerView(model: model, palette: palette)
        }
    }

    private var listenerPickerButton: some View {
        let title = model.selection.map(model.listenerTitle) ?? "自动选择"
        return Button {
            model.refreshNetworks()
            showingListenerPicker = true
        } label: {
            HStack(spacing: 8) {
                Text("监听地址")
                    .foregroundStyle(palette.text)
                Spacer(minLength: 8)
                Text(title)
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(palette.surface, in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(palette.border) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("监听地址")
        .accessibilityValue(title)
    }

    private var powerDial: some View {
        ZStack {
            Circle()
                .strokeBorder(palette.border, lineWidth: 1)
            if running {
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: palette.accent, location: 0.14),
                                .init(color: .clear, location: 0.35),
                                .init(color: .clear, location: 1),
                            ],
                            center: .center, startAngle: .degrees(-150), endAngle: .degrees(210)
                        ),
                        lineWidth: 1
                    )
            }
            Circle()
                .fill(
                    AngularGradient(
                        stops: rimStops,
                        center: .center, startAngle: .degrees(120), endAngle: .degrees(480)
                    )
                )
                .frame(width: 134, height: 134)
                .shadow(
                    color: running ? palette.accent.opacity(0.27) : .black.opacity(0.20),
                    radius: running ? 13 : 9, x: 0, y: running ? 0 : 7)
            Circle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(rgb: 0x343C49), location: 0),
                            .init(color: Color(rgb: 0x171C25), location: 0.65),
                            .init(color: Color(rgb: 0x141821), location: 1),
                        ],
                        startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1)
                    )
                )
                .frame(width: 126, height: 126)
            if model.state.isBusy {
                ProgressView().tint(Color(rgb: 0xA8C9FF))
            } else {
                PowerGlyph()
                    .stroke(
                        Color(rgb: running ? 0xA8C9FF : 0xC8D0DC),
                        style: StrokeStyle(lineWidth: 3.1, lineCap: .round)
                    )
                    .frame(width: 42, height: 46)
            }
        }
        .frame(width: 184, height: 184)
        .contentShape(Circle())
    }

    private var rimStops: [Gradient.Stop] {
        if running {
            return [
                .init(color: Color(rgb: 0x394152), location: 0),
                .init(color: Color(rgb: 0xB5CDF4), location: 0.34),
                .init(color: Color(rgb: 0x628BD2), location: 0.55),
                .init(color: Color(rgb: 0x303D57), location: 0.84),
                .init(color: Color(rgb: 0x394152), location: 1),
            ]
        }
        return [
            .init(color: Color(rgb: 0x2B323F), location: 0),
            .init(color: Color(rgb: 0x86909E), location: 0.31),
            .init(color: Color(rgb: 0x414C5B), location: 0.53),
            .init(color: Color(rgb: 0x232C38), location: 0.80),
            .init(color: Color(rgb: 0x2B323F), location: 1),
        ]
    }

    private func addressCard(_ endpoint: ProxyModel.Endpoint) -> some View {
        let listener = endpoint.listener
        let title = model.listenerTitle(listener)
        let kind = listener.kind
        return VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    addressText(endpoint.text, source: title, icon: kind.icon)
                    Spacer(minLength: 0)
                    copyButton(endpoint.text)
                }
                VStack(alignment: .leading, spacing: 8) {
                    addressText(endpoint.text, source: title, icon: kind.icon)
                    copyButton(endpoint.text)
                }
            }
            Text(kind.connectionHint)
                .font(.caption)
                .foregroundStyle(palette.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(palette.border) }
    }

    private func addressText(_ address: String, source: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text("代理地址")
                    .foregroundStyle(palette.secondary)
                    .fixedSize()
                Label(source, systemImage: icon)
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
            }
            .font(.caption)
            Text(address)
                .font(.body.monospaced().weight(.semibold))
                .tracking(-0.5)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
    }

    private func copyButton(_ address: String) -> some View {
        Button {
            UIPasteboard.general.string = address
            copied = true
        } label: {
            Text(copied ? "已复制" : "复制")
                .font(.caption.weight(.semibold))
                .frame(minWidth: 60, minHeight: 44)
                .padding(.horizontal, 4)
                .background(palette.copySurface, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "代理地址已复制" : "复制代理地址")
    }
}

private struct PowerGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY + size * 0.09),
            radius: size * 0.44, startAngle: .degrees(-45), endAngle: .degrees(225), clockwise: false
        )
        path.move(to: CGPoint(x: rect.midX, y: rect.midY - size * 0.50))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY - size * 0.08))
        return path
    }
}
