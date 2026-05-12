import Foundation

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

@MainActor
class FileTransferManager: ObservableObject {
    @Published var state: TransferState = .idle
    @Published var totalFiles = 0
    @Published var completedFiles = 0
    @Published var failedCount = 0
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
                    guard !Task.isCancelled else { return FileResult(filename: "", size: 0, success: false) }

                    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
                    let dest = destination.appendingPathComponent(file.lastPathComponent)
                    do {
                        if mode == .copy {
                            if FileManager.default.fileExists(atPath: dest.path) {
                                try FileManager.default.removeItem(at: dest)
                            }
                            try FileManager.default.copyItem(at: file, to: dest)
                        } else {
                            try FileManager.default.moveItem(at: file, to: dest)
                        }
                        return FileResult(filename: file.lastPathComponent, size: size, success: true)
                    } catch {
                        return FileResult(filename: file.lastPathComponent, size: size, success: false)
                    }
                }
            }
            for await result in group {
                guard !result.filename.isEmpty else { continue }
                completedFiles += 1
                bytesTransferred += result.size
                currentFile = result.filename
                if !result.success { failedCount += 1 }
            }
        }

        state = Task.isCancelled ? .idle : .complete
    }
}
