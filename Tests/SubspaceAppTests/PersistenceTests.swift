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
}
