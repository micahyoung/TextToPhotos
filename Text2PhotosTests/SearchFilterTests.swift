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
            "question": "best photos from New York City in 2025",
            "answer": "SELECT ZUUID FROM ZASSET WHERE ZTRASHEDSTATE = 0 AND ZKIND = 0 AND ZLATITUDE BETWEEN 37.60 AND 37.90 AND ZLONGITUDE BETWEEN -123.00 AND -122.20 AND ZDATECREATED > (strftime('%s','now','-1 days') - 978307200) ORDER BY ZDATECREATED DESC LIMIT 50"
        ],
        [
            "question": "photos of Tina Turner from today",
            "answer": ""
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
            XCTAssertTrue(answer.contains("SELECT ZUUID FROM"), "Example \(index + 1) answer should be a valid SQL query starting with SELECT ZUUID FROM")

            let actualAnswer = try await generateDynamicSearchFilter(from: question)

            // Normalize whitespace for comparison
            let normalizedActual = actualAnswer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let normalizedExpected = answer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            XCTAssertEqual(
                normalizedActual,
                normalizedExpected,
                "Example \(index + 1): Question '\(question)' should generate expected SQL. Got: \(normalizedActual)"
            )

            print("✅ Example \(index + 1) passed: '\(question)'")
        }
    }
}
