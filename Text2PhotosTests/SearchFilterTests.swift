//
//  SearchFilterTests.swift
//  Text2PhotosTests
//
//  Created by user on 9/27/25.
//

import XCTest
import FoundationModels
@testable import Text2Photos

final class SearchFilterTests: XCTestCase {
    let testOnlySearchExamples: [[String: String]] = [
        [
            "question": "photos taken near Libreville, Gabon in 2025",
            "answer": "SELECT a.ZUUID FROM ZASSET a WHERE a.ZTRASHEDSTATE = 0 AND a.ZKIND = 0 AND a.ZLATITUDE BETWEEN 2.5 AND 3.5 AND a.ZLONGITUDE BETWEEN 10.5 AND 11.5 AND a.ZDATECREATED >= (strftime('%s','2025-01-01') - 978307200) AND a.ZDATECREATED < (strftime('%s','2026-01-01') - 978307200) ORDER BY a.ZDATECREATED DESC LIMIT 50"
        ],
        [
            "question": "photos of Bob and Louise taken today",
            "answer": "SELECT a.ZUUID FROM ZASSET a WHERE a.ZTRASHEDSTATE = 0 AND a.ZKIND = 0 AND EXISTS (SELECT 1 FROM ZDETECTEDFACE df JOIN ZPERSON p ON p.Z_PK = df.ZPERSONFORFACE WHERE df.ZASSETFORFACE = a.Z_PK AND p.ZDISPLAYNAME LIKE '%Bob%') AND EXISTS (SELECT 1 FROM ZDETECTEDFACE df JOIN ZPERSON p ON p.Z_PK = df.ZPERSONFORFACE WHERE df.ZASSETFORFACE = a.Z_PK AND p.ZDISPLAYNAME LIKE '%Louise%') AND a.ZDATECREATED > (strftime('%s','now','start of day') - 978307200) ORDER BY a.ZDATECREATED DESC LIMIT 50"
        ]
    ]

    @MainActor
    func testGenerateDynamicSearchFilterWithExampleQuestions() async throws {
        let client = AppleGenerationClient()

        let allExamples = testOnlySearchExamples + searchExamples

        // Test each example question to ensure it generates the expected SQL answer
        for (index, example) in allExamples.enumerated() {
            let question = example["question"]!
            let answer = example["answer"]!

            XCTAssertFalse(question.isEmpty, "Example \(index + 1) question should not be empty")
            XCTAssertFalse(answer.isEmpty, "Example \(index + 1) answer should not be empty")

            let actualAnswer = try await generateDynamicSearchFilter(from: question, client: client)

            // Normalize whitespace for comparison
            let normalizedActual = actualAnswer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let normalizedExpected = answer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            XCTAssertEqual(
                normalizedActual,
                normalizedExpected,
            )
        }
    }
}
