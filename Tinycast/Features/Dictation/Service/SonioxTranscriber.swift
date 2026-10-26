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

    @concurrent
    static func transcribe(
        _ samples: [Float], languageCode: String?, apiKey: String
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        return try await withTaskCancellationHandler {
            try await send(samples, languageCode: languageCode, over: socket)
            return try await receiveTranscript(from: socket)
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }

    private static func send(
        _ samples: [Float], languageCode: String?, over socket: URLSessionWebSocketTask
    ) async throws {
        var config: [String: Any] = [
            "model": model,
            "audio_format": "pcm_s16le",
            "sample_rate": DictationWire.sampleRate,
            "num_channels": 1
        ]
        if let languageCode { config["language_hints"] = [languageCode] }
        let configData = try JSONSerialization.data(withJSONObject: config)
        try await socket.send(.string(String(decoding: configData, as: UTF8.self)))
        let pcm = pcm16(samples)
        var offset = 0
        while offset < pcm.count {
            try Task.checkCancellation()
            let end = min(offset + frameBytes, pcm.count)
            try await socket.send(.data(pcm.subdata(in: offset..<end)))
            offset = end
        }
        // An empty text frame ends the stream; an empty binary frame would not.
        try await socket.send(.string(""))
    }

    private static func receiveTranscript(from socket: URLSessionWebSocketTask) async throws -> String {
        var text = ""
        while true {
            try Task.checkCancellation()
            let data: Data
            switch try await socket.receive() {
            case .string(let string): data = Data(string.utf8)
            case .data(let bytes): data = bytes
            @unknown default: continue
            }
            let response = try JSONDecoder().decode(Response.self, from: data)
            if let message = response.errorMessage { throw Failure.server(message) }
            for token in response.tokens ?? [] where token.isFinal && !token.isMarker {
                text += token.text
            }
            if response.finished == true { return text }
        }
    }

    private static func pcm16(_ samples: [Float]) -> Data {
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
