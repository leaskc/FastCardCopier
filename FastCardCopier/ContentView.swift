import SwiftUI
import AppKit

// MARK: - Color helpers

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let a, r, g, b: UInt64
        switch s.count {
        case 3:  (a, r, g, b) = (255, (v >> 8) * 17, (v >> 4 & 0xF) * 17, (v & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, v >> 16, v >> 8 & 0xFF, v & 0xFF)
        case 8:  (a, r, g, b) = (v >> 24, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Window drag support

struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> DragNSView { DragNSView() }
    func updateNSView(_ nsView: DragNSView, context: Context) {}
    class DragNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

// MARK: - Window configurator (transparent titlebar + movable background)

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let window = v.window else { return }
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .clear
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Design tokens

private let sysBlue       = Color(hex: "0a84ff")
private let sysBlueLight  = Color(hex: "9bb6ff")  // blue on dark bg
private let successGreen  = Color(hex: "28a745")
private let warnOrange    = Color(hex: "ff9500")

// MARK: - Shared component: CardRow

struct CardRow<Trailing: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String?
    let iconName: String
    let iconColor: Color
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.colorScheme) private var cs

    init(eyebrow: String, title: String, subtitle: String? = nil,
         iconName: String, iconColor: Color,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.eyebrow = eyebrow; self.title = title; self.subtitle = subtitle
        self.iconName = iconName; self.iconColor = iconColor; self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(cs == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    .frame(width: 38, height: 38)
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(eyebrow)
                    .font(.system(size: 10.5, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(cardBackground)
    }

    private var cardBackground: some View {
        let fill = cs == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.7)
        let stroke = cs == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        let inner = cs == .dark ? Color.clear : Color.white.opacity(0.7)
        return RoundedRectangle(cornerRadius: 12)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(stroke, lineWidth: 0.5))
            .shadow(color: inner, radius: 0, x: 0, y: -1)
    }
}

// MARK: - Shared component: StatBadge (RAW / JPG / MOV counts)

struct StatBadge: View {
    let label: String
    let value: Int
    let accent: Bool
    @Environment(\.colorScheme) private var cs

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(value)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(accent
                    ? (cs == .dark ? sysBlueLight : sysBlue)
                    : (cs == .dark ? Color.white : Color(hex: "1c1c1e")))
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
}

// MARK: - Shared component: KV row (transfer stats)

struct KVRow: View {
    let key: String
    let value: String
    let mono: Bool
    @Environment(\.colorScheme) private var cs

    init(_ key: String, _ value: String, mono: Bool = false) {
        self.key = key; self.value = value; self.mono = mono
    }

    var body: some View {
        HStack {
            Text(key).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 12, design: .rounded))
                .monospacedDigit()
                .foregroundColor(cs == .dark ? .white : Color(hex: "1c1c1e"))
        }
        .font(.system(size: 12))
        .padding(.vertical, 4)
        Divider().opacity(0.4)
    }
}

// MARK: - Shared component: Ring progress

struct RingProgress: View {
    let progress: Double
    let remaining: Int
    @Environment(\.colorScheme) private var cs

    var body: some View {
        ZStack {
            Circle()
                .stroke(cs == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1)))
                .stroke(sysBlue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)
            VStack(spacing: 1) {
                Text("\(remaining)")
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: remaining)
                Text("FILES LEFT")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 200, height: 200)
    }
}

// MARK: - Shared component: Primary button

struct PrimaryButton: View {
    let label: String
    let disabled: Bool
    let variant: Variant
    let action: () -> Void
    @Environment(\.colorScheme) private var cs

    enum Variant { case blue, green, danger }

