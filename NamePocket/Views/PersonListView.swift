import SwiftUI
import SwiftData

struct PersonListView: View {
    @Query private var people: [Person]

    var body: some View {
        List {
            ForEach(people.sorted { $0.name < $1.name }) { person in
                NavigationLink {
                    PersonDetailView(person: person)
                } label: {
                    VStack(alignment: .leading) {
                        Text(person.name)
                            .font(.headline)
                        if let category = person.category {
                            Text(category.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("All People")
    }
}

#Preview {
    NavigationStack {
        PersonListView()
    }
    .modelContainer(for: [Category.self, Person.self], inMemory: true)
}
