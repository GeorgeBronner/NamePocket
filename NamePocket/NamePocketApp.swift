import SwiftUI
import SwiftData

@main
struct NamePocketApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Category.self, Person.self])
    }
}
