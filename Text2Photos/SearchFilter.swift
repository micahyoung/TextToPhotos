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
        "answer": "SELECT a.ZUUID FROM ZASSET a WHERE a.ZTRASHEDSTATE = 0 AND a.ZKIND = 0 AND a.ZFAVORITE = 1 ORDER BY a.ZDATECREATED DESC LIMIT 50"
    ],
    [
        "question": "best photos",
        "answer": "SELECT a.ZUUID FROM ZASSET a WHERE a.ZTRASHEDSTATE = 0 AND a.ZKIND = 0 ORDER BY a.ZOVERALLAESTHETICSCORE DESC LIMIT 50"
    ],
    [
        "question": "photos from San Francisco",
        "answer": "SELECT a.ZUUID FROM ZASSET a WHERE a.ZTRASHEDSTATE = 0 AND a.ZKIND = 0 AND a.ZLATITUDE BETWEEN 37.60 AND 37.90 AND a.ZLONGITUDE BETWEEN -123.00 AND -122.20 ORDER BY a.ZDATECREATED DESC LIMIT 50"
    ],
    [
        "question": "photos from this month",
        "answer": "SELECT a.ZUUID FROM ZASSET a WHERE a.ZTRASHEDSTATE = 0 AND a.ZKIND = 0 AND a.ZDATECREATED > (strftime('%s','now','start of month') - 978307200) ORDER BY a.ZDATECREATED DESC LIMIT 50"
    ],
    [
        "question": "photos from 2024",
        "answer": "SELECT a.ZUUID FROM ZASSET a WHERE a.ZTRASHEDSTATE = 0 AND a.ZKIND = 0 AND a.ZDATECREATED >= (strftime('%s','2024-01-01') - 978307200) AND a.ZDATECREATED < (strftime('%s','2025-01-01') - 978307200) ORDER BY a.ZDATECREATED DESC LIMIT 50"
    ],
    [
        "question": "large photos",
        "answer": "SELECT a.ZUUID FROM ZASSET a WHERE a.ZTRASHEDSTATE = 0 AND a.ZKIND = 0 AND (a.ZPIXELWIDTH > 2000 OR a.ZPIXELHEIGHT > 2000) ORDER BY a.ZDATECREATED DESC LIMIT 50"
    ],
    [
        "question": "portrait photos",
        "answer": "SELECT a.ZUUID FROM ZASSET a WHERE a.ZTRASHEDSTATE = 0 AND a.ZKIND = 0 AND a.ZPIXELHEIGHT > a.ZPIXELWIDTH ORDER BY a.ZDATECREATED DESC LIMIT 50"
    ],
    [
        "question": "photos of Tina Turner",
        "answer": "SELECT DISTINCT a.ZUUID FROM ZASSET a INNER JOIN ZDETECTEDFACE df ON df.ZASSETFORFACE = a.Z_PK INNER JOIN ZPERSON p ON p.Z_PK = df.ZPERSONFORFACE WHERE a.ZTRASHEDSTATE = 0 AND a.ZKIND = 0 AND p.ZDISPLAYNAME LIKE '%Tina Turner%' ORDER BY a.ZDATECREATED DESC LIMIT 50"
    ],
    [
        "question": "photos of my favorite people",
        "answer": "SELECT DISTINCT a.ZUUID FROM ZASSET a INNER JOIN ZDETECTEDFACE df ON df.ZASSETFORFACE = a.Z_PK INNER JOIN ZPERSON p ON p.Z_PK = df.ZPERSONFORFACE WHERE a.ZTRASHEDSTATE = 0 AND a.ZKIND = 0 AND p.ZDISPLAYNAME IS NOT NULL AND p.ZDISPLAYNAME != '' GROUP BY a.ZUUID ORDER BY COUNT(DISTINCT p.Z_PK) DESC LIMIT 50"
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
SELECT a.ZUUID FROM ...
```

RULES:
1. Return valid SQL only without explanations
2. Use proper SQL syntax for Photos SQLite database
5. Always SELECT a.ZUUID as the first column
6. Base table is ZASSET for photos
7. Always include JOIN for any columns from other tables
8. Always subtract offset of 978307200 when using relative time functions: "today" is `strftime('%s','now','start of day') - 978307200`
9. Always wrap SQL response in ```sql blocks

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

CREATE TABLE ZPERSON (
  Z_PK INTEGER PRIMARY KEY,
  ZDISPLAYNAME TEXT, -- Person's display name (manually set or suggested)
);

CREATE TABLE ZDETECTEDFACE (
  Z_PK INTEGER PRIMARY KEY,
  ZASSETFORFACE INTEGER, -- Foreign key to ZASSET.Z_PK
  ZPERSONFORFACE INTEGER, -- Foreign key to ZPERSON.Z_PK
);
```

EXAMPLE RESPONSES:

\(examplesSection)
"""

    do {
        // Create session with system instructions
        let session = LanguageModelSession(instructions: systemInstructions)

        // Generate structured response from user query with temperature setting
        let options = GenerationOptions(temperature: 0.0)
        let response = try await session.respond(to: query, options: options)
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
