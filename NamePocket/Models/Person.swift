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
    var photoFilename: String?

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
    }
}
