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
    static func container(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SubspaceSchemaV1.self)
        let configuration: ModelConfiguration
        if let url { configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none) }
        return try ModelContainer(for: schema, migrationPlan: SubspaceMigrationPlan.self, configurations: [configuration])
    }
}
