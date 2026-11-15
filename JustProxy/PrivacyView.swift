import SwiftUI

struct PrivacyView: View {
    let palette: ProxyPalette
    @Environment(\.dismiss) private var dismiss

    private var policyURL: URL {
        let language = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? "zh" : "en"
        return URL(string: "https://nullptrpanic.github.io/JustProxy/privacy/?lang=" + language)!
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "hand.raised")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(palette.accent)
                            .accessibilityHidden(true)
                        Text("Local stats. On-demand forwarding.")
                            .font(.title2.weight(.semibold))
                        Text("JustProxy requires no account or sign-in, includes no ads or third-party analytics SDKs, and does not upload proxy traffic or connection records to developer-operated servers.")
                            .font(.subheadline)
                            .foregroundStyle(palette.secondary)
                    }

                    section("Proxy requests", text: "When the proxy is running, JustProxy processes client requests on your iPhone and forwards them to their requested destinations. Destination services and networks may process these requests under their own privacy policies. HTTPS CONNECT traffic is relayed through tunnels; JustProxy does not install certificates to decrypt HTTPS.")
                    section("Session data", text: "Upload and download totals, and the destination host, port, request method, and traffic for up to 50 recent connections, are kept only in device memory. They are not written to persistent files or uploaded to the developer. Statistics reset for a new proxy session; these records are released when the app process ends.")
                    section("Network access", text: "The app reads available local network addresses so you can choose a listening address. Local Network permission is used to reach destinations on your local network. JustProxy does not request location access or read Wi-Fi network names.")
                    section("Stopping and clearing data", text: "You can stop the proxy at any time using the main power button. Ending the app process clears its session records from memory. There is no account or personal profile stored on developer-operated servers to delete.")

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Policy and contact")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Link(destination: policyURL) {
                            Label("Read the privacy policy online", systemImage: "arrow.up.right.square")
                        }
                        Link(destination: URL(string: "mailto:liyufeiat010@gmail.com")!) {
                            Label("liyufeiat010@gmail.com", systemImage: "envelope")
                        }
                        .textSelection(.enabled)
                        Text("If you contact us by email, your message is used only to handle your inquiry. The online policy is hosted by GitHub Pages; its hosting privacy policy applies when you visit the website.")
                            .font(.footnote)
                            .foregroundStyle(palette.secondary)
                        Text("Last updated: November 15, 2026")
                            .font(.caption)
                            .foregroundStyle(palette.secondary)
                    }
                    .font(.subheadline)
                    .tint(palette.accent)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .foregroundStyle(palette.text)
            .background(palette.background)
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(palette.accent)
                }
            }
        }
    }

    private func section(_ title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
