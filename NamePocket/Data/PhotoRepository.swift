import UIKit

actor PhotoRepository {
    static let shared = PhotoRepository()

    private let fileManager = FileManager.default

    var photosDir: URL {
        get throws {
            let dir = try fileManager
                .url(for: .applicationSupportDirectory, in: .userDomainMask,
                     appropriateFor: nil, create: true)
                .appendingPathComponent("photos", isDirectory: true)
            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir
        }
    }

    func savePhoto(personId: String, image: UIImage) throws -> String {
        guard let jpeg = compressedJpeg(from: image) else {
            throw PhotoError.compressionFailed
        }
        let filename = "\(personId).jpg"
        let dest = try photosDir.appendingPathComponent(filename)
        try jpeg.write(to: dest, options: .atomic)
        return filename
    }

    func deletePhoto(personId: String) throws {
        let file = try photosDir.appendingPathComponent("\(personId).jpg")
        if fileManager.fileExists(atPath: file.path) {
            try fileManager.removeItem(at: file)
        }
    }

    func photoURL(personId: String) throws -> URL? {
        let file = try photosDir.appendingPathComponent("\(personId).jpg")
        return fileManager.fileExists(atPath: file.path) ? file : nil
    }

    func pruneOrphans(validPersonIds: Set<String>) throws {
        let dir = try photosDir
        let files = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "jpg" {
            let id = file.deletingPathExtension().lastPathComponent
            if !validPersonIds.contains(id) {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func compressedJpeg(from image: UIImage, maxDimension: CGFloat = 1024) -> Data? {
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

enum PhotoError: Error {
    case compressionFailed
}
