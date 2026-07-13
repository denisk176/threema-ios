import Foundation
import Testing

@testable import Threema

@Suite("SendLocationURLBuilder placeholder replacement")
struct SendLocationURLBuilderTests {

    // MARK: - Matched placeholders

    @Test("Replaces all placeholders found in the path")
    func replacesAllPlaceholdersFoundInPath() {
        let path = SendLocationURLBuilder.replacingPlaceholders(
            in: "/surrounding/{latitude}/{longitude}/{radius}/",
            with: [
                "{latitude}": "47.366869",
                "{longitude}": "8.543220",
                "{radius}": "10000",
            ]
        )

        #expect(path == "/surrounding/47.366869/8.543220/10000/")
    }

    @Test("Leaves a placeholder untouched if it has no matching replacement")
    func leavesUnmatchedPlaceholderUntouched() {
        let path = SendLocationURLBuilder.replacingPlaceholders(
            in: "/surrounding/{latitude}/{unknown}/",
            with: [
                "{latitude}": "47.366869",
            ]
        )

        #expect(path == "/surrounding/47.366869/{unknown}/")
    }

    @Test("Does not modify the path when there are no replacements")
    func doesNothingWhenReplacementsIsEmpty() {
        let path = SendLocationURLBuilder.replacingPlaceholders(
            in: "/surrounding/{latitude}/",
            with: [:]
        )

        #expect(path == "/surrounding/{latitude}/")
    }

    // MARK: - Encoding

    @Test("Percent-encodes substituted values so they cannot add path segments")
    func percentEncodesSubstitutedValues() {
        let path = SendLocationURLBuilder.replacingPlaceholders(
            in: "/search/{query}",
            with: [
                "{query}": "a/b c",
            ]
        )

        #expect(path == "/search/a%2Fb%20c")
    }
}
