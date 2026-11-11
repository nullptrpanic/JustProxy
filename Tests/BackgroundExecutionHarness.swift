import Foundation

@main
struct BackgroundExecutionHarness {
    @MainActor
    static func main() {
        var starts = 0
        var ended: [Int] = []
        var expirations: [@MainActor @Sendable () -> Void] = []
        let scenario = CommandLine.arguments.dropFirst().first ?? ""
        var execution: BackgroundExecution? = BackgroundExecution(
            beginTask: { expiration in
                starts += 1
                expirations.append(expiration)
                if scenario == "unavailable" { return nil }
                if scenario == "immediate-expiration" { expiration() }
                return starts
            },
            endTask: { ended.append($0) }
        )

        switch scenario {
        case "stop":
            execution!.begin()
            execution!.begin()
            execution!.end()
            execution!.end()
        case "expiration":
            execution!.begin()
            if let expire = expirations.first { expire() }
        case "renew":
            execution!.begin()
            let oldExpiration = expirations.first
            execution!.renew()
            oldExpiration?()
            print(ended.map(String.init).joined(separator: ","))
            execution!.end()
        case "unavailable", "immediate-expiration":
            execution!.begin()
            execution!.end()
        case "release":
            execution!.begin()
            execution = nil
        default:
            fatalError("Unknown scenario")
        }
        print(starts)
        print(ended.map(String.init).joined(separator: ","))
    }
}
