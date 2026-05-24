import SwiftUI

struct PersonPhotoView: View {
    let personId: String
    @State private var url: URL? = nil

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .task {
            url = try? await PhotoRepository.shared.photoURL(personId: personId)
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundStyle(.green)
    }
}
