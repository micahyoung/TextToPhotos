//
//  SQLGenerationClient.swift
//  Text2Photos
//
//  Created by user on 9/27/25.
//

import Foundation
import FoundationModels

public protocol GenerationClientProtocol {
    func generate(query: String, systemInstructions: String) async throws -> String
}

enum SearchError: LocalizedError {
    case foundationModelsNotAvailable(reason: String)
    case foundationModelsError(Error)
    case predicateCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .foundationModelsNotAvailable(let reason):
            return "AI search is not available: \(reason). Please ensure Apple Intelligence is enabled in Settings."
        case .foundationModelsError(let error):
            return "AI search error: \(error.localizedDescription)"
        case .predicateCreationFailed(let predicateString):
            return "Failed to create search filter from: '\(predicateString)'. Please try rephrasing your search."
        }
    }
}

public class AppleGenerationClient: GenerationClientProtocol {
    public init() {}
    
    public
    func generate(query: String, systemInstructions: String) async throws -> String {
        // Check if Foundation Models is available
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            throw SearchError.foundationModelsNotAvailable(reason: "Device not eligible for Apple Intelligence")
        case .unavailable(.appleIntelligenceNotEnabled):
            throw SearchError.foundationModelsNotAvailable(reason: "Apple Intelligence not enabled")
        case .unavailable(.modelNotReady):
            throw SearchError.foundationModelsNotAvailable(reason: "AI model not ready (downloading or system busy)")
        case .unavailable(let other):
            throw SearchError.foundationModelsNotAvailable(reason: "Unknown reason: \(other)")
        }
        
        // Create session with system instructions
        let session = LanguageModelSession(instructions: systemInstructions)

        // Generate structured response from user query with temperature setting
        let options = GenerationOptions(sampling: GenerationOptions.SamplingMode.greedy)
        let response = try await session.respond(to: query, options: options)
        let rawSQLString = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        return rawSQLString
    }
}
