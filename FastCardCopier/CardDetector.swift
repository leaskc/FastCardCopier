import Foundation
import AppKit

struct DetectedCard: Equatable {
    let name: String
    let url: URL
    let files: [URL]

    static func == (lhs: DetectedCard, rhs: DetectedCard) -> Bool {
        lhs.url == rhs.url
    }
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
        let keys: [URLResourceKey] = [.volumeIsRemovableKey, .volumeIsInternalKey]
        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: []
        ) else { return }
        for volume in volumes where isLikelyMemoryCard(volume) {
            Task { await handleMount(volume) }
            return
        }
    }

    private func isLikelyMemoryCard(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsInternalKey])
        else { return false }
        return values.volumeIsRemovable == true && values.volumeIsInternal != true
    }

    private func handleMount(_ url: URL) async {
        guard isLikelyMemoryCard(url) else { return }
        isScanning = true
        let files = await Task.detached(priority: .userInitiated) {
            CardDetector.discoverPhotoFiles(at: url)
        }.value
        isScanning = false
        guard !files.isEmpty else { return }
        detectedCard = DetectedCard(name: url.lastPathComponent, url: url, files: files)
    }

    private func handleUnmount(_ url: URL) {
        if detectedCard?.url == url { detectedCard = nil }
    }

    func rescan() {
        guard let card = detectedCard else { return }
        Task { await handleMount(card.url) }
    }

    nonisolated static func discoverPhotoFiles(at url: URL) -> [URL] {
        let extensions: Set<String> = [
            "arw", "cr2", "cr3", "nef", "nrw", "orf", "rw2", "dng", "raf",
            "3fr", "erf", "kdc", "mrw", "pef", "r3d", "srw", "x3f",
            "jpg", "jpeg", "tif", "tiff", "heic", "heif", "png",
            "mp4", "mov", "mts", "m2ts", "m4v", "avi", "mxf"
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  extensions.contains(fileURL.pathExtension.lowercased())
            else { continue }
            results.append(fileURL)
        }
        return results
    }
}
