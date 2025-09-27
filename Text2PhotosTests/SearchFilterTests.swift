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
            "question": "best photos within one degree N/E/S/W of Libreville, Gabon in 2025",
            "answer": "SELECT a.ZUUID FROM ZASSET a WHERE a.ZTRASHEDSTATE = 0 AND a.ZKIND = 0 AND (a.ZLATITUDE BETWEEN 2.00 AND 4.00 OR a.ZLONGITUDE BETWEEN 10.00 AND 12.00) AND a.ZDATECREATED >= (strftime('%s','2025-01-01') - 978307200) AND a.ZDATECREATED < (strftime('%s','2026-01-01') - 978307200) ORDER BY a.ZDATECREATED DESC LIMIT 50"
        ],
        [
            "question": "photos of Tina Turner from today",
            "answer": "SELECT DISTINCT a.ZUUID FROM ZASSET a INNER JOIN ZDETECTEDFACE df ON df.ZASSETFORFACE = a.Z_PK INNER JOIN ZPERSON p ON p.Z_PK = df.ZPERSONFORFACE WHERE a.ZTRASHEDSTATE = 0 AND a.ZKIND = 0 AND p.ZDISPLAYNAME LIKE '%Tina Turner%' AND a.ZDATECREATED > (strftime('%s','now','start of day') - 978307200) ORDER BY a.ZDATECREATED DESC LIMIT 50"
        ]
    ]

    func testGenerateDynamicSearchFilterWithExampleQuestions() async throws {
        // Skip test if Foundation Models is not available
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            throw XCTSkip("Foundation Models not available on this device")
        }

        let allExamples = testOnlySearchExamples + searchExamples

        // Test each example question to ensure it generates the expected SQL answer
        for (index, example) in allExamples.enumerated() {
            let question = example["question"]!
            let answer = example["answer"]!

            XCTAssertFalse(question.isEmpty, "Example \(index + 1) question should not be empty")
            XCTAssertFalse(answer.isEmpty, "Example \(index + 1) answer should not be empty")

            let actualAnswer = try await generateDynamicSearchFilter(from: question)

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
