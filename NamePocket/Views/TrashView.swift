import SwiftUI
import SwiftData

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext

    // Fetched on demand into plain @State arrays, already sorted, rather than
    // via @Query — see CategoryListView's @State doc comment for why: @Query
    // re-fetches on every `body` evaluation, and body is invoked several
    // times per navigation transaction, so a large trash would reproduce the
    // same freeze this app previously fixed for the category list.
    @State private var trashedPeople: [Person] = []
    @State private var trashedCategories: [Category] = []

    @State private var showingEmptyTrashConfirm = false

    private let calendar = Calendar.current

    var body: some View {
        List {
            if !trashedCategories.isEmpty {
                Section("Categories") {
                    ForEach(trashedCategories) { category in
                        trashRow(
                            icon: "folder.fill",
                            iconColor: .blue,
                            name: category.name,
                            deletedAt: category.deletedAt ?? Date()
                        )
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                restore(category: category)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                permanentlyDelete(category: category)
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                    }
                }
            }

            if !trashedPeople.isEmpty {
                Section("People") {
                    ForEach(trashedPeople) { person in
                        trashRow(
                            icon: "person.fill",
                            iconColor: .accentColor,
                            name: person.name,
                            deletedAt: person.deletedAt ?? Date()
                        )
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                restore(person: person)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                permanentlyDelete(person: person)
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                    }
                }
            }

            if trashedPeople.isEmpty && trashedCategories.isEmpty {
                ContentUnavailableView(
                    "Trash is Empty",
                    systemImage: "trash",
                    description: Text("Deleted items are kept for 30 days before being removed automatically")
                )
            }
        }
        .navigationTitle("Trash")
        .toolbar {
            if !trashedPeople.isEmpty || !trashedCategories.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Empty Trash") {
                        showingEmptyTrashConfirm = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog(
            "Permanently delete all \(trashedPeople.count + trashedCategories.count) items?",
            isPresented: $showingEmptyTrashConfirm,
            titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) { emptyTrash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .onAppear { refreshTrash() }
    }

    private func refreshTrash() {
        let personDescriptor = FetchDescriptor<Person>(
            predicate: #Predicate<Person> { $0.deletedAt != nil }
        )
        let categoryDescriptor = FetchDescriptor<Category>(
            predicate: #Predicate<Category> { $0.deletedAt != nil }
        )
        let people = (try? modelContext.fetch(personDescriptor)) ?? []
        let categories = (try? modelContext.fetch(categoryDescriptor)) ?? []
        trashedPeople = people.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        trashedCategories = categories.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    @ViewBuilder
    private func trashRow(icon: String, iconColor: Color, name: String, deletedAt: Date) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(deletionSummary(for: deletedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deletionSummary(for date: Date) -> String {
        let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
        let daysLeft = max(0, 30 - daysAgo)
        let ago: String
        switch daysAgo {
        case 0: ago = "Deleted today"
        case 1: ago = "Deleted yesterday"
        default: ago = "Deleted \(daysAgo) days ago"
        }
        return "\(ago) · auto-deletes in \(daysLeft) day\(daysLeft == 1 ? "" : "s")"
    }

    private func restore(person: Person) {
        withAnimation {
            person.deletedAt = nil
            // Restore the parent category chain so the person is visible in lists
            var cat = person.category
            while let c = cat {
                if c.deletedAt != nil { c.deletedAt = nil }
                cat = c.parentCategory
            }
        }
        refreshTrash()
    }

    private func restore(category: Category) {
        withAnimation {
            category.deletedAt = nil
            // Restore parent chain so the category is visible
            var parent = category.parentCategory
            while let p = parent {
                if p.deletedAt != nil { p.deletedAt = nil }
                parent = p.parentCategory
            }
        }
        refreshTrash()
    }

    private func permanentlyDelete(person: Person) {
        let personId = person.id.uuidString
        modelContext.delete(person)
        Task { try? await PhotoRepository.shared.deletePhoto(personId: personId) }
        refreshTrash()
    }

    private func permanentlyDelete(category: Category) {
        // Detach any restored children before cascade deletes them
        detachRestoredChildren(category)
        modelContext.delete(category)
        refreshTrash()
    }

    // Scalar-ID-filtered fetches rather than the subcategories/people
    // relationships — see softDeleteCategory in CategoryListView for why.
    private func detachRestoredChildren(_ category: Category) {
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
            if sub.deletedAt == nil {
                sub.parentCategory = nil
                sub.parentCategoryID = nil
            } else {
                detachRestoredChildren(sub)
            }
        }
        for person in people {
            if person.deletedAt == nil {
                person.category = nil
                person.categoryID = nil
            } else {
                // Still-trashed people are left attached and cascade-deleted
                // along with `category`, which bypasses permanentlyDelete(person:)
                // — clean up their photo file explicitly so it isn't orphaned.
                let personId = person.id.uuidString
                Task { try? await PhotoRepository.shared.deletePhoto(personId: personId) }
            }
        }
    }

    private func emptyTrash() {
        let peopleCopy = Array(trashedPeople)
        let categoriesCopy = Array(trashedCategories)

        for person in peopleCopy {
            let id = person.id.uuidString
            modelContext.delete(person)
            Task { try? await PhotoRepository.shared.deletePhoto(personId: id) }
        }

        // Only delete root-level trashed categories; cascade handles trashed children
        for category in categoriesCopy {
            let parentAlsoTrashed = category.parentCategory?.deletedAt != nil
            if !parentAlsoTrashed {
                detachRestoredChildren(category)
                modelContext.delete(category)
            }
        }
        refreshTrash()
    }
}

#Preview {
    NavigationStack {
        TrashView()
    }
    .modelContainer(for: [Category.self, Person.self], inMemory: true)
}
