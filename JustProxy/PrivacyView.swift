import SwiftUI

struct PrivacyView: View {
    let palette: ProxyPalette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "hand.raised")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(palette.accent)
                            .accessibilityHidden(true)
                        Text("本地统计，按需转发")
                            .font(.title2.weight(.semibold))
                        Text("JustProxy 无需注册或登录，不集成广告或第三方统计 SDK，也不向开发者服务器上传代理流量或连接记录。")
                            .font(.subheadline)
                            .foregroundStyle(palette.secondary)
                    }

                    section("代理请求", text: "开启代理后，JustProxy 在你的 iPhone 上处理客户端请求，并转发到请求指定的目标服务器。目标服务和所用网络可能按各自的隐私政策处理这些请求。HTTPS CONNECT 使用隧道转发，JustProxy 不安装用于解密 HTTPS 的证书。")
                    section("会话数据", text: "上传、下载字节数及最近 50 条连接的目标主机、端口、请求方式和流量仅保存在本机内存中，不写入持久化文件，也不上传给开发者。新代理会话会重新统计；应用进程结束后，这些内存记录随之释放。")
                    section("网络权限", text: "应用读取本机可用网络地址，以提供监听地址选择。本地网络权限用于访问局域网目标。JustProxy 不申请定位权限，也不读取 Wi-Fi 名称。")
                    section("停止与清除", text: "你可以随时点击主界面的大按钮关闭代理。结束应用进程可清除内存中的会话记录。应用没有开发者服务器上的账号或个人档案需要删除。")

                    VStack(alignment: .leading, spacing: 14) {
                        Text("政策与联系")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Link(destination: URL(string: "https://nullptrpanic.github.io/JustProxy/privacy/")!) {
                            Label("查看网页版隐私政策", systemImage: "arrow.up.right.square")
                        }
                        Link(destination: URL(string: "mailto:liyufeiat010@gmail.com")!) {
                            Label("liyufeiat010@gmail.com", systemImage: "envelope")
                        }
                        .textSelection(.enabled)
                        Text("如主动通过邮件联系我们，邮件内容仅用于处理你的咨询。网页版政策由 GitHub Pages 托管，访问网页时适用其托管服务隐私政策。")
                            .font(.footnote)
                            .foregroundStyle(palette.secondary)
                        Text("更新日期：2026 年 11 月 11 日")
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
            .navigationTitle("隐私说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .tint(palette.accent)
                }
            }
        }
    }

    private func section(_ title: String, text: String) -> some View {
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
