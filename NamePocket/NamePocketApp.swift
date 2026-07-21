import SwiftUI
import SwiftData
import CoreData

@main
struct NamePocketApp: App {
    @State private var modelContainer: ModelContainer = {
        BackupRepository.applyPendingRestoreIfNeeded()
        return makeContainer()
    }()

    static func makeContainer() -> ModelContainer {
        let schema = Schema([Category.self, Person.self])
        let config = ModelConfiguration(schema: schema)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            backfillScalarParentIDsIfNeeded(container)
            return container
        } catch {
            guard isStoreCorruptionError(error) else {
                fatalError("Could not create ModelContainer: \(error)")
            }
            // The store file itself is unreadable (corrupted file, failed
            // migration, bad restore). Move it aside so the app can start
            // with a fresh database instead of crash-looping; the damaged
            // files are kept on disk for manual recovery. Other failures
            // (e.g. disk full, permissions) are left to fatalError above
            // rather than risk wiping a healthy store.
            moveStoreAside()
            do {
                let container = try ModelContainer(for: schema, configurations: [config])
                backfillScalarParentIDsIfNeeded(container)
                return container
            } catch {
                fatalError("Could not create ModelContainer even after resetting the store: \(error)")
            }
        }
    }

    /// `parentCategoryID`/`categoryID` are scalar mirrors of the
    /// `parentCategory`/`category` relationships, added so `CategoryListView`
    /// can filter/sort via SQL instead of traversing the relationship in
    /// Swift (see Category.parentCategoryID doc comment for why). Existing
    /// stores — including restored backups, which copy the raw `.sqlite`
    /// file rather than going through model `init` — predate this column and
    /// have it NULL. Backfill walks the relationship exactly like the old
    /// per-render code did, but only once per store rather than on every
    /// `body` evaluation.
    ///
    /// Gated by `backfillCompleteKey` so the full-table fetch this requires
    /// only runs the first launch after install/restore, not on every cold
    /// launch — an unconditional fetch here runs on the main thread before
    /// the first screen renders, which is exactly the "materializing fetched
    /// rows is expensive" cost this project has already hit freezes from.
    /// `BackupRepository.applyPendingRestoreIfNeeded` clears the flag when it
    /// installs a restored store, since that store may predate this column.
    static let backfillCompleteKey = "backfillComplete"

    private static func backfillScalarParentIDsIfNeeded(_ container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: backfillCompleteKey) else { return }

        let context = ModelContext(container)
        var didChange = false

        if let categories = try? context.fetch(FetchDescriptor<Category>()) {
            for category in categories where category.parentCategoryID == nil && category.parentCategory != nil {
                category.parentCategoryID = category.parentCategory?.id
                didChange = true
            }
        }

        if let people = try? context.fetch(FetchDescriptor<Person>()) {
            for person in people where person.categoryID == nil && person.category != nil {
                person.categoryID = person.category?.id
                didChange = true
            }
        }

        if didChange {
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: backfillCompleteKey)
    }

    /// Whether `error` indicates the on-disk store file is damaged or
    /// incompatible, as opposed to a transient/environmental failure.
    private static func isStoreCorruptionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSSQLiteErrorDomain,
           [11 /* SQLITE_CORRUPT */, 26 /* SQLITE_NOTADB */].contains(nsError.code) {
            return true
        }
        let corruptionCodes: Set<Int> = [
            NSPersistentStoreIncompatibleVersionHashError,
            NSMigrationError,
            NSMigrationMissingSourceModelError,
            NSMigrationMissingMappingModelError,
            NSPersistentStoreIncompatibleSchemaError,
            NSFileReadCorruptFileError,
        ]
        if nsError.domain == NSCocoaErrorDomain, corruptionCodes.contains(nsError.code) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isStoreCorruptionError(underlying)
        }
        return false
    }

    private static func moveStoreAside() {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: true) else { return }
        let timestamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let store = appSupport.appendingPathComponent("default.store\(suffix)")
            guard fm.fileExists(atPath: store.path) else { continue }
            let corrupt = appSupport.appendingPathComponent("default.store\(suffix).corrupt-\(timestamp)")
            try? fm.moveItem(at: store, to: corrupt)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task(priority: .background) {
                    await runStartupCleanup()
                }
        }
        .modelContainer(modelContainer)
    }

    private func runStartupCleanup() async {
        let context = ModelContext(modelContainer)
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        // Permanently purge items that have been in the trash for more than 30 days.
        // Filtered to deletedAt != nil in the fetch itself (rather than fetching
        // every row and filtering in Swift) so this doesn't duplicate the
        // full-table materialization the startup backfill already pays for.
        let trashedPeopleDescriptor = FetchDescriptor<Person>(
            predicate: #Predicate<Person> { $0.deletedAt != nil }
        )
        if let trashedPeopleRows = try? context.fetch(trashedPeopleDescriptor) {
            for person in trashedPeopleRows {
                guard let deletedAt = person.deletedAt, deletedAt < cutoff else { continue }
                let id = person.id.uuidString
                context.delete(person)
                try? await PhotoRepository.shared.deletePhoto(personId: id)
            }
        }

        let trashedCategoriesDescriptor = FetchDescriptor<Category>(
            predicate: #Predicate<Category> { $0.deletedAt != nil }
        )
        if let trashedCategoryRows = try? context.fetch(trashedCategoriesDescriptor) {
            let purgeable = trashedCategoryRows.filter {
                guard let deletedAt = $0.deletedAt else { return false }
                return deletedAt < cutoff
            }
            let purgeableIds = Set(purgeable.map(\.id))
            // Delete only the topmost purgeable category of each chain; the
            // cascade delete rule removes its descendants. Walking the full
            // ancestor chain (rather than checking just the immediate parent)
            // keeps this correct even if a purgeable category is separated
            // from a purgeable ancestor by a not-yet-purgeable one. Walked via
            // the scalar parentCategoryID map built from the already-fetched
            // trashed rows (not the `parentCategory` relationship) to avoid
            // an N+1 relationship fault per ancestor — the map has to include
            // every *trashed* row, not just the purgeable ones, since a
            // not-yet-purgeable trashed category can sit between two
            // purgeable ones in the chain.
            let trashedParentByID = Dictionary(
                uniqueKeysWithValues: trashedCategoryRows.map { ($0.id, $0.parentCategoryID) }
            )
            for category in purgeable {
                var coveredByAncestor = false
                var currentParentID = category.parentCategoryID
                while let parentID = currentParentID {
                    if purgeableIds.contains(parentID) {
                        coveredByAncestor = true
                        break
                    }
                    currentParentID = trashedParentByID[parentID] ?? nil
                }
                if !coveredByAncestor {
                    context.delete(category)
                }
            }
        }

        try? context.save()

        // Only check IDs that actually have a photo file on disk against
        // SwiftData, rather than fetching every Person row just to build a
        // valid-IDs set — this scales with how many people have photos, not
        // with total contact count.
        let candidateIds = (try? await PhotoRepository.shared.photoPersonIds()) ?? []
        guard !candidateIds.isEmpty else { return }
        let candidateUUIDs = Set(candidateIds.compactMap { UUID(uuidString: $0) })
        let existingDescriptor = FetchDescriptor<Person>(
            predicate: #Predicate<Person> { candidateUUIDs.contains($0.id) }
        )
        let existingIds = Set(((try? context.fetch(existingDescriptor)) ?? []).map { $0.id.uuidString })
        try? await PhotoRepository.shared.pruneOrphans(validPersonIds: existingIds)
    }
}
