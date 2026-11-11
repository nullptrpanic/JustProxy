import select
import shutil
import socket
import subprocess
import tempfile
import unittest
from pathlib import Path


def receive_until(sock, delimiter):
    data = b""
    while delimiter not in data:
        chunk = sock.recv(4096)
        if not chunk:
            raise AssertionError(f"Connection closed before {delimiter!r}: {data!r}")
        data += chunk
    return data


def receive_all(sock):
    chunks = []
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)


class ProxyIntegrationTests(unittest.TestCase):
    binary = None

    def setUp(self):
        self.origin = socket.socket()
        self.addCleanup(self.origin.close)
        self.origin.bind(("127.0.0.1", 0))
        self.origin.listen(1)
        self.origin.settimeout(4)
        self.target = f"127.0.0.1:{self.origin.getsockname()[1]}".encode()

        self.proxy = subprocess.Popen(
            [self.binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True
        )
        self.addCleanup(self.cleanup_proxy)
        ready = self.proxy_line()
        self.assertTrue(ready.startswith("READY "), ready)
        self.port = int(ready.split()[1])

    def proxy_line(self):
        readable, _, _ = select.select([self.proxy.stdout], [], [], 5)
        self.assertTrue(readable, "Proxy did not report its state")
        return self.proxy.stdout.readline().rstrip()

    def cleanup_proxy(self):
        if self.proxy.poll() is None:
            self.proxy.kill()
        self.proxy.wait(timeout=5)
        self.proxy.stdin.close()
        self.proxy.stdout.close()

    def client(self):
        connection = socket.create_connection(("127.0.0.1", self.port), timeout=4)
        self.addCleanup(connection.close)
        return connection

    def upstream(self):
        connection, _ = self.origin.accept()
        connection.settimeout(4)
        self.addCleanup(connection.close)
        return connection

    def stop_proxy(self):
        self.proxy.stdin.write("\n")
        self.proxy.stdin.flush()
        result = self.proxy_line()
        self.assertEqual(self.proxy.wait(timeout=5), 0)
        return result

    def test_http_routes_by_absolute_target_and_strips_hop_headers(self):
        client = self.client()
        client.sendall(b"GET http://" + self.target + b"/status?q=a%2Fb HTTP/1.1\r\n"
                       b"Host: wrong.invalid\r\nConnection: X-Hop\r\nX-Hop: local\r\n"
                       b"Proxy-Authorization: local-credentials\r\n\r\n")
        upstream = self.upstream()
        self.assertEqual(receive_until(upstream, b"\r\n\r\n"),
                         b"GET /status?q=a%2Fb HTTP/1.1\r\nHost: " + self.target
                         + b"\r\nConnection: close\r\n\r\n")
        upstream.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n"
                         b"Connection: X-Origin-Hop\r\nX-Origin-Hop: local\r\n\r\nok")
        response = receive_all(client)
        self.assertTrue(response.endswith(b"\r\n\r\nok"), response)
        self.assertIn(b"Connection: close\r\n", response)
        self.assertNotIn(b"X-Origin-Hop", response)

    def test_fixed_upload_does_not_forward_a_pipelined_request(self):
        client = self.client()
        client.sendall(b"POST http://" + self.target + b"/upload HTTP/1.1\r\n"
                       b"Host: " + self.target + b"\r\nContent-Length: 4\r\n\r\n"
                       b"bodyGET http://wrong.invalid/ HTTP/1.1\r\nHost: wrong.invalid\r\n\r\n")
        upstream = self.upstream()
        request = receive_until(upstream, b"\r\n\r\nbody")
        self.assertEqual(request.split(b"\r\n\r\n", 1)[1], b"body")
        upstream.settimeout(0.2)
        try:
            self.assertEqual(upstream.recv(4096), b"")
        except socket.timeout:
            pass
        upstream.sendall(b"HTTP/1.1 201 Created\r\nContent-Length: 0\r\n\r\n")
        self.assertTrue(receive_all(client).startswith(b"HTTP/1.1 201"))

    def test_fragmented_chunked_upload_and_chunked_response(self):
        client = self.client()
        client.sendall(b"POST http://" + self.target + b"/ HTTP/1.1\r\nHost: " + self.target
                       + b"\r\nTransfer-Encoding: chunked\r\nTrailer: X-End\r\n\r")
        for fragment in (b"\n3\r", b"\nabc\r", b"\n0\r\nX-End: yes\r\n\r", b"\n"):
            client.sendall(fragment)
        upstream = self.upstream()
        self.assertTrue(receive_until(upstream, b"X-End: yes\r\n\r\n")
                        .endswith(b"3\r\nabc\r\n0\r\nX-End: yes\r\n\r\n"))
        upstream.sendall(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
                         b"2\r\nok\r\n0\r\n\r\nEXTRA")
        self.assertTrue(receive_all(client).endswith(b"2\r\nok\r\n0\r\n\r\n"))

    def test_connect_preserves_early_bytes_and_tcp_half_close(self):
        client = self.client()
        client.sendall(b"CONNECT " + self.target + b" HTTP/1.1\r\nHost: " + self.target + b"\r\n\r")
        client.sendall(b"\nearly-tunnel-data")
        client.shutdown(socket.SHUT_WR)
        upstream = self.upstream()
        self.assertEqual(receive_all(upstream), b"early-tunnel-data")
        upstream.sendall(b"tunnel-response")
        upstream.shutdown(socket.SHUT_WR)
        response = receive_all(client)
        self.assertTrue(response.startswith(b"HTTP/1.1 200 "), response)
        self.assertEqual(response.split(b"\r\n\r\n", 1)[1], b"tunnel-response")
        self.assertEqual(self.stop_proxy(), "STOPPED 17 15 1 -")

    def test_rejects_conflicting_body_framing(self):
        client = self.client()
        client.sendall(b"POST http://" + self.target + b"/ HTTP/1.1\r\nHost: " + self.target
                       + b"\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n0\r\n\r\n")
        self.assertTrue(receive_all(client).startswith(b"HTTP/1.1 400 "))

    def test_stop_closes_listener_and_active_tunnel(self):
        client = self.client()
        client.sendall(b"CONNECT " + self.target + b" HTTP/1.1\r\nHost: " + self.target + b"\r\n\r\n")
        upstream = self.upstream()
        self.assertTrue(receive_until(client, b"\r\n\r\n").startswith(b"HTTP/1.1 200 "))
        self.assertEqual(self.stop_proxy(), "STOPPED 0 0 1 -")
        self.assertEqual(client.recv(1), b"")
        self.assertEqual(upstream.recv(1), b"")
        with self.assertRaises(OSError):
            self.client()

    def test_listener_state_can_be_rechecked_without_stopping_the_proxy(self):
        self.proxy.stdin.write("check\n")
        self.proxy.stdin.flush()
        self.assertEqual(self.proxy_line(), f"READY {self.port}")
        client = self.client()
        client.sendall(b"INVALID\r\n\r\n")
        self.assertTrue(receive_all(client).startswith(b"HTTP/1.1 400 "))
        self.assertEqual(self.stop_proxy(), "STOPPED 0 0 0 -")
        self.assertEqual(client.recv(1), b"")

    def guide_request(self, method="GET", target="/", headers=None, body=b""):
        client = self.client()
        if headers is None:
            headers = f"Host: 127.0.0.1:{self.port}\r\n"
        client.sendall(f"{method} {target} HTTP/1.1\r\n{headers}\r\n".encode() + body)
        head, content = receive_all(client).split(b"\r\n\r\n", 1)
        lines = head.decode().split("\r\n")
        fields = dict(line.split(": ", 1) for line in lines[1:])
        return lines[0], fields, content

    def test_direct_guide_uses_real_endpoint_without_recording_proxy_traffic(self):
        status, headers, content = self.guide_request()
        self.assertEqual(status, "HTTP/1.1 200 OK")
        self.assertEqual(headers["Content-Type"], "text/html; charset=utf-8")
        self.assertEqual(int(headers["Content-Length"]), len(content))
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(headers["Connection"], "close")
        self.assertIn(f"127.0.0.1:{self.port}".encode(), content)
        self.assertIn("服务器地址".encode(), content)
        self.assertNotIn(b"192.168.1.23", content)
        self.assertNotIn(b"{{", content)
        self.assertEqual(self.stop_proxy(), "STOPPED 0 0 0 -")

    def test_absolute_self_request_also_serves_the_guide_without_reflecting_host(self):
        status, _, content = self.guide_request(
            target=f"http://127.0.0.1:{self.port}/?from=browser",
            headers="Host: attacker.invalid\r\n")
        self.assertEqual(status, "HTTP/1.1 200 OK")
        self.assertIn(f"127.0.0.1:{self.port}".encode(), content)
        self.assertNotIn(b"attacker.invalid", content)

    def test_guide_head_returns_get_length_without_body(self):
        get_status, get_headers, _ = self.guide_request()
        status, headers, content = self.guide_request(method="HEAD")
        self.assertEqual(get_status, "HTTP/1.1 200 OK")
        self.assertEqual(status, get_status)
        self.assertEqual(headers["Content-Length"], get_headers["Content-Length"])
        self.assertEqual(content, b"")

    def test_guide_unknown_path_and_unsupported_method_return_local_errors(self):
        status, _, _ = self.guide_request(target="/missing")
        self.assertEqual(status, "HTTP/1.1 404 Not Found")
        status, headers, _ = self.guide_request(method="POST")
        self.assertEqual(status, "HTTP/1.1 405 Method Not Allowed")
        self.assertEqual(headers["Allow"], "GET, HEAD")
        self.assertEqual(self.stop_proxy(), "STOPPED 0 0 0 -")

    def test_guide_does_not_accept_invalid_hosts_bodies_or_a_self_tunnel(self):
        local = f"Host: 127.0.0.1:{self.port}\r\n"
        cases = [
            ("GET", "/", "", b""),
            ("GET", "/", "Host: other.invalid\r\n", b""),
            ("GET", "/", local + local, b""),
            ("GET", "/", local + "Content-Length: 1\r\n", b"x"),
            ("GET", "/", local + "Content-Length: 0\r\nTransfer-Encoding: chunked\r\n", b"0\r\n\r\n"),
            ("CONNECT", f"127.0.0.1:{self.port}", local, b""),
        ]
        for method, target, headers, body in cases:
            with self.subTest(method=method, target=target, headers=headers):
                status, _, _ = self.guide_request(method, target, headers, body)
                self.assertEqual(status, "HTTP/1.1 400 Bad Request")

    def test_external_absolute_target_is_not_replaced_by_guide_for_local_host(self):
        client = self.client()
        client.sendall(b"GET http://" + self.target + b"/ HTTP/1.1\r\n"
                       + f"Host: 127.0.0.1:{self.port}\r\n\r\n".encode())
        upstream = self.upstream()
        self.assertIn(b"Host: " + self.target + b"\r\n", receive_until(upstream, b"\r\n\r\n"))
        upstream.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\norigin")
        self.assertTrue(receive_all(client).endswith(b"\r\n\r\norigin"))


