import Foundation

/// Builds request paths for the Threema POI endpoints from a server-provided URL template
///
/// Used exclusively by `SendLocationSearchDataSource` and `SendLocationMapDataSource` to fill in
/// `{latitude}`/`{longitude}`/`{query}`/`{radius}` placeholders in `ThreemaPOINamesURL`/`ThreemaPOIAroundURL`.
enum SendLocationURLBuilder {
    /// Replaces `{placeholder}` tokens in `path` with the given values
    ///
    /// Placeholders without a matching entry in `replacements` are left untouched. Replacement values are
    /// percent-encoded so they cannot introduce additional path segments or otherwise change the URL structure.
    /// - Parameters:
    ///   - path: Path template containing `{placeholder}` tokens
    ///   - replacements: Maps placeholder tokens (e.g. `"{latitude}"`) to their replacement value
    /// - Returns: `path` with all placeholders resolved
    static func replacingPlaceholders(in path: String, with replacements: [String: String]) -> String {
        guard let regex = try? Regex(#"\{\w+\}"#) else {
            return path
        }

        return path.replacing(regex) { match in
            let token = String(path[match.range])
            guard let value = replacements[token] else {
                return token
            }
            return value.addingPercentEncoding(withAllowedCharacters: .rfc3986Unreserved) ?? value
        }
    }
}

extension CharacterSet {
    /// RFC 3986 "unreserved" characters - the only characters guaranteed to never act as a delimiter in any URI
    /// component
    ///
    /// Deliberately not `.urlPathAllowed`/`.urlQueryAllowed`: both still leave `/` (and other sub-delimiters)
    /// unescaped since `/` is syntactically legal within a path or query component as a whole. But values here are
    /// inserted as a single path *segment*, so a literal `/` would still split it into multiple segments and change
    /// the URL's structure - regardless of which "allowed" character set was used to decide it didn't need escaping.
    fileprivate static let rfc3986Unreserved = CharacterSet(charactersIn: "-._~").union(.alphanumerics)
}
