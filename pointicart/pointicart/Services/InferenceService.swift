import UIKit

// MARK: - Inference Protocol
// Replace the placeholder implementation with your Gemini multimodal API call.

protocol InferenceService: Sendable {
    func identify(image: UIImage, candidates: [String]) async throws -> String?
}

// MARK: - Placeholder Implementation
// Swap this out with your real Gemini call.
//
// Expected contract:
//   - Send the cropped `image` (JPEG) and the `candidates` list to Gemini
//   - System prompt tells Gemini to return ONLY one of the candidate strings
//   - Return the matched candidate, or nil if no match
//
// Example Gemini request shape:
// ```
// POST /v1beta/models/gemini-pro-vision:generateContent
// {
//   "contents": [{
//     "parts": [
//       { "text": "Identify which ONE product is shown: [\(candidates)]. Reply with ONLY the name." },
//       { "inline_data": { "mime_type": "image/jpeg", "data": "<base64>" } }
//     ]
//   }]
// }
// ```

final class PlaceholderInferenceService: InferenceService {
    nonisolated func identify(image: UIImage, candidates: [String]) async throws -> String? {
        // -------------------------------------------------------
        // PASTE YOUR GEMINI / MODEL IMPLEMENTATION HERE
        // -------------------------------------------------------

        // Placeholder: simulate a 0.3s network call and return nil
        try await Task.sleep(for: .milliseconds(300))
        return nil
    }
}