class BackgroundExecutionTests(unittest.TestCase):
    binary = None

    def run_scenario(self, scenario):
        return subprocess.check_output([self.binary, scenario], text=True, timeout=5).splitlines()

    def test_repeated_start_and_stop_balance_one_background_task(self):
        self.assertEqual(self.run_scenario("stop"), ["1", "1"])

    def test_expiration_ends_the_task_without_automatically_starting_another(self):
        self.assertEqual(self.run_scenario("expiration"), ["1", "1"])

    def test_a_late_expiration_cannot_end_a_renewed_foreground_task(self):
        self.assertEqual(self.run_scenario("renew"), ["1", "2", "1,2"])

    def test_unavailable_background_time_does_not_end_an_invalid_task(self):
        self.assertEqual(self.run_scenario("unavailable"), ["1", ""])

    def test_immediate_expiration_does_not_leak_the_returned_task(self):
        self.assertEqual(self.run_scenario("immediate-expiration"), ["1", "1"])

    def test_releasing_the_owner_ends_the_background_task(self):
        self.assertEqual(self.run_scenario("release"), ["1", "1"])


class InterfaceTypeTests(unittest.TestCase):
    binary = None

    def is_wifi(self, interface):
        return subprocess.check_output([self.binary, interface], text=True, timeout=5).strip()

    def test_vpn_tunnels_are_not_wifi_even_when_their_underlying_transport_is_wifi(self):
        for interface in ["utun3", "ipsec0"]:
            with self.subTest(interface=interface):
                self.assertEqual(self.is_wifi(interface), "0")

    def test_only_infrastructure_wifi_is_classified_as_wifi(self):
        for interface, expected in [("en5", "1"), ("pdp_ip0", "0"), ("awdl0", "0")]:
            with self.subTest(interface=interface):
                self.assertEqual(self.is_wifi(interface), expected)

    def test_failed_interface_queries_do_not_produce_wifi_choices(self):
        for interface in ["flags-failed", "type-failed"]:
            with self.subTest(interface=interface):
                self.assertEqual(self.is_wifi(interface), "0")


