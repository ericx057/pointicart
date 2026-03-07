import UIKit

// MARK: - Gemini Multimodal Inference
// Sends the full portrait-oriented camera frame to gemini-2.0-flash.
// Returns the matched product key + a bounding box (0-1 normalized, portrait image space).

final class GeminiInferenceService: InferenceService {

    private let apiKey: String
    private let model = "gemini-2.0-flash"
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
                "maxOutputTokens": 80,
                "responseMimeType": "application/json"
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

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
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
        else { return nil }

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = cleaned.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return nil }

        guard let productName = parsed["product"] as? String,
              productName.lowercased() != "none"
        else { return nil }

        // Match to a known store key (case-insensitive)
        guard let matchedKey = validCandidates.first(where: {
            $0.lowercased() == productName.lowercased()
        }) else { return nil }

        // Parse bounding box if present (0-1000 → 0-1 normalized)
        var box: CGRect?
        if let ymin = parsed["ymin"] as? Double,
           let xmin = parsed["xmin"] as? Double,
           let ymax = parsed["ymax"] as? Double,
           let xmax = parsed["xmax"] as? Double {
            box = CGRect(
                x: xmin / 1000.0,
                y: ymin / 1000.0,
                width: (xmax - xmin) / 1000.0,
                height: (ymax - ymin) / 1000.0
            )
        }

        return IdentificationResult(productKey: matchedKey, normalizedBox: box)
    }
}
