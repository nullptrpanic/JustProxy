# JustProxy

A local HTTP proxy for iPhone, with a simple on/off control and session traffic statistics.

JustProxy accepts requests from clients configured to use its displayed address and port. It forwards HTTP requests and supports HTTPS through CONNECT tunnels. Clients must be able to reach the iPhone over the network; Personal Hotspot is optional.

[User guide](https://nullptrpanic.github.io/JustProxy/) · [Privacy policy](https://nullptrpanic.github.io/JustProxy/privacy/)

## Features

- Start and stop the proxy with one prominent control.
- View and copy the listening address on port `8080`.
- Choose a listening address automatically or manually. Automatic selection prefers Personal Hotspot, then Wi-Fi, then the active cellular interface.
- View cumulative upload/download traffic and the most recent 50 connections for the current or last session.
- Open the listening address in a browser for a device-aware setup guide, with manual device selection available.
- Read the in-app privacy explanation from the question mark in the top-right corner.

The app and public support pages currently use Simplified Chinese. Repository documentation is maintained in English.

## Use the proxy

1. Connect the iPhone and client to a network that allows them to communicate.
2. Open JustProxy, choose a listening address, and tap the power control.
3. Configure the client's HTTP proxy with the displayed IP address and port `8080`.
4. Add `http://` before the copied endpoint to open the setup guide, or use a proxy-aware client:

   ```sh
   curl --proxy 'http://<displayed-ip>:8080' https://example.com/
   ```

   IPv6 endpoints include brackets, for example `http://[2001:db8::2]:8080/`. When the client has separate server and port fields, enter the IP address without brackets and port `8080`.

5. Tap the power control again to stop. Disable the client's manual proxy setting when finished.

### Scope and limitations

- JustProxy provides an explicit HTTP proxy. It does not automatically intercept hotspot traffic, create a VPN, or configure a system-wide VPN.
- Outbound connections follow iOS routing. Choosing a listening address selects where clients connect; it does not choose an outbound VPN or guarantee that another VPN carries the traffic.
- The listener supports IPv4 and IPv6. It prefers configured IPv4 on each interface, then IPv6, then self-assigned IPv4 (`169.254.*`). IPv6 link-local addresses are not advertised because clients require their own interface scope. A listed cellular address may be unreachable from other devices because of carrier routing or network isolation.
- The proxy does not implement client authentication. Use it only with trusted clients on trusted networks.
- Background execution is best effort. Switching apps does not explicitly stop the listener, but iOS may suspend or terminate the app. Keep JustProxy in the foreground for sustained use.
- HTTPS CONNECT relays tunnel bytes without installing certificates or decrypting HTTPS.

## Build and run

Requirements:

- macOS with a recent Xcode release that can open the project. The current development setup uses Xcode 27.2.
- An iPhone or simulator running iOS 17 or later.
- Python 3 to run the integration harness.

Open `JustProxy.xcodeproj` in Xcode, select the `JustProxy` scheme, and choose an iPhone or simulator. Configure your signing team when building for a physical device. The app uses Apple system frameworks and has no third-party package dependencies.

To build for the simulator from the repository root:

```sh
xcodebuild \
  -project JustProxy.xcodeproj \
  -scheme JustProxy \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Keep derived data, archives, exported IPAs, test output, and release records under `build/`, which is excluded from Git. Public versions use `MAJOR.MINOR.PATCH`, starting at `1.0.0`; distribution build numbers increase separately.

## Verification

Run the socket-level integration suite on macOS:

```sh
python3 Tests/proxy_integration.py
```

The suite compiles native Swift/C harnesses and uses loopback sockets to exercise HTTP forwarding, CONNECT tunnels, body framing, the local setup guide, traffic accounting, listener selection, and background-task bookkeeping. Temporary test binaries are created under `build/Tests/`.

These checks do not replace physical-device testing of network reachability, Personal Hotspot, cellular routing, or iOS background suspension.

## Repository layout

| Path | Purpose |
| --- | --- |
| `JustProxy/` | SwiftUI app, state model, privacy view, and assets |
| `JustProxy/Proxy/` | Listener discovery, HTTP parsing, forwarding, and the bundled connection guide |
| `JustProxy.xcodeproj/` | iOS project and build configuration |
| `Tests/` | Native harnesses and Python integration tests |
| `docs/` | Project design and maintenance documentation |
| `website/` | Public support and privacy pages deployed to GitHub Pages |
| `.github/workflows/pages.yml` | Website deployment from `master` |
| `build/` | Ignored build and verification artifacts |

## Documentation and website

- [Current design](docs/design.md): component responsibilities, request flow, network selection, and lifecycle constraints.
- [Website deployment](docs/website-deployment.md): GitHub Pages setup, local preview, and deployment verification.

Only the contents of `website/` are deployed. Project documentation in `docs/` is not part of the public website artifact. Moving the website source does not change its public URLs or require a new app build.

Use `dev` for ongoing development and merge release-ready changes into `master`. Website changes on `master` trigger deployment; documentation-only changes do not.

## Privacy and support

JustProxy has no account system, advertising SDK, or analytics SDK. Traffic counters and recent connection metadata remain in process memory. Starting a new proxy session resets the counters; ending the app process clears the in-memory records. The app declares local-network access, does not request location permission, and does not read Wi-Fi SSIDs.

See the [privacy policy](https://nullptrpanic.github.io/JustProxy/privacy/) for details about proxy requests, the hosted website, and support email.

Contact: [liyufeiat010@gmail.com](mailto:liyufeiat010@gmail.com). Do not include passwords, authentication tokens, or sensitive proxy traffic in support requests.
