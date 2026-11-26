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
        previewFinal += final
        previewTentative = tentative
        // Trimmed rarely and in one big cut, so the line view can absorb it as a single jump.
        guard previewFinal.count > DictationPreview.characterLimit * 2 else { return }
        let tail = previewFinal.suffix(DictationPreview.characterLimit)
        previewFinal = String(tail.drop { !$0.isWhitespace })
    }

    /// The translation as it streams in, replacing the spoken line rather than following it.
    func showTranslation(_ text: String) {
        let flattened = text.replacing("\n", with: " ")
        previewFinal =
            flattened.count > DictationPreview.characterLimit
            ? String(flattened.suffix(DictationPreview.characterLimit)) : flattened
        previewTentative = ""
    }

    func clearPreview() {
        previewFinal = ""
        previewTentative = ""
    }
}

private enum DictationPreview {
    static let characterLimit = 300
    static let expandedWidth: CGFloat = 360
    static let compactBars = 7
    static let fadeWidth: CGFloat = 56
    static let trailingFadeWidth: CGFloat = 28
    /// How far the newest end rests from the edge, so it sits in the fade's clear half.
    static let trailingRest: CGFloat = 14
    /// A shrink this large is a trim, not a revised guess, so it moves without animation.
    static let trimJump: CGFloat = 120
    static let scroll = Animation.smooth(duration: 0.45)
}

