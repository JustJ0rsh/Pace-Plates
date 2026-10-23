import Foundation

/// Keeps delayed platform callbacks bound to the consent that started them.
/// Re-enabling Community never authorizes an older pending submission.
final class CommunityConsent {
    private let lock = NSRecursiveLock()
    private var generation: UInt64 = 0
    private let readEnabled: () -> Bool
    private let writeEnabled: (Bool) -> Void

    init(readEnabled: @escaping () -> Bool, writeEnabled: @escaping (Bool) -> Void) {
        self.readEnabled = readEnabled
        self.writeEnabled = writeEnabled
    }

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return readEnabled()
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        writeEnabled(enabled)
    }

    func performWhenPrepared<Value>(
        prepare: (@escaping (Value) -> Void) -> Void,
        submit: @escaping (Value) -> Void
    ) {
        lock.lock()
        guard readEnabled() else { lock.unlock(); return }
        let consentGeneration = generation
        lock.unlock()

        prepare { [self] value in
            lock.lock()
            defer { lock.unlock() }
            guard readEnabled(), generation == consentGeneration else { return }
            // Keep the check and platform submission in one critical section.
            // The recursive lock allows a synchronous completion to opt out.
            submit(value)
        }
    }
}
