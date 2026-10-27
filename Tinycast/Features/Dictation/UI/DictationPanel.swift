import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
@Observable
final class DictationDisplayState {
    enum Phase { case listening, transcribing }
    var phase: Phase = .listening
    var levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
    /// Soniox's running transcript: settled words, then its still-changing guess.
    private(set) var previewFinal = ""
    private(set) var previewTentative = ""

    func appendPreview(final: String, tentative: String) {
        previewFinal = String((previewFinal + final).suffix(DictationPreview.characterLimit))
        previewTentative = tentative
    }

    func clearPreview() {
        previewFinal = ""
        previewTentative = ""
    }
}

private enum DictationPreview {
    static let characterLimit = 400
    /// Enough words that the oldest ones can fade out on the left while the newest stay readable.
    static let visibleWords = 12
    static let expandedWidth: CGFloat = 360
    static let compactBars = 7
    static let fadeWidth: CGFloat = 56
}

/// The newest words on one line, right-aligned, so older ones slide left into a fade.
private struct DictationPreviewLine: View {
    let state: DictationDisplayState

    var body: some View {
        let finalWords = state.previewFinal.split(whereSeparator: \.isWhitespace)
        let guessWords = state.previewTentative.split(whereSeparator: \.isWhitespace)
        let guessShown = Array(guessWords.suffix(DictationPreview.visibleWords))
        let finalShown = finalWords.suffix(DictationPreview.visibleWords - guessShown.count)
        let settled = Text(verbatim: finalShown.joined(separator: " ")).foregroundStyle(Color.white)
        let separator = finalShown.isEmpty || guessShown.isEmpty ? "" : " "
        let guess = Text(verbatim: separator + guessShown.joined(separator: " "))
            .foregroundStyle(Color.white.opacity(0.45))
        Color.clear
            .overlay(alignment: .trailing) {
                Text("\(settled)\(guess)")
                    .font(.body)
                    .lineLimit(1)
                    .fixedSize()
            }
            .clipped()
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black], startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: DictationPreview.fadeWidth)
                    Color.black
                }
            }
            .animation(.easeOut(duration: 0.12), value: state.previewFinal + state.previewTentative)
            .accessibilityLabel("Dictation preview")
    }
}

private struct DictationWaveform: View {
    let levels: [Float]
    let processing: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.dictationWaveGap) {
            ForEach(levels.indices, id: \.self) { index in
                let emphasis =
                    processing
                    ? Double(levels[index])
                    : min(1, Double(min(index, levels.count - 1 - index)) / 3)
                Capsule()
                    .fill(Color.white.opacity(0.4 + 0.6 * emphasis))
                    .frame(
                        width: Theme.Size.dictationWaveBar,
                        height: 3 + (processing ? 9 : 25) * CGFloat(levels[index]))
            }
        }
        .animation(.easeOut(duration: 0.06), value: levels)
    }
}

private struct DictationProcessingWave: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let progress =
                timeline.date.timeIntervalSince(startedAt)
                .truncatingRemainder(dividingBy: 1.2) / 1.2
            let center = (reduceMotion ? 0.5 : progress) * 28 - 4
            DictationWaveform(
                levels: (0..<DictationSpectrum.barCount).map { index in
                    Float(max(0, 1 - abs(Double(index) - center) / 4))
                }, processing: true)
        }
    }
}

private struct DictationPanelView: View {
    let state: DictationDisplayState

    private var showsText: Bool { !state.previewFinal.isEmpty || !state.previewTentative.isEmpty }

    var body: some View {
        let height = Theme.Size.dictationPanel.height
        HStack(spacing: 0) {
            waveform
                .frame(width: showsText ? height : Theme.Size.dictationPanel.width, height: height)
            if showsText {
                DictationPreviewLine(state: state)
                    .padding(.trailing, Theme.Spacing.lg)
                    .transition(.opacity)
            }
        }
        .frame(
            width: showsText ? DictationPreview.expandedWidth : Theme.Size.dictationPanel.width,
            height: height)
        .background(DictationFlatSurface(shape: .capsule))
        .animation(.spring(duration: 0.3, bounce: 0.1), value: showsText)
        .frame(
            width: DictationPanelController.panelSize.width,
            height: DictationPanelController.panelSize.height)
    }

    /// Every third band while text shows, so the wave fits a square beside it.
    private func shown(_ levels: [Float]) -> [Float] {
        guard showsText else { return levels }
        let step = max(1, levels.count / DictationPreview.compactBars)
        return stride(from: step / 2, to: levels.count, by: step).map { levels[$0] }
    }

    @ViewBuilder
    private var waveform: some View {
        if state.phase == .listening {
            let levels = shown(state.levels)
            DictationWaveform(
                levels: levels.enumerated().map { index, level in
                    let edge = min(1, Float(min(index, levels.count - 1 - index)) / 4)
                    let taper = showsText ? 1 : edge * edge * (3 - 2 * edge)
                    return level * (0.2 + 0.8 * taper)
                }, processing: false
            )
            .accessibilityLabel("Dictation listening")
        } else {
            DictationProcessingWave()
                .scaleEffect(showsText ? 0.4 : 1)
                .accessibilityLabel("Transcribing dictation")
        }
    }
}

/// A flat, solid dark surface: no glass and no shadow, readable over any background.
private struct DictationFlatSurface<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(Color.black.opacity(0.88))
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private final class DictationPanel: NSPanel, AnimatedPanel {
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: DictationPanelController.panelSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = content
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        followMotion()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !event.isARepeat {
            switch Int(event.keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter: onAccept?(); return
            case kVK_Escape: onCancel?(); return
            default: break
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
final class DictationPanelController {
    static let panelSize = CGSize(
        width: max(Theme.Size.dictationPanel.width, DictationPreview.expandedWidth),
        height: Theme.Size.dictationPanel.height)
    let state = DictationDisplayState()
    private var panel: DictationPanel?
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?

    func show() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let panel =
            panel
            ?? DictationPanel(
                content: NSHostingView(rootView: DictationPanelView(state: state).motionScope()))
        panel.onAccept = onAccept
        panel.onCancel = onCancel
        self.panel = panel
        let size = Theme.Size.dictationPanel
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - Self.panelSize.width / 2,
                y: frame.minY + frame.height * 0.1 - size.height / 2))
        state.phase = .listening
        state.clearPreview()
        state.levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
