@MainActor
final class BackgroundExecution {
    private let beginTask: (@escaping @MainActor @Sendable () -> Void) -> Int?
    private let endTask: (Int) -> Void
    private var identifier: Int?
    private var generation: UInt = 0

    init(
        beginTask: @escaping (@escaping @MainActor @Sendable () -> Void) -> Int?,
        endTask: @escaping (Int) -> Void
    ) {
        self.beginTask = beginTask
        self.endTask = endTask
    }

    deinit {
        if let identifier { endTask(identifier) }
    }

    func begin() {
        guard identifier == nil else { return }
        generation += 1
        let requestGeneration = generation
        let started = beginTask { [weak self] in
            guard let self, self.generation == requestGeneration else { return }
            self.end()
        }
        if generation == requestGeneration {
            identifier = started
        } else if let started {
            // Expiration can arrive before the platform returns the task identifier.
            endTask(started)
        }
    }

    func end() {
        generation += 1
        guard let identifier else { return }
        self.identifier = nil
        endTask(identifier)
    }

    func renew() {
        end()
        begin()
    }
}
