//
//  SearchFilter.swift
//  Text2Photos
//
//  Created by user on 9/27/25.
//

import Foundation
import FoundationModels
import CoreLocation

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

public let searchExamples: [[String: String]] = [
    [
        "question": "favorite photos",
        "answer": "SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 AND ZFAVORITE = 1 ORDER BY ZDATECREATED DESC LIMIT 50"
    ],
    [
        "question": "best photos",
        "answer": "SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 ORDER BY ZOVERALLAESTHETICSCORE DESC LIMIT 50"
    ],
    [
        "question": "photos from San Francisco",
        "answer": "SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 AND ZLATITUDE BETWEEN 37.60 AND 37.90 AND ZLONGITUDE BETWEEN -123.00 AND -122.20 ORDER BY ZDATECREATED DESC LIMIT 50"
    ],
    [
        "question": "photos from this month",
        "answer": "SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 AND ZDATECREATED > (strftime('%s','now','-30 days') - 978307200) ORDER BY ZDATECREATED DESC LIMIT 50"
    ],
    [
        "question": "large photos",
        "answer": "SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 AND (ZPIXELWIDTH > 2000 OR ZPIXELHEIGHT > 2000) ORDER BY ZDATECREATED DESC LIMIT 50"
    ],
    [
        "question": "hidden photos",
        "answer": "SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 AND ZHIDDEN = 1 ORDER BY ZDATECREATED DESC LIMIT 50"
    ],
    [
        "question": "recent photos",
        "answer": "SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 ORDER BY ZDATECREATED DESC LIMIT 50"
    ],
    [
        "question": "portrait photos",
        "answer": "SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 AND ZPIXELHEIGHT > ZPIXELWIDTH ORDER BY ZDATECREATED DESC LIMIT 50"
    ]
]

public func generateDynamicSearchFilter(from searchText: String) async throws -> String {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

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

    // Generate examples section from data
    let examplesSection = searchExamples.map { example in
        "Q: \(example["question"]!)\nA: ```sql\n\(example["answer"]!)\n```"
    }.joined(separator: "\n\n")

    // Create system instructions with templated examples
    let systemInstructions = """
You are an expert at analyzing natural language photo search queries and returning SQL queries for the macOS Photos SQLite database.

Your task is to analyze the user's search query and return a SQL query reponse.

RESPONSE FORMAT (SQL):
```sql
SELECT ZUUID FROM ...
```

RULES:
1. Return valid SQL only without explanations
2. Use proper SQL syntax for Photos SQLite database
5. Always SELECT ZUUID as the first column
6. Base table is ZASSET for photos
7. Always wrap SQL response in ```sql blocks

PHOTOS DATABASE SCHEMA (DDL subset):
```sql
CREATE TABLE ZASSET (
  Z_PK INTEGER PRIMARY KEY,
  ZUUID TEXT, -- Unique identifier for photo
  ZDATECREATED REAL, -- Creation timestamp (Core Data absolute time)
  ZLATITUDE REAL, -- GPS latitude
  ZLONGITUDE REAL, -- GPS longitude
  ZKIND INTEGER, -- Media type (0=photo, 1=video)
  ZTRASHEDSTATE INTEGER, -- 0=not trashed, 1=trashed
  ZFAVORITE INTEGER, -- 0=not favorite, 1=favorite
  ZHIDDEN INTEGER, -- 0=not hidden, 1=hidden
  ZPIXELWIDTH INTEGER, -- Image width in pixels
  ZPIXELHEIGHT INTEGER, -- Image height in pixels
  ZADDEDDATE REAL, -- Date added (Core Data absolute time)
  ZMODIFICATIONDATE REAL, -- Last modification date (Core Data absolute time)
  ZOVERALLAESTHETICSCORE REAL -- Machine-learned aesthetic quality score (higher is better); may be null
);
```

COMMON SQL PATTERNS:
- Always filter out trashed photos: `WHERE ZTRASHEDSTATE = 0`
- Photo only (not video): `AND ZKIND = 0`
- Sort by creation date: `ORDER BY ZDATECREATED DESC`
- Limit results: `LIMIT 50`
- Favorites: `AND ZFAVORITE = 1`
- Hidden photos: `AND ZHIDDEN = 1`
- Location: `AND ZLATITUDE BETWEEN`
- Date ranges in sqlite timestamp format: `AND ZDATECREATED > (strftime('%s','now','-1 days')`

EXAMPLE RESPONSES:

\(examplesSection)
"""

    do {
        // Create session with system instructions
        let session = LanguageModelSession(instructions: systemInstructions)

        // Generate structured response from user query
        let response = try await session.respond(to: query)
        let rawSQLString = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clean the response - remove markdown code blocks if present
        let sqlString: String
        if rawSQLString.hasPrefix("```sql") && rawSQLString.hasSuffix("```") {
            // Remove ```sql at start and ``` at end
            let startIndex = rawSQLString.index(rawSQLString.startIndex, offsetBy: 6) // "```sql".count
            let endIndex = rawSQLString.index(rawSQLString.endIndex, offsetBy: -3) // "```".count
            sqlString = String(rawSQLString[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            sqlString = rawSQLString
        }

        return sqlString

    } catch let error as SearchError {
        throw error
    } catch {
        throw SearchError.foundationModelsError(error)
    }
}
