import Foundation

/// Boundary-aware path checks used whenever a user-selected file or folder is
/// interpreted relative to a registered music root. String prefixes alone are
/// not sufficient: `Music-old` must not match `Music`, and a symlink inside a
/// root must not be allowed to resolve outside it.
enum RegisteredPathSecurity {
    static func resolvedURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func contains(_ candidateURL: URL, within rootURL: URL) -> Bool {
        let root = resolvedURL(rootURL).path
        let candidate = resolvedURL(candidateURL).path
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    static func relativePath(of candidateURL: URL, within rootURL: URL) -> String? {
        guard contains(candidateURL, within: rootURL) else { return nil }
        let root = rootURL.standardizedFileURL.path
        let candidate = candidateURL.standardizedFileURL.path
        guard candidate != root else { return "" }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard candidate.hasPrefix(prefix) else { return nil }
        return String(candidate.dropFirst(prefix.count))
    }

    /// CUE `FILE` values are relative references. Reject values which could
    /// escape the CUE directory before they are resolved against a root.
    static func isUnsafeRelativeReference(_ value: String) -> Bool {
        guard !value.isEmpty, !value.unicodeScalars.contains(where: { $0.value == 0 }) else { return true }
        if value.hasPrefix("/") || value.hasPrefix("~") { return true }
        let components = value.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        return components.contains { $0 == ".." }
    }
}
