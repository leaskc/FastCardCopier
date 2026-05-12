import Foundation
import CryptoKit

enum TransferMode: String, CaseIterable {
    case copy = "Copy"
    case move = "Move"
}

enum CollisionMode: String, CaseIterable {
    case rename    = "Rename"     // append _2, _3… — never loses data
    case skip      = "Skip"       // leave existing file, mark as skipped
    case overwrite = "Overwrite"  // replace existing file
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
    let skipped: Bool   // file existed and collision mode is .skip
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

/// Returns the path of `file` relative to `root`, or nil if file is directly in root.
/// e.g. /Volumes/CARD/DCIM/100EOS/IMG_0001.CR3 relative to /Volumes/CARD → "DCIM/100EOS"
private func relativeSubdirectory(of file: URL, from root: URL) -> String? {
    let filePath = file.standardized.path
    var rootPath = root.standardized.path
    if !rootPath.hasSuffix("/") { rootPath += "/" }
    guard filePath.hasPrefix(rootPath) else { return nil }
    let rel = String(filePath.dropFirst(rootPath.count))
    let dir = URL(fileURLWithPath: rel).deletingLastPathComponent().path
    return (dir == "." || dir == "") ? nil : dir
}

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

/// Copies `source` into a hidden `.tmp-{uuid}` file, then atomically renames it to `dest`.
/// The file is never visible at its final path until the copy is complete, so watch-folder
/// apps never see a partial file.
///
/// When `verify` is true, the temp file is re-read after writing and its SHA-256 is compared
/// against the source hash captured during the copy. Throws CopyError.checksumMismatch
/// (and removes the temp) if they differ. When `verify` is false the rename happens
/// immediately after the write — no extra read pass.
private func copyAndVerify(from source: URL, to dest: URL, verify: Bool) throws -> String {
    let dir    = dest.deletingLastPathComponent()
    let tmpURL = dir.appendingPathComponent(".\(UUID().uuidString).tmp")

    // ── 1. Stream-copy while hashing the source (hashing is free vs. I/O) ─
    let src = try FileHandle(forReadingFrom: source)
    defer { try? src.close() }

    FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
    let dst = try FileHandle(forWritingTo: tmpURL)

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
        try? FileManager.default.removeItem(at: tmpURL)
        throw error
    }
    let srcDigest = srcHasher.finalize()

    // ── 2. (Optional) Re-read temp and compare hashes ────────────────────
    if verify {
        let fh = try FileHandle(forReadingFrom: tmpURL)
        defer { try? fh.close() }

        var dstHasher = SHA256()
        while true {
            guard let chunk = try fh.read(upToCount: kBufSize), !chunk.isEmpty else { break }
            dstHasher.update(data: chunk)
        }

        guard srcDigest == dstHasher.finalize() else {
            try? FileManager.default.removeItem(at: tmpURL)
            throw CopyError.checksumMismatch
        }
    }

    // ── 3. Preserve source timestamps on the temp file before rename ─────
    //    (moveItem carries the temp's attributes forward, so we must stamp
    //     before the rename, not after)
    if let srcAttrs = try? FileManager.default.attributesOfItem(atPath: source.path) {
        var stamp: [FileAttributeKey: Any] = [:]
        if let d = srcAttrs[.creationDate]     { stamp[.creationDate]     = d }
        if let d = srcAttrs[.modificationDate] { stamp[.modificationDate] = d }
        try? FileManager.default.setAttributes(stamp, ofItemAtPath: tmpURL.path)
    }

