import XCTest
import SwiftData
import SubspaceCore
@testable import Subspace

@MainActor final class PersistenceTests: XCTestCase {
    func testSaveEditArchiveDeleteAndReload() throws {
        let container = try Persistence.container(inMemory: true)
        let store = AppStore(container: container)
        var record = SubscriptionRecord(name: "Test", amount: 10)
        try store.save(record)
        XCTAssertEqual(store.records.count, 1)
        record.amount = 20; try store.save(record)
        XCTAssertEqual(store.summary.monthly, 20)
        record.archived = true; try store.save(record)
        XCTAssertTrue(store.visible.isEmpty)
        XCTAssertEqual(AppStore(container: container).records, [record])
        record.archived = false; try store.save(record)
        XCTAssertEqual(store.visible.count, 1)
        try store.delete(record)
        XCTAssertTrue(AppStore(container: container).records.isEmpty)
    }
    func testBackupImportIsValidatedAndMergedAtomically() throws {
        let container = try Persistence.container(inMemory: true)
        let store = AppStore(container: container)
        let record = SubscriptionRecord(name: "Original", amount: 25)
        try store.save(record)
        let backup = try store.backupData()
        XCTAssertEqual(try store.importBackup(backup), 1)
        XCTAssertEqual(store.records.count, 1)
        var invalid = record; invalid.amount = -1
        let bad = try JSONEncoder().encode(Backup(subscriptions: [invalid]))
        XCTAssertThrowsError(try store.importBackup(bad))
        XCTAssertEqual(store.records, [record])
    }
    func testDiskStoreSurvivesContainerRecreation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { XCTFail("Could not clean temporary store: \(error)") }
        }
        let url = directory.appendingPathComponent("Subscriptions.store")
        let record = SubscriptionRecord(name: "On disk", amount: Decimal(1299) / 100)
        try autoreleasepool {
            let container = try Persistence.container(url: url)
            let context = ModelContext(container)
            context.insert(try StoredSubscription(record: record))
            try context.save()
        }
        let reopened = try Persistence.container(url: url)
        let context = ModelContext(reopened)
        let entities = try context.fetch(FetchDescriptor<StoredSubscription>())
        XCTAssertEqual(entities.count, 1)
        let entity = try XCTUnwrap(entities.first)
        XCTAssertEqual(try JSONDecoder().decode(SubscriptionRecord.self, from: entity.payload), record)
    }
    func testPayloadRoundTripsInNewContext() throws {
        let container = try Persistence.container(inMemory: true)
        let record = SubscriptionRecord(name: "Decimal", amount: Decimal(1099) / 100)
        let context = ModelContext(container)
        context.insert(try StoredSubscription(record: record)); try context.save()
        let newContext = ModelContext(container)
        let stored = try XCTUnwrap(newContext.fetch(FetchDescriptor<StoredSubscription>()).first)
        XCTAssertEqual(try JSONDecoder().decode(SubscriptionRecord.self, from: stored.payload), record)
    }
    func testAutomaticFolderBackupWritesRestorableCopiesAndPrunes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // Old dated copies beyond the retention limit, plus an unrelated file that must survive pruning.
        for day in 1...15 {
            try Data("{}".utf8).write(to: folder.appendingPathComponent(String(format: "Subvelle Backup 2020-01-%02d.json", day)))
        }
        try Data("keep".utf8).write(to: folder.appendingPathComponent("Notes.txt"))
        let suite = "auto-backup-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(container: try Persistence.container(inMemory: true), defaults: defaults)
        try store.save(SubscriptionRecord(name: "Backed up", amount: 12))

        await store.setBackupFolder(folder)
        XCTAssertNil(store.backupProblem)
        XCTAssertEqual(store.backupFolderName, folder.lastPathComponent)
        XCTAssertNotNil(store.lastBackup)
        let latest = try Data(contentsOf: folder.appendingPathComponent(BackupPlan.latestFileName))
        XCTAssertEqual(try JSONDecoder().decode(Backup.self, from: latest).validated().map(\.name), ["Backed up"])
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertTrue(names.contains(BackupPlan.snapshotName(for: .now)))
        XCTAssertTrue(names.contains("Notes.txt"))
        XCTAssertEqual(names.filter(BackupPlan.isSnapshot).count, BackupPlan.snapshotsKept)
        // The written file restores into an empty store (separate settings: no automatic backup there).
        let restoreSuite = "restore-" + UUID().uuidString
        defer { UserDefaults().removePersistentDomain(forName: restoreSuite) }
        let restored = AppStore(container: try Persistence.container(inMemory: true), defaults: try XCTUnwrap(UserDefaults(suiteName: restoreSuite)))
        XCTAssertEqual(try restored.importBackup(latest), 1)

        // Settings survive relaunch; turning off keeps existing files.
        XCTAssertEqual(AppStore(container: try Persistence.container(inMemory: true), defaults: defaults).backupFolderName, folder.lastPathComponent)
        store.stopAutoBackup()
        XCTAssertNil(store.backupFolderName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(BackupPlan.latestFileName).path))
    }
}
