import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var rootCategories: [Category]

    init() {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.parentCategory == nil },
            sortBy: [SortDescriptor(\.name)]
        )
        _rootCategories = Query(descriptor)
    }

    var body: some View {
        NavigationStack {
            CategoryListView(categories: rootCategories, parentCategory: nil)
                .navigationTitle("NamePocket")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Category.self, Person.self], inMemory: true)
}
