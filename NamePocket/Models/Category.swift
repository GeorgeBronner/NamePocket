import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID
    var name: String
    var createdAt: Date
    var deletedAt: Date?

    // Scalar mirror of parentCategory?.id. SwiftData does not compile
    // predicates that traverse a relationship (e.g. `parentCategory?.id ==`)
    // down to SQL in this project — it evaluates them in Swift instead,
    // which is what caused the George-folder freeze. Filtering @Query on
    // this plain UUID column instead lets the fetch actually happen in SQL.
    // Kept in sync manually at every write site (init, TrashView detach) —
    // see CategoryListView's @Query init for how it's used.
    var parentCategoryID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \Category.parentCategory)
    var subcategories: [Category]?

    @Relationship(deleteRule: .nullify)
    var parentCategory: Category?

    @Relationship(deleteRule: .cascade, inverse: \Person.category)
    var people: [Person]?

    init(name: String, parentCategory: Category? = nil) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.parentCategory = parentCategory
        self.parentCategoryID = parentCategory?.id
        self.subcategories = []
        self.people = []
    }
}
