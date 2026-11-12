#if DEBUG
import SwiftUI
import MusicApplication

struct FolderRecoveryFileFixtureWorkspace: View {
    @State private var fixture: FolderRecoveryFileFixture?
    @State private var failure: String?
    @State private var integrity: String?
    @State private var showsPreview = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Disposable real-file verification").font(.title2.bold())
            Text("Temporary SQLite and seeded bytes only. Uses the real folder picker, security scope and verifier.")
            if let fixture {
                Text(fixture.candidate.path).font(.callout.monospaced()).textSelection(.enabled)
                Button("Open Real-File Preview") {
                    fixture.session.selectCandidate(nil)
                    showsPreview = true
                }
                Button("Check Fixture Integrity") {
                    Task {
                        do { integrity = try await fixture.checkIntegrity() }
                        catch { integrity = error.localizedDescription }
                    }
                }
            }
            if let integrity { Text(integrity).textSelection(.enabled) }
            if let failure { Text(failure).foregroundStyle(.red) }
        }
        .padding(24).frame(width: 980, height: 640)
        .task {
            guard fixture == nil, failure == nil else { return }
            do { fixture = try await FolderRecoveryFileFixture.make(); showsPreview = true }
            catch { failure = error.localizedDescription }
        }
        .sheet(isPresented: $showsPreview, onDismiss: { fixture?.close() }) {
            if let fixture { FolderRecoveryPreview(fileFixture: fixture) }
        }
        .onDisappear { fixture?.close() }
    }
}
#endif