class ListenerAddressTests(unittest.TestCase):
    def test_automatic_listener_prefers_hotspot_then_wifi_then_cellular(self):
        addresses = subprocess.check_output(
            [ProxyIntegrationTests.binary, "--listener-addresses"], text=True, timeout=5
        ).splitlines()
        self.assertEqual(addresses, ["192.168.42.19", "192.0.0.1", "100.64.10.3", "-"])

    def test_switching_data_lines_invalidates_only_the_old_cellular_selection(self):
        choices = subprocess.check_output(
            [ProxyIntegrationTests.binary, "--cellular-selection"], text=True, timeout=5
        ).splitlines()
        self.assertEqual(choices, [
            "192.168.42.19,100.64.10.3", "second",
            "192.168.42.19,100.64.20.4", "first",
            "-", "192.168.42.19", "-", "-",
        ])

    def test_start_rejects_an_interface_without_the_selected_address(self):
        non_loopback = next(name for _, name in socket.if_nameindex() if not name.startswith("lo"))
        for interface in [non_loopback, "jp_missing"]:
            with self.subTest(interface=interface):
                output = subprocess.check_output(
                    [ProxyIntegrationTests.binary, "--interface", interface], input="\n", text=True, timeout=5
                ).splitlines()
                self.assertEqual(len(output), 1, output)
                self.assertTrue(output[0].startswith("STOPPED 0 0 0 "), output)
                self.assertFalse(output[0].endswith(" -"), output)


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    test_output = root / "build" / "Tests"
    test_output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="justproxy-tests-", dir=test_output) as temp:
        binary = Path(temp) / "ProxyHarness"
        sources = sorted((root / "JustProxy" / "Proxy").glob("*.swift"))
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", *sources, root / "Tests" / "ProxyHarness.swift",
                        "-o", binary], check=True)
        ProxyIntegrationTests.binary = binary
        shutil.copyfile(root / "JustProxy" / "Proxy" / "ConnectionGuide.html", Path(temp) / "ConnectionGuide.html")
        interface_binary = Path(temp) / "InterfaceTypesHarness"
        subprocess.run(["xcrun", "clang", "-Wall", "-Wextra", "-Werror",
                        root / "Tests" / "InterfaceTypesHarness.c", "-o", interface_binary], check=True)
        InterfaceTypeTests.binary = interface_binary
        background_binary = Path(temp) / "BackgroundExecutionHarness"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library",
                        root / "JustProxy" / "BackgroundExecution.swift",
                        root / "Tests" / "BackgroundExecutionHarness.swift", "-o", background_binary], check=True)
        BackgroundExecutionTests.binary = background_binary
        unittest.main(verbosity=2)