/// The whole running line, scrolled so its newest end stays in view; a spring keeps its pace.
private struct DictationPreviewLine: View {
    let state: DictationDisplayState
    @State private var lineWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        let final = String(state.previewFinal.trimmingPrefix(while: \.isWhitespace))
        let tentative = final.isEmpty
            ? String(state.previewTentative.trimmingPrefix(while: \.isWhitespace))
            : state.previewTentative
        let settled = Text(verbatim: final).foregroundStyle(Color.white)
        let guess = Text(verbatim: tentative).foregroundStyle(Color.white.opacity(0.45))
        Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                boxWidth = width
                settle(animated: false)
            }
            .overlay(alignment: .leading) {
                Text("\(settled)\(guess)")
                    .font(.body)
                    .lineLimit(1)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        let trimmed = width < lineWidth - DictationPreview.trimJump
                        lineWidth = width
                        settle(animated: !trimmed)
                    }
                    .offset(x: offset)
            }
            .clipped()
            .mask {
                HStack(spacing: 0) {
                    ZStack {
                        LinearGradient(
                            colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        // Opaque until the line scrolls, so the phrase's first words stay readable.
                        Color.black.opacity(offset < 0 ? 0 : 1)
                    }
                    .frame(width: DictationPreview.fadeWidth)
                    Color.black
                    LinearGradient(
                        colors: [.black, .clear], startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: DictationPreview.trailingFadeWidth)
                }
                .animation(.easeOut(duration: 0.3), value: offset < 0)
            }
            .accessibilityLabel("Dictation preview")
    }

    private func settle(animated: Bool) {
        let target = min(0, boxWidth - DictationPreview.trailingRest - lineWidth)
        guard target != offset else { return }
        if animated {
            withAnimation(DictationPreview.scroll) { offset = target }
        } else {
            offset = target
        }
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

/// The live waveform, or the processing wave once recording stops; `compact` thins it beside text.
private struct DictationActivity: View {
    let state: DictationDisplayState
    let compact: Bool

    var body: some View {
        if state.phase == .listening {
            let levels = shown(state.levels)
            DictationWaveform(
                levels: levels.enumerated().map { index, level in
                    let edge = min(1, Float(min(index, levels.count - 1 - index)) / 4)
                    let taper = compact ? 1 : edge * edge * (3 - 2 * edge)
                    return level * (0.2 + 0.8 * taper)
                }, processing: false
            )
            .accessibilityLabel("Dictation listening")
        } else {
            DictationProcessingWave()
                .scaleEffect(compact ? 0.4 : 1)
                .accessibilityLabel("Transcribing dictation")
        }
    }

    /// Every third band when compact, so the wave fits a square.
    private func shown(_ levels: [Float]) -> [Float] {
        guard compact else { return levels }
        let step = max(1, levels.count / DictationPreview.compactBars)
        return stride(from: step / 2, to: levels.count, by: step).map { levels[$0] }
    }
}

private extension DictationDisplayState {
    var showsText: Bool { !previewFinal.isEmpty || !previewTentative.isEmpty }
}

private struct DictationPanelView: View {
    let state: DictationDisplayState

    var body: some View {
        let height = Theme.Size.dictationPanel.height
        let showsText = state.showsText
        HStack(spacing: 0) {
            DictationActivity(state: state, compact: showsText)
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
            width: DictationPanelController.pillSize.width,
            height: DictationPanelController.pillSize.height)
    }
}

/// The built-in display's camera housing, which the notch layout grows out of.
private struct DictationNotch {
    let width: CGFloat
    let height: CGFloat

    static let wingWidth: CGFloat = 64
    static let expandedWidth: CGFloat = 520
    static let textRowHeight: CGFloat = 44
    static let cornerRadius: CGFloat = 18

    var panelSize: CGSize {
        CGSize(width: max(Self.expandedWidth, width + 2 * Self.wingWidth), height: height + Self.textRowHeight)
    }

    /// Only a lone notched built-in display gets it; any external display keeps the pill.
    init?(screens: [NSScreen]) {
        guard screens.count == 1, let screen = screens.first,
            screen.safeAreaInsets.top > 0,
            let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea
        else { return nil }
        width = screen.frame.width - left.width - right.width
        height = screen.safeAreaInsets.top
    }
}

/// Black like the notch, so it reads as the housing growing down to show the transcript.
private struct DictationNotchView: View {
    let state: DictationDisplayState
    let notch: DictationNotch

    var body: some View {
        let showsText = state.showsText
        let wing = DictationNotch.wingWidth
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                DictationActivity(state: state, compact: true)
                    .frame(width: wing, height: notch.height)
                Spacer(minLength: notch.width)
            }
            if showsText {
                DictationPreviewLine(state: state)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .frame(height: DictationNotch.textRowHeight)
                    .transition(.opacity)
            }
        }
        .frame(width: showsText ? notch.panelSize.width : notch.width + 2 * wing)
        .background(
            UnevenRoundedRectangle(
                bottomLeadingRadius: DictationNotch.cornerRadius,
                bottomTrailingRadius: DictationNotch.cornerRadius
            )
            .fill(Color.black))
        .animation(.spring(duration: 0.3, bounce: 0.1), value: showsText)
        .frame(width: notch.panelSize.width, height: notch.panelSize.height, alignment: .top)
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

    init(content: NSView, size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
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

    /// The notch layout sits over the menu bar, which AppKit would otherwise push it below.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
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
    static let pillSize = CGSize(
        width: max(Theme.Size.dictationPanel.width, DictationPreview.expandedWidth),
        height: Theme.Size.dictationPanel.height)
    let state = DictationDisplayState()
    private var panel: DictationPanel?
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?

    func show() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let panel = panel ?? makePanel(on: screen)
        panel.onAccept = onAccept
        panel.onCancel = onCancel
        self.panel = panel
        state.phase = .listening
        state.clearPreview()
        state.levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel(on screen: NSScreen) -> DictationPanel {
        if let notch = DictationNotch(screens: NSScreen.screens) {
            let size = notch.panelSize
            let panel = DictationPanel(
                content: NSHostingView(
                    rootView: DictationNotchView(state: state, notch: notch).motionScope()),
                size: size)
            panel.level = .statusBar
            panel.setFrameOrigin(
                NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height))
            return panel
        }
        let frame = screen.visibleFrame
        let panel = DictationPanel(
            content: NSHostingView(rootView: DictationPanelView(state: state).motionScope()),
            size: Self.pillSize)
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - Self.pillSize.width / 2,
                y: frame.minY + frame.height * 0.1 - Theme.Size.dictationPanel.height / 2))
        return panel
    }
}
