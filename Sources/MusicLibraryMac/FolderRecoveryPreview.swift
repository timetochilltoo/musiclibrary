import SwiftUI
import UniformTypeIdentifiers
import MusicApplication
import MusicDomain

/// Session-only inspection. Closing never changes the registered folder.
struct FolderRecoveryPreview: View {
    let root: StorageRoot
    @StateObject private var session: FolderRecoveryPreviewSession
    @Environment(\.dismiss) private var dismiss
    @State private var showsPicker = false
    @State private var pickerError: String?
    #if DEBUG
    private var fixture: FolderRecoveryPreviewFixture?
    private var fileFixture: FolderRecoveryFileFixture?

    init(fileFixture: FolderRecoveryFileFixture) {
        root = fileFixture.root
        self.fileFixture = fileFixture
        _session = StateObject(wrappedValue: fileFixture.session)
    }

    init(fixture: FolderRecoveryPreviewFixture) {
        root = fixture.root
        self.fixture = fixture
        _session = StateObject(wrappedValue: fixture.session)
    }
    #endif

    init(library: LibraryStore, root: StorageRoot) {
        self.root = root
        _session = StateObject(wrappedValue: FolderRecoveryPreviewSession(library: library, rootID: root.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Review Replacement Folder").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("Compare the files referenced by this music folder before deciding what to do next.")
                    .foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            Divider()
            #if DEBUG
            if let fixture { FolderRecoveryFixtureControls(fixture: fixture) }
            if let fileFixture {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DISPOSABLE FIXTURE — real hashing and folder permission, temporary SQLite only").font(.caption.bold())
                    Text("Choose only this directory:").font(.caption)
                    Text(fileFixture.candidate.path).font(.caption.monospaced()).textSelection(.enabled)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary)
            }
            #endif
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox("Registered folder") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.completion?.report.manifest.root.displayName ?? root.displayName).font(.headline)
                            path(session.completion?.report.manifest.root.registeredPath ?? root.lastKnownPath)
                            if let volume = session.completion?.report.manifest.root.volumeIdentifier ?? root.volumeIdentifier {
                                Text("Recorded volume: \(volume)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                    GroupBox("Folder to compare") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let candidate = session.candidateURL { path(candidate.path) }
                            else { Text("Choose the folder containing the same relative file layout.").foregroundStyle(.secondary) }
                            Button(session.candidateURL == nil ? "Choose Folder…" : "Choose Another Folder…", systemImage: "folder") {
                                pickerError = nil
                                showsPicker = true
                            }
                            .disabled(usesSyntheticCandidates)
                            Text("Choosing a folder does not start a check. Verify reads referenced files only and may take time on a NAS.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                    if session.isRunning { progress }
                    if session.phase == .cancelled {
                        Label("Verification cancelled. You can verify again.", systemImage: "stop.circle").foregroundStyle(.secondary)
                    }
                    if let error = pickerError ?? session.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
                    }
                    if let completion = session.completion { results(completion) }
                    Label("Preview only. Your registered folder and catalogue stay unchanged; no files are moved or retagged.", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(20)
            }
            Divider()
            HStack {
                Button("Close") { session.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if session.isRunning {
                    Button("Cancel Verification") { session.cancel() }.disabled(session.phase == .cancelling)
                }
                Button(session.completion == nil ? "Verify References" : "Verify Again", systemImage: "checkmark.shield") {
                    pickerError = nil
                    session.verify()
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.candidateURL == nil || session.isRunning)
                .keyboardShortcut(.defaultAction)
            }.padding(16)
        }
        .frame(minWidth: 600, idealWidth: 740, minHeight: 480, idealHeight: 580)
        .fileImporter(isPresented: $showsPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): pickerError = nil; session.selectCandidate(url)
            case .failure(let error):
                let failure = error as NSError
                if failure.domain != NSCocoaErrorDomain || failure.code != NSUserCancelledError { pickerError = error.localizedDescription }
            }
        }
        .onDisappear { session.cancel() }
    }

