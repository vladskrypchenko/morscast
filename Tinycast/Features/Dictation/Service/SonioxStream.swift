import Foundation

/// One Soniox connection for a whole recording: audio goes up as it is captured, and whole
/// finalized words come back through `onWords` while the user is still speaking, and every
/// message's final and tentative text goes to `onPreview` for display only.
@MainActor
final class SonioxStream {
    private let socket: URLSessionWebSocketTask
    private let onWords: (String) -> Void
    private let onPreview: (_ final: String, _ tentative: String) -> Void
    private let onFailure: (Error) -> Void
    private var sentSamples = 0
    private var sendChain: Task<Void, Never>?
    private var receiver: Task<Void, Never>?
    private var pending = ""
    private var finishing = false
    private var isOver = false
    private var failure: Error?
    private var waiter: CheckedContinuation<Void, Never>?

    init(
        apiKey: String, languageCode: String?,
        onWords: @escaping (String) -> Void,
        onPreview: @escaping (_ final: String, _ tentative: String) -> Void,
        onFailure: @escaping (Error) -> Void
    ) throws {
        socket = SonioxTranscriber.openSocket(apiKey: apiKey)
        self.onWords = onWords
        self.onPreview = onPreview
        self.onFailure = onFailure
        enqueue([try SonioxTranscriber.configMessage(languageCode: languageCode)])
        receiver = Task { [weak self] in await self?.receive() }
    }

    /// Sends whatever part of the recording has not gone up yet.
    func send(_ samples: [Float]) {
        guard !isOver, samples.count > sentSamples else { return }
        let fresh = samples[sentSamples...]
        sentSamples = samples.count
        enqueue(SonioxTranscriber.audioFrames(fresh))
    }

    /// Ends the audio and returns the finalized text not yet handed to `onWords`.
    func finish(with samples: [Float]) async throws -> String {
        finishing = true
        send(samples)
        enqueue([SonioxTranscriber.endOfAudio])
        await withTaskCancellationHandler {
            if !isOver { await withCheckedContinuation { waiter = $0 } }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
        try Task.checkCancellation()
        if let failure { throw failure }
        return pending
    }

    func cancel() {
        receiver?.cancel()
        sendChain?.cancel()
        socket.cancel(with: .goingAway, reason: nil)
        end()
    }

    private func enqueue(_ messages: [URLSessionWebSocketTask.Message]) {
        let previous = sendChain
        let socket = socket
        sendChain = Task {
            await previous?.value
            for message in messages {
                guard !Task.isCancelled else { return }
                try? await socket.send(message)
            }
        }
    }

    private func receive() async {
        do {
            while !isOver {
                let update = try SonioxTranscriber.parse(try await socket.receive())
                pending += update.finalText
                onPreview(update.finalText, update.tentativeText)
                if !finishing { update.endpoint ? emitAll() : emitWholeWords() }
                if update.finished { break }
            }
        } catch {
            guard !isOver else { return }
            failure = error
            if !finishing { onFailure(error) }
        }
        socket.cancel(with: .normalClosure, reason: nil)
        end()
    }

    /// Tokens are word pieces, so only text up to the last space is a finished word.
    private func emitWholeWords() {
        guard let cut = pending.lastIndex(where: \.isWhitespace), cut > pending.startIndex else { return }
        let words = String(pending[..<cut])
        pending = String(pending[cut...])
        guard !words.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onWords(words)
    }

    private func emitAll() {
        let words = pending
        pending = ""
        guard !words.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onWords(words)
    }

    private func end() {
        isOver = true
        waiter?.resume()
        waiter = nil
    }
}