    // ── 4. Atomic rename → dest (file appears at final path only now) ─────
    do {
        try FileManager.default.moveItem(at: tmpURL, to: dest)
    } catch {
        try? FileManager.default.removeItem(at: tmpURL)
        throw error
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
    @Published var skippedCount = 0
    @Published var verifyEnabled = true   // reflects the setting used for the current/last run
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

    func start(files: [URL], destination: URL, mode: TransferMode,
               collisionMode: CollisionMode = .rename, verify: Bool = true,
               preserveStructure: Bool = false, cardRootURL: URL? = nil, cardName: String = "",
               totalBytes: Int64 = 0) {
        state = .running
        totalFiles = files.count
        completedFiles = 0
        failedCount = 0
        checksumFailedCount = 0
        skippedCount = 0
        verifyEnabled = verify
        currentFile = ""
        bytesTransferred = 0
        totalTransferBytes = totalBytes
        startTime = Date()
        transferTask = Task {
            await performTransfer(files: files, destination: destination,
                                  mode: mode, collisionMode: collisionMode, verify: verify,
                                  preserveStructure: preserveStructure,
                                  cardRootURL: cardRootURL, cardName: cardName,
                                  startTime: self.startTime ?? Date())
        }
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
        skippedCount = 0
        currentFile = ""
        bytesTransferred = 0
        totalTransferBytes = 0
        startTime = nil
    }

    private func performTransfer(files: [URL], destination: URL,
                                  mode: TransferMode, collisionMode: CollisionMode,
                                  verify: Bool, preserveStructure: Bool,
                                  cardRootURL: URL?, cardName: String,
                                  startTime: Date) async {
        // When preserving structure, all files go under a single dated session folder.
        let rootDest: URL
        if preserveStructure {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd_HHmmss"
            let folderName = cardName.isEmpty
                ? fmt.string(from: startTime)
                : "\(fmt.string(from: startTime)) \(cardName)"
            rootDest = destination.appendingPathComponent(folderName)
        } else {
            rootDest = destination
        }

        do {
            try FileManager.default.createDirectory(at: rootDest, withIntermediateDirectories: true)
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
                        return FileResult(filename: "", size: 0, success: false,
                                          verified: false, skipped: false)
                    }

                    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                        .map { Int64($0) } ?? 0

                    // Resolve the target directory for this file
                    let targetDir: URL
                    if preserveStructure, let root = cardRootURL,
                       let subdir = relativeSubdirectory(of: file, from: root) {
                        targetDir = rootDest.appendingPathComponent(subdir)
                        // createDirectory is idempotent with intermediates; safe for concurrent tasks
                        try? FileManager.default.createDirectory(
                            at: targetDir, withIntermediateDirectories: true)
                    } else {
                        targetDir = rootDest
                    }

                    // Resolve destination path based on collision mode
                    let destURL: URL
                    switch collisionMode {
                    case .rename:
                        destURL = uniqueDestination(for: file, in: targetDir)
                    case .skip:
                        let candidate = targetDir.appendingPathComponent(file.lastPathComponent)
                        if FileManager.default.fileExists(atPath: candidate.path) {
                            return FileResult(filename: file.lastPathComponent, size: 0,
                                              success: true, verified: true, skipped: true)
                        }
                        destURL = candidate
                    case .overwrite:
                        destURL = targetDir.appendingPathComponent(file.lastPathComponent)
                        // Pre-remove so the atomic rename inside copyAndVerify can succeed
                        try? FileManager.default.removeItem(at: destURL)
                    }

                    do {
                        _ = try copyAndVerify(from: file, to: destURL, verify: verify)

                        // For Move: only delete source after confirmed good copy
                        if mode == .move {
                            try FileManager.default.removeItem(at: file)
                        }

                        return FileResult(filename: file.lastPathComponent, size: size,
                                          success: true, verified: true, skipped: false)
                    } catch CopyError.checksumMismatch {
                        // temp already removed by copyAndVerify
                        return FileResult(filename: file.lastPathComponent, size: size,
                                          success: false, verified: false, skipped: false)
                    } catch {
                        return FileResult(filename: file.lastPathComponent, size: size,
                                          success: false, verified: false, skipped: false)
                    }
                }
            }

            for await result in group {
                guard !result.filename.isEmpty else { continue }
                completedFiles += 1
                currentFile = result.filename
                if result.skipped {
                    skippedCount += 1
                } else if result.success {
                    bytesTransferred += result.size
                } else {
                    if !result.verified { checksumFailedCount += 1 }
                    else { failedCount += 1 }
                }
            }
        }

        state = Task.isCancelled ? .idle : .complete
    }
}
