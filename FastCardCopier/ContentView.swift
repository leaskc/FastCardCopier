import SwiftUI

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
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

struct ContentView: View {
    @StateObject private var cardDetector = CardDetector()
    @StateObject private var transferManager = FileTransferManager()

    @AppStorage("destinationPath") private var destinationPath = ""
    @AppStorage("transferMode") private var transferModeRaw = TransferMode.copy.rawValue
    @AppStorage("autoCopy") private var autoCopy = false

    private var transferMode: TransferMode {
        TransferMode(rawValue: transferModeRaw) ?? .copy
    }

    private var destinationURL: URL? {
        destinationPath.isEmpty ? nil : URL(fileURLWithPath: destinationPath)
    }

    var body: some View {
        ZStack {
            Color(hex: "131313").ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar

                Color(hex: "414755").opacity(0.3)
                    .frame(height: 1)

                VStack(spacing: 14) {
                    statusCard
                    destinationRow
                    modeAndActionRow
                    autoCopyRow
                }
                .padding(16)
                .padding(.bottom, 4)
            }
        }
        .frame(width: 400)
        .preferredColorScheme(.dark)
        .onChange(of: cardDetector.detectedCard) { _, newCard in
            guard autoCopy, let card = newCard, let dest = destinationURL,
                  !transferManager.isRunning, !transferManager.isComplete
            else { return }
            transferManager.start(files: card.files, destination: dest, mode: transferMode)
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sdcard.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "adc6ff"))
            Text("FastCard Copier")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "e5e2e1"))
            Spacer()
            if cardDetector.isScanning {
                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                    Text("Scanning…")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "c1c6d7").opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Status Card

    private var statusCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(statusBackground)

            statusContent
        }
        .frame(height: 170)
        .shadow(color: Color(hex: "0e0e0e").opacity(0.5), radius: 8, y: 2)
        .animation(.easeInOut(duration: 0.3), value: transferManager.isComplete)
        .animation(.easeInOut(duration: 0.3), value: transferManager.isRunning)
    }

    private var statusBackground: Color {
        if transferManager.isComplete { return Color(hex: "192919") }
        if transferManager.isRunning  { return Color(hex: "151e30") }
        if cardDetector.detectedCard != nil { return Color(hex: "202020") }
        return Color(hex: "1b1b1c")
    }

    @ViewBuilder
    private var statusContent: some View {
        if transferManager.isComplete {
            completeView
        } else if transferManager.isRunning {
            runningView
        } else if let card = cardDetector.detectedCard {
            readyView(card: card)
        } else {
            waitingView
        }
    }

    private var waitingView: some View {
        VStack(spacing: 10) {
            Image(systemName: "sdcard")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundColor(Color(hex: "c1c6d7").opacity(0.25))
            Text("Waiting for card…")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "c1c6d7").opacity(0.4))
        }
    }

    private func readyView(card: DetectedCard) -> some View {
        VStack(spacing: 2) {
            Text(card.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "c1c6d7").opacity(0.6))
                .lineLimit(1)

            Text("\(card.files.count)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "e5e2e1"))
                .monospacedDigit()

            Text(card.files.count == 1 ? "file found" : "files found")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "c1c6d7").opacity(0.6))
        }
    }

    private var runningView: some View {
        VStack(spacing: 4) {
            Text("\(transferManager.remainingFiles)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "adc6ff"))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(response: 0.25, dampingFraction: 0.8),
                           value: transferManager.remainingFiles)

            Text(transferManager.remainingFiles == 1 ? "file remaining" : "files remaining")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "c1c6d7").opacity(0.6))

            ProgressView(value: transferManager.progress)
                .tint(Color(hex: "adc6ff"))
                .frame(width: 260)
                .padding(.top, 6)
        }
    }

    private var completeView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(Color(hex: "4CAF50"))

            Text("Transfer complete")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: "81C784"))

            if transferManager.failedCount > 0 {
                Text("\(transferManager.failedCount) file\(transferManager.failedCount == 1 ? "" : "s") failed")
                    .font(.system(size: 11))
                    .foregroundColor(.orange.opacity(0.8))
            }
        }
    }

    // MARK: - Destination Row

    private var destinationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DESTINATION")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(hex: "c1c6d7").opacity(0.45))
                .tracking(1.5)

            Button(action: chooseDestination) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundColor(destinationPath.isEmpty
                            ? Color(hex: "adc6ff").opacity(0.35)
                            : Color(hex: "adc6ff").opacity(0.75))

                    Text(destinationPath.isEmpty ? "No folder selected — tap to choose" : destinationPath)
                        .font(.system(size: 12))
                        .foregroundColor(destinationPath.isEmpty
                            ? Color(hex: "c1c6d7").opacity(0.35)
                            : Color(hex: "e5e2e1"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "c1c6d7").opacity(0.3))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "353535"))
                )
            }
            .buttonStyle(.plain)
            .disabled(transferManager.isRunning)
        }
    }

    // MARK: - Mode and Action Row

    private var modeAndActionRow: some View {
        HStack(spacing: 10) {
            modePicker
            Spacer()
            actionButton
        }
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(TransferMode.allCases, id: \.self) { mode in
                Button(action: { transferModeRaw = mode.rawValue }) {
                    Text(mode.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(transferMode == mode
                            ? Color(hex: "131313")
                            : Color(hex: "c1c6d7").opacity(0.55))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(transferMode == mode ? Color(hex: "adc6ff") : .clear)
                        )
                }
                .buttonStyle(.plain)
                .disabled(transferManager.isRunning || transferManager.isComplete)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(hex: "1b1b1c"))
        )
    }

    @ViewBuilder
    private var actionButton: some View {
        if transferManager.isComplete {
            Button(action: { transferManager.reset() }) {
                Label("New Transfer", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "81C784"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "192919"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(hex: "4CAF50").opacity(0.35), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        } else if transferManager.isRunning {
            Button(action: { transferManager.cancel() }) {
                Label("Cancel", systemImage: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "e5e2e1").opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "353535"))
                    )
            }
            .buttonStyle(.plain)
        } else {
            let ready = cardDetector.detectedCard != nil && !destinationPath.isEmpty
            Button(action: triggerTransfer) {
                HStack(spacing: 6) {
                    Image(systemName: transferMode == .copy
                          ? "doc.on.doc.fill"
                          : "arrow.right.doc.on.clipboard")
                        .font(.system(size: 12))
                    Text("Start \(transferMode.rawValue)")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(ready ? .white : Color(hex: "e5e2e1").opacity(0.25))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ready
                            ? LinearGradient(
                                colors: [Color(hex: "4b8eff"), Color(hex: "adc6ff")],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(
                                colors: [Color(hex: "2a2a2a"), Color(hex: "2a2a2a")],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                )
            }
            .buttonStyle(.plain)
            .disabled(!ready)
        }
    }

    // MARK: - Auto-copy Row

    private var autoCopyRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-copy on insert")
                    .font(.system(size: 12))
                    .foregroundColor(destinationPath.isEmpty
                        ? Color(hex: "e5e2e1").opacity(0.3)
                        : Color(hex: "e5e2e1").opacity(0.8))
                Text("Starts immediately when a card is detected")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "c1c6d7").opacity(0.35))
            }
            Spacer()
            Toggle("", isOn: $autoCopy)
                .toggleStyle(.switch)
                .tint(Color(hex: "adc6ff"))
                .disabled(destinationPath.isEmpty)
                .labelsHidden()
        }
        .padding(.top, 2)
    }

    // MARK: - Actions

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.title = "Choose Ingest Destination"
        panel.message = "Select the folder where photos will be copied"
        if panel.runModal() == .OK, let url = panel.url {
            destinationPath = url.path
        }
    }

    private func triggerTransfer() {
        guard let card = cardDetector.detectedCard, let dest = destinationURL else { return }
        transferManager.start(files: card.files, destination: dest, mode: transferMode)
    }
}

#Preview {
    ContentView()
}
