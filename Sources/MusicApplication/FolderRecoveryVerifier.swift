import CryptoKit
import Darwin
import Foundation
import MusicDomain

public enum FolderRecoveryVerificationError: Error, LocalizedError, Equatable, Sendable {
    case invalidCandidateRoot
    case candidateRootChanged

    public var errorDescription: String? {
        switch self {
        case .invalidCandidateRoot: "Choose an accessible candidate directory. No catalogue association was changed."
        case .candidateRootChanged: "The selected directory changed during verification. Choose it again and retry."
        }
    }
}

/// Explicit, read-only verification. The caller owns any required security scope.
/// Reports are captured evidence, never permission to change a root association.
public enum FolderRecoveryVerifier {
    public enum Outcome: Equatable, Sendable {
        case verified, differentContent, unverified, missing, unreadable, unsafePath, catalogueConflict, unstableFile
    }
    public struct Evidence: Equatable, Sendable {
        public let group: FolderRecoveryReferencePlan.Group
        public let outcome: Outcome
        public let actualContentHash: String?
        public let detail: String?
    }
    public struct Progress: Equatable, Sendable {
        public let completedGroups: Int
        public let totalGroups: Int
        public let currentRelativePath: String?
        public let bytesRead: Int64
    }
    public struct CandidateIdentity: Equatable, Sendable {
        public let selectedPath: String
        public let resolvedPath: String
        public let device: Int64
        public let inode: UInt64
    }
    public struct Report: Equatable, Sendable {
        public let manifest: FolderRecoveryManifest
        public let candidate: CandidateIdentity
        public let evidence: [Evidence]
    }

    public static func verify(
        _ plan: FolderRecoveryReferencePlan,
        candidateRoot: URL,
        onProgress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async throws -> Report {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try verifySynchronously(plan, candidateRoot: candidateRoot, onProgress: onProgress)
        }
        return try await withTaskCancellationHandler {
            let report = try await worker.value
            try Task.checkCancellation()
            return report
        } onCancel: { worker.cancel() }
    }

