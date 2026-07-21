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
                            // The badge is offset outside the bare Image's own
                            // bounds; a plain `.overlay` doesn't grow the
                            // parent's reported size, so without extra room
                            // the toolbar sizes itself to just the icon and
                            // clips the badge that spills past it. With
                            // `.topTrailing` alignment the badge's own corner
                            // starts flush with the icon's, so padding that
                            // matches the offset exactly covers the overflow
                            // without guessing at a fixed frame size.
                            Image(systemName: trashCount > 0 ? "trash.fill" : "trash")
                                .overlay(alignment: .topTrailing) {
                                    if trashCount > 0 {
                                        Text("\(min(trashCount, 99))")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.red, in: Capsule())
                                            .offset(x: 8, y: -6)
                                    }
                                }
                                .padding(.top, 6)
                                .padding(.trailing, 8)
                        }
                        .accessibilityIdentifier("trash")
                    }
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Category.self, Person.self], inMemory: true)
}
