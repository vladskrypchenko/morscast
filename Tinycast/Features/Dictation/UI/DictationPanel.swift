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
    static let width: CGFloat = 520
    static let height: CGFloat = 64
    static let gap: CGFloat = 8
}

private struct DictationPreviewBubble: View {
    let state: DictationDisplayState

    var body: some View {
        let final = String(state.previewFinal.trimmingPrefix(while: \.isWhitespace))
        let tentative = final.isEmpty
            ? String(state.previewTentative.trimmingPrefix(while: \.isWhitespace))
            : state.previewTentative
        let settled = Text(verbatim: final).foregroundStyle(Color.white)
        let guess = Text(verbatim: tentative).foregroundStyle(Color.white.opacity(0.45))
        Text("\(settled)\(guess)")
            .font(.body)
            .lineLimit(2)
            .truncationMode(.head)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(DictationFlatSurface(shape: .rect(cornerRadius: Theme.Radius.formField)))
            .frame(maxWidth: DictationPreview.width)
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

    var body: some View {
        VStack(spacing: DictationPreview.gap) {
            if !state.previewFinal.isEmpty || !state.previewTentative.isEmpty {
                DictationPreviewBubble(state: state)
            }
            capsule
        }
        .frame(
            width: DictationPanelController.panelSize.width,
            height: DictationPanelController.panelSize.height, alignment: .bottom)
    }

    private var capsule: some View {
        Group {
            if state.phase == .listening {
                DictationWaveform(
                    levels: state.levels.enumerated().map { index, level in
                        let edge = min(1, Float(min(index, state.levels.count - 1 - index)) / 4)
                        let taper = edge * edge * (3 - 2 * edge)
                        return level * (0.2 + 0.8 * taper)
                    }, processing: false
                )
                .accessibilityLabel("Dictation listening")
            } else {
                DictationProcessingWave()
                    .accessibilityLabel("Transcribing dictation")
            }
        }
        .frame(width: Theme.Size.dictationPanel.width, height: Theme.Size.dictationPanel.height)
        .background(DictationFlatSurface(shape: .capsule))
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
        width: max(Theme.Size.dictationPanel.width, DictationPreview.width),
        height: Theme.Size.dictationPanel.height + DictationPreview.gap + DictationPreview.height)
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
