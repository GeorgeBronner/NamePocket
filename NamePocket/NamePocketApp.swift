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
        guard let people = try? context.fetch(FetchDescriptor<Person>()) else { return }
        let validIds = Set(people.map { $0.id.uuidString })
        try? await PhotoRepository.shared.pruneOrphans(validPersonIds: validIds)
    }
}
