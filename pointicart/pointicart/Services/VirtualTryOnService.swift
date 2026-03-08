import UIKit

/// Calls Google's virtual-try-on-001 model via the Vertex AI REST API.
/// Authenticates using an OAuth2 refresh token to obtain short-lived access tokens.
final class VirtualTryOnService: Sendable {

    private let projectID: String
    private let location: String
    private let clientID: String
    private let clientSecret: String
    private let refreshToken: String
    private let model = "virtual-try-on-001"

    init(projectID: String, location: String, clientID: String, clientSecret: String, refreshToken: String) {
        self.projectID = projectID
        self.location = location
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.refreshToken = refreshToken
    }

    /// Send a person image + product (clothing) image to the virtual try-on model,
    /// returning the generated composite image.
    nonisolated func tryOn(personImage: UIImage, productImage: UIImage) async throws -> UIImage {
        let personResized = Self.resizeImage(personImage, maxDimension: 1024)
        let productResized = Self.resizeImage(productImage, maxDimension: 1024)

        guard let personData = personResized.jpegData(compressionQuality: 0.85) else {
            throw TryOnError.imageEncodingFailed
        }
        guard let productData = productResized.pngData() else {
            throw TryOnError.imageEncodingFailed
        }

        let personBase64 = personData.base64EncodedString()
        let productBase64 = productData.base64EncodedString()

        NSLog("[PTIC][TryOn] Person image: %.0fx%.0f (%d bytes), Product image: %.0fx%.0f (%d bytes)",
              personResized.size.width, personResized.size.height, personData.count,
              productResized.size.width, productResized.size.height, productData.count)

        // Get a fresh access token
        let accessToken = try await fetchAccessToken()
        NSLog("[PTIC][TryOn] Got access token (%d chars)", accessToken.count)

        // Build request body — Vertex AI predict format
        let requestBody: [String: Any] = [
            "instances": [
                [
                    "personImage": [
                        "image": ["bytesBase64Encoded": personBase64]
                    ],
                    "productImages": [
                        [
                            "image": ["bytesBase64Encoded": productBase64]
                        ]
                    ]
                ]
            ],
            "parameters": [
                "sampleCount": 1
            ]
        ]

        let urlString = "https://\(location)-aiplatform.googleapis.com/v1/projects/\(projectID)/locations/\(location)/publishers/google/models/\(model):predict"
        guard let url = URL(string: urlString) else {
            throw TryOnError.invalidURL
        }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw TryOnError.requestSerializationFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 90

        NSLog("[PTIC][TryOn] Sending POST to %@", urlString.prefix(120).description)

        let (data, response) = try await URLSession.shared.data(for: request)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        NSLog("[PTIC][TryOn] HTTP %d — response size=%d bytes", statusCode, data.count)

        guard statusCode == 200 else {
            if let body = String(data: data, encoding: .utf8) {
                NSLog("[PTIC][TryOn] Error body: %@", body.prefix(500).description)
            }
            throw TryOnError.httpError(statusCode)
        }

        return try parseResponse(data: data)
    }

    // MARK: - OAuth2 Token Refresh

    /// Exchange the refresh token for a fresh access token via Google's OAuth2 endpoint.
    nonisolated private func fetchAccessToken() async throws -> String {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw TryOnError.invalidURL
        }

        let params = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        let bodyString = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

        guard statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            if let body = String(data: data, encoding: .utf8) {
                NSLog("[PTIC][TryOn] Token refresh failed (HTTP %d): %@", statusCode, body.prefix(300).description)
            }
            throw TryOnError.authenticationFailed
        }

        return token
    }

    // MARK: - Response Parsing

    nonisolated private func parseResponse(data: Data) throws -> UIImage {
        guard
            let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let predictions = envelope["predictions"] as? [[String: Any]],
            let firstPrediction = predictions.first,
            let base64String = firstPrediction["bytesBase64Encoded"] as? String
        else {
            if let raw = String(data: data, encoding: .utf8) {
                NSLog("[PTIC][TryOn] Response parse failed: %@", raw.prefix(500).description)
            }
            throw TryOnError.responseParsingFailed
        }

        guard let imageData = Data(base64Encoded: base64String),
              let image = UIImage(data: imageData) else {
            throw TryOnError.imageDecodingFailed
        }

        NSLog("[PTIC][TryOn] Generated image: %.0fx%.0f", image.size.width, image.size.height)
        return image
    }

    // MARK: - Image Resizing

    nonisolated private static func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }

        let scale: CGFloat = if size.width > size.height {
            maxDimension / size.width
        } else {
            maxDimension / size.height
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Errors

enum TryOnError: Error, LocalizedError {
    case imageEncodingFailed
    case invalidURL
    case requestSerializationFailed
    case httpError(Int)
    case responseParsingFailed
    case imageDecodingFailed
    case noSnapshot
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: "Failed to encode image"
        case .invalidURL: "Invalid API URL"
        case .requestSerializationFailed: "Failed to serialize request"
        case .httpError(let code): "HTTP error \(code)"
        case .responseParsingFailed: "Failed to parse try-on response"
        case .imageDecodingFailed: "Failed to decode generated image"
        case .noSnapshot: "Could not capture camera frame"
        case .authenticationFailed: "Google Cloud authentication failed"
        }
    }
}
