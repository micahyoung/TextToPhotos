//
//  OpenAIGenerationClient.swift
//  Text2Photos
//
//  Created by user on 9/27/25.
//

import Foundation

public class OpenAIGenerationClient: GenerationClientProtocol {
    private let baseURL: String
    private let apiKey: String
    private let model: String
    private let session: URLSession
    
    public init(baseURL: String = "https://api.openai.com", model: String, apiKey: String? = nil) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        self.model = model
        self.session = URLSession.shared
    }
    
    public func generate(query: String, systemInstructions: String) async throws -> String {
        let url = URL(string: "\(baseURL)/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let messages: [[String: Any]] = [
            [
                "role": "system",
                "content": systemInstructions
            ],
            [
                "role": "user",
                "content": query
            ]
        ]
        
        let requestBody: [String: Any] = [
            "model": self.model,
            "messages": messages,
            "temperature": 0.0,
            "max_tokens": 1000
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw OpenAIError.apiError(message)
            }
            throw OpenAIError.httpError(httpResponse.statusCode)
        }
        
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = jsonResponse["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponseFormat
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum OpenAIError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case httpError(Int)
    case invalidResponseFormat
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .apiError(let message):
            return "OpenAI API error: \(message)"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .invalidResponseFormat:
            return "Invalid response format from OpenAI API"
        }
    }
}
