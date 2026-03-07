import UIKit

// MARK: - Gemini Multimodal Inference
// Sends the full portrait-oriented camera frame to gemini-2.0-flash.
// Returns the matched product key + a bounding box (0-1 normalized, portrait image space).

final class GeminiInferenceService: InferenceService {

    private let apiKey: String
    private let model = "gemini-1.5-flash"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    nonisolated func identify(image: UIImage, candidates: [String]) async throws -> IdentificationResult? {
        guard !candidates.isEmpty else { return nil }
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return nil }

        let base64Image = imageData.base64EncodedString()
        let candidateList = candidates.joined(separator: ", ")

        // Ask Gemini to identify the product AND return its bounding box.
        // Box format: values 0-1000 (Gemini standard), origin top-left.
        let prompt = """
        You are a product identifier for a retail store. \
        Look at this image and identify if any of these products are visible: [\(candidateList)].

        If you find one of the listed products, respond with ONLY valid JSON (no markdown, no explanation):
        {"product": "Chair", "ymin": 200, "xmin": 100, "ymax": 800, "xmax": 900}

        The box values (ymin, xmin, ymax, xmax) are integers 0-1000 representing the bounding box \
        of the detected product (0,0 = top-left of image, 1000,1000 = bottom-right).

        If NONE of the listed products are visible, respond with ONLY:
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
                "maxOutputTokens": 100
            ]
        ]

        guard let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)") else {
            return nil
        }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("[Gemini] HTTP \(statusCode)")

        guard statusCode == 200 else {
            if let body = String(data: data, encoding: .utf8) {
                print("[Gemini] Error body: \(body)")
            }
            return nil
        }

        if let raw = String(data: data, encoding: .utf8) {
            print("[Gemini] Raw response: \(raw)")
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
            print("[Gemini] Failed to extract text from response")
            return nil
        }

        print("[Gemini] Model text: \(text)")

        // Strip markdown code fences if present (```json ... ``` or ``` ... ```)
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let jsonData = cleaned.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            print("[Gemini] JSON parse failed for: \(cleaned)")
            return nil
        }

        guard let productName = parsed["product"] as? String,
              productName.lowercased() != "none"
        else {
            print("[Gemini] Product is none or missing")
            return nil
        }

        // Match to a known store key (case-insensitive)
        guard let matchedKey = validCandidates.first(where: {
            $0.lowercased() == productName.lowercased()
        }) else {
            print("[Gemini] No match for '\(productName)' in candidates: \(validCandidates)")
            return nil
        }

        print("[Gemini] Matched key: \(matchedKey)")

        // Parse bounding box if present (0-1000 → 0-1 normalized)
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
            print("[Gemini] Bounding box: \(box!)")
        } else {
            print("[Gemini] No bounding box in response")
        }

        return IdentificationResult(productKey: matchedKey, normalizedBox: box)
    }
}
