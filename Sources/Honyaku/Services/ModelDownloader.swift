import Foundation
import CryptoKit

enum ModelDownloadError: Error, LocalizedError {
    case checksumMismatch(expected: String, actual: String)
    case insufficientDiskSpace(needed: Int64, available: Int64)
    case downloadFailed(URLError)
    case fileSystemError(Error)

    var errorDescription: String? {
        switch self {
        case .checksumMismatch: return "Download corrupted — please retry."
        case .insufficientDiskSpace(let needed, let available):
            return "Need \(needed / 1_000_000) MB but only \(available / 1_000_000) MB available."
        case .downloadFailed(let e): return "Download failed: \(e.localizedDescription)"
        case .fileSystemError(let e): return e.localizedDescription
        }
    }
}

actor ModelDownloader: ModelDownloading {
    private let store = ModelStore.shared
    private let session: URLSession
    // Track whether this download is user-initiated (for the network audit)
    nonisolated static let isModelDownload = "com.honyaku.isModelDownload"

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated func isDownloaded(_ model: ModelInfo) -> Bool {
        ModelStore.shared.isDownloaded(model)
    }

    nonisolated func delete(_ model: ModelInfo) throws {
        try ModelStore.shared.delete(model)
    }

    func download(model: ModelInfo, progress: @escaping @Sendable (Double) -> Void) async throws {
        let targetDir = store.modelDirectory(for: model)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // Mark directory as excluded from backup
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        var mutableURL = targetDir
        try? mutableURL.setResourceValues(rv)

        // Disk space pre-check
        let neededBytes = Int64(model.sizeMB) * 1_000_000
        if let available = try? targetDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage {
            if available < neededBytes {
                throw ModelDownloadError.insufficientDiskSpace(needed: neededBytes, available: available)
            }
        }

        let hfToken = KeychainService.load(key: KeychainService.hfTokenKey)

        // MLX models: fileNames is empty — fetch the repo file listing from the HF API first
        let fileNames: [String]
        if model.fileNames.isEmpty {
            fileNames = try await fetchMLXRepoFiles(repoPath: model.hfRepoPath, token: hfToken)
        } else {
            fileNames = model.fileNames
        }

        let baseURLString = "https://huggingface.co/\(model.hfRepoPath)/resolve/main"

        for (index, fileName) in fileNames.enumerated() {
            let fileProgress: @Sendable (Double) -> Void = { p in
                let base = Double(index) / Double(fileNames.count)
                let step = 1.0 / Double(fileNames.count)
                progress(base + p * step)
            }
            let downloadURL = URL(string: "\(baseURLString)/\(fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName)")!
            var request = URLRequest(url: downloadURL)
            request.setValue("Honyaku/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("true", forHTTPHeaderField: "X-Honyaku-Model-Download")
            if let token = hfToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            // Preserve subdirectory structure (e.g. tokenizer files)
            let destURL = targetDir.appendingPathComponent(fileName)
            let destDir = destURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

            try await downloadFile(request: request, to: destURL, progress: fileProgress)
        }

        progress(1.0)
    }

    /// Fetches the list of files in a HuggingFace repo and returns those needed to run an MLX model.
    private func fetchMLXRepoFiles(repoPath: String, token: String?) async throws -> [String] {
        let apiURL = URL(string: "https://huggingface.co/api/models/\(repoPath)")!
        var request = URLRequest(url: apiURL)
        request.setValue("Honyaku/1.0", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, _) = try await session.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let siblings = json["siblings"] as? [[String: Any]] else {
            throw ModelDownloadError.downloadFailed(URLError(.badServerResponse))
        }

        let allowed: Set<String> = ["safetensors", "json", "txt", "model", "tiktoken"]
        return siblings.compactMap { $0["rfilename"] as? String }.filter { name in
            guard let ext = name.split(separator: ".").last.map(String.init) else { return false }
            return allowed.contains(ext)
        }
    }

    // MARK: - Helpers

    private func downloadFile(request: URLRequest, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = session.downloadTask(with: request) { tempURL, response, error in
                if let error = error as? URLError {
                    continuation.resume(throwing: ModelDownloadError.downloadFailed(error))
                    return
                }
                guard let tempURL else {
                    continuation.resume(throwing: ModelDownloadError.downloadFailed(URLError(.badServerResponse)))
                    return
                }
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: ModelDownloadError.fileSystemError(error))
                }
            }
            task.resume()
            // Note: progress reporting via observation omitted for brevity;
            // use URLSessionDownloadDelegate for production progress tracking
        }
    }

    private func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func unzip(at zipURL: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", directory.path]
        try process.run()
        process.waitUntilExit()
    }
}
