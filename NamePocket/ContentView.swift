import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(filter: #Predicate<Person> { $0.deletedAt != nil }) private var trashedPeople: [Person]
    @Query(filter: #Predicate<Category> { $0.deletedAt != nil }) private var trashedCategories: [Category]

    var trashCount: Int { trashedPeople.count + trashedCategories.count }

    var body: some View {
        NavigationStack {
            CategoryListView(parentCategory: nil)
                .navigationTitle("NamePocket")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            TrashView()
                        } label: {
                            Image(systemName: trashCount > 0 ? "trash.fill" : "trash")
                                .overlay(alignment: .topTrailing) {
                                    if trashCount > 0 {
                                        Text("\(min(trashCount, 99))")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.red, in: Capsule())
                                            .offset(x: 10, y: -8)
                                    }
                                }
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
