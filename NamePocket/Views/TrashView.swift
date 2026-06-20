import SwiftUI
import SwiftData

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Person> { $0.deletedAt != nil }) private var trashedPeople: [Person]
    @Query(filter: #Predicate<Category> { $0.deletedAt != nil }) private var trashedCategories: [Category]

    @State private var showingEmptyTrashConfirm = false

    private let calendar = Calendar.current

    var sortedTrashedPeople: [Person] {
        trashedPeople.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var sortedTrashedCategories: [Category] {
        trashedCategories.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var body: some View {
        List {
            if !sortedTrashedCategories.isEmpty {
                Section("Categories") {
                    ForEach(sortedTrashedCategories) { category in
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

            if !sortedTrashedPeople.isEmpty {
                Section("People") {
                    ForEach(sortedTrashedPeople) { person in
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
    }

    private func permanentlyDelete(person: Person) {
        let personId = person.id.uuidString
        modelContext.delete(person)
        Task { try? await PhotoRepository.shared.deletePhoto(personId: personId) }
    }

    private func permanentlyDelete(category: Category) {
        // Detach any restored children before cascade deletes them
        detachRestoredChildren(category)
        modelContext.delete(category)
    }

    private func detachRestoredChildren(_ category: Category) {
        for sub in category.subcategories ?? [] {
            if sub.deletedAt == nil {
                sub.parentCategory = nil
            } else {
                detachRestoredChildren(sub)
            }
        }
        for person in category.people ?? [] where person.deletedAt == nil {
            person.category = nil
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
    }
}

#Preview {
    NavigationStack {
        TrashView()
    }
    .modelContainer(for: [Category.self, Person.self], inMemory: true)
}
