import UIKit

// MARK: - Gemini Multimodal Inference
// Uses gemini-1.5-flash to map a cropped camera frame to one of the store's product keys.
// The API key is loaded from Secrets.swift (gitignored — never committed).

final class GeminiInferenceService: InferenceService {

    private let apiKey: String
    private let model = "gemini-1.5-flash"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    nonisolated func identify(image: UIImage, candidates: [String]) async throws -> String? {
        guard !candidates.isEmpty else { return nil }
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { return nil }

        let base64Image = imageData.base64EncodedString()
        let candidateList = candidates.joined(separator: ", ")

        let prompt = """
        You are a product identifier for a retail store. \
        A customer is pointing at a product in the image. \
        Identify which ONE of these products is shown: [\(candidateList)]. \
        Reply with ONLY the exact product name from that list. \
        If none match, reply with exactly: none
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
                "maxOutputTokens": 30
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
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        return parseResponse(data: data, validCandidates: candidates)
    }

    nonisolated private func parseResponse(data: Data, validCandidates: [String]) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else {
            return nil
        }

        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reject "none" responses
        guard result.lowercased() != "none" else { return nil }

        // Only return a result that maps to a known store key (case-insensitive match)
        return validCandidates.first {
            $0.lowercased() == result.lowercased()
        }
    }
}
