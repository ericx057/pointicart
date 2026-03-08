import UIKit

// MARK: - Errors

enum GeminiError: Error {
    case rateLimited(retryAfter: TimeInterval)
}

// MARK: - Gemini Multimodal Inference
// Sends a cropped region around the user's fingertip to gemini-2.5.
// Returns the matched clothing item key.

final class GeminiInferenceService: InferenceService {

    private let apiKey: String
    private let model = "gemini-2.5-flash"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    nonisolated func identify(image: UIImage, candidates: [String], candidateDescriptions: [String: String]) async throws -> IdentificationResult? {
        NSLog("[PTIC][Gemini] identify called — candidates=%@", candidates.joined(separator: ", "))

        guard !candidates.isEmpty else {
            NSLog("[PTIC][Gemini] SKIP — empty candidates")
            return nil
        }

        // Downscale to max 512px on longest side to reduce token usage
        let resized = Self.resizeImage(image, maxDimension: 512)
        NSLog("[PTIC][Gemini] Resized from %.0fx%.0f to %.0fx%.0f",
              image.size.width, image.size.height,
              resized.size.width, resized.size.height)

        guard let imageData = resized.jpegData(compressionQuality: 0.4) else {
            NSLog("[PTIC][Gemini] FAILED — jpegData returned nil")
            return nil
        }

        let base64Image = imageData.base64EncodedString()
        NSLog("[PTIC][Gemini] Image encoded: %d bytes JPEG, %d chars base64",
              imageData.count, base64Image.count)

        // Build a detailed product reference list with visual descriptions
        var productReference = ""
        for candidate in candidates {
            if let desc = candidateDescriptions[candidate], !desc.isEmpty {
                productReference += "- \(candidate): \(desc)\n"
            } else {
                productReference += "- \(candidate)\n"
            }
        }

        // Ask Gemini to compare the image against every product description
        let prompt = """
        You are a product identification system for a retail store. A customer is pointing at a product. \
        Compare everything visible in this camera frame against each product description below and identify the best match.

        PRODUCT CATALOG:
        \(productReference)
        Carefully compare the visual features in the image (shape, texture, pattern, color, material, construction) \
        against EVERY product description above. Pick the single best match.

        If you find a match, respond with ONLY valid JSON (no markdown, no explanation):
        {"product": "Sweater", "ymin": 200, "xmin": 150, "ymax": 600, "xmax": 450}

        The bounding box coordinates must be in 0-1000 space (where 0,0 is top-left and 1000,1000 is bottom-right).

        IMPORTANT RULES:
        - The "product" value must EXACTLY match one of the product names listed above.
        - Do NOT add adjectives, hyphens, or extra words. Use the product name verbatim.
        - Always include a bounding box (ymin, xmin, ymax, xmax) around the matched product.
        - Compare against ALL products — do not stop at the first plausible match.
        - Focus on items on racks, mannequins, shelves, or being held — not what someone is wearing.

        If NONE of the listed products are clearly visible, respond with ONLY:
        {"product": "none"}
        """

        let requestBody: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    [
                        "inline_data": [
                            "mime_type": "image/jpeg",
                            "data": base64Image
                        ]
                    ]
                ]
            ]],
            "generationConfig": [
                "temperature": 0,
                "maxOutputTokens": 1024
            ]
        ]

        guard let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)") else {
            NSLog("[PTIC][Gemini] FAILED — could not build URL")
            return nil
        }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            NSLog("[PTIC][Gemini] FAILED — could not serialize request body")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 20

        NSLog("[PTIC][Gemini] Sending POST to %@", url.absoluteString.prefix(80).description)

        let (data, response) = try await URLSession.shared.data(for: request)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        NSLog("[PTIC][Gemini] HTTP %d — response size=%d bytes", statusCode, data.count)

        guard statusCode == 200 else {
            if let body = String(data: data, encoding: .utf8) {
                NSLog("[PTIC][Gemini] Error body: %@", body.prefix(500).description)
                if statusCode == 429 {
                    let retryAfter = Self.parseRetryAfter(from: body)
                    NSLog("[PTIC][Gemini] Rate limited (429) — retry after %.1fs", retryAfter)
                    throw GeminiError.rateLimited(retryAfter: retryAfter)
                }
            } else if statusCode == 429 {
                throw GeminiError.rateLimited(retryAfter: 60)
            }
            return nil
        }

        if let raw = String(data: data, encoding: .utf8) {
            NSLog("[PTIC][Gemini] Raw response: %@", raw.prefix(500).description)
        }

        return parseResponse(data: data, validCandidates: candidates)
    }

    nonisolated private func parseResponse(data: Data, validCandidates: [String]) -> IdentificationResult? {
        // Extract the text from Gemini's response envelope
        guard
            let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = envelope["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else {
            NSLog("[PTIC][Gemini] FAILED — could not extract text from response envelope")
            return nil
        }

        NSLog("[PTIC][Gemini] Model text: %@", text)

        // Strip markdown code fences if present (```json ... ``` or ``` ... ```)
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Extract the first valid JSON object using brace matching
        // (handles extra trailing braces or surrounding text)
        if let start = cleaned.firstIndex(of: "{") {
            var depth = 0
            var end = start
            for i in cleaned[start...].indices {
                if cleaned[i] == "{" { depth += 1 }
                if cleaned[i] == "}" { depth -= 1 }
                if depth == 0 { end = i; break }
            }
            cleaned = String(cleaned[start...end])
        }

        NSLog("[PTIC][Gemini] Cleaned JSON: %@", cleaned)

        var parsed: [String: Any]?
        if let jsonData = cleaned.data(using: .utf8) {
            parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        }

        // Fallback: if JSON is truncated (MAX_TOKENS), extract product name with regex
        if parsed == nil {
            NSLog("[PTIC][Gemini] JSON parse failed — trying regex fallback on: %@", cleaned)
            if let range = cleaned.range(of: #""product"\s*:\s*"([^"]+)""#, options: .regularExpression) {
                let match = cleaned[range]
                if let nameStart = match.range(of: #":\s*""#, options: .regularExpression)?.upperBound,
                   let nameEnd = match[nameStart...].firstIndex(of: "\"") {
                    let extractedName = String(match[nameStart..<nameEnd])
                    NSLog("[PTIC][Gemini] Regex extracted product: %@", extractedName)
                    parsed = ["product": extractedName]
                }
            }
        }

        guard let parsed else {
            NSLog("[PTIC][Gemini] FAILED — could not extract product from: %@", cleaned)
            return nil
        }

        guard let productName = parsed["product"] as? String,
              productName.lowercased() != "none"
        else {
            NSLog("[PTIC][Gemini] Product is 'none' or missing")
            return nil
        }

        // Match to a known store key (case-insensitive)
        guard let matchedKey = validCandidates.first(where: {
            $0.lowercased() == productName.lowercased()
        }) else {
            NSLog("[PTIC][Gemini] No match for '%@' in candidates: %@",
                  productName, validCandidates.joined(separator: ", "))
            return nil
        }

        NSLog("[PTIC][Gemini] Matched key: %@", matchedKey)

        // Parse bounding box if present (0-1000 -> 0-1 normalized)
        // Gemini may return ints or doubles
        func toDouble(_ v: Any?) -> Double? {
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            return nil
        }

        var box: CGRect?
        if let ymin = toDouble(parsed["ymin"]),
           let xmin = toDouble(parsed["xmin"]),
           let ymax = toDouble(parsed["ymax"]),
           let xmax = toDouble(parsed["xmax"]) {
            box = CGRect(
                x: xmin / 1000.0,
                y: ymin / 1000.0,
                width: (xmax - xmin) / 1000.0,
                height: (ymax - ymin) / 1000.0
            )
            NSLog("[PTIC][Gemini] Bounding box: %@", NSCoder.string(for: box!))
        } else {
            NSLog("[PTIC][Gemini] No bounding box in response")
        }

        return IdentificationResult(productKey: matchedKey, normalizedBox: box)
    }

    // MARK: - Rate Limit Parsing

    /// Extracts the retry delay from a 429 response body.
    /// Looks for patterns like "retry in 58.3s" or "retryDelay":"58s" in the JSON.
    nonisolated private static func parseRetryAfter(from body: String) -> TimeInterval {
        // Try "retry in X.Xs" pattern from the human-readable message
        let retryPattern = #"retry in (\d+(?:\.\d+)?)s"#
        if let range = body.range(of: retryPattern, options: [.regularExpression, .caseInsensitive]),
           let numRange = body[range].range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) {
            if let seconds = Double(body[range][numRange]) {
                return seconds + 1  // add 1s buffer
            }
        }
        // Try "retryDelay":"58s" pattern from the error details JSON
        let delayPattern = #""retryDelay"\s*:\s*"(\d+(?:\.\d+)?)s""#
        if let range = body.range(of: delayPattern, options: .regularExpression),
           let numRange = body[range].range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) {
            if let seconds = Double(body[range][numRange]) {
                return seconds + 1
            }
        }
        return 60  // safe fallback
    }

    // MARK: - Image Resizing

    nonisolated private static func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }

        let scale: CGFloat
        if size.width > size.height {
            scale = maxDimension / size.width
        } else {
            scale = maxDimension / size.height
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
