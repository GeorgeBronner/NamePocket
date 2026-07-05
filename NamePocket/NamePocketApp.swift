import SwiftUI
import SwiftData

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
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // The store could not be opened (corrupted file, failed migration,
            // bad restore). Move it aside so the app can start with a fresh
            // database instead of crash-looping; the damaged files are kept
            // on disk for manual recovery.
            moveStoreAside()
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer even after resetting the store: \(error)")
            }
        }
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

        // Permanently purge items that have been in the trash for more than 30 days
        if let allPeople = try? context.fetch(FetchDescriptor<Person>()) {
            for person in allPeople {
                guard let deletedAt = person.deletedAt, deletedAt < cutoff else { continue }
                let id = person.id.uuidString
                context.delete(person)
                try? await PhotoRepository.shared.deletePhoto(personId: id)
            }
        }

        if let allCategories = try? context.fetch(FetchDescriptor<Category>()) {
            let purgeable = allCategories.filter {
                guard let deletedAt = $0.deletedAt else { return false }
                return deletedAt < cutoff
            }
            let purgeableIds = Set(purgeable.map(\.id))
            // Delete only the topmost purgeable category of each chain; the
            // cascade delete rule removes its descendants. Walking the full
            // ancestor chain (rather than checking just the immediate parent)
            // keeps this correct even if a purgeable category is separated
            // from a purgeable ancestor by a not-yet-purgeable one.
            for category in purgeable {
                var coveredByAncestor = false
                var ancestor = category.parentCategory
                while let current = ancestor {
                    if purgeableIds.contains(current.id) {
                        coveredByAncestor = true
                        break
                    }
                    ancestor = current.parentCategory
                }
                if !coveredByAncestor {
                    context.delete(category)
                }
            }
        }

        try? context.save()

        guard let people = try? context.fetch(FetchDescriptor<Person>()) else { return }
        let validIds = Set(people.map { $0.id.uuidString })
        try? await PhotoRepository.shared.pruneOrphans(validPersonIds: validIds)
    }
}
