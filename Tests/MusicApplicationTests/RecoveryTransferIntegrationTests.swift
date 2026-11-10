import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Isolated recovery transfer integration")
@MainActor
struct RecoveryTransferIntegrationTests {
    @Test("Interrupted archive rollback retains recovery after restoring some originals", arguments: [LibraryStore.RecoveryFixtureRollbackFailure.afterDatabase, .afterArtwork])
    func archiveRollbackInterruption(point: LibraryStore.RecoveryFixtureRollbackFailure) async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = FileManager.default
        let store = try await LibraryStore(recoveryFixtureDirectory: root, failRecoveryInstallation: true, failRecoveryRollbackAt: point)
        let album = try await store.addAlbum(.init(title: "Archived title"))
        let cover = root.appending(path: "Artwork/cover.jpg")
        try manager.createDirectory(at: cover.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2]).write(to: cover)
        let archive = try await store.exportCompleteCatalogueArchive(to: root.appending(path: "Exports"))
        try await store.updateAlbum(album.id, with: .init(title: "Live original"))
        try Data([9, 8]).write(to: cover)
        let audio = root.appending(path: "source-sentinel.flac")
        try Data([4, 5]).write(to: audio)
        let revision = store.catalogueRevision
        var caught: RestoreRecoveryError?
        do { try await store.restoreCompleteCatalogueArchive(from: archive); Issue.record("Expected interrupted rollback") }
        catch { caught = try #require(error as? RestoreRecoveryError) }
        let report = try #require(caught)
        let step = point == .afterDatabase ? "database" : "artwork"
        #expect(report.outcome == .recoveryIncomplete)
        #expect(report.restoreFailure == "Injected recovery installation failure.")
        #expect(report.recoveryFailure == "Injected recovery rollback failure after \(step) restoration.")
        #expect(store.recoveryReviewMessage == report.localizedDescription)
        #expect(!report.localizedDescription.contains("was restored and reopened"))
        #expect(try CompleteCatalogueArchive.verify(at: report.recoveryURL).revision == revision)
        let restoredDatabase = root.appending(path: "MusicLibrary.sqlite")
        try MusicDatabase.verifyStandaloneBackupFile(at: restoredDatabase)
        let original = try MusicDatabase(url: restoredDatabase)
        #expect(try await original.albums().first?.title == "Live original")
        let rollback = try #require(manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("RestoreRollback-") })
        #expect(!manager.fileExists(atPath: rollback.appending(path: CompleteCatalogueArchive.databaseFileName).path))
        if point == .afterDatabase {
            #expect(try Data(contentsOf: cover) == Data([1, 2]))
            #expect(try Data(contentsOf: rollback.appending(path: "Artwork/cover.jpg")) == Data([9, 8]))
        } else {
            #expect(try Data(contentsOf: cover) == Data([9, 8]))
            #expect(!manager.fileExists(atPath: rollback.appending(path: "Artwork").path))
        }
        #expect(try Data(contentsOf: audio) == Data([4, 5]))
        #expect(!store.transferActivity.isBusy)
        do { _ = try await store.addAlbum(.init(title: "Must refuse")); Issue.record("Interrupted rollback accepted edits") } catch {}
        do { try await store.restoreCompleteCatalogueArchive(from: archive); Issue.record("Interrupted rollback accepted restore") } catch {}
        #expect(store.recoveryReviewMessage == report.localizedDescription)
        #expect(try CompleteCatalogueArchive.verify(at: report.recoveryURL).revision == revision)
    }

    @Test("Database rollback interruption retains the original without enabling catalogue edits")
    func databaseRollbackInterruption() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root, failRecoveryInstallation: true, failRecoveryRollbackAt: .afterDatabase)
        let album = try await store.addAlbum(.init(title: "Backed up title"))
        let backup = try await createDatabaseBackup(in: root)
        try await store.updateAlbum(album.id, with: .init(title: "Live original"))
        let cover = root.appending(path: "Artwork/cover.jpg")
        try FileManager.default.createDirectory(at: cover.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([9, 8]).write(to: cover)
        var caught: RestoreRecoveryError?
        do { try await store.restoreMasterBackup(from: backup); Issue.record("Expected interrupted rollback") }
        catch { caught = try #require(error as? RestoreRecoveryError) }
        let report = try #require(caught)
        #expect(report.outcome == .recoveryIncomplete)
        #expect(report.restoreFailure == "Injected recovery installation failure.")
        #expect(report.recoveryFailure == "Injected recovery rollback failure after database restoration.")
        #expect(report.recoveryURL == root.appending(path: "MusicLibrary.sqlite"))
        try MusicDatabase.verifyStandaloneBackupFile(at: report.recoveryURL)
        let original = try MusicDatabase(url: report.recoveryURL)
        #expect(try await original.albums().first?.title == "Live original")
        #expect(try Data(contentsOf: cover) == Data([9, 8]))
        #expect(store.recoveryReviewMessage == report.localizedDescription)
        #expect(!store.transferActivity.isBusy)
        do { _ = try await store.addAlbum(.init(title: "Must refuse")); Issue.record("Interrupted rollback accepted edits") } catch {}
        do { try await store.restoreMasterBackup(from: backup); Issue.record("Interrupted rollback accepted restore") } catch {}
        #expect(store.recoveryReviewMessage == report.localizedDescription)
        try MusicDatabase.verifyStandaloneBackupFile(at: report.recoveryURL)
    }

    @Test("Archive move failure preserves unmoved originals and permits retry", arguments: [LibraryStore.RecoveryFixtureMoveFailure.database, .artwork])
    func archiveOriginalMoveFailure(point: LibraryStore.RecoveryFixtureMoveFailure) async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root, failRecoveryMove: point)
        let album = try await store.addAlbum(.init(title: "Archive before move failure"))
        let cover = root.appending(path: "Artwork/cover.jpg")
        try FileManager.default.createDirectory(at: cover.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2]).write(to: cover)
        let archive = try await store.exportCompleteCatalogueArchive(to: root.appending(path: "Exports"))
        try await store.updateAlbum(album.id, with: .init(title: "Live before move failure"))
        try Data([9, 8]).write(to: cover)
        let audio = root.appending(path: "source-sentinel.flac")
        try Data([4, 5]).write(to: audio)
        let revision = store.catalogueRevision
        do { try await store.restoreCompleteCatalogueArchive(from: archive); Issue.record("Expected move failure") }
        catch {
            let report = try #require(error as? RestoreRecoveryError)
            #expect(report.restoreFailure == "Injected recovery original move failure.")
            #expect(report.outcome == .restoredPreviousCatalogue)
            #expect(try CompleteCatalogueArchive.verify(at: report.recoveryURL).revision == revision)
        }
        #expect(!store.recoveryRequiresReview)
        #expect(!store.transferActivity.isBusy)
        #expect(try Data(contentsOf: audio) == Data([4, 5]))
        guard !store.recoveryRequiresReview else { return }
        try await store.reload()
        #expect(store.catalogueRevision == revision)
        #expect(store.catalogueAlbums.first?.title == "Live before move failure")
        #expect(try Data(contentsOf: cover) == Data([9, 8]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix("RestoreRollback-") })
        try await store.updateAlbum(album.id, with: .init(title: "Writable after move failure"))
        try await store.restoreCompleteCatalogueArchive(from: archive)
        #expect(store.catalogueAlbums.first?.title == "Archive before move failure")
        #expect(try Data(contentsOf: cover) == Data([1, 2]))
    }

    @Test("Database move failure reopens the untouched original and permits retry")
    func databaseOriginalMoveFailure() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root, failRecoveryMove: .database)
        let album = try await store.addAlbum(.init(title: "Backup before move failure"))
        let backup = try await createDatabaseBackup(in: root)
        try await store.updateAlbum(album.id, with: .init(title: "Live before move failure"))
        let revision = store.catalogueRevision
        do { try await store.restoreMasterBackup(from: backup); Issue.record("Expected move failure") }
        catch {
            let report = try #require(error as? RestoreRecoveryError)
            #expect(report.restoreFailure == "Injected recovery original move failure.")
            #expect(report.outcome == .restoredPreviousCatalogue)
        }
        #expect(!store.recoveryRequiresReview)
        #expect(!store.transferActivity.isBusy)
        guard !store.recoveryRequiresReview else { return }
        try await store.reload()
        #expect(store.catalogueRevision == revision)
        #expect(store.catalogueAlbums.first?.title == "Live before move failure")
        try await store.updateAlbum(album.id, with: .init(title: "Writable after move failure"))
        try await store.restoreMasterBackup(from: backup)
        #expect(store.catalogueAlbums.first?.title == "Backup before move failure")
        // Consecutive successful restores must retain separate prior catalogues.
        try await store.restoreMasterBackup(from: backup)
        let retained = try FileManager.default.contentsOfDirectory(at: root.appending(path: "Recovery"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "sqlite" }
        #expect(retained.count == 2)
        for file in retained { try MusicDatabase.verifyStandaloneBackupFile(at: file) }
    }

    @Test("Partial artwork copies restore the original tree or retain verified recovery", arguments: [false, true])
    func partialArtworkCopy(rollbackFails: Bool) async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = FileManager.default
        let store = try await LibraryStore(recoveryFixtureDirectory: root, failRecoveryRollback: rollbackFails, failRecoveryArtworkCopy: true)
        let album = try await store.addAlbum(.init(title: "Archived artwork edition"))
        let artwork = root.appending(path: "Artwork")
        let cover = artwork.appending(path: "a-cover.jpg")
        let back = artwork.appending(path: "z-back.jpg")
        let liveOnly = artwork.appending(path: "live-only.jpg")
        try manager.createDirectory(at: cover.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 512).write(to: cover)
        try Data(repeating: 2, count: 256).write(to: back)
        let archive = try await store.exportCompleteCatalogueArchive(to: root.appending(path: "Exports"))
        try await store.updateAlbum(album.id, with: .init(title: "Live artwork edition"))
        try Data(repeating: 9, count: 512).write(to: cover)
        try manager.removeItem(at: back)
        try Data([7, 8, 9]).write(to: liveOnly)
        let audio = root.appending(path: "source-sentinel.flac")
        try Data([4, 5, 6]).write(to: audio)
        let revision = store.catalogueRevision
        var caught: RestoreRecoveryError?
        do { try await store.restoreCompleteCatalogueArchive(from: archive); Issue.record("Expected partial artwork-copy failure") }
        catch { caught = try #require(error as? RestoreRecoveryError) }
        let report = try #require(caught)
        #expect(report.restoreFailure == "Injected recovery artwork copy failure after a partial file.")
        #expect(try CompleteCatalogueArchive.verify(at: report.recoveryURL).revision == revision)
        #expect(store.transferActivity == LibraryTransferActivity())
        #expect(try Data(contentsOf: audio) == Data([4, 5, 6]))
        if rollbackFails {
            #expect(report.outcome == .recoveryIncomplete)
            #expect(report.recoveryFailure == "Injected recovery rollback failure.")
            #expect(store.recoveryReviewMessage == report.localizedDescription)
            #expect(try Data(contentsOf: cover) == Data(repeating: 1, count: 128))
            #expect(!manager.fileExists(atPath: back.path))
            #expect(!manager.fileExists(atPath: liveOnly.path))
            // Database copy completed before artwork failed, but must remain unavailable.
            try MusicDatabase.verifyStandaloneBackupFile(at: root.appending(path: "MusicLibrary.sqlite"))
            let rollback = try #require(manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("RestoreRollback-") })
            try MusicDatabase.verifyStandaloneBackupFile(at: rollback.appending(path: CompleteCatalogueArchive.databaseFileName))
            let originals = rollback.appending(path: CompleteCatalogueArchive.artworkDirectoryName)
            #expect(try Data(contentsOf: originals.appending(path: "a-cover.jpg")) == Data(repeating: 9, count: 512))
            #expect(try Data(contentsOf: originals.appending(path: "live-only.jpg")) == Data([7, 8, 9]))
            #expect(!manager.fileExists(atPath: originals.appending(path: "z-back.jpg").path))
            do { _ = try await store.addAlbum(.init(title: "Must refuse")); Issue.record("Partial artwork installation accepted edits") } catch {}
        } else {
            #expect(report.outcome == .restoredPreviousCatalogue)
            #expect(!store.recoveryRequiresReview)
            try await store.reload()
            #expect(store.catalogueRevision == revision)
            #expect(store.catalogueAlbums.first?.title == "Live artwork edition")
            #expect(try Data(contentsOf: cover) == Data(repeating: 9, count: 512))
            #expect(try Data(contentsOf: liveOnly) == Data([7, 8, 9]))
            #expect(!manager.fileExists(atPath: back.path))
            #expect(try manager.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix("RestoreRollback-") })
            try await store.updateAlbum(album.id, with: .init(title: "Writable after artwork failure"))
            try await store.restoreCompleteCatalogueArchive(from: archive)
            #expect(store.catalogueAlbums.first?.title == "Archived artwork edition")
            #expect(try Data(contentsOf: cover) == Data(repeating: 1, count: 512))
            #expect(try Data(contentsOf: back) == Data(repeating: 2, count: 256))
            #expect(!manager.fileExists(atPath: liveOnly.path))
            #expect(!store.transferActivity.isBusy)
        }
    }

    @Test("Partial database copies recover or retain originals safely", arguments: [true, false], [true, false])
    func partialDatabaseCopy(archive: Bool, rollbackFails: Bool) async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root, failRecoveryRollback: rollbackFails, failRecoveryDatabaseCopy: true)
        let album = try await store.addAlbum(.init(title: "Archived before partial copy"))
        let artwork = root.appending(path: "Artwork/cover.jpg")
        try FileManager.default.createDirectory(at: artwork.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: artwork)
        let source = archive
            ? try await store.exportCompleteCatalogueArchive(to: root.appending(path: "Exports"))
            : try await createDatabaseBackup(in: root)
        try await store.updateAlbum(album.id, with: .init(title: "Live before partial copy"))
        try Data([9, 8, 7]).write(to: artwork)
        let audio = root.appending(path: "source-sentinel.flac")
        try Data([4, 5, 6]).write(to: audio)
        let revision = store.catalogueRevision
        var caught: RestoreRecoveryError?
        do {
            if archive { try await store.restoreCompleteCatalogueArchive(from: source) }
            else { try await store.restoreMasterBackup(from: source) }
            Issue.record("Expected partial-copy failure")
        } catch { caught = try #require(error as? RestoreRecoveryError) }
        let report = try #require(caught)
        #expect(report.restoreFailure == "Injected recovery database copy failure after 128 bytes.")
        #expect(store.transferActivity == LibraryTransferActivity())
        #expect(try Data(contentsOf: audio) == Data([4, 5, 6]))
        if archive {
            let manifest = try CompleteCatalogueArchive.verify(at: report.recoveryURL)
            #expect(manifest.revision == revision)
        }
        if rollbackFails {
            #expect(report.outcome == .recoveryIncomplete)
            #expect(report.recoveryFailure == "Injected recovery rollback failure.")
            #expect(store.recoveryReviewMessage == report.localizedDescription)
            #expect(try Data(contentsOf: root.appending(path: "MusicLibrary.sqlite")).count == 128)
            if archive {
                let rollback = try #require(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("RestoreRollback-") })
                try MusicDatabase.verifyStandaloneBackupFile(at: rollback.appending(path: CompleteCatalogueArchive.databaseFileName))
                #expect(try Data(contentsOf: rollback.appending(path: CompleteCatalogueArchive.artworkDirectoryName).appending(path: "cover.jpg")) == Data([9, 8, 7]))
            } else {
                try MusicDatabase.verifyStandaloneBackupFile(at: report.recoveryURL)
                #expect(try Data(contentsOf: artwork) == Data([9, 8, 7]))
            }
            do { _ = try await store.addAlbum(.init(title: "Must refuse")); Issue.record("Unresolved catalogue accepted edits") } catch {}
        } else {
            #expect(report.outcome == .restoredPreviousCatalogue)
            #expect(!store.recoveryRequiresReview)
            try await store.reload()
            #expect(store.catalogueRevision == revision)
            #expect(store.catalogueAlbums.first?.title == "Live before partial copy")
            #expect(try Data(contentsOf: artwork) == Data([9, 8, 7]))
            try await store.updateAlbum(album.id, with: .init(title: "Writable after partial copy"))
            if archive { try await store.restoreCompleteCatalogueArchive(from: source) }
            else { try await store.restoreMasterBackup(from: source) }
            #expect(store.catalogueAlbums.first?.title == "Archived before partial copy")
            #expect(try Data(contentsOf: artwork) == (archive ? Data([1, 2, 3]) : Data([9, 8, 7])))
            #expect(!store.transferActivity.isBusy)
        }
    }

    @Test("Complete archive installation failure rolls back catalogue/artwork and permits retry")
    func archiveInstallationRollback() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root, failRecoveryInstallation: true)
        let album = try await store.addAlbum(.init(title: "Archive title"))
        let art = root.appending(path: "Artwork/cover.jpg")
        try FileManager.default.createDirectory(at: art.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: art)
        let archive = try await store.exportCompleteCatalogueArchive(to: root.appending(path: "Exports"))
        try await store.updateAlbum(album.id, with: .init(title: "Live title before failure"))
        try Data([9]).write(to: art)
        let revision = store.catalogueRevision
        do { try await store.restoreCompleteCatalogueArchive(from: archive); Issue.record("Expected injected failure") }
        catch {
            let report = try #require(error as? RestoreRecoveryError)
            #expect(report.outcome == .restoredPreviousCatalogue)
            #expect(report.restoreFailure == "Injected recovery installation failure.")
            #expect(report.localizedDescription.contains("previous catalogue was restored and reopened"))
        }
        try await store.reload()
        #expect(store.catalogueAlbums.first?.title == "Live title before failure")
        #expect(store.catalogueRevision == revision)
        #expect(try Data(contentsOf: art) == Data([9]))
        #expect(!store.transferActivity.isBusy)
        let recovery = root.appending(path: "Recovery/CatalogueArchives/before-archive-restore")
        let saved = try #require(FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil).first)
        _ = try CompleteCatalogueArchive.verify(at: saved)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix("RestoreRollback-") })
        try await store.updateAlbum(album.id, with: .init(title: "Writable after rollback"))
        try await store.restoreCompleteCatalogueArchive(from: archive)
        #expect(store.catalogueAlbums.first?.title == "Archive title")
        #expect(try Data(contentsOf: art) == Data([1]))
        #expect(!store.transferActivity.isBusy)
    }

    @Test("Database installation failure rolls back the live database, leaves artwork intact and permits retry")
    func databaseInstallationRollback() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root, failRecoveryInstallation: true)
        let album = try await store.addAlbum(.init(title: "Backup title"))
        let backup = try await createDatabaseBackup(in: root)
        try await store.updateAlbum(album.id, with: .init(title: "Live database before failure"))
        let art = root.appending(path: "Artwork/current.jpg")
        try FileManager.default.createDirectory(at: art.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([8]).write(to: art)
        let revision = store.catalogueRevision
        do { try await store.restoreMasterBackup(from: backup); Issue.record("Expected injected failure") }
        catch {
            let report = try #require(error as? RestoreRecoveryError)
            #expect(report.outcome == .restoredPreviousCatalogue)
            #expect(report.restoreFailure == "Injected recovery installation failure.")
            #expect(store.masterBackupStatus == report.localizedDescription)
        }
        try await store.reload()
        #expect(store.catalogueAlbums.first?.title == "Live database before failure")
        #expect(store.catalogueRevision == revision)
        #expect(try Data(contentsOf: art) == Data([8]))
        #expect(!store.transferActivity.isBusy)
        try await store.updateAlbum(album.id, with: .init(title: "Writable after rollback"))
        try await store.restoreMasterBackup(from: backup)
        #expect(store.catalogueAlbums.first?.title == "Backup title")
        #expect(try Data(contentsOf: art) == Data([8]))
        #expect(!store.transferActivity.isBusy)
    }

    @Test("Incomplete rollback reports both failures and retained recovery data without claiming recovery", arguments: [true, false])
    func incompleteRecovery(archive: Bool) async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root, failRecoveryInstallation: true, failRecoveryRollback: true)
        let album = try await store.addAlbum(.init(title: "Archived title"))
        let source = archive
            ? try await store.exportCompleteCatalogueArchive(to: root.appending(path: "Exports"))
            : try await createDatabaseBackup(in: root)
        try await store.updateAlbum(album.id, with: .init(title: "Live before failure"))
        do {
            if archive { try await store.restoreCompleteCatalogueArchive(from: source) }
            else { try await store.restoreMasterBackup(from: source) }
            Issue.record("Expected incomplete recovery")
        } catch {
            let report = try #require(error as? RestoreRecoveryError)
            #expect(report.outcome == .recoveryIncomplete)
            #expect(store.recoveryRequiresReview)
            #expect(store.recoveryReviewMessage == report.localizedDescription)
            #expect(report.restoreFailure == "Injected recovery installation failure.")
            #expect(report.recoveryFailure == "Injected recovery rollback failure.")
            #expect(report.localizedDescription.contains("Do not retry"))
            #expect(!report.localizedDescription.contains("was restored and reopened"))
            #expect(archive ? store.catalogueMaintenanceStatus == report.localizedDescription : store.masterBackupStatus == report.localizedDescription)
            if archive { _ = try CompleteCatalogueArchive.verify(at: report.recoveryURL) }
            else { try MusicDatabase.verifyStandaloneBackupFile(at: report.recoveryURL) }
        }
        #expect(!store.transferActivity.isBusy)
        do { _ = try await store.addAlbum(.init(title: "Must refuse while recovery unresolved")); Issue.record("Unresolved catalogue accepted edits") } catch {}
        let review = store.recoveryReviewMessage
        let replacementURL = root.appending(path: "MusicLibrary.sqlite")
        let replacementBytes = try Data(contentsOf: replacementURL)
        do {
            if archive { try await store.restoreCompleteCatalogueArchive(from: source) }
            else { try await store.restoreMasterBackup(from: source) }
            Issue.record("Unresolved recovery accepted another restore")
        } catch {}
        #expect(store.recoveryReviewMessage == review)
        #expect(try Data(contentsOf: replacementURL) == replacementBytes)
    }

    @Test("Reset requires exact confirmation, preserves roots and audio, and verifies complete recovery")
    func resetPreservesRoots() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        try await seedPublishedAlbum(in: root)
        try await store.reload()
        let roots = store.storageRoots
        let revision = store.catalogueRevision
        let audio = root.appending(path: "AudioReferences/synthetic.flac")
        try FileManager.default.createDirectory(at: audio.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sentinel = Data("Disposable source sentinel".utf8)
        try sentinel.write(to: audio)
        let artwork = root.appending(path: "Artwork/cover.jpg")
        try FileManager.default.createDirectory(at: artwork.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: artwork)
        for confirmation in ["reset", " RESET", "RESET ", ""] {
            do { _ = try await store.resetCatalogue(confirmation: confirmation); Issue.record("Invalid reset accepted") } catch {}
        }
        #expect(store.catalogueRevision == revision)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Recovery").path))
        let archive = try await store.resetCatalogue(confirmation: "RESET")
        let manifest = try CompleteCatalogueArchive.verify(at: archive)
        #expect(manifest.revision == revision)
        #expect(manifest.artwork.map(\.fileName) == ["cover.jpg"])
        #expect(store.storageRoots == roots)
        #expect(store.catalogueAlbums.isEmpty)
        #expect(try Data(contentsOf: audio) == sentinel)
        #expect(try FileManager.default.contentsOfDirectory(atPath: artwork.deletingLastPathComponent().path).isEmpty)
        let archived = try MusicDatabase(url: archive.appending(path: CompleteCatalogueArchive.databaseFileName))
        #expect(try await archived.albums().first?.title == "Archived original")
        #expect(!store.transferActivity.isBusy)
    }

    @Test("Database-only restore preserves current artwork/audio and keeps the prior database")
    func databaseRestore() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        let album = try await store.addAlbum(.init(title: "Backed up title"))
        let backup = try await createDatabaseBackup(in: root)
        try await store.updateAlbum(album.id, with: .init(title: "Before restore"))
        let artwork = root.appending(path: "Artwork/current.jpg")
        try FileManager.default.createDirectory(at: artwork.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([9, 8, 7]).write(to: artwork)
        let audio = root.appending(path: "source-sentinel.flac")
        try Data([4, 5]).write(to: audio)
        try await store.restoreMasterBackup(from: backup)
        #expect(store.catalogueAlbums.first?.title == "Backed up title")
        #expect(try Data(contentsOf: artwork) == Data([9, 8, 7]))
        #expect(try Data(contentsOf: audio) == Data([4, 5]))
        let recovery = root.appending(path: "Recovery")
        let saved = try #require(FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "sqlite" }))
        try MusicDatabase.verifyStandaloneBackupFile(at: saved)
        let previous = try MusicDatabase(url: saved)
        #expect(try await previous.albums().first?.title == "Before restore")
        #expect(!store.transferActivity.isBusy)
    }

    @Test("Tampered database backup refuses before recovery or replacement and leaves queue reusable")
    func tamperedDatabaseRestore() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        _ = try await store.addAlbum(.init(title: "Keep live title"))
        let manifestURL = try await createDatabaseBackup(in: root)
        let manifest = try JSONDecoder().decode(MasterBackupManifest.self, from: Data(contentsOf: manifestURL))
        let payload = try MasterBackupArchive.validatedBackupURL(for: manifest, in: manifestURL.deletingLastPathComponent())
        try Data([0]).write(to: payload)
        let revision = store.catalogueRevision
        do { try await store.restoreMasterBackup(from: manifestURL); Issue.record("Tampered backup accepted") } catch {}
        #expect(store.catalogueRevision == revision)
        #expect(store.catalogueAlbums.first?.title == "Keep live title")
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Recovery").path))
        #expect(!store.transferActivity.isBusy)
        _ = try await store.publishSnapshot(to: root.appending(path: "Shared"))
    }

    private func createDatabaseBackup(in root: URL) async throws -> URL {
        let database = try MusicDatabase(url: root.appending(path: "MusicLibrary.sqlite"))
        let destination = root.appending(path: "Database Backups #? fixture")
        let manifest = try await MasterBackupArchive.create(database: database, in: destination)
        let payload = try MasterBackupArchive.validatedBackupURL(for: manifest, in: destination)
        let original = try Data(contentsOf: payload)
        try await MasterBackupArchive.verify(manifest, in: destination)
        #expect(try Data(contentsOf: payload) == original)
        try await MasterBackupArchive.verify(manifest, in: destination)
        return destination.appending(path: manifest.fileName + ".manifest.json")
    }

    @Test("Queued real restore replaces catalogue and artwork before later publication")
    func restoreThenPublish() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        try await seedPublishedAlbum(in: root)
        try await store.reload()
        let album = try #require(store.catalogueAlbums.first)
        let art = root.appending(path: "Artwork/cover.jpg")
        try FileManager.default.createDirectory(at: art.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: art)
        let archive = try await store.exportCompleteCatalogueArchive(to: root.appending(path: "Exports"))
        try await store.updateAlbum(album.id, with: .init(title: "Later correction"))
        try Data([9]).write(to: art)
        var release: CheckedContinuation<Void, Never>?
        let writer = Task { try await store.transferQueue.run(.sharing) {
            await withCheckedContinuation { release = $0 }
        } }
        while release == nil { await Task.yield() }
        let restore = Task { try await store.restoreCompleteCatalogueArchive(from: archive) }
        while !store.transferActivity.waiting.contains(.archiveRestore) { await Task.yield() }
        let destination = root.appending(path: "Shared")
        let publish = Task { try await store.publishSnapshot(to: destination) }
        while store.transferActivity.waiting.count < 2 { await Task.yield() }
        #expect(store.catalogueAlbums.first?.title == "Later correction")
        release?.resume()
        try await writer.value
        try await restore.value
        let manifest = try await publish.value
        #expect(store.catalogueAlbums.first?.title == "Archived original")
        #expect(try Data(contentsOf: art) == Data([1, 2, 3]))
        let json = try String(contentsOf: destination.appending(path: manifest.fileName), encoding: .utf8)
        #expect(json.contains("Archived original") && !json.contains("Later correction"))
        #expect(manifest.revision == store.catalogueRevision)
        #expect(store.transferActivity == LibraryTransferActivity())
        let recovery = root.appending(path: "Recovery/CatalogueArchives/before-archive-restore")
        let saved = try #require(FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil).first)
        _ = try CompleteCatalogueArchive.verify(at: saved)
    }

    private func seedPublishedAlbum(in root: URL) async throws {
        let database = try MusicDatabase(url: root.appending(path: "MusicLibrary.sqlite"))
        let storage = try await database.createStorageRoot(.init(displayName: "Synthetic published root", lastKnownPath: root.appending(path: "AudioReferences").path, bookmarkData: nil, scope: .nasPublished))
        let batch = try await database.createImportBatch(storageRootID: storage.id, sourceDescription: "No audio files")
        try await database.recordImportCandidate(batchID: batch.id, payload: .init(relativePath: "synthetic.flac", fileName: "synthetic.flac", contentTypeIdentifier: "org.xiph.flac", fileSize: 1, modifiedAt: nil))
        let candidate = try #require(await database.importCandidates(batchID: batch.id).first)
        try await database.saveEmbeddedMetadata(.init(title: "Synthetic track", albumTitle: "Archived original", artist: nil, albumArtist: nil, discNumber: 1, trackNumber: 1, durationMilliseconds: 1000, rawTags: [:]), for: candidate.id)
        try await database.rebuildImportReleaseProposals(batchID: batch.id, drafts: [.init(title: "Archived original", artist: nil, discCount: 1, confidence: 1, candidateIDs: [candidate.id])])
        let proposal = try #require(await database.importReleaseProposals(batchID: batch.id).first)
        _ = try await database.confirmImportReleaseProposal(proposal.id)
    }

    @Test("Tampered restore refuses replacement and releases the queue for publication")
    func tamperThenPublish() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        _ = try await store.addAlbum(.init(title: "Live catalogue"))
        let archive = try await store.exportCompleteCatalogueArchive(to: root.appending(path: "Exports"))
        try Data([0]).write(to: archive.appending(path: CompleteCatalogueArchive.databaseFileName))
        let revision = store.catalogueRevision
        do { try await store.restoreCompleteCatalogueArchive(from: archive); Issue.record("Tampered archive accepted") } catch {}
        let destination = root.appending(path: "Shared")
        let manifest = try await store.publishSnapshot(to: destination)
        #expect(manifest.revision == revision)
        #expect(store.catalogueAlbums.first?.title == "Live catalogue")
        #expect(!store.transferActivity.isBusy)
    }

    @Test("Fixture refuses outside paths and persistent sharing configuration")
    func boundary() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        do { try store.setSnapshotDestination(root); Issue.record("Fixture preferences enabled") } catch {}
        do { _ = try await store.publishSnapshot(to: root.deletingLastPathComponent()); Issue.record("Outside path accepted") } catch {}
        do { _ = try await LibraryStore(recoveryFixtureDirectory: FileManager.default.temporaryDirectory); Issue.record("Temporary root accepted") } catch {}
        #expect(!store.transferActivity.isBusy)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "RecoveryIntegration-\(UUID().uuidString)")
    }
}
