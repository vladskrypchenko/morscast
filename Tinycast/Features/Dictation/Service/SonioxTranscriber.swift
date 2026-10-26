import Foundation

/// Cloud dictation through Soniox's real-time API, used instead of a local model when switched on.
enum SonioxTranscriber {
    enum Failure: LocalizedError {
        case missingKey
        case server(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: "Add a Soniox API key in Dictation settings"
            case .server(let message): "Soniox: \(message)"
            }
        }
    }

    /// One server message: the finalized text it carried and whether the stream is over.
    struct Update: Sendable {
        let finalText: String
        let finished: Bool
    }

    static let enabledKey = "dictationSonioxEnabled"
    static let keychain = KeychainSecretStore(scope: "soniox")
    private static let keyAccount = UUID(uuidString: "6D1E2A5C-0B7F-4E3A-9C61-50A10C5D1C7A")!
    private static let model = "stt-rt-v5"
    private static let endpoint = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!
    private static let frameBytes = 32_000

    /// Cacheless, never `URLSession.shared`, so no audio or transcript lands in a shared cache.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    @MainActor static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var hasKey: Bool { (try? keychain.hasSecret(for: keyAccount)) ?? false }

    static func apiKey() throws -> String {
        guard let key = try keychain.secret(for: keyAccount), !key.isEmpty else {
            throw Failure.missingKey
        }
        return key
    }

    static func setAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychain.removeSecret(for: keyAccount)
        } else {
            try keychain.setSecret(trimmed, for: keyAccount)
        }
    }

    static func openSocket(apiKey: String) -> URLSessionWebSocketTask {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request)
        socket.resume()
        return socket
    }

    static func configMessage(languageCode: String?) throws -> URLSessionWebSocketTask.Message {
        var config: [String: Any] = [
            "model": model,
            "audio_format": "pcm_s16le",
            "sample_rate": DictationWire.sampleRate,
            "num_channels": 1
        ]
        if let languageCode { config["language_hints"] = [languageCode] }
        let data = try JSONSerialization.data(withJSONObject: config)
        return .string(String(decoding: data, as: UTF8.self))
    }

    /// An empty text frame ends the stream; an empty binary frame would not.
    static let endOfAudio = URLSessionWebSocketTask.Message.string("")

    static func audioFrames(_ samples: ArraySlice<Float>) -> [URLSessionWebSocketTask.Message] {
        let pcm = pcm16(samples)
        return stride(from: 0, to: pcm.count, by: frameBytes).map {
            .data(pcm.subdata(in: $0..<min($0 + frameBytes, pcm.count)))
        }
    }

    static func parse(_ message: URLSessionWebSocketTask.Message) throws -> Update {
        let data: Data
        switch message {
        case .string(let string): data = Data(string.utf8)
        case .data(let bytes): data = bytes
        @unknown default: return Update(finalText: "", finished: false)
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let message = response.errorMessage { throw Failure.server(message) }
        let text = (response.tokens ?? []).filter { $0.isFinal && !$0.isMarker }.map(\.text).joined()
        return Update(finalText: text, finished: response.finished == true)
    }

    @concurrent
    static func transcribe(
        _ samples: [Float], languageCode: String?, apiKey: String
    ) async throws -> String {
        let socket = openSocket(apiKey: apiKey)
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        return try await withTaskCancellationHandler {
            try await socket.send(configMessage(languageCode: languageCode))
            for frame in audioFrames(samples[...]) {
                try Task.checkCancellation()
                try await socket.send(frame)
            }
            try await socket.send(endOfAudio)
            var text = ""
            while true {
                try Task.checkCancellation()
                let update = try parse(try await socket.receive())
                text += update.finalText
                if update.finished { return text }
            }
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }

    private static func pcm16(_ samples: ArraySlice<Float>) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let value = Int16(max(-1, min(1, sample)) * Float(Int16.max))
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    private struct Response: Decodable {
        struct Token: Decodable {
            let text: String
            let isFinal: Bool
            /// Endpoint and finalize markers such as `<end>` are control tokens, not speech.
            var isMarker: Bool { text.hasPrefix("<") && text.hasSuffix(">") }

            enum CodingKeys: String, CodingKey {
                case text
                case isFinal = "is_final"
            }
        }

        let tokens: [Token]?
        let finished: Bool?
        let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case tokens, finished
            case errorMessage = "error_message"
        }
    }
}
