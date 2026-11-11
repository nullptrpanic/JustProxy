import Darwin
import Foundation

@main
struct HTTPBodyHarness {
    static func main() throws {
        switch CommandLine.arguments[1] {
        case "stream":
            let length = UInt64(CommandLine.arguments[2])! * 1024 * 1024
            var body = HTTPBody(.fixed(length))
            let chunk = Data(repeating: 65, count: 32 * 1024)
            var received = 0
            for _ in 0..<(length / UInt64(chunk.count)) {
                received += try body.consume(chunk, eof: false).count
            }
            var usage = rusage()
            guard getrusage(RUSAGE_SELF, &usage) == 0 else { fatalError("getrusage failed") }
            print(received, body.finished, usage.ru_maxrss)
        case "fragments":
            var body = HTTPBody(.fixed(5))
            print(try body.consume(Data(), eof: false).count, body.finished)
            print(String(decoding: try body.consume(Data("ab".utf8), eof: false), as: UTF8.self), body.finished)
            let slice = Data("prefixcdeNEXT".utf8).dropFirst(6)
            print(String(decoding: try body.consume(slice, eof: true), as: UTF8.self), body.finished)
            print(try body.consume(Data("ignored".utf8), eof: true).count, body.finished)
        case "early-eof":
            var body = HTTPBody(.fixed(8))
            do {
                _ = try body.consume(Data("short".utf8), eof: true)
                print("accepted")
            } catch HTTPMessageError.malformed {
                print("malformed")
            }
        default:
            fatalError("Unknown scenario")
        }
    }
}
