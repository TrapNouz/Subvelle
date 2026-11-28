import Foundation
import SwiftData
import SubspaceCore

// Version one uses a versioned Codable payload: additive fields can be migrated explicitly
// without binding financial domain types to SwiftData's schema representation.
enum SubspaceSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredSubscription.self] }
    @Model final class StoredSubscription {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(record: SubscriptionRecord) throws { id = record.id; payload = try JSONEncoder().encode(record) }
    }
}
enum SubspaceMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SubspaceSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
typealias StoredSubscription = SubspaceSchemaV1.StoredSubscription

@MainActor enum Persistence {
    /// The database's permanent home. Same path as SwiftData's default, so existing data stays put,
    /// but set explicitly: the default never created `Application Support` on a fresh install, and the
    /// store could end up in storage that iOS clears when the app has not been used for a while.
    static var storeURL: URL { URL.applicationSupportDirectory.appendingPathComponent("default.store") }

    static func container(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SubspaceSchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory && url == nil {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let target = url ?? storeURL
            // Create the folder first; SwiftData does not reliably do it.
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, url: target, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: SubspaceMigrationPlan.self, configurations: [configuration])
    }
}
