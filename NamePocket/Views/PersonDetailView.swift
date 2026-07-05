import SwiftUI
import SwiftData

struct PersonDetailView: View {
    @Bindable var person: Person
    @Environment(\.modelContext) private var modelContext

    @State private var photoURL: URL? = nil
    @State private var showingPhotoPicker = false
    @State private var showingPhotoOptions = false
    @State private var showingPhotoError = false
    @State private var photoErrorMessage = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let url = photoURL {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().scaledToFill()
                                    default:
                                        Image(systemName: "person.circle.fill")
                                            .resizable()
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .onTapGesture { showingPhotoOptions = true }

                        Image(systemName: "camera.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                            .onTapGesture { showingPhotoOptions = true }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

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
        .task { await loadPhoto() }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoPicker { image in savePhoto(image) }
        }
        .confirmationDialog("Photo", isPresented: $showingPhotoOptions) {
            if photoURL != nil {
                Button("Replace Photo") { showingPhotoPicker = true }
                Button("Remove Photo", role: .destructive) { removePhoto() }
            } else {
                Button("Choose from Library") { showingPhotoPicker = true }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't Save Photo", isPresented: $showingPhotoError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoErrorMessage)
        }
    }

    private func loadPhoto() async {
        photoURL = try? await PhotoRepository.shared.photoURL(personId: person.id.uuidString)
    }

    private func savePhoto(_ image: UIImage) {
        Task {
            do {
                _ = try await PhotoRepository.shared.savePhoto(
                    personId: person.id.uuidString, image: image)
                if var url = try await PhotoRepository.shared.photoURL(personId: person.id.uuidString) {
                    url = url.appending(queryItems: [URLQueryItem(name: "t", value: "\(Date().timeIntervalSince1970)")])
                    photoURL = url
                }
            } catch {
                photoErrorMessage = error.localizedDescription
                showingPhotoError = true
            }
        }
    }

    private func removePhoto() {
        Task {
            try? await PhotoRepository.shared.deletePhoto(personId: person.id.uuidString)
            photoURL = nil
        }
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
