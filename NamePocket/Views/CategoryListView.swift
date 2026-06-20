import SwiftUI
import SwiftData

private enum DeletionCandidate {
    case person(Person)
    case category(Category)

    var displayName: String {
        switch self {
        case .person(let p): return p.name
        case .category(let c): return c.name
        }
    }
}

struct CategoryListView: View {
    @Environment(\.modelContext) private var modelContext
    let categories: [Category]
    let parentCategory: Category?

    @AppStorage("showNotesPreview") private var showNotesPreview = true
    @State private var showingAddCategory = false
    @State private var showingAddPerson = false
    @State private var newCategoryName = ""
    @State private var newPersonName = ""
    @State private var categoryToRename: Category?
    @State private var renameCategoryName = ""
    @State private var deletionCandidate: DeletionCandidate?

    var sortedSubcategories: [Category] {
        (parentCategory?.subcategories ?? categories)
            .filter { $0.deletedAt == nil }
            .sorted { $0.name < $1.name }
    }

    var sortedPeople: [Person] {
        (parentCategory?.people ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            if !sortedSubcategories.isEmpty {
                Section("Categories") {
                    ForEach(sortedSubcategories) { subcategory in
                        NavigationLink {
                            CategoryListView(categories: subcategory.subcategories ?? [], parentCategory: subcategory)
                                .navigationTitle(subcategory.name)
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(subcategory.name)
                            }
                        }
                        .contextMenu {
                            Button {
                                categoryToRename = subcategory
                                renameCategoryName = subcategory.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deletionCandidate = .category(subcategory)
                            } label: {
                                Label("Move to Trash", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deletionCandidate = .category(subcategory)
                            } label: {
                                Label("Trash", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !sortedPeople.isEmpty {
                Section("People") {
                    ForEach(sortedPeople) { person in
                        NavigationLink {
                            PersonDetailView(person: person)
                        } label: {
                            HStack {
                                PersonPhotoView(personId: person.id.uuidString)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name)
                                    if showNotesPreview && !person.notes.isEmpty {
                                        Text(person.notes.components(separatedBy: "\n").first ?? "")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deletionCandidate = .person(person)
                            } label: {
                                Label("Trash", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if sortedSubcategories.isEmpty && sortedPeople.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "tray",
                    description: Text("Add a category or person to get started")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNotesPreview.toggle()
                } label: {
                    Image(systemName: showNotesPreview ? "eye.slash" : "eye")
                }
                .accessibilityLabel(showNotesPreview ? "Hide notes preview" : "Show notes preview")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingAddCategory = true
                    } label: {
                        Label("Add Category", systemImage: "folder.badge.plus")
                    }
                    Button {
                        showingAddPerson = true
                    } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("plus")
            }
        }
        .alert("New Category", isPresented: $showingAddCategory) {
            TextField("Category Name", text: $newCategoryName)
                .accessibilityIdentifier("Category Name")
            Button("Cancel", role: .cancel) { newCategoryName = "" }
            Button("Add") { addCategory() }
        }
        .alert("New Person", isPresented: $showingAddPerson) {
            TextField("Person Name", text: $newPersonName)
                .accessibilityIdentifier("Person Name")
            Button("Cancel", role: .cancel) { newPersonName = "" }
            Button("Add") { addPerson() }
        }
        .alert("Rename Category", isPresented: Binding(
            get: { categoryToRename != nil },
            set: { if !$0 { categoryToRename = nil } }
        )) {
            TextField("Category Name", text: $renameCategoryName)
            Button("Cancel", role: .cancel) { categoryToRename = nil }
            Button("Rename") { renameCategory() }
        }
        .confirmationDialog(
            "Move \"\(deletionCandidate?.displayName ?? "")\" to Trash?",
            isPresented: Binding(
                get: { deletionCandidate != nil },
                set: { if !$0 { deletionCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let candidate = deletionCandidate {
                    moveToTrash(candidate)
                    deletionCandidate = nil
                }
            }
            Button("Cancel", role: .cancel) { deletionCandidate = nil }
        }
    }

    private func addCategory() {
        guard !newCategoryName.isEmpty else { return }
        withAnimation {
            let newCategory = Category(name: newCategoryName, parentCategory: parentCategory)
            modelContext.insert(newCategory)
            newCategoryName = ""
        }
    }

    private func addPerson() {
        guard !newPersonName.isEmpty else { return }
        withAnimation {
            let newPerson = Person(name: newPersonName, category: parentCategory)
            modelContext.insert(newPerson)
            newPersonName = ""
        }
    }

    private func renameCategory() {
        guard let category = categoryToRename, !renameCategoryName.isEmpty else { return }
        category.name = renameCategoryName
        categoryToRename = nil
    }

    private func moveToTrash(_ candidate: DeletionCandidate) {
        withAnimation {
            switch candidate {
            case .person(let person):
                person.deletedAt = Date()
            case .category(let category):
                softDeleteCategory(category)
            }
        }
    }

    private func softDeleteCategory(_ category: Category) {
        category.deletedAt = Date()
        for sub in category.subcategories ?? [] {
            softDeleteCategory(sub)
        }
        for person in category.people ?? [] {
            person.deletedAt = Date()
        }
    }
}

#Preview {
    NavigationStack {
        CategoryListView(categories: [], parentCategory: nil)
            .navigationTitle("NamePocket")
    }
    .modelContainer(for: [Category.self, Person.self], inMemory: true)
}
