//
//  AnalyticsStore.swift
//  StickiesPro
//

import Foundation
import GRDB

actor AnalyticsStore {
    static let shared = AnalyticsStore()
    
    private var dbQueue: DatabaseQueue
    private var pendingNoteIDs: [UUID] = []
    
    init() {
        do {
            let databaseURL = try Self.analyticsDatabaseURL()
            var configuration = Configuration()
            configuration.journalMode = .wal
            dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            try Self.migrateDatabase(dbQueue)
        } catch {
            fatalError("Failed to initialize analytics store: \(error)")
        }
    }
    
    func prepare() {}
    
    func enqueueNoteForProcessing(_ id: UUID) {
        pendingNoteIDs.append(id)
        print("note queued: \(id)")
    }
    
    private static func analyticsDatabaseURL() throws -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directoryURL = applicationSupportURL.appendingPathComponent("StickiesPro", isDirectory: true)
        
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        
        return directoryURL.appendingPathComponent("analytics.db")
    }
    
    private static func migrateDatabase(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1") { db in
            try db.create(table: "concordance_entry") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("term", .text).notNull().indexed()
                t.column("note_id", .text).notNull().indexed()
                t.column("vault_id", .text).indexed()
                t.column("weight", .double).notNull()
                t.column("positions", .text)
                t.column("updated_at", .datetime).notNull()
            }
            
            try db.create(table: "term_metadata") { t in
                t.column("term", .text).primaryKey()
                t.column("root_forms", .text)
                t.column("first_seen", .datetime).notNull()
                t.column("last_seen", .datetime).notNull()
                t.column("vault_frequency", .text)
            }
            
            try db.create(table: "note_embedding") { t in
                t.column("note_id", .text).primaryKey()
                t.column("vector", .blob).notNull()
                t.column("model", .text).notNull()
                t.column("generated_at", .datetime).notNull()
            }
            
            try db.create(table: "catalog_index") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("note_id", .text).notNull().indexed()
                t.column("address", .text).notNull().indexed()
                t.column("depth", .integer).notNull()
                t.column("parent_address", .text).indexed()
            }
        }
        
        try migrator.migrate(dbQueue)
    }
}
