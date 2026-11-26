import Foundation
import Testing
@testable import SubspaceCore

@Suite("Automatic backup plan") struct BackupPlanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    @Test("Dated copies use the local calendar day and are recognized")
    func snapshotNames() throws {
        let name = BackupPlan.snapshotName(for: try date(2026, 3, 7), calendar: calendar)
        #expect(name == "Subspace Backup 2026-03-07.json")
        #expect(BackupPlan.isSnapshot(name))
        #expect(!BackupPlan.isSnapshot(BackupPlan.latestFileName))
        #expect(!BackupPlan.isSnapshot("Subspace Backup 2026-03-07.json.icloud"))
    }

    @Test("Only the oldest dated copies beyond the limit are pruned; other files are kept")
    func pruning() {
        let snapshots = (1...16).map { String(format: "Subspace Backup 2026-01-%02d.json", $0) }
        let names = snapshots.shuffled() + [BackupPlan.latestFileName, "Notes.txt", "Subspace-2026-01-01.json"]
        #expect(BackupPlan.snapshotsToPrune(names) == ["Subspace Backup 2026-01-01.json", "Subspace Backup 2026-01-02.json"])
        #expect(BackupPlan.snapshotsToPrune(Array(snapshots.prefix(14))).isEmpty)
        #expect(BackupPlan.snapshotsToPrune(snapshots, keep: -1).count == 16)
    }

    @Test("A backup is due after 24 hours and overdue after seven calendar days")
    func freshness() throws {
        let now = try date(2026, 11, 26)
        #expect(BackupPlan.isDue(lastBackup: nil, now: now))
        #expect(!BackupPlan.isDue(lastBackup: now.addingTimeInterval(-3_600), now: now))
        #expect(BackupPlan.isDue(lastBackup: now.addingTimeInterval(-86_400), now: now))
        #expect(BackupPlan.isOverdue(lastBackup: nil, now: now, calendar: calendar))
        #expect(!BackupPlan.isOverdue(lastBackup: try date(2026, 11, 20, hour: 0), now: now, calendar: calendar))
        #expect(BackupPlan.isOverdue(lastBackup: try date(2026, 11, 19, hour: 23), now: now, calendar: calendar))
    }
}