    private func path(_ value: String) -> some View {
        Text(value).font(.callout.monospaced()).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usesSyntheticCandidates: Bool {
        #if DEBUG
        fixture != nil
        #else
        false
        #endif
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let update = session.progress, session.phase == .verifying {
                ProgressView(value: Double(update.completedGroups), total: Double(max(update.totalGroups, 1))) {
                    Text("Checked \(update.completedGroups) of \(update.totalGroups) referenced paths")
                }
                Text("\(ByteCountFormatter.string(fromByteCount: update.bytesRead, countStyle: .file)) read").font(.caption).foregroundStyle(.secondary)
                if let relativePath = update.currentRelativePath { path(relativePath) }
            } else {
                ProgressView(progressTitle)
            }
            if session.phase == .cancelling {
                Text("Waiting for the current file operation to stop before releasing folder access. A NAS may take longer to respond.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }

    private var progressTitle: String {
        switch session.phase {
        case .capturing: "Reading catalogue references…"
        case .checkingCatalogue: "Checking whether the catalogue changed…"
        case .cancelling: "Stopping verification…"
        default: "Verifying referenced files…"
        }
    }

    private func results(_ completion: FolderRecoveryPreviewSession.Completion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verification results").font(.headline).accessibilityAddTraits(.isHeader)
            switch completion.freshness {
            case .unchanged:
                Label("Catalogue matched the captured references at completion.", systemImage: "checkmark.circle")
            case .changed:
                Label("Catalogue changed during verification. These results describe the earlier references. Verify again for a new comparison.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case .unavailable(let detail):
                Label("Catalogue could not be rechecked. These results are historical; verify again before relying on them.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(detail).font(.caption).textSelection(.enabled)
            }
            Text("A captured comparison, not a guarantee that files or the catalogue remain unchanged. Matching files do not change this folder's association.")
                .font(.caption).foregroundStyle(.secondary)
            if completion.report.evidence.isEmpty {
                Text("No catalogue references to compare. This does not establish that the selected folder matches.")
            } else {
                Text("\(completion.report.evidence.count) distinct referenced paths · \(completion.report.manifest.references.count) asset references")
                    .font(.subheadline).foregroundStyle(.secondary)
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Self.outcomes, id: \.title) { item in
                        let entries = completion.report.evidence.filter { $0.outcome == item.outcome }
                        if !entries.isEmpty {
                            DisclosureGroup("\(item.title) · \(entries.count)") {
                                ForEach(entries.indices, id: \.self) { index in
                                    evidence(entries[index], title: item.title)
                                    if index != entries.indices.last { Divider() }
                                }
                            }
                        }
                    }
                }
            }
            DisclosureGroup("Comparison details") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resolved candidate path").font(.caption).foregroundStyle(.secondary)
                    path(completion.report.candidate.resolvedPath)
                    Text("Catalogue revision: \(completion.report.manifest.catalogueRevision)").font(.caption)
                    Text("Volume names and folder names alone do not prove a match. Candidate volume identity is not used as content evidence.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
        }
    }

    private func evidence(_ entry: FolderRecoveryVerifier.Evidence, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            path(entry.group.relativePath).accessibilityAddTraits(.isHeader)
            if let detail = entry.detail { Text(detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.group.references.count == 1 ? "1 asset reference" : "\(entry.group.references.count) asset references").font(.caption)
                    ForEach(entry.group.references.indices, id: \.self) { index in
                        let reference = entry.group.references[index]
                        Text("Expected: \(reference.expectedContentHash ?? "No recorded full hash")").font(.caption.monospaced()).textSelection(.enabled)
                            .accessibilityLabel("Expected SHA-256 for reference \(index + 1): \(reference.expectedContentHash ?? "No recorded full hash")")
                    }
                    Text("Read: \(entry.actualContentHash ?? "No full hash read")").font(.caption.monospaced()).textSelection(.enabled)
                        .accessibilityLabel("Computed SHA-256: \(entry.actualContentHash ?? "No full hash read")")
                }
            } label: {
                Text("Hashes and references")
                    .accessibilityLabel("\(title). Hashes and references for \(entry.group.relativePath)")
                    .accessibilityIdentifier("folder-recovery-hashes-\(entry.group.relativePath)")
            }
            .font(.caption)
        }.padding(.vertical, 8).padding(.leading, 10)
    }

    private static let outcomes: [(outcome: FolderRecoveryVerifier.Outcome, title: String)] = [
        (.verified, "Verified"), (.differentContent, "Different content"), (.unverified, "Unverified"),
        (.missing, "Missing"), (.unreadable, "Unreadable"), (.unsafePath, "Unsafe path"),
        (.catalogueConflict, "Catalogue conflict"), (.unstableFile, "Changed during verification")
    ]
}
