import UIKit

// MARK: - Gemini Multimodal Inference
// Sends a cropped region around the user's fingertip to gemini-2.0-flash.
// Returns the matched clothing item key.

final class GeminiInferenceService: InferenceService {

    private let apiKey: String
    private let model = "gemini-2.0-flash"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    nonisolated func identify(image: UIImage, candidates: [String]) async throws -> IdentificationResult? {
        NSLog("[PTIC][Gemini] identify called — candidates=%@", candidates.joined(separator: ", "))

        guard !candidates.isEmpty else {
            NSLog("[PTIC][Gemini] SKIP — empty candidates")
            return nil
        }

        // Downscale to max 768px on longest side to reduce token usage
        let resized = Self.resizeImage(image, maxDimension: 768)
        NSLog("[PTIC][Gemini] Resized from %.0fx%.0f to %.0fx%.0f",
              image.size.width, image.size.height,
              resized.size.width, resized.size.height)

        guard let imageData = resized.jpegData(compressionQuality: 0.7) else {
            NSLog("[PTIC][Gemini] FAILED — jpegData returned nil")
            return nil
        }

        let base64Image = imageData.base64EncodedString()
        NSLog("[PTIC][Gemini] Image encoded: %d bytes JPEG, %d chars base64",
              imageData.count, base64Image.count)

        let candidateList = candidates.joined(separator: ", ")

        // Ask Gemini to identify the product from the cropped fingertip region.
        let prompt = """
        You are a clothing identifier for a retail clothing store. A customer is pointing at an article of clothing. \
        This image is cropped around where the customer is pointing. Identify which ONE of these clothing items \
        is most prominent in this image: [\(candidateList)].

        If you find one of the listed clothing items, respond with ONLY valid JSON (no markdown, no explanation):
        {"product": "Jacket"}

        IMPORTANT RULES:
        - The "product" value must EXACTLY match one of the candidate names listed above.
        - Do NOT add adjectives, hyphens, or extra words. Use the candidate name verbatim.
        - Focus on the article of clothing in the image, not background objects or people.
        - Identify the clothing item itself (on a rack, mannequin, shelf, or being held), not what someone is wearing.

        If NONE of the listed clothing items are clearly visible, respond with ONLY:
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
                "maxOutputTokens": 128
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

        guard let jsonData = cleaned.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            NSLog("[PTIC][Gemini] FAILED — JSON parse failed for: %@", cleaned)
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
