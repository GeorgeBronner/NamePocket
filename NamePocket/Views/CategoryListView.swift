import SwiftUI
import SwiftData

struct CategoryListView: View {
    @Environment(\.modelContext) private var modelContext
    let categories: [Category]
    let parentCategory: Category?

    @State private var showingAddCategory = false
    @State private var showingAddPerson = false
    @State private var newCategoryName = ""
    @State private var newPersonName = ""
    @State private var categoryToRename: Category?
    @State private var renameCategoryName = ""

    var sortedSubcategories: [Category] {
        (parentCategory?.subcategories ?? categories).sorted { $0.name < $1.name }
    }

    var sortedPeople: [Person] {
        (parentCategory?.people ?? []).sorted { $0.name < $1.name }
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
                                modelContext.delete(subcategory)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteCategories)
                }
            }

            if !sortedPeople.isEmpty {
                Section("People") {
                    ForEach(sortedPeople) { person in
                        NavigationLink {
                            PersonDetailView(person: person)
                        } label: {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundStyle(.green)
                                Text(person.name)
                            }
                        }
                    }
                    .onDelete(perform: deletePeople)
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
            Button("Cancel", role: .cancel) {
                newCategoryName = ""
            }
            Button("Add") {
                addCategory()
            }
        }
        .alert("New Person", isPresented: $showingAddPerson) {
            TextField("Person Name", text: $newPersonName)
                .accessibilityIdentifier("Person Name")
            Button("Cancel", role: .cancel) {
                newPersonName = ""
            }
            Button("Add") {
                addPerson()
            }
        }
        .alert("Rename Category", isPresented: Binding(
            get: { categoryToRename != nil },
            set: { if !$0 { categoryToRename = nil } }
        )) {
            TextField("Category Name", text: $renameCategoryName)
            Button("Cancel", role: .cancel) {
                categoryToRename = nil
            }
            Button("Rename") {
                renameCategory()
            }
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

    private func deleteCategories(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(sortedSubcategories[index])
            }
        }
    }

    private func deletePeople(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(sortedPeople[index])
            }
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
