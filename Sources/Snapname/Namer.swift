import Foundation

enum NamerError: LocalizedError {
    case notRunning
    case modelMissing(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: "Ollama isn't running. Open the Ollama app or run `ollama serve`."
        case .modelMissing(let model): "Model “\(model)” isn't installed. Run `ollama pull \(model)`."
        case .badResponse(let detail): "Ollama returned an unexpected response: \(detail)"
        }
    }
}

/// Asks the local vision model what a screenshot shows.
enum Namer {
    static let baseURL = URL(string: "http://localhost:11434")!
    static var model: String { UserDefaults.standard.string(forKey: "model") ?? "gemma4" }

    struct Result: Decodable, Equatable {
        let name: String
        let description: String
    }

    static let prompt = """
    Look at this screenshot and reply with JSON: {"name": "...", "description": "..."}
    - name: what the screenshot shows, 2 to 6 lowercase words joined by hyphens, specific (app, site, topic), no dates, no file extension. Example: "stripe-dashboard-failed-payments".
    - description: one sentence describing what is visible, including any key names, numbers or text someone might search for later.
    """

    static func describe(_ image: URL) async throws -> Result {
        let data = try Data(contentsOf: image)
        let payload: [String: Any] = [
            "model": model, "stream": false, "think": false, "format": "json", "keep_alive": "15m",
            "options": ["temperature": 0],
            "messages": [["role": "user", "content": prompt, "images": [data.base64EncodedString()]]],
        ]
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 300

        let (body, response): (Data, URLResponse)
        do {
            (body, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw NamerError.notRunning
        }
        if (response as? HTTPURLResponse)?.statusCode == 404 { throw NamerError.modelMissing(model) }
        return try parse(body)
    }

    static func parse(_ body: Data) throws -> Result {
        struct Chat: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        guard let content = try? JSONDecoder().decode(Chat.self, from: body).message.content,
              let result = try? JSONDecoder().decode(Result.self, from: Data(content.utf8)) else {
            throw NamerError.badResponse(String(decoding: body.prefix(200), as: UTF8.self))
        }
        return result
    }

    /// Loads the model into memory ahead of time so the first screenshot isn't slow.
    static func warmUp() {
        Task.detached {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
            request.httpMethod = "POST"
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "keep_alive": "15m"])
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}
