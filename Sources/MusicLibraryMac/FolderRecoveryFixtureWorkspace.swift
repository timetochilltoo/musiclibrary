#if DEBUG
import SwiftUI
import MusicApplication

struct FolderRecoveryFixtureWorkspace: View {
    @State private var fixture: FolderRecoveryPreviewFixture?
    @State private var failure: String?
    @State private var showsPreview = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Synthetic folder recovery preview").font(.title2.bold())
            Text("Temporary folders only. No catalogue, candidate-file reads or real permission grants.")
            if let fixture {
                Button("Open Synthetic Preview") {
                    fixture.session.selectCandidate(nil)
                    showsPreview = true
                }
            }
            if let failure { Text(failure).foregroundStyle(.red) }
        }
        .padding(24).frame(width: 980, height: 640)
        .task {
            guard fixture == nil, failure == nil else { return }
            do { fixture = try FolderRecoveryPreviewFixture.make(); showsPreview = true }
            catch { failure = error.localizedDescription }
        }
        .sheet(isPresented: $showsPreview, onDismiss: { fixture?.close() }) {
            if let fixture { FolderRecoveryPreview(fixture: fixture) }
        }
        .onDisappear { fixture?.close() }
    }
}

struct FolderRecoveryFixtureControls: View {
    let fixture: FolderRecoveryPreviewFixture
    @ObservedObject private var control: FolderRecoveryPreviewFixture.Control

    init(fixture: FolderRecoveryPreviewFixture) {
        self.fixture = fixture
        _control = ObservedObject(wrappedValue: fixture.control)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SYNTHETIC — no catalogue or file reads").font(.caption.bold())
            Picker("Scenario for next verification", selection: $control.mode) {
                ForEach(FolderRecoveryPreviewFixture.Mode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }.pickerStyle(.menu)
            HStack {
                Button("Candidate A") { fixture.session.selectCandidate(fixture.candidateA) }
                Button("Candidate B") { fixture.session.selectCandidate(fixture.candidateB) }
                Button("Advance Progress") { control.advance() }.disabled(!control.waiting)
                Button("Release Worker") { control.finishWorker() }.disabled(!control.waiting)
            }
            Text("Access starts: \(control.starts) · releases: \(control.releases) · peak concurrent: \(control.peakAccess)")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary)
    }
}
#endif
