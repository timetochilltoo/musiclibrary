/// Small state machine used to prevent concurrent startup work while still
/// allowing a later retry when initialization fails.
struct LibraryStartGate: Equatable, Sendable {
    private(set) var hasStarted = false
    private(set) var isStarting = false

    mutating func begin() -> Bool {
        guard !hasStarted, !isStarting else { return false }
        isStarting = true
        return true
    }

    mutating func succeed() {
        isStarting = false
        hasStarted = true
    }

    mutating func fail() {
        isStarting = false
        hasStarted = false
    }
}
