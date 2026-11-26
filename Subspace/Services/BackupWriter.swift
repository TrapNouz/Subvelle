import Foundation
import SubspaceCore

/// Writes backups into a user-chosen folder (typically in iCloud Drive) that the app reaches through a
/// bookmark of the security-scoped URL returned by the folder picker. No iCloud entitlement is needed:
/// the Files provider syncs the folder. Runs off the main actor; all writes are file-coordinated so the
/// iCloud Drive provider never sees a half-written file.
enum BackupWriter {
    /// Stores the latest backup and today's dated copy, prunes old dated copies, and returns a refreshed
    /// bookmark when the stored one was stale.
    static func write(_ data: Data, bookmark: Data, now: Date = .now) throws -> Data? {
        var stale = false
        let folder: URL
        do { folder = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) }
        catch { throw DataError.invalid("The backup folder can no longer be found. Choose it again in Settings.") }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let refreshed = stale ? try bookmarkData(for: folder) : nil
        try coordinatedWrite(data, to: folder.appendingPathComponent(BackupPlan.latestFileName))
        try coordinatedWrite(data, to: folder.appendingPathComponent(BackupPlan.snapshotName(for: now)))
        // Pruning is best effort: a copy that cannot be removed now is retried after the next change.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in BackupPlan.snapshotsToPrune(names) { try? coordinatedDelete(folder.appendingPathComponent(name)) }
        return refreshed
    }
    /// Bookmark for a URL returned by the folder picker; call while its security scope is open.
    static func bookmarkData(for folder: URL) throws -> Data {
        try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    private static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
    private static func coordinatedDelete(_ url: URL) throws {
        var coordinationError: NSError?
        var deleteError: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
            do { try FileManager.default.removeItem(at: target) } catch { deleteError = error }
        }
        if let coordinationError { throw coordinationError }
        if let deleteError { throw deleteError }
    }
}
