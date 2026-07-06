import Foundation

/// The diary's spirit. Exactly like the original: the committed page is sent as
/// an inline PNG to a vision model over an OpenAI-compatible `/chat/completions`
/// endpoint (OpenRouter), and the reply is streamed back sentence by sentence.
struct OpenRouterOracle {
    let apiKey: String
    let model: String

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// Reads the writer's ink (a PNG of the committed page) and streams the
    /// diary's reply. `onDelta` is delivered on the main actor as text arrives.
    func respond(imagePNG: Data, allowSketch: Bool = false, onDelta: @escaping (String) -> Void) async throws -> String {
        guard !apiKey.isEmpty else { throw OracleError.missingKey }

        let dataURI = "data:image/png;base64,\(imagePNG.base64EncodedString())"
        let userContent: [[String: Any]] = [
            ["type": "text", "text": "Read what is written to you on the page, and reply."],
            ["type": "image_url", "image_url": ["url": dataURI]],
        ]
        let system = allowSketch ? diarySystemPrompt + sketchDirective : diarySystemPrompt
        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": userContent],
        ]
        let payload: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
            "max_tokens": 2000,
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Riddle", forHTTPHeaderField: "X-Title")
        request.setValue("https://riddle.app", forHTTPHeaderField: "HTTP-Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OracleError.badResponse("the diary could not be reached")
        }

        guard http.statusCode == 200 else {
            var raw = ""
            for try await line in bytes.lines { raw += line }
            throw OracleError.badResponse(Self.errorMessage(from: raw, status: http.statusCode))
        }

        var full = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payloadText = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payloadText == "[DONE]" { break }

            guard
                let data = payloadText.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let delta = choices.first?["delta"] as? [String: Any],
                let content = delta["content"] as? String,
                !content.isEmpty
            else { continue }

            full += content
            await MainActor.run { onDelta(content) }
        }

        return full.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Conjures an ink illustration of `subject` using the image model, and
    /// returns the raw PNG data. The prompt forces monochrome pen-and-ink.
    func draw(subject: String, model imageModel: String) async throws -> Data {
        guard !apiKey.isEmpty else { throw OracleError.missingKey }

        let payload: [String: Any] = [
            "model": imageModel,
            "modalities": ["image", "text"],
            "messages": [["role": "user", "content": inkStylePrompt(for: subject)]],
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Riddle", forHTTPHeaderField: "X-Title")
        request.setValue("https://riddle.app", forHTTPHeaderField: "HTTP-Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw OracleError.badResponse(Self.errorMessage(from: String(data: data, encoding: .utf8) ?? "", status: status))
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any]
        else {
            throw OracleError.badResponse("the ink would not take shape")
        }

        // Images may arrive as message.images[].image_url.url, or as image_url
        // parts inside message.content — try both.
        var uri: String?
        if let images = message["images"] as? [[String: Any]] {
            uri = (images.first?["image_url"] as? [String: Any])?["url"] as? String
        }
        if uri == nil, let content = message["content"] as? [[String: Any]] {
            for part in content {
                if let imageURL = part["image_url"] as? [String: Any], let url = imageURL["url"] as? String {
                    uri = url
                    break
                }
            }
        }

        guard
            let dataURI = uri,
            let comma = dataURI.range(of: ","),
            let imageData = Data(base64Encoded: String(dataURI[comma.upperBound...]))
        else {
            throw OracleError.badResponse("the diary drew nothing")
        }

        return imageData
    }

    /// A tiny text-only request used to verify the key + model from Settings.
    /// Returns `nil` on success, or a human error string.
    func probe() async -> String? {
        guard !apiKey.isEmpty else { return "no key set" }
        let payload: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "Reply with the single word: ready"]],
            "max_tokens": 5,
        ]
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Riddle", forHTTPHeaderField: "X-Title")
        request.setValue("https://riddle.app", forHTTPHeaderField: "HTTP-Referer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return nil }
            let raw = String(data: data, encoding: .utf8) ?? ""
            return Self.errorMessage(from: raw, status: status)
        } catch {
            return error.localizedDescription
        }
    }

    private static func errorMessage(from raw: String, status: Int) -> String {
        var detail = ""
        if
            let data = raw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        {
            detail = message
        }

        switch status {
        case 401:
            return "the diary does not recognise that key — it must be an OpenRouter key (sk-or-…)"
        case 402:
            return "your OpenRouter account is out of credit"
        case 403:
            return "that key is not permitted to use this model"
        case 404:
            return "no such model — pick a vision model in the guide"
        case 429:
            return "the diary is asked too much, too fast — wait a moment"
        default:
            return detail.isEmpty ? "the diary is silent (\(status))" : detail
        }
    }
}
