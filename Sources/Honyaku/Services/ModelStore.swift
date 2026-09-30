import Foundation

final class ModelStore {
    static let shared = ModelStore()

    private let baseURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Honyaku/Models", isDirectory: true)
    }()

    private init() {
        try? setupBaseDirectory()
    }

    private func setupBaseDirectory() throws {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        var mutableURL = baseURL
        try mutableURL.setResourceValues(rv)
    }

    var baseDirectory: URL { baseURL }

    func modelDirectory(for model: ModelInfo) -> URL {
        baseURL.appendingPathComponent("\(model.type.rawValue)/\(model.id)", isDirectory: true)
    }

    func isDownloaded(_ model: ModelInfo) -> Bool {
        let dir = modelDirectory(for: model)
        // Registry models list no files; each engine decides what a complete install looks like
        if model.fileNames.isEmpty {
            return ModelInstaller.isInstalled(model)
        }
        return model.fileNames.allSatisfy { fileName in
            let stripped = (fileName as NSString).deletingPathExtension  // handle .zip
            let fileURL = dir.appendingPathComponent(stripped.isEmpty ? fileName : stripped)
            return FileManager.default.fileExists(atPath: fileURL.path) ||
                   FileManager.default.fileExists(atPath: dir.appendingPathComponent(fileName).path)
        }
    }

    func delete(_ model: ModelInfo) throws {
        let dir = modelDirectory(for: model)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    func sizeOnDisk(_ model: ModelInfo) -> Int64 {
        let dir = modelDirectory(for: model)
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return enumerator.reduce(into: Int64(0)) { total, item in
            guard let url = item as? URL,
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return }
            total += Int64(size)
        }
    }
}