    private static func verifySynchronously(_ plan: FolderRecoveryReferencePlan, candidateRoot: URL,
                                            onProgress: @Sendable (Progress) -> Void) throws -> Report {
        try Task.checkCancellation()
        guard candidateRoot.isFileURL, !candidateRoot.path.contains("\0") else { throw FolderRecoveryVerificationError.invalidCandidateRoot }
        guard let canonical = resolvedPath(candidateRoot.standardizedFileURL.path) else { throw FolderRecoveryVerificationError.invalidCandidateRoot }
        var rootInfo = stat()
        guard lstat(canonical, &rootInfo) == 0, kind(rootInfo) == mode_t(S_IFDIR) else {
            throw FolderRecoveryVerificationError.invalidCandidateRoot
        }
        // The canonical path must contain no symlink even if a path component is
        // substituted after resolution. Relative reads stay anchored to this fd.
        let fd = Darwin.open(canonical, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard fd >= 0 else { throw FolderRecoveryVerificationError.invalidCandidateRoot }
        let root = Descriptor(fd)
        defer { withExtendedLifetime(root) {} }
        var opened = stat()
        guard fstat(root.value, &opened) == 0, sameIdentity(rootInfo, opened) else {
            throw FolderRecoveryVerificationError.candidateRootChanged
        }
        let identity = CandidateIdentity(selectedPath: candidateRoot.standardizedFileURL.path,
            resolvedPath: canonical, device: Int64(opened.st_dev), inode: UInt64(opened.st_ino))
        var results: [Evidence] = []
        var bytesRead: Int64 = 0
        for group in plan.groups {
            try Task.checkCancellation()
            try checkRoot(candidateRoot, canonical: canonical, expected: opened)
            onProgress(.init(completedGroups: results.count, totalGroups: plan.groups.count,
                             currentRelativePath: group.relativePath, bytesRead: bytesRead))
            try Task.checkCancellation()
            let evidence: Evidence
            switch group.eligibility {
            case .unsafePath:
                evidence = .init(group: group, outcome: .unsafePath, actualContentHash: nil, detail: "Unsafe relative path; no file was opened.")
            case .unverified:
                evidence = .init(group: group, outcome: .unverified, actualContentHash: nil, detail: "A valid recorded full hash is required; no file was opened.")
            case .conflictingHashes:
                evidence = .init(group: group, outcome: .catalogueConflict, actualContentHash: nil, detail: "Recorded hashes disagree; no file was opened.")
            case .readyToVerify:
                do {
                    let hash = try hashFile(group.relativePath, root: root.value) { count in
                        let (updated, overflow) = bytesRead.addingReportingOverflow(Int64(count))
                        guard !overflow else { throw FileFailure(outcome: .unreadable, detail: "Read counter overflow.") }
                        bytesRead = updated
                        onProgress(.init(completedGroups: results.count, totalGroups: plan.groups.count,
                                         currentRelativePath: group.relativePath, bytesRead: bytesRead))
                    }
                    evidence = .init(group: group, outcome: hash == group.expectedContentHash ? .verified : .differentContent,
                                     actualContentHash: hash, detail: nil)
                } catch is CancellationError { throw CancellationError() }
                catch let failure as FileFailure {
                    evidence = .init(group: group, outcome: failure.outcome, actualContentHash: nil, detail: failure.detail)
                }
            }
            try Task.checkCancellation()
            try checkRoot(candidateRoot, canonical: canonical, expected: opened)
            results.append(evidence)
            onProgress(.init(completedGroups: results.count, totalGroups: plan.groups.count,
                             currentRelativePath: nil, bytesRead: bytesRead))
        }
        try Task.checkCancellation()
        try checkRoot(candidateRoot, canonical: canonical, expected: opened)
        return .init(manifest: plan.manifest, candidate: identity, evidence: results)
    }

    private static func hashFile(_ path: String, root: Int32, onChunk: (Int) throws -> Void) throws -> String {
        let file = try openRelativeFile(path, root: root)
        defer { withExtendedLifetime(file) {} }
        let before = try stamp(file.value)
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 256 * 1024)
        var countRead: Int64 = 0
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file.value, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw systemFailure(errno)
            }
            if count == 0 { break }
            let (updated, overflow) = countRead.addingReportingOverflow(Int64(count))
            guard !overflow else { throw FileFailure(outcome: .unreadable, detail: "File size overflow.") }
            countRead = updated
            hasher.update(data: Data(buffer.prefix(count)))
            try onChunk(count)
            try Task.checkCancellation()
        }
        guard try stamp(file.value) == before, countRead == before.size else { throw unstable() }
        // Re-walk from the root fd to catch replacement/rename of any component.
        do {
            let current = try openRelativeFile(path, root: root)
            guard try withExtendedLifetime(current, { try stamp($0.value) }) == before else { throw unstable() }
        } catch is CancellationError { throw CancellationError() }
        catch { throw unstable() }
        try Task.checkCancellation()
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func openRelativeFile(_ path: String, root: Int32) throws -> Descriptor {
        try Task.checkCancellation()
        // Only preflight-ready paths reach here; each component is still checked
        // without following symlinks, including links that stay inside the root.
        let components = path.split(separator: "/").map(String.init)
        guard let name = components.last else { throw FileFailure(outcome: .unsafePath, detail: "Empty relative path.") }
        var parent = root
        var heldDirectory: Descriptor?
        for component in components.dropLast() {
            try Task.checkCancellation()
            let directory = try withExtendedLifetime(heldDirectory) {
                try rejectSymlink(parent: parent, name: component)
                let fd = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard fd >= 0 else { throw systemFailure(errno) }
                return Descriptor(fd)
            }
            parent = directory.value
            heldDirectory = directory
        }
        // Keep the last directory alive through the final open.
        return try withExtendedLifetime(heldDirectory) {
            try Task.checkCancellation()
            try rejectSymlink(parent: parent, name: name)
            let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { throw systemFailure(errno) }
            let file = Descriptor(fd)
            _ = try stamp(file.value)
            return file
        }
    }

    private static func rejectSymlink(parent: Int32, name: String) throws {
        var info = stat()
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw systemFailure(errno) }
        if kind(info) == mode_t(S_IFLNK) {
            throw FileFailure(outcome: .unsafePath, detail: "Symbolic links are not followed during verification.")
        }
    }

    private struct FileStamp: Equatable {
        let device: Int64, inode: UInt64, size: Int64
        let modifiedSeconds: Int, modifiedNanos: Int, changedSeconds: Int, changedNanos: Int
    }
    private static func stamp(_ fd: Int32) throws -> FileStamp {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw systemFailure(errno) }
        guard kind(info) == mode_t(S_IFREG), info.st_size >= 0 else {
            throw FileFailure(outcome: .unreadable, detail: "The referenced path is not a regular file.")
        }
        return .init(device: Int64(info.st_dev), inode: UInt64(info.st_ino), size: info.st_size,
            modifiedSeconds: info.st_mtimespec.tv_sec, modifiedNanos: info.st_mtimespec.tv_nsec,
            changedSeconds: info.st_ctimespec.tv_sec, changedNanos: info.st_ctimespec.tv_nsec)
    }
    private static func checkRoot(_ selected: URL, canonical: String, expected: stat) throws {
        try Task.checkCancellation()
        var info = stat()
        guard let current = resolvedPath(selected.standardizedFileURL.path), current == canonical, lstat(current, &info) == 0,
              kind(info) == mode_t(S_IFDIR), sameIdentity(info, expected) else {
            throw FolderRecoveryVerificationError.candidateRootChanged
        }
    }
    private static func resolvedPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
    private static func kind(_ info: stat) -> mode_t { info.st_mode & mode_t(S_IFMT) }
    private static func sameIdentity(_ lhs: stat, _ rhs: stat) -> Bool { lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino }
    private static func unstable() -> FileFailure { .init(outcome: .unstableFile, detail: "The file or its path changed during verification. Retry with a stable file.") }
    private static func systemFailure(_ code: Int32) -> FileFailure {
        .init(outcome: code == ENOENT ? .missing : (code == ELOOP ? .unsafePath : .unreadable), detail: String(cString: strerror(code)))
    }
    private struct FileFailure: Error {
        let outcome: Outcome
        let detail: String
    }
    private final class Descriptor {
        let value: Int32
        init(_ value: Int32) { self.value = value }
        deinit { Darwin.close(value) }
    }
}