    init(_ label: String, disabled: Bool = false, variant: Variant = .blue, action: @escaping () -> Void) {
        self.label = label; self.disabled = disabled; self.variant = variant; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(disabled
                    ? (cs == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.3))
                    : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(disabled
                            ? (cs == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                            : bgColor)
                        .shadow(color: disabled ? .clear : Color.black.opacity(0.18), radius: 1, y: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var bgColor: Color {
        switch variant {
        case .blue:   return sysBlue
        case .green:  return successGreen
        case .danger: return Color(hex: "ff453a")
        }
    }
}

// MARK: - Shared component: Secondary button

struct SecondaryButton: View {
    let label: String
    let action: () -> Void
    @Environment(\.colorScheme) private var cs

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(cs == .dark ? .white : Color(hex: "1c1c1e"))
                .frame(height: 36)
                .padding(.horizontal, 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(cs == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - State: Idle

struct IdleStateView: View {
    let isScanning: Bool
    @Environment(\.colorScheme) private var cs

    var body: some View {
        Spacer()
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(muted, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: 96, height: 96)
                if isScanning {
                    ProgressView().scaleEffect(1.2)
                } else {
                    Image(systemName: "sdcard")
                        .font(.system(size: 38, weight: .light))
                        .foregroundColor(muted)
                }
            }
            VStack(spacing: 4) {
                Text(isScanning ? "Scanning card…" : "Waiting for card")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(cs == .dark ? Color(hex: "f3f4f7") : Color(hex: "1c1c1e"))
                Text(isScanning ? "Finding your photos" : "Insert an SD or CF card to begin")
                    .font(.system(size: 13))
                    .foregroundColor(muted)
            }
        }
        Spacer()
    }

    private var muted: Color { cs == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.45) }
}

// MARK: - State: No Destination

struct NoDestStateView: View {
    let card: DetectedCard
    let onChooseFolder: () -> Void
    @Environment(\.colorScheme) private var cs

    var body: some View {
        CardRow(eyebrow: "Source", title: card.name,
                subtitle: "\(card.totalFiles.formatted()) files · \(card.totalGBString)",
                iconName: "sdcard.fill",
                iconColor: cs == .dark ? sysBlueLight : sysBlue)

        // Orange warning
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(warnOrange).frame(width: 24, height: 24)
                Text("!").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose a destination folder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(cs == .dark ? Color(hex: "ffb84d") : Color(hex: "a85a00"))
                Text("FastCard Copier needs to know where to put these photos. Pick a folder your editor watches for ingest.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "ff9500").opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "ff9500").opacity(0.4), lineWidth: 0.5))
        )

        Spacer()
        PrimaryButton("Choose folder…", action: onChooseFolder)
    }
}

// MARK: - State: Ready

struct ReadyStateView: View {
    let card: DetectedCard
    @Binding var transferModeRaw: String
    @Binding var autoCopy: Bool
    let destinationPath: String
    let onChangeDestination: () -> Void
    let onStartTransfer: () -> Void
    @Environment(\.colorScheme) private var cs

    private var transferMode: TransferMode { TransferMode(rawValue: transferModeRaw) ?? .copy }
    private var muted: Color { cs == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55) }
    private var destName: String {
        URL(fileURLWithPath: destinationPath).lastPathComponent
    }

    var body: some View {
        // Source card with RAW/JPG/MOV stats
        CardRow(eyebrow: "Source", title: card.name,
                subtitle: "\(card.totalFiles.formatted()) files · \(card.totalGBString)",
                iconName: "sdcard.fill",
                iconColor: cs == .dark ? sysBlueLight : sysBlue) {
            HStack(spacing: 14) {
                StatBadge(label: "RAW", value: card.rawCount, accent: true)
                StatBadge(label: "JPG", value: card.jpgCount, accent: false)
                if card.videoCount > 0 {
                    StatBadge(label: "MOV", value: card.videoCount, accent: false)
                }
            }
        }

        // Destination card
        CardRow(eyebrow: "Destination", title: destName,
                subtitle: destinationPath,
                iconName: "folder.fill",
                iconColor: cs == .dark ? Color(hex: "e4c97a") : Color(hex: "c08a1a")) {
            Button("Change…") { onChangeDestination() }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(cs == .dark ? sysBlueLight : sysBlue)
                .buttonStyle(.plain)
        }

        Spacer()

        // Auto-start + mode row
        HStack {
            Toggle(isOn: $autoCopy) {
                Text("Auto-start when card inserted")
                    .font(.system(size: 12))
                    .foregroundColor(muted)
            }
            .toggleStyle(.switch)
            .tint(sysBlue)
            .labelsHidden()
            Text("Auto-start when card inserted")
                .font(.system(size: 12))
                .foregroundColor(muted)
                .onTapGesture { autoCopy.toggle() }
            Spacer()
            Text(transferMode == .copy ? "Copy · keep originals" : "Move · remove from card")
                .font(.system(size: 12))
                .foregroundColor(muted)
        }

        // Copy button
        PrimaryButton("Copy \(card.totalFiles.formatted()) files · \(card.totalGBString)",
                      action: onStartTransfer)
    }
}

// MARK: - State: Transferring

struct TransferringStateView: View {
    @ObservedObject var manager: FileTransferManager
    let cardName: String
    let onCancel: () -> Void

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 32) {
            RingProgress(progress: manager.progress, remaining: manager.remainingFiles)

            VStack(alignment: .leading, spacing: 0) {
                Text("Copying from")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundColor(.secondary)
                Text(cardName)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.top, 2)
                    .padding(.bottom, 14)

                VStack(spacing: 0) {
                    KVRow("Progress", "\(manager.completedFiles.formatted()) / \(manager.totalFiles.formatted())")
                    if let mbps = manager.throughputMBps {
                        KVRow("Throughput", String(format: "%.0f MB/s", mbps))
                    }
                    if let eta = manager.etaSeconds {
                        KVRow("Time remaining", formatSeconds(eta))
                    } else {
                        KVRow("Elapsed", elapsedString)
                    }
                    if !manager.currentFile.isEmpty {
                        KVRow("Current", manager.currentFile, mono: true)
                    }
                }
                .font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)

        SecondaryButton(label: "Cancel", action: onCancel)
            .frame(maxWidth: .infinity, alignment: .center)
        .onReceive(timer) { now = $0 }
    }

