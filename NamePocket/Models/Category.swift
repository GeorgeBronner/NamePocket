import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID
    var name: String
    var createdAt: Date

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
        self.subcategories = []
        self.people = []
    }
}
