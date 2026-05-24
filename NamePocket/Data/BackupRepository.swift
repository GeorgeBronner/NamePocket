import Foundation
import ZIPFoundation

actor BackupRepository {
    static let shared = BackupRepository()

    private let fileManager = FileManager.default

    private var appSupportDir: URL {
        get throws {
            try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true)
        }
    }

    private var photosDir: URL {
        get throws { try appSupportDir.appendingPathComponent("photos", isDirectory: true) }
    }

    // MARK: - Backup

    func backup() throws -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        let tempZip = fileManager.temporaryDirectory
            .appendingPathComponent("namepocket_backup_\(timestamp).zip")

        guard let archive = Archive(url: tempZip, accessMode: .create) else {
            throw BackupError.archiveCreationFailed
        }

        let dbBase = try appSupportDir.appendingPathComponent("default.store")
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: dbBase.path + suffix)
            if fileManager.fileExists(atPath: src.path) {
                try archive.addEntry(with: "namepocket_database.sqlite\(suffix)", fileURL: src)
            }
        }

        let photos = try photosDir
        if fileManager.fileExists(atPath: photos.path) {
            let files = (try? fileManager.contentsOfDirectory(
                at: photos, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "jpg" {
                try archive.addEntry(with: "photos/\(file.lastPathComponent)", fileURL: file)
            }
        }

        return tempZip
    }

    // MARK: - Stage Restore (applied on next launch)

    func stageRestore(from zipURL: URL) throws {
        let header = try Data(contentsOf: zipURL, options: .mappedIfSafe).prefix(2)
        guard header == Data([0x50, 0x4B]) else { throw BackupError.unsupportedFormat }

        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            throw BackupError.archiveReadFailed
        }

        let pendingDir = try appSupportDir.appendingPathComponent("pending_restore", isDirectory: true)
        if fileManager.fileExists(atPath: pendingDir.path) {
            try fileManager.removeItem(at: pendingDir)
        }
        try fileManager.createDirectory(at: pendingDir, withIntermediateDirectories: true)

        let pendingPhotos = pendingDir.appendingPathComponent("photos", isDirectory: true)
        try fileManager.createDirectory(at: pendingPhotos, withIntermediateDirectories: true)

        for entry in archive {
            if entry.path.hasPrefix("namepocket_database.sqlite") {
                let suffix = String(entry.path.dropFirst("namepocket_database.sqlite".count))
                let dest = pendingDir.appendingPathComponent("default.store\(suffix)")
                _ = try archive.extract(entry, to: dest)
            } else if entry.path.hasPrefix("photos/") {
                let filename = (entry.path as NSString).lastPathComponent
                let dest = pendingPhotos.appendingPathComponent(filename)
                _ = try archive.extract(entry, to: dest)
            }
        }

        UserDefaults.standard.set(true, forKey: "pendingRestore")
    }

    // MARK: - Apply Pending Restore (called on launch, before SwiftData init)

    nonisolated static func applyPendingRestoreIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "pendingRestore") else { return }
        let fm = FileManager.default
        guard let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: true) else { return }
        let pendingDir = appSupport.appendingPathComponent("pending_restore", isDirectory: true)
        guard fm.fileExists(atPath: pendingDir.path) else {
            UserDefaults.standard.removeObject(forKey: "pendingRestore")
            return
        }

        for suffix in ["", "-wal", "-shm"] {
            let src = pendingDir.appendingPathComponent("default.store\(suffix)")
            let dest = appSupport.appendingPathComponent("default.store\(suffix)")
            if fm.fileExists(atPath: src.path) {
                try? fm.removeItem(at: dest)
                try? fm.moveItem(at: src, to: dest)
            } else {
                try? fm.removeItem(at: dest)
            }
        }

        let destPhotos = appSupport.appendingPathComponent("photos", isDirectory: true)
        let srcPhotos = pendingDir.appendingPathComponent("photos", isDirectory: true)
        try? fm.removeItem(at: destPhotos)
        if fm.fileExists(atPath: srcPhotos.path) {
            try? fm.moveItem(at: srcPhotos, to: destPhotos)
        }

        try? fm.removeItem(at: pendingDir)
        UserDefaults.standard.removeObject(forKey: "pendingRestore")
    }
}

enum BackupError: Error {
    case archiveCreationFailed
    case archiveReadFailed
    case unsupportedFormat
}
