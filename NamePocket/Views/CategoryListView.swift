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
    let parentCategory: Category?

    // Subcategories and people for this screen are fetched on demand into
    // plain @State arrays — NOT via @Query. SwiftUI's DynamicProperty
    // contract calls a @Query's update()/fetch on every `body` evaluation,
    // and body legitimately gets invoked several times per navigation
    // transaction as part of normal AttributeGraph resolution. Each fetch
    // costs real time even when scoped to a plain scalar column and sorted
    // in SQL (SwiftData's Core Data-backed materialization of fetched rows
    // into model instances is not free), so paying that cost repeatedly
    // per render compounds into a multi-second-to-minutes freeze — this is
    // what caused the original George-folder freeze. Fetching once, outside
    // the render path, and caching into @State makes `body` itself O(1)
    // regardless of how many times SwiftUI re-invokes it.
    @State private var subcategories: [Category] = []
    @State private var people: [Person] = []

    @AppStorage("showNotesPreview") private var showNotesPreview = true
    @State private var showingAddCategory = false
    @State private var showingAddPerson = false
    @State private var newCategoryName = ""
    @State private var newPersonName = ""
    @State private var categoryToRename: Category?
    @State private var renameCategoryName = ""
    @State private var deletionCandidate: DeletionCandidate?

    init(parentCategory: Category?) {
        self.parentCategory = parentCategory
    }

    var body: some View {
        List {
            if !subcategories.isEmpty {
                Section("Categories") {
                    ForEach(subcategories) { subcategory in
                        NavigationLink {
                            CategoryListView(parentCategory: subcategory)
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

            if !people.isEmpty {
                Section("People") {
                    ForEach(people) { person in
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

            if subcategories.isEmpty && people.isEmpty {
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
        .onAppear { refreshLists() }
    }

    private func refreshLists() {
        let parentID = parentCategory?.id
        let categoryDescriptor = FetchDescriptor<Category>(
            predicate: #Predicate<Category> { $0.parentCategoryID == parentID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.name)]
        )
        let personDescriptor = FetchDescriptor<Person>(
            predicate: #Predicate<Person> { $0.categoryID == parentID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.name)]
        )
        subcategories = (try? modelContext.fetch(categoryDescriptor)) ?? []
        people = (try? modelContext.fetch(personDescriptor)) ?? []
    }

    private func addCategory() {
        guard !newCategoryName.isEmpty else { return }
        withAnimation {
            let newCategory = Category(name: newCategoryName, parentCategory: parentCategory)
            modelContext.insert(newCategory)
            newCategoryName = ""
        }
        refreshLists()
    }

    private func addPerson() {
        guard !newPersonName.isEmpty else { return }
        withAnimation {
            let newPerson = Person(name: newPersonName, category: parentCategory)
            modelContext.insert(newPerson)
            newPersonName = ""
        }
        refreshLists()
    }

    private func renameCategory() {
        guard let category = categoryToRename, !renameCategoryName.isEmpty else { return }
        category.name = renameCategoryName
        categoryToRename = nil
        refreshLists()
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
        refreshLists()
    }

    // Walks subcategories/people via scalar-ID-filtered fetches rather than
    // the `subcategories`/`people` relationships — the same reasoning as the
    // @State fetch above applies here: relationship access triggers Core
    // Data faulting per object, which for a large/deep tree run synchronously
    // on the main thread (this runs directly from a button action) reproduces
    // the freeze this scalar-ID scheme exists to avoid.
    private func softDeleteCategory(_ category: Category) {
        category.deletedAt = Date()
        let categoryID = category.id
        let subDescriptor = FetchDescriptor<Category>(
            predicate: #Predicate<Category> { $0.parentCategoryID == categoryID }
        )
        let peopleDescriptor = FetchDescriptor<Person>(
            predicate: #Predicate<Person> { $0.categoryID == categoryID }
        )
        let subs = (try? modelContext.fetch(subDescriptor)) ?? []
        let people = (try? modelContext.fetch(peopleDescriptor)) ?? []
        for sub in subs {
            softDeleteCategory(sub)
        }
        for person in people {
            person.deletedAt = Date()
        }
    }
}

#Preview {
    NavigationStack {
        CategoryListView(parentCategory: nil)
            .navigationTitle("NamePocket")
    }
    .modelContainer(for: [Category.self, Person.self], inMemory: true)
}
