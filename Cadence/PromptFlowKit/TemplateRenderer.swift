import Foundation

/// Mirror of @promptflow/core's `renderPrompt` and `extractVariables`.
///
/// We use the same `{{variable}}` mustache-style syntax as Langfuse and the
/// rest of PromptFlow. Whitespace inside braces is tolerated; missing
/// variables are left as the literal `{{name}}` token (matches the JS `lenient`
/// default — handy in AIPlay-style runs where you can spot what wasn't filled).
enum TemplateRenderer {
    /// Distinct variables from the template, in first-seen order.
    static func extractVariables(from template: String) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        forEachMatch(in: template) { name in
            if !seen.contains(name) {
                seen.insert(name)
                ordered.append(name)
            }
        }
        return ordered
    }

    /// Substitute every `{{variable}}` for which we have a value in `variables`.
    /// Variables not present in the dictionary are left untouched.
    static func render(_ template: String, variables: [String: String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return template }
        let ns = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: ns.length))

        // Walk in reverse so range offsets stay valid as we replace.
        var result = template
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range, in: result),
                  let nameRange = Range(match.range(at: 1), in: result) else { continue }
            let name = String(result[nameRange])
            if let value = variables[name] {
                result.replaceSubrange(fullRange, with: value)
            }
        }
        return result
    }

    private static let pattern = #"\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}"#

    private static func forEachMatch(in template: String, body: (String) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let ns = template as NSString
        let range = NSRange(location: 0, length: ns.length)
        regex.enumerateMatches(in: template, range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 2,
                  let nameRange = Range(match.range(at: 1), in: template) else { return }
            body(String(template[nameRange]))
        }
    }
}
