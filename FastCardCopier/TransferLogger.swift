import Foundation
import AppKit

struct TransferLogger {

    // MARK: - Log directory

    static var logDirectory: URL {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return lib.appendingPathComponent("Logs/FastCardCopier")
    }

    static func openLogFolder() {
        let dir = logDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    // MARK: - Write session log

    static func write(
        startTime: Date,
        cardName: String,
        cardPath: String,
        destination: String,
        mode: TransferMode,
        verify: Bool,
        results: [FileResult],
        skippedCount: Int,
        failedCount: Int,
        checksumFailedCount: Int,
        bytesTransferred: Int64
    ) {
        let dir = logDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filenameFmt = DateFormatter()
        filenameFmt.dateFormat = "yyyy-MM-dd_HHmmss"
        let safeName = cardName.replacingOccurrences(of: "/", with: "-")
        let logURL = dir.appendingPathComponent("\(filenameFmt.string(from: startTime))_\(safeName).log")

        let headerFmt = DateFormatter()
        headerFmt.dateStyle = .long
        headerFmt.timeStyle = .medium

        let totalTransferred = results.filter { $0.success && !$0.skipped }.count
        let gb = Double(bytesTransferred) / 1_073_741_824
        let transferredSize = gb >= 1
            ? String(format: "%.2f GB", gb)
            : String(format: "%.0f MB", gb * 1024)

        var lines: [String] = []
        lines.append("FastCardCopier Transfer Log")
        lines.append(String(repeating: "=", count: 72))
        lines.append("Date:         \(headerFmt.string(from: startTime))")
        lines.append("Source:       \(cardName)  [\(cardPath)]")
        lines.append("Destination:  \(destination)")
        lines.append("Mode:         \(mode == .move ? "Move — clear card" : "Copy — keep originals")")
        lines.append("SHA-256:      \(verify ? "enabled" : "disabled")")
        lines.append("")
        lines.append(String(format: "%-14s  %-12s  %s", "Result", "Size", "Source path"))
        lines.append(String(repeating: "-", count: 72))

        let byteFmt = ByteCountFormatter()
        byteFmt.countStyle = .file
        byteFmt.allowedUnits = [.useGB, .useMB, .useKB, .useBytes]

        for result in results where !result.filename.isEmpty {
            let status: String
            if result.skipped            { status = "SKIP" }
            else if !result.verified && !result.success { status = "CHECKSUM FAIL" }
            else if !result.success      { status = "FAIL" }
            else if mode == .move        { status = "MOVED" }
            else                         { status = "OK" }

            let sizeStr = byteFmt.string(fromByteCount: result.size)
            lines.append(String(format: "%-14s  %-12s  %@", status, sizeStr, result.sourcePath))
        }

        lines.append(String(repeating: "-", count: 72))
        lines.append("Total:        \(results.filter { !$0.filename.isEmpty }.count) files")
        lines.append("Transferred:  \(totalTransferred) files  (\(transferredSize))")
        if skippedCount > 0      { lines.append("Skipped:      \(skippedCount) files") }
        if failedCount > 0       { lines.append("Failed:       \(failedCount) files") }
        if checksumFailedCount > 0 { lines.append("Checksum errors: \(checksumFailedCount) files") }
        lines.append("")

        let content = lines.joined(separator: "\n")
        try? content.write(to: logURL, atomically: true, encoding: .utf8)
    }
}
