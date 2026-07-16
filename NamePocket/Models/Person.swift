import Foundation
import SwiftData

@Model
final class Person {
    var id: UUID
    var name: String
    var phoneNumber: String
    var email: String
    var notes: String
    var createdAt: Date
    var deletedAt: Date?
    // Legacy field kept for store compatibility — no longer written.
    // Photos are looked up by person id (see PhotoRepository).
    var photoFilename: String?

    // Scalar mirror of category?.id — see Category.parentCategoryID for why
    // this exists. Kept in sync manually at every write site (init,
    // TrashView detach).
    var categoryID: UUID?

    @Relationship(deleteRule: .nullify)
    var category: Category?

    init(name: String, phoneNumber: String = "", email: String = "", notes: String = "", category: Category? = nil) {
        self.id = UUID()
        self.name = name
        self.phoneNumber = phoneNumber
        self.email = email
        self.notes = notes
        self.createdAt = Date()
        self.category = category
        self.categoryID = category?.id
    }
}
