import Foundation

/// The diary's spirit. Exactly like the original: the committed page is sent as
/// an inline PNG to a vision model over an OpenAI-compatible `/chat/completions`
/// endpoint (OpenRouter). Prior live turns are sent back with each page so the
/// open diary keeps continuity until the app is truly closed.
struct OpenRouterOracle {
    let apiKey: String
    let model: String

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// Reads the writer's ink (a PNG of the committed page) and streams the
    /// diary's reply. `onDelta` is delivered on the main actor as text arrives.
    func respond(
        imagePNG: Data,
        history: [DiaryTurn] = [],
        memoryProfile: String? = nil,
        preservedMemory: String? = nil,
        allowSketch: Bool = false,
        webQuery: String? = nil,
        onDelta: @escaping (String) -> Void
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw OracleError.missingKey }

        let dataURI = "data:image/png;base64,\(imagePNG.base64EncodedString())"
        let userContent: [[String: Any]] = [
            [
                "type": "text",
                "text": "Read this handwritten page with maximum care. Infer the writer's intended words as best you can, using spelling, shape, and the prior conversation. Continue the same conversation and reply."
            ],
            ["type": "image_url", "image_url": ["url": dataURI]],
        ]
        // First passes may carry a few saved pages. RECALL still lets Tom reach
        // deeper when an exact old phrase matters.
        let firstPass = webQuery == nil
        let system = diarySystemPrompt
            + (webQuery == nil ? webEscalationDirective : webSearchDirective)
            + (firstPass ? memoryRecallDirective : "")
            + memoryDistillDirective
            + (allowSketch ? sketchDirective : "")
            + readingDirective
            + visibleBrevityDirective
        var messages: [[String: Any]] = [["role": "system", "content": system]]

        // The writer's soul travels with every turn — small enough to cost little,
        // rich enough that the diary always knows them (no second round-trip).
        if let memoryProfile = memoryProfile?.trimmingCharacters(in: .whitespacesAndNewlines), !memoryProfile.isEmpty {
            messages.append([
                "role": "system",
                "content": """
                What you have come to know of this writer, kept in these pages across every opening — their soul. Speak as one who truly knows them: weave it in naturally, and notice patterns — a word they keep circling, a thing they avoid, a fear they will not name, a phrase returning in disguise. When one memory genuinely touches the new ink, use one brief callback. Never recite this back as a list.

                \(memoryProfile)
                """
            ])
        }
        if let preservedMemory = preservedMemory?.trimmingCharacters(in: .whitespacesAndNewlines), !preservedMemory.isEmpty {
            messages.append([
                "role": "system",
                "content": """
                These are preserved pages from earlier openings of this diary, most recent first. Treat them as things the page remembers after being closed. If the writer asks what you remember, answer from these details. Reuse names, phrases, secrets, and emotional callbacks when it feels natural. Some older pages preserve only your answering ink; do not invent missing writer words. Never mention files, storage, JSON, history, sessions, or app closing.

                \(preservedMemory)
                """
            ])
        }
        if !history.isEmpty {
            messages.append([
                "role": "system",
                "content": "These are the earlier living exchanges on these pages. Keep continuity with them. Reuse names, private phrases, secrets, and emotional details when it feels alive, but never summarize them mechanically."
            ])
            for turn in history {
                messages.append(["role": "user", "content": "Earlier, the writer wrote: \(turn.writer)"])
                messages.append(["role": "assistant", "content": turn.reply])
            }
        }
        if let webQuery {
            messages.append([
                "role": "system",
                "content": "The writer's current question requires fresh traces for: \(webQuery). Consult them silently, then answer naturally in the diary's voice. Do not cite, link, or mention sources."
            ])
        }
        messages.append(["role": "user", "content": userContent])

        var payload: [String: Any] = [
            "model": model,
            "messages": messages,
            // The visible reply stays short by instruction, but the hidden
            // bookkeeping lines (READ transcription, MEMORY, WEB) trail after it;
            // too tight a cap silently truncates them and recall/soul degrade.
            "stream": true,
            "max_tokens": 420,
        ]
        if webQuery != nil {
            payload["tools"] = Self.webSearchTools
        }

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

    private static let webSearchTools: [[String: Any]] = [
        [
            "type": "openrouter:web_search",
            "parameters": [
                "engine": "auto",
                "max_results": 3,
                "max_total_results": 6,
                "search_context_size": "low",
            ] as [String: Any],
        ]
    ]

    /// Conjures a fresh ink illustration of `subject`. The prompt forces
    /// monochrome pen-and-ink on the diary's cream paper.
    func draw(subject: String, model imageModel: String) async throws -> Data {
        try await requestImage(model: imageModel, content: [["type": "text", "text": inkStylePrompt(for: subject)]])
    }

    /// Refines the writer's *own* drawing: the committed page is sent back to
    /// the image model with an ink instruction (image-to-image), so the diary
    /// perfects what they drew — still borderless ink on cream paper.
    func redraw(instruction: String, source: Data, model imageModel: String) async throws -> Data {
        let dataURI = "data:image/png;base64,\(source.base64EncodedString())"
        return try await requestImage(model: imageModel, content: [
            ["type": "text", "text": inkEditPrompt(for: instruction)],
            ["type": "image_url", "image_url": ["url": dataURI]],
        ])
    }

    /// Shared image-generation call for `draw` / `redraw`.
    private func requestImage(model imageModel: String, content: [[String: Any]]) async throws -> Data {
        guard !apiKey.isEmpty else { throw OracleError.missingKey }

        let payload: [String: Any] = [
            "model": imageModel,
            "modalities": ["image", "text"],
            "messages": [["role": "user", "content": content]],
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
        if uri == nil, let contentParts = message["content"] as? [[String: Any]] {
            for part in contentParts {
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
