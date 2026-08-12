import Testing
@testable import MusicApplication

@Suite("Library startup")
struct LibraryStartGateTests {
    @Test("Startup blocks concurrent work and permits retry after failure")
    func retryAfterFailure() {
        var gate = LibraryStartGate()

        let firstBegin = gate.begin()
        #expect(firstBegin)
        let concurrentBegin = gate.begin()
        #expect(!concurrentBegin)
        #expect(gate.isStarting)

        gate.fail()
        #expect(!gate.hasStarted)
        #expect(!gate.isStarting)
        let retryBegin = gate.begin()
        #expect(retryBegin)

        gate.succeed()
        #expect(gate.hasStarted)
        #expect(!gate.isStarting)
        let startedBegin = gate.begin()
        #expect(!startedBegin)
    }
}
