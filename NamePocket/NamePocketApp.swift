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
        return try! ModelContainer(for: schema, configurations: [config])
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
            for category in allCategories {
                guard let deletedAt = category.deletedAt, deletedAt < cutoff else { continue }
                // Skip subcategories whose trashed parent will cascade-delete them
                let parentAlsoPurging = category.parentCategory?.deletedAt.map { $0 < cutoff } ?? false
                if !parentAlsoPurging {
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
