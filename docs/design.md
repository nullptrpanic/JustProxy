# JustProxy Design

This document describes the current implementation. It records existing behavior and constraints rather than a roadmap or an unlimited-background-execution promise.

## Product scope

JustProxy is an explicit HTTP proxy running inside an iPhone app. Its main screen exposes one power control, listener selection, and a copyable endpoint. A separate traffic screen shows real session statistics. The question mark opens an offline privacy explanation with a link to the public policy.

Clients must configure the proxy themselves. Personal Hotspot is optional. JustProxy does not implement a VPN, transparent interception, SOCKS, UDP relay, TLS interception, or proxy authentication.

## Components

| Component | Responsibility |
| --- | --- |
| `JustProxyApp` and SwiftUI views | App lifecycle integration, proxy controls, network picker, traffic, and privacy presentation |
| `ProxyModel` | Main-actor observable state, selected listener, session identity, and server event handling |
| `LocalIPv4` and `InterfaceTypes.h` | Enumerate active IPv4 interfaces and identify infrastructure Wi-Fi interfaces |
| `ListenerNetworks` | Classify and order supported listener choices and resolve a selected address |
| `ProxyServer` | Own the listener, accepted peers, session counters, and periodic state validation on a serial queue |
| `ProxyConnection` | Own one client/upstream pair and handle forwarding, completion, half-close, and idle expiry |
| `HTTPMessage` | Parse and validate HTTP headers, routing targets, and message body framing |
| `ConnectionGuide` and its HTML resource | Serve setup instructions when a browser accesses the bound proxy endpoint |
| `BackgroundExecution` | Balance finite UIKit background-task requests across a proxy session |

## Listener and session lifecycle

The model transitions through `off`, `starting`, `running`, and `stopping`. A listener-ready event is required before showing the proxy as running. Each start creates a new session identity so delayed events from an older session cannot affect a new one.

The server binds to the selected IPv4 address and interface on port `8080`. Automatic selection prefers a detected hotspot, then infrastructure Wi-Fi, then the active cellular interface. Hotspot detection uses known interface/address heuristics because there is no public Personal Hotspot interface type.

The picker excludes loopback addresses and does not classify point-to-point VPN tunnels as Wi-Fi. It does not read SSIDs. Cellular metadata identifies the current data line and radio generation; standby lines do not provide independent listening endpoints.

The server validates that its bound address still exists. An invalid address or listener failure clears the running state. Returning to the foreground revalidates the existing listener. Stopping closes the listener and every accepted connection. A fresh app process starts with the proxy off.

## Request flow

1. `NWListener` accepts a TCP client and creates a `ProxyConnection` on the server's serial queue.
2. The connection parses the HTTP header and validates the destination and body framing.
3. Requests addressed to the bound local endpoint are handled by the bundled setup guide. They do not create an upstream connection or increment proxy traffic counters.
4. An ordinary proxy request opens a TCP connection to the requested host and port using system routing. Hop-by-hop headers are removed and message boundaries are enforced.
5. A CONNECT request receives a successful tunnel response after the upstream connection is ready, then relays bytes in both directions. Early tunnel bytes and TCP half-close are preserved.
6. Send completions control subsequent reads, bounding queued data. Buffered bytes are drained before terminal I/O conditions close a connection.

An ordinary HTTP connection handles one request/response exchange and closes; pipelined bytes are not forwarded as another request. The proxy enforces declared HTTP body boundaries rather than forwarding all received bytes blindly.

Reads use a minimum of one byte and a maximum of 128 KiB. The maximum bounds each receive operation; the connection does not wait to fill 128 KiB before forwarding. Fixed-length body parsing does not retain the entire body as transfers grow.

The server accepts up to 128 concurrent connections. Idle connections expire after 20 seconds before upstream readiness or 180 seconds after readiness.

## Traffic and privacy

The server accumulates bytes passed through its forwarding path and retains the most recent 50 connection records. These are application-level counts, not total device traffic or cellular billing measurements. Changed snapshots are delivered approximately once per second while the process is scheduled.

The main actor consumes immutable snapshots for display. The last session remains visible after stopping, and a new ready session resets the counters. Statistics and recent targets are not persisted to files or uploaded to a developer service.

The app uses a local-network usage description. It has no location permission, SSID entitlement, VPN extension, background audio mode, or Background Fetch mode.

## Background execution

Starting the proxy requests a finite UIKit background task. Switching apps does not intentionally stop the listener. Expiration ends the background task without automatically creating a replacement or explicitly closing the proxy.

iOS may then suspend or terminate the process. Returning to the foreground validates the listener and renews the finite background task. This design does not guarantee continuous background availability.

## Public website and project documentation

The in-app connection guide is bundled at `JustProxy/Proxy/ConnectionGuide.html` and is served by the proxy itself. It is separate from the static support/privacy website in `website/`.

GitHub Pages publishes only `website/` from `master`. The stable support and privacy URLs are also used by App Store Connect and the app. See [website deployment](website-deployment.md) for configuration and verification.

Project documentation belongs in `docs/` and is written in English. Historical local implementation plans may exist under `docs/superpowers/plans/`; that directory is intentionally ignored by Git. Those plans are historical records, while this document describes the current implementation.

## Verification boundaries

`python3 Tests/proxy_integration.py` compiles native harnesses and checks protocol behavior with real loopback sockets, along with listener-selection and background-task lifecycle cases. All generated files stay under `build/Tests/`.

Physical-device testing is still needed for carrier reachability, hotspot behavior, actual VPN routing, and iOS background suspension. Loopback tests do not establish those behaviors.
