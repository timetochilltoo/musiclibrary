import Foundation
import Testing
@testable import MusicApplication

@Suite("Catalogue admission lifecycle", .timeLimit(.minutes(1)))
@MainActor
struct CatalogueAdmissionTests {
    @Test("Maintenance drains shared users and allows their explicit nested context")
    func drain() async throws {
        let admission = CatalogueAdmission()
        let a = Gate(), b = Gate(), maintenance = Gate()
        defer { a.open(); b.open(); maintenance.open() }
        let first = Task {
            try await admission.withOperation { context in
                await a.hold()
                try await admission.withOperation(using: context) { nested in
                    #expect(nested == context && admission.activeOperationCount == 2)
                }
                return context
            }
        }
        let second = Task { try await admission.withOperation { _ in await b.hold() } }
        try await until { a.started && b.started }
        #expect(admission.phase == .open && admission.activeOperationCount == 2)
        let exclusive = Task { try await admission.withMaintenance { context in
            #expect(admission.phase == .exclusive && admission.activeOperationCount == 0)
            try admission.validate(context)
            await maintenance.hold()
        } }
        try await until { admission.phase == .draining }
        await refuses(admission, failure: .maintenancePending)
        a.open()
        let ended = try await first.value
        #expect(throws: CatalogueAdmission.Failure.invalidContext) { try admission.validate(ended) }
        #expect(admission.phase == .draining && admission.activeOperationCount == 1 && !maintenance.started)
        b.open(); try await second.value
        try await until { maintenance.started }
        await refuses(admission, failure: .maintenancePending)
        maintenance.open(); try await exclusive.value
        #expect(admission.phase == .open && admission.activeOperationCount == 0)
    }

    @Test("Queued maintenance is FIFO with no ordinary admission gap; cancelled middle waiter is skipped")
    func fairness() async throws {
        let admission = CatalogueAdmission()
        let firstGate = Gate(), lastGate = Gate()
        defer { firstGate.open(); lastGate.open() }
        let events = Events()
        let first = Task { try await admission.withMaintenance { _ in events.values.append(1); await firstGate.hold() } }
        try await until { firstGate.started }
        let middle = Task { try await admission.withMaintenance { _ in events.values.append(2) } }
        try await until { admission.waitingMaintenanceCount == 1 }
        let last = Task { try await admission.withMaintenance { _ in events.values.append(3); await lastGate.hold() } }
        try await until { admission.waitingMaintenanceCount == 2 }
        let fourth = Task { try await admission.withMaintenance { _ in events.values.append(4) } }
        try await until { admission.waitingMaintenanceCount == 3 }
        middle.cancel()
        await cancelled(middle)
        #expect(admission.phase == .exclusive && admission.waitingMaintenanceCount == 2)
        firstGate.open(); try await first.value
        await refuses(admission, failure: .maintenancePending)
        try await until { lastGate.started }
        #expect(events.values == [1, 3])
        lastGate.open(); try await last.value
        try await fourth.value
        #expect(events.values == [1, 3, 4])
        #expect(admission.phase == .open && admission.waitingMaintenanceCount == 0)
    }

