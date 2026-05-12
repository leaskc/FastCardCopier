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

actor TransferSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { count = limit }

    func wait() async {
        if count > 0 { count -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if let first = waiters.first {
            waiters.removeFirst()
            first.resume()
        } else {
            count += 1
        }
    }
}

@MainActor
class FileTransferManager: ObservableObject {
    @Published var state: TransferState = .idle
    @Published var totalFiles = 0
    @Published var completedFiles = 0
    @Published var currentFile = ""
    @Published var failedCount = 0

    var remainingFiles: Int { max(0, totalFiles - completedFiles) }
    var progress: Double { totalFiles > 0 ? Double(completedFiles) / Double(totalFiles) : 0 }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var isComplete: Bool {
        if case .complete = state { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let msg) = state { return msg }
        return nil
    }

    private var transferTask: Task<Void, Never>?

    func start(files: [URL], destination: URL, mode: TransferMode) {
        state = .running
        totalFiles = files.count
        completedFiles = 0
        failedCount = 0
        currentFile = ""

        transferTask = Task {
            await performTransfer(files: files, destination: destination, mode: mode)
        }
    }

    func cancel() {
        transferTask?.cancel()
        transferTask = nil
        state = .idle
    }

    func reset() {
        state = .idle
        totalFiles = 0
        completedFiles = 0
        currentFile = ""
        failedCount = 0
    }

    private func performTransfer(files: [URL], destination: URL, mode: TransferMode) async {
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            state = .failed("Cannot create destination: \(error.localizedDescription)")
            return
        }

        let semaphore = TransferSemaphore(limit: 4)

        await withTaskGroup(of: Bool.self) { group in
            for file in files {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
                    guard !Task.isCancelled else { return false }

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
                        return true
                    } catch {
                        return false
                    }
                }
            }

            for await success in group {
                completedFiles += 1
                if !success { failedCount += 1 }
            }
        }

        if Task.isCancelled {
            state = .idle
        } else {
            state = .complete
        }
    }
}
