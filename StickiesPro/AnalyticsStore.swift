//
//  AnalyticsStore.swift
//  StickiesPro
//

import Foundation
import FoundationModels
import GRDB
import NaturalLanguage
import SwiftData

actor AnalyticsStore {
    static let shared = AnalyticsStore()
    
    private struct NoteSnapshot: Sendable {
        let id: UUID
        let content: String
        let vaultID: UUID?
    }
    
    private struct GenerationTimeoutError: Error {}
    
    private var dbQueue: DatabaseQueue
    private var pendingQueue: [UUID] = []
    private var isProcessing = false
    
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
        pendingQueue.append(id)
        print("note queued: \(id)")
        Task {
            await drainQueue()
        }
    }
    
    private func drainQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        
        while let id = pendingQueue.first {
            pendingQueue.removeFirst()
            await processNote(id)
        }
        
        isProcessing = false
    }
    
    private func processNote(_ id: UUID) async {
        guard let note = await fetchNoteSnapshot(id) else { return }
        let content = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.count >= 20 else { return }
        
        await extractTerms(content: content, noteId: note.id, vaultId: note.vaultID)
        await assignCatalogAddress(content: content, noteId: note.id)
        await generateEmbedding(content: content, noteId: note.id)
        print("processed note: \(id)")
    }
    
    private func fetchNoteSnapshot(_ id: UUID) async -> NoteSnapshot? {
        await MainActor.run {
            let context = ModelContext(StickiesProApp.sharedModelContainer)
            let descriptor = FetchDescriptor<Sticky>(
                predicate: #Predicate { sticky in
                    sticky.id == id
                }
            )
            
            guard let sticky = try? context.fetch(descriptor).first else { return nil }
            return NoteSnapshot(id: sticky.id, content: sticky.content, vaultID: sticky.vault?.id)
        }
    }
    
    private func extractTerms(content: String, noteId: UUID, vaultId: UUID?) async {
        let prompt = """
        Extract the most meaningful terms from this note. Focus on domain terms, proper nouns, and concepts -- not common stop words. Normalize terms to lowercase. Use character offsets from the note content for positions. Limit to the 12 strongest terms.
        Note content: \(content)
        """
        
        let noteTerms: NoteTerms
        do {
            noteTerms = try await generatedContent(for: prompt, as: NoteTerms.self)
        } catch {
            logGenerationError(error, operation: "term extraction", noteId: noteId)
            return
        }
        
        let terms = noteTerms.terms
            .map(normalizedTerm)
            .filter { !$0.term.isEmpty }
        guard !terms.isEmpty else { return }
        
        let existingTerms = existingTermSet(terms.map(\.term))
        var etymologies: [String: TermEtymology] = [:]
        
        for term in terms where !existingTerms.contains(term.term) {
            if let etymology = await generateEtymology(for: term.term, usageHint: term.localUsageHint) {
                etymologies[term.term] = etymology
            }
        }
        
        let etymologyByTerm = etymologies
        
        try? await dbQueue.write { db in
            let now = Date()
            let noteID = noteId.uuidString
            let vaultID = vaultId?.uuidString
            
            try db.execute(sql: "DELETE FROM concordance_entry WHERE note_id = ?", arguments: [noteID])
            
            for term in terms {
                try db.execute(
                    sql: """
                    INSERT INTO concordance_entry (term, note_id, vault_id, weight, positions, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        term.term,
                        noteID,
                        vaultID,
                        term.weight,
                        jsonString(term.positions),
                        now
                    ]
                )
                
                let row = try Row.fetchOne(
                    db,
                    sql: "SELECT vault_frequency FROM term_metadata WHERE term = ?",
                    arguments: [term.term]
                )
                var frequencies = decodeVaultFrequency(row?["vault_frequency"])
                frequencies[vaultID ?? "freestanding", default: 0] += 1
                
                if row == nil {
                    let etymology = etymologyByTerm[term.term]
                    try db.execute(
                        sql: """
                        INSERT INTO term_metadata (term, root_forms, first_seen, last_seen, vault_frequency)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            term.term,
                            jsonString(etymology?.rootForms ?? []),
                            now,
                            now,
                            jsonString(frequencies)
                        ]
                    )
                } else {
                    try db.execute(
                        sql: """
                        UPDATE term_metadata
                        SET last_seen = ?, vault_frequency = ?
                        WHERE term = ?
                        """,
                        arguments: [now, jsonString(frequencies), term.term]
                    )
                }
            }
        }
    }
    
    private func assignCatalogAddress(content: String, noteId: UUID) async {
        let prompt = """
        Assign a Dewey Decimal-style address to this note. Use standard Dewey categories for primary: 000s for computing and information, 100s philosophy, 200s religion, 300s social sciences, 400s language, 500s science, 600s technology, 700s arts, 800s literature, 900s history and geography.
        Note content: \(content)
        """
        
        let address: NoteCatalogAddress
        do {
            address = try await generatedContent(for: prompt, as: NoteCatalogAddress.self)
        } catch {
            logGenerationError(error, operation: "catalog assignment", noteId: noteId)
            return
        }
        
        let primary = min(max(address.primary, 0), 999)
        let secondary = min(max(address.secondary, 0), 99)
        let tertiary = min(max(address.tertiary, 0), 9)
        let addressString = "\(primary).\(secondary).\(tertiary)"
        let parentAddress = "\(primary).\(secondary)"
        
        try? await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM catalog_index WHERE note_id = ?", arguments: [noteId.uuidString])
            try db.execute(
                sql: """
                INSERT INTO catalog_index (note_id, address, depth, parent_address)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [noteId.uuidString, addressString, 3, parentAddress]
            )
        }
        
        await updateCatalogAddress(addressString, noteId: noteId)
    }
    
    private func generateEmbedding(content: String, noteId: UUID) async {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return }
        
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = content
        var vectors: [[Double]] = []
        
        tokenizer.enumerateTokens(in: content.startIndex..<content.endIndex) { range, _ in
            let token = String(content[range]).lowercased()
            if let vector = embedding.vector(for: token) {
                vectors.append(vector)
            }
            return true
        }
        
        guard let dimension = vectors.first?.count, dimension > 0 else { return }
        var averaged = Array(repeating: 0.0, count: dimension)
        
        for vector in vectors {
            for index in 0..<dimension {
                averaged[index] += vector[index]
            }
        }
        
        let count = Double(vectors.count)
        let floatVector = averaged.map { Float($0 / count) }
        let blob = floatVector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        try? await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM note_embedding WHERE note_id = ?", arguments: [noteId.uuidString])
            try db.execute(
                sql: """
                INSERT INTO note_embedding (note_id, vector, model, generated_at)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [noteId.uuidString, blob, "nl.wordEmbedding.en", Date()]
            )
        }
    }
    
    private func generateEtymology(for term: String, usageHint: String) async -> TermEtymology? {
        let prompt = """
        Provide concise etymology root forms for this term. If roots are unknown, return an empty rootForms array and a brief uncertainty summary.
        Term: \(term)
        Usage in note: \(usageHint)
        """
        
        do {
            return try await generatedContent(for: prompt, as: TermEtymology.self)
        } catch {
            logGenerationError(error, operation: "etymology", noteId: nil)
            return nil
        }
    }
    
    private func generatedContent<Content: Generable>(for prompt: String, as type: Content.Type) async throws -> Content {
        try await withThrowingTaskGroup(of: Content.self) { group in
            group.addTask {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt, generating: type)
                return response.content
            }
            
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw GenerationTimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw GenerationTimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
    
    private func updateCatalogAddress(_ address: String, noteId: UUID) async {
        await MainActor.run {
            let context = ModelContext(StickiesProApp.sharedModelContainer)
            let descriptor = FetchDescriptor<Sticky>(
                predicate: #Predicate { sticky in
                    sticky.id == noteId
                }
            )
            
            guard let sticky = try? context.fetch(descriptor).first else { return }
            sticky.catalogAddress = address
            sticky.modifiedAt = Date()
            try? context.save()
        }
    }
    
    private func existingTermSet(_ terms: [String]) -> Set<String> {
        guard !terms.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: terms.count).joined(separator: ",")
        let rows = try? dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT term FROM term_metadata WHERE term IN (\(placeholders))",
                arguments: StatementArguments(terms)
            )
        }
        return Set(rows ?? [])
    }
    
    private func normalizedTerm(_ term: ExtractedTerm) -> ExtractedTerm {
        ExtractedTerm(
            term: term.term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            weight: min(max(term.weight, 0), 1),
            positions: term.positions.filter { $0 >= 0 },
            localUsageHint: term.localUsageHint
        )
    }
    
    private func logGenerationError(_ error: Error, operation: String, noteId: UUID?) {
        let noteSuffix = noteId.map { " for note \($0)" } ?? ""
        
        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .guardrailViolation:
                print("FoundationModels guardrail skipped \(operation)\(noteSuffix): \(generationError.localizedDescription)")
            case .unsupportedLanguageOrLocale:
                print("FoundationModels unsupported language skipped \(operation)\(noteSuffix): \(generationError.localizedDescription)")
            case .assetsUnavailable:
                print("FoundationModels unavailable for \(operation)\(noteSuffix): \(generationError.localizedDescription)")
            default:
                print("FoundationModels failed \(operation)\(noteSuffix): \(generationError.localizedDescription)")
            }
        } else if error is GenerationTimeoutError {
            print("FoundationModels timed out \(operation)\(noteSuffix)")
        } else {
            print("FoundationModels failed \(operation)\(noteSuffix): \(error.localizedDescription)")
        }
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

nonisolated private func jsonString<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(value) else { return "null" }
    return String(data: data, encoding: .utf8) ?? "null"
}

nonisolated private func decodeVaultFrequency(_ value: String?) -> [String: Int] {
    guard let value, let data = value.data(using: .utf8) else { return [:] }
    return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
}
