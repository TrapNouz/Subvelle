import Foundation

/// File naming, retention and freshness rules for automatic folder backups (for example, a folder in
/// iCloud Drive). Kept free of file-system access so it can be tested on any platform.
public enum BackupPlan {
    public static let latestFileName = "Subspace Backup.json"
    public static let snapshotsKept = 14
    public static let overdueAfterDays = 7

    /// One dated copy per local calendar day, e.g. "Subspace Backup 2026-11-26.json".
    public static func snapshotName(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "Subspace Backup " + String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0) + ".json"
    }
    public static func isSnapshot(_ name: String) -> Bool {
        name.range(of: #"^Subspace Backup \d{4}-\d{2}-\d{2}\.json$"#, options: .regularExpression) != nil
    }
    /// Dated copies beyond the newest `keep`, oldest first. Other files in the folder are never returned.
    public static func snapshotsToPrune(_ names: [String], keep: Int = snapshotsKept) -> [String] {
        // ISO dates sort chronologically as strings.
        Array(names.filter(isSnapshot).sorted(by: >).dropFirst(max(keep, 0))).sorted()
    }
    /// An automatic backup is due when none has completed in the last 24 hours.
    public static func isDue(lastBackup: Date?, now: Date = .now) -> Bool {
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) >= 86_400
    }
    /// Warn when no backup of any kind has completed for `overdueAfterDays` calendar days.
    public static func isOverdue(lastBackup: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let lastBackup else { return true }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastBackup), to: calendar.startOfDay(for: now)).day ?? 0
        return days >= overdueAfterDays
    }
}
