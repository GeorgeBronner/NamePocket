import SwiftUI
import SwiftData

struct PersonDetailView: View {
    @Bindable var person: Person
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("Basic Information") {
                TextField("Name", text: $person.name)
                TextField("Phone Number", text: $person.phoneNumber)
                    .keyboardType(.phonePad)
                TextField("Email", text: $person.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }

            Section("Notes") {
                TextEditor(text: $person.notes)
                    .frame(minHeight: 100)
            }

            Section("Details") {
                LabeledContent("Created", value: person.createdAt, format: .dateTime)
                if let category = person.category {
                    LabeledContent("Category", value: category.name)
                }
            }
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Category.self, Person.self, configurations: config)

    let category = Category(name: "Friends")
    let person = Person(name: "John Doe", phoneNumber: "555-1234", email: "john@example.com", category: category)

    container.mainContext.insert(category)
    container.mainContext.insert(person)

    return NavigationStack {
        PersonDetailView(person: person)
    }
    .modelContainer(container)
}
