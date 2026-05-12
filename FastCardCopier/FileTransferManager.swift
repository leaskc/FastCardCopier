import Foundation
import CryptoKit

enum TransferMode: String, CaseIterable {
    case copy = "Copy"
    case move = "Move"
}

enum TransferState {
    case idle
    case running
    case complete
    case failed(String)
}

struct FileResult {
    let filename: String
    let size: Int64
    let success: Bool
    let verified: Bool  // checksum matched; false also when success is false
}

actor TransferSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { count = limit }
    func wait() async {
        if count > 0 { count -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func signal() {
        if let first = waiters.first { waiters.removeFirst(); first.resume() } else { count += 1 }
    }
}

// MARK: - Streaming copy with inline source hash + destination verification

private let kBufSize = 4 * 1024 * 1024  // 4 MB — good balance for card I/O

private enum CopyError: Error { case writeFailed, checksumMismatch }

private func uniqueDestination(for source: URL, in directory: URL) -> URL {
    var candidate = directory.appendingPathComponent(source.lastPathComponent)
    guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
    let stem = source.deletingPathExtension().lastPathComponent
    let ext  = source.pathExtension
    var i = 2
    repeat {
        let name = ext.isEmpty ? "\(stem)_\(i)" : "\(stem)_\(i).\(ext)"
        candidate = directory.appendingPathComponent(name)
        i += 1
    } while FileManager.default.fileExists(atPath: candidate.path)
    return candidate
}

/// Copies `source` → `dest`, hashing the source inline as it reads, then
/// re-reads the destination to verify. Returns the hex digest on success.
/// Throws CopyError.checksumMismatch (and removes the partial dest) if hashes differ.
private func copyAndVerify(from source: URL, to dest: URL) throws -> String {
    // ── 1. Stream-copy while hashing the source ──────────────────────────
    let src = try FileHandle(forReadingFrom: source)
    defer { try? src.close() }

    FileManager.default.createFile(atPath: dest.path, contents: nil)
    let dst = try FileHandle(forWritingTo: dest)

    var srcHasher = SHA256()
    do {
        while true {
            guard let chunk = try src.read(upToCount: kBufSize), !chunk.isEmpty else { break }
            srcHasher.update(data: chunk)
            try dst.write(contentsOf: chunk)
        }
        try dst.close()
    } catch {
        try? dst.close()
        try? FileManager.default.removeItem(at: dest)
        throw error
    }
    let srcDigest = srcHasher.finalize()

    // ── 2. Re-read destination and hash it ───────────────────────────────
    let verify = try FileHandle(forReadingFrom: dest)
    defer { try? verify.close() }

    var dstHasher = SHA256()
    while true {
        guard let chunk = try verify.read(upToCount: kBufSize), !chunk.isEmpty else { break }
        dstHasher.update(data: chunk)
    }
    let dstDigest = dstHasher.finalize()

    // ── 3. Compare ────────────────────────────────────────────────────────
    guard srcDigest == dstDigest else {
        try? FileManager.default.removeItem(at: dest)
        throw CopyError.checksumMismatch
    }

    return srcDigest.compactMap { String(format: "%02x", $0) }.joined()
}

// MARK: - FileTransferManager

@MainActor
class FileTransferManager: ObservableObject {
    @Published var state: TransferState = .idle
    @Published var totalFiles = 0
    @Published var completedFiles = 0
    @Published var failedCount = 0
    @Published var checksumFailedCount = 0
    @Published var currentFile = ""
    @Published var bytesTransferred: Int64 = 0
    var totalTransferBytes: Int64 = 0
    var startTime: Date?

    var remainingFiles: Int { max(0, totalFiles - completedFiles) }
    var progress: Double { totalFiles > 0 ? Double(completedFiles) / Double(totalFiles) : 0 }

    var isRunning: Bool { if case .running = state { return true }; return false }
    var isComplete: Bool { if case .complete = state { return true }; return false }

    var throughputMBps: Double? {
        guard let start = startTime, bytesTransferred > 1_048_576 else { return nil }
        let elapsed = max(0.5, -start.timeIntervalSinceNow)
        return Double(bytesTransferred) / elapsed / 1_048_576
    }

    var etaSeconds: Int? {
        guard let mbps = throughputMBps, mbps > 0 else { return nil }
        let remaining = max(0, totalTransferBytes - bytesTransferred)
        return Int(Double(remaining) / (mbps * 1_048_576))
    }

    private var transferTask: Task<Void, Never>?

    func start(files: [URL], destination: URL, mode: TransferMode, totalBytes: Int64 = 0) {
        state = .running
        totalFiles = files.count
        completedFiles = 0
        failedCount = 0
        checksumFailedCount = 0
        currentFile = ""
        bytesTransferred = 0
        totalTransferBytes = totalBytes
        startTime = Date()
        transferTask = Task { await performTransfer(files: files, destination: destination, mode: mode) }
    }

    func cancel() {
        transferTask?.cancel()
        transferTask = nil
        state = .idle
        startTime = nil
    }

    func reset() {
        state = .idle
        totalFiles = 0
        completedFiles = 0
        failedCount = 0
        checksumFailedCount = 0
        currentFile = ""
        bytesTransferred = 0
        totalTransferBytes = 0
        startTime = nil
    }

    private func performTransfer(files: [URL], destination: URL, mode: TransferMode) async {
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            state = .failed("Cannot create destination: \(error.localizedDescription)")
            return
        }

        let semaphore = TransferSemaphore(limit: 4)

        await withTaskGroup(of: FileResult.self) { group in
            for file in files {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
                    guard !Task.isCancelled else {
                        return FileResult(filename: "", size: 0, success: false, verified: false)
                    }

                    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                        .map { Int64($0) } ?? 0
                    let dest = uniqueDestination(for: file, in: destination)

                    do {
                        // Copy with inline source hash + destination read-back verification
                        _ = try copyAndVerify(from: file, to: dest)

                        // For Move: only delete source after confirmed good copy
                        if mode == .move {
                            try FileManager.default.removeItem(at: file)
                        }

                        return FileResult(filename: file.lastPathComponent, size: size,
                                          success: true, verified: true)
                    } catch CopyError.checksumMismatch {
                        // dest already removed by copyAndVerify
                        return FileResult(filename: file.lastPathComponent, size: size,
                                          success: false, verified: false)
                    } catch {
                        try? FileManager.default.removeItem(at: dest)
                        return FileResult(filename: file.lastPathComponent, size: size,
                                          success: false, verified: false)
                    }
                }
            }

            for await result in group {
                guard !result.filename.isEmpty else { continue }
                completedFiles += 1
                bytesTransferred += result.size
                currentFile = result.filename
                if !result.success {
                    if result.verified == false { checksumFailedCount += 1 }
                    else { failedCount += 1 }
                }
            }
        }

        state = Task.isCancelled ? .idle : .complete
    }
}
