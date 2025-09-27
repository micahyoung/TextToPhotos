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
            "question": "best photos within one degree of Libreville, Gabon in 2025",
            "answer": "SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 AND ZLATITUDE BETWEEN 2.00 AND 3.00 AND ZLONGITUDE BETWEEN 10.00 AND 11.00 AND ZDATECREATED >= (strftime('%s','2025-01-01') - 978307200) AND ZDATECREATED < (strftime('%s','2025-12-31') - 978307200) ORDER BY ZDATECREATED DESC LIMIT 50"
        ],
        [
            "question": "photos of Tina Turner from today",
            "answer": "SELECT DISTINCT ZASSET.ZUUID FROM ZASSET INNER JOIN ZDETECTEDFACE ON ZDETECTEDFACE.ZASSETFORFACE = ZASSET.Z_PK INNER JOIN ZPERSON ON ZPERSON.Z_PK = ZDETECTEDFACE.ZPERSONFORFACE WHERE ZASSET.ZTRASHEDSTATE = 0 AND ZASSET.ZKIND = 0 AND ZPERSON.ZDISPLAYNAME LIKE '%Tina Turner%' AND ZASSET.ZDATECREATED = (strftime('%s','now','start of day')) ORDER BY ZASSET.ZDATECREATED DESC LIMIT 50"
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