    @Test("Cancelling a draining reservation preserves users and any queued successor", arguments: [false, true])
    func cancelDraining(keepSuccessor: Bool) async throws {
        let admission = CatalogueAdmission(), gate = Gate()
        defer { gate.open() }
        let owner = Task { try await admission.withOperation { context in
            await gate.hold()
            try admission.validate(context)
            #expect(!Task.isCancelled)
        } }
        try await until { gate.started }
        let waiter = Task { try await admission.withMaintenance { _ in _ = Issue.record("Cancelled maintenance entered") } }
        try await until { admission.phase == .draining }
        let successor: Task<Void, any Error>? = keepSuccessor ? Task { try await admission.withMaintenance { _ in } } : nil
        if keepSuccessor { try await until { admission.waitingMaintenanceCount == 2 } }
        waiter.cancel(); await cancelled(waiter)
        #expect(admission.activeOperationCount == 1)
        if keepSuccessor {
            #expect(admission.phase == .draining && admission.waitingMaintenanceCount == 1)
            await refuses(admission, failure: .maintenancePending)
        } else {
            #expect(admission.phase == .open)
            try await admission.withOperation { _ in #expect(admission.activeOperationCount == 2) }
        }
        gate.open(); try await owner.value
        try await successor?.value
        #expect(admission.activeOperationCount == 0 && admission.phase == .open)
    }

    @Test("Cancellation racing with drain/grant never enters a cancelled reservation")
    func cancelGrant() async throws {
        for _ in 0..<20 {
            let admission = CatalogueAdmission(), gate = Gate()
            defer { gate.open() }
            let owner = Task { try await admission.withOperation { _ in await gate.hold() } }
            try await until { gate.started }
            let waiter = Task { try await admission.withMaintenance { _ in _ = Issue.record("Cancelled reservation entered") } }
            try await until { admission.phase == .draining }
            // Cancel sets the flag synchronously; the handler and final lease
            // release can then race in either order on the main actor.
            waiter.cancel(); gate.open()
            try await owner.value
            await cancelled(waiter)
            #expect(admission.phase == .open && admission.waitingMaintenanceCount == 0)
            try await admission.withMaintenance { _ in }
        }
    }

    @Test("Running cancellation retains ownership until an uncooperative body drains", arguments: [false, true])
    func cancelRunning(maintenance: Bool) async throws {
        let admission = CatalogueAdmission(), held = Gate(), next = Gate()
        defer { held.open(); next.open() }
        let body: @MainActor (CatalogueAdmission.Context) async throws -> Bool = { context in
            let worker = Task.detached { await held.hold(); return Task.isCancelled }
            let workerWasCancelled = await worker.value
            #expect(!workerWasCancelled)
            try admission.validate(context)
            return Task.isCancelled
        }
        let owner = Task {
            if maintenance { return try await admission.withMaintenance(body) }
            return try await admission.withOperation(body)
        }
        try await until { held.started }
        let waiter = Task { try await admission.withMaintenance { _ in await next.hold() } }
        try await until { admission.waitingMaintenanceCount == 1 }
        owner.cancel()
        #expect(!next.started && admission.phase == (maintenance ? .exclusive : .draining))
        await refuses(admission, failure: .maintenancePending)
        held.open()
        #expect(try await owner.value)
        try await until { next.started }
        next.open(); try await waiter.value
        #expect(admission.phase == .open && admission.activeOperationCount == 0)
    }

    @Test("Thrown bodies release ownership and allow subsequent work")
    func failures() async throws {
        let admission = CatalogueAdmission()
        for maintenance in [false, true] {
            let body: @MainActor (CatalogueAdmission.Context) async throws -> Void = { _ in throw Harness.expected }
            do {
                if maintenance { try await admission.withMaintenance(body) }
                else { try await admission.withOperation(body) }
                Issue.record("Expected body failure")
            } catch { #expect(error as? Harness == .expected) }
            #expect(admission.phase == .open && admission.activeOperationCount == 0)
        }
        #expect(try await admission.withOperation { _ in 7 } == 7)
        #expect(try await admission.withMaintenance { _ in 8 } == 8)
    }

    @Test("Contexts cannot cross coordinators, outlive a scope or give ordinary work review authority")
    func contexts() async throws {
        let admission = CatalogueAdmission(), other = CatalogueAdmission()
        let ended = try await admission.withOperation { context in
            #expect(throws: CatalogueAdmission.Failure.invalidContext) { try other.validate(context) }
            #expect(throws: CatalogueAdmission.Failure.invalidContext) { try admission.requireReview(using: context) }
            do { try await other.withOperation(using: context) { _ in _ = Issue.record("Foreign context admitted") } }
            catch { #expect(error as? CatalogueAdmission.Failure == .invalidContext) }
            return context
        }
        do { try await admission.withOperation(using: ended) { _ in _ = Issue.record("Expired context admitted") } }
        catch { #expect(error as? CatalogueAdmission.Failure == .invalidContext) }
        let exclusive = try await admission.withMaintenance { context in
            try await admission.withOperation(using: context) { nested in
                #expect(nested == context && admission.activeOperationCount == 0)
                try admission.validate(nested)
            }
            return context
        }
        #expect(throws: CatalogueAdmission.Failure.invalidContext) { try admission.validate(exclusive) }
        #expect(admission.phase == .open)
    }

    @Test("Only the exclusive owner can fail closed; queued and new work are refused")
    func review() async throws {
        let admission = CatalogueAdmission(), trigger = Gate(), cleanup = Gate()
        defer { trigger.open(); cleanup.open() }
        let owner = Task { try await admission.withMaintenance { context in
            await trigger.hold()
            try admission.requireReview(using: context)
            try await admission.withOperation(using: context) { _ in await cleanup.hold() }
        } }
        try await until { trigger.started }
        let waiting = Task { try await admission.withMaintenance { _ in _ = Issue.record("Review-required waiter ran") } }
        try await until { admission.waitingMaintenanceCount == 1 }
        trigger.open()
        do { try await waiting.value; Issue.record("Expected review refusal") }
        catch { #expect(error as? CatalogueAdmission.Failure == .reviewRequired) }
        try await until { cleanup.started }
        await refuses(admission, failure: .reviewRequired)
        do { try await admission.withMaintenance { _ in _ = Issue.record("Review-required admission ran") } }
        catch { #expect(error as? CatalogueAdmission.Failure == .reviewRequired) }
        cleanup.open(); try await owner.value
        #expect(admission.phase == .reviewRequired && admission.activeOperationCount == 0 && admission.waitingMaintenanceCount == 0)
    }

    @Test("Pre-cancelled requests do not acquire either kind of ownership", arguments: [false, true])
    func preCancelled(maintenance: Bool) async throws {
        let admission = CatalogueAdmission()
        let request = Task {
            if maintenance { try await admission.withMaintenance { _ in _ = Issue.record("Pre-cancelled maintenance ran") } }
            else { try await admission.withOperation { _ in _ = Issue.record("Pre-cancelled operation ran") } }
        }
        request.cancel(); await cancelled(request)
        #expect(admission.phase == .open && admission.activeOperationCount == 0 && admission.waitingMaintenanceCount == 0)
    }

    private func refuses(_ admission: CatalogueAdmission, failure: CatalogueAdmission.Failure) async {
        do { try await admission.withOperation { _ in _ = Issue.record("Closed admission accepted ordinary work") } }
        catch { #expect(error as? CatalogueAdmission.Failure == failure) }
    }
    private func cancelled(_ task: Task<Void, any Error>) async {
        do { try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
    }
    private func until(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw Harness.timeout }
            await Task.yield()
        }
    }
    private enum Harness: Error { case expected, timeout }
    @MainActor private final class Events { var values: [Int] = [] }
    @MainActor private final class Gate {
        var started = false
        private var isOpen = false
        private var continuation: CheckedContinuation<Void, Never>?
        func hold() async {
            guard !isOpen else { return }
            await withCheckedContinuation { continuation = $0; started = true }
        }
        func open() { isOpen = true; let held = continuation; continuation = nil; held?.resume() }
    }
}
