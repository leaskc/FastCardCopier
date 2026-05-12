import Foundation
import AppKit

struct DetectedCard: Equatable {
    let name: String
    let url: URL
    let files: [URL]
    let rawCount: Int
    let jpgCount: Int
    let videoCount: Int
    let audioCount: Int
    let totalBytes: Int64

    var totalFiles: Int { files.count }
    var totalGBString: String {
        let gb = Double(totalBytes) / 1_073_741_824
        return gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", gb * 1024)
    }

    static func == (lhs: DetectedCard, rhs: DetectedCard) -> Bool { lhs.url == rhs.url }
}

@MainActor
class CardDetector: ObservableObject {
    @Published var detectedCard: DetectedCard?
    @Published var isScanning = false

    private var mountObserver: NSObjectProtocol?
    private var unmountObserver: NSObjectProtocol?

    init() {
        startMonitoring()
        checkExistingVolumes()
    }

    deinit {
        if let obs = mountObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        if let obs = unmountObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
    }

    private func startMonitoring() {
        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            Task { @MainActor [weak self] in await self?.handleMount(url) }
        }
        unmountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            Task { @MainActor [weak self] in self?.handleUnmount(url) }
        }
    }

    private func checkExistingVolumes() {
        let keys: [URLResourceKey] = [.volumeIsRemovableKey]
        guard let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [])
        else { return }
        for volume in volumes where isLikelyMemoryCard(volume) {
            Task { await handleMount(volume) }
            return
        }
    }

    private func isLikelyMemoryCard(_ url: URL) -> Bool {
        // Only require the volume to be removable — do not check volumeIsInternal,
        // which is true for built-in SD card readers on MacBook Pro / Mac mini even
        // though the media itself is removable. scanCard acts as the real filter:
        // volumes with no recognised media files return nil.
        guard let v = try? url.resourceValues(forKeys: [.volumeIsRemovableKey])
        else { return false }
        return v.volumeIsRemovable == true
    }

    private func handleMount(_ url: URL) async {
        guard isLikelyMemoryCard(url) else { return }
        isScanning = true
        let card = await Task.detached(priority: .userInitiated) {
            CardDetector.scanCard(at: url)
        }.value
        isScanning = false
        guard let card else { return }
        detectedCard = card
    }

    private func handleUnmount(_ url: URL) {
        if detectedCard?.url == url { detectedCard = nil }
    }

    func rescan() {
        guard let card = detectedCard else { return }
        Task { await handleMount(card.url) }
    }

    nonisolated static func scanCard(at url: URL) -> DetectedCard? {
        let rawExts: Set<String> = ["arw","cr2","cr3","nef","nrw","orf","rw2","dng","raf",
                                    "3fr","erf","kdc","mrw","pef","r3d","srw","x3f"]
        let jpgExts: Set<String> = ["jpg","jpeg","tif","tiff","heic","heif","png"]
        let vidExts: Set<String> = ["mp4","mov","mts","m2ts","m4v","avi","mxf"]
        let audExts: Set<String> = ["wav","aif","aiff","mp3","flac","m4a","bwf"]
        let allExts = rawExts.union(jpgExts).union(vidExts).union(audExts)

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var files: [URL] = []
        var rawCount = 0, jpgCount = 0, videoCount = 0, audioCount = 0
        var totalBytes: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  vals.isRegularFile == true
            else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard allExts.contains(ext) else { continue }
            files.append(fileURL)
            totalBytes += Int64(vals.fileSize ?? 0)
            if rawExts.contains(ext)      { rawCount += 1 }
            else if jpgExts.contains(ext) { jpgCount += 1 }
            else if vidExts.contains(ext) { videoCount += 1 }
            else                          { audioCount += 1 }
        }
        guard !files.isEmpty else { return nil }
        return DetectedCard(name: url.lastPathComponent, url: url, files: files,
                            rawCount: rawCount, jpgCount: jpgCount, videoCount: videoCount,
                            audioCount: audioCount, totalBytes: totalBytes)
    }
}