    private var elapsedString: String {
        guard let start = manager.startTime else { return "—" }
        let s = Int(now.timeIntervalSince(start))
        let m = s / 60; let r = s % 60
        return m > 0 ? "\(m)m \(String(format: "%02d", r))s" : "\(r)s"
    }

    private func formatSeconds(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        let m = s / 60; let r = s % 60
        return "\(m)m \(String(format: "%02d", r))s"
    }
}

// MARK: - State: Complete

struct CompleteStateView: View {
    @ObservedObject var manager: FileTransferManager
    let destinationURL: URL?
    let cardURL: URL?
    let onReset: () -> Void
    @Environment(\.colorScheme) private var cs

    private var durationString: String {
        guard let start = manager.startTime else { return "" }
        let s = Int(-start.timeIntervalSinceNow)
        let m = s / 60; let r = s % 60
        return m > 0 ? "\(m)m \(r)s" : "\(s)s"
    }

    private var summaryLine: String {
        var parts: [String] = []
        if manager.bytesTransferred > 0 {
            let gb = Double(manager.bytesTransferred) / 1_073_741_824
            parts.append(gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", gb * 1024))
        }
        if !durationString.isEmpty { parts.append(durationString) }
        if let mbps = manager.throughputMBps { parts.append(String(format: "%.0f MB/s avg", mbps)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Spacer()
        VStack(spacing: 18) {
            // Big green circle
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: "34d058"), Color(hex: "28a745")],
                                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 140, height: 140)
                    .shadow(color: Color(hex: "28a745").opacity(0.4), radius: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 6) {
                Text("All \(manager.totalFiles.formatted()) files copied")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                if !summaryLine.isEmpty {
                    Text(summaryLine)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                if manager.failedCount > 0 {
                    Text("\(manager.failedCount) file\(manager.failedCount == 1 ? "" : "s") failed")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
            }
        }
        Spacer()

        HStack(spacing: 10) {
            // Eject card
            if let cardURL {
                Button(action: { NSWorkspace.shared.unmountAndEjectDevice(atPath: cardURL.path) }) {
                    Text("Eject card")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .stroke(cs == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .foregroundColor(cs == .dark ? .white : Color(hex: "1c1c1e"))
            }

            // Reveal in Finder
            if let dest = destinationURL {
                Button(action: { NSWorkspace.shared.open(dest) }) {
                    Text("Reveal in Finder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 9).fill(sysBlue))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Main ContentView

struct ContentView: View {
    @StateObject private var cardDetector = CardDetector()
    @StateObject private var transferManager = FileTransferManager()

    @AppStorage("destinationPath") private var destinationPath = ""
    @AppStorage("transferMode") private var transferModeRaw = TransferMode.copy.rawValue
    @AppStorage("autoCopy") private var autoCopy = false
    @AppStorage("useDarkMode") private var useDarkMode = false

    @Environment(\.colorScheme) private var cs
    private var isDark: Bool { cs == .dark }

    private var destinationURL: URL? {
        destinationPath.isEmpty ? nil : URL(fileURLWithPath: destinationPath)
    }

    private enum AppState {
        case idle, scanning
        case ready(DetectedCard)
        case noDestination(DetectedCard)
        case transferring
        case complete
    }

    private var appState: AppState {
        if transferManager.isComplete { return .complete }
        if transferManager.isRunning  { return .transferring }
        if let card = cardDetector.detectedCard {
            return destinationPath.isEmpty ? .noDestination(card) : .ready(card)
        }
        return cardDetector.isScanning ? .scanning : .idle
    }

    var body: some View {
        ZStack {
            // Full-window gradient background
            windowGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom title bar
                titleBar

                Divider()
                    .opacity(isDark ? 0.06 : 0.08)

                // State content
                VStack(spacing: 14) {
                    stateContent
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 520, height: 490)
        .preferredColorScheme(useDarkMode ? .dark : .light)
        .background(WindowConfigurator())
        .onChange(of: cardDetector.detectedCard) { _, newCard in
            guard autoCopy, let card = newCard, let dest = destinationURL,
                  !transferManager.isRunning, !transferManager.isComplete
            else { return }
            transferManager.start(files: card.files, destination: dest,
                                  mode: transferMode, totalBytes: card.totalBytes)
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        ZStack {
            // Drag area behind everything
            WindowDragView()

            HStack(spacing: 0) {
                // Space for macOS traffic lights (52px)
                Spacer().frame(width: 52)

                Spacer()
                Text("FastCard Copier")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? Color.white.opacity(0.75) : Color.black.opacity(0.7))
                    .kerning(-0.1)
                Spacer()

                // Dark/light mode toggle
                Button(action: { useDarkMode.toggle() }) {
                    Image(systemName: isDark ? "sun.max" : "moon")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(isDark ? "Switch to Light Mode" : "Switch to Dark Mode")
                .padding(.trailing, 10)
            }
        }
        .frame(height: 40)
        .background(
            isDark ? Color.white.opacity(0.02) : Color.white.opacity(0.45),
            in: Rectangle()
        )
    }

    // MARK: - State content switch

    @ViewBuilder
    private var stateContent: some View {
        switch appState {
        case .idle:
            IdleStateView(isScanning: false)
        case .scanning:
            IdleStateView(isScanning: true)
        case .noDestination(let card):
            NoDestStateView(card: card, onChooseFolder: chooseDestination)
        case .ready(let card):
            ReadyStateView(
                card: card,
                transferModeRaw: $transferModeRaw,
                autoCopy: $autoCopy,
                destinationPath: destinationPath,
                onChangeDestination: chooseDestination,
                onStartTransfer: {
                    guard let dest = destinationURL else { return }
                    transferManager.start(files: card.files, destination: dest,
                                          mode: transferMode, totalBytes: card.totalBytes)
                }
            )
        case .transferring:
            TransferringStateView(
                manager: transferManager,
                cardName: cardDetector.detectedCard?.name ?? "Card",
                onCancel: { transferManager.cancel() }
            )
        case .complete:
            CompleteStateView(
                manager: transferManager,
                destinationURL: destinationURL,
                cardURL: cardDetector.detectedCard?.url,
                onReset: { transferManager.reset() }
            )
        }
    }

    // MARK: - Helpers

    private var transferMode: TransferMode { TransferMode(rawValue: transferModeRaw) ?? .copy }

    private var windowGradient: LinearGradient {
        isDark
            ? LinearGradient(colors: [Color(hex: "2a2c30"), Color(hex: "1f2125")], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(hex: "e9eaf0"), Color(hex: "e2e3ea")], startPoint: .top, endPoint: .bottom)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.title = "Choose Ingest Destination"
        panel.message = "Select the folder where photos will be ingested"
        if panel.runModal() == .OK, let url = panel.url { destinationPath = url.path }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
