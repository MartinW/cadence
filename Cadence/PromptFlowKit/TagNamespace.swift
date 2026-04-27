import Foundation

/// Mirror of @promptflow/core's tag namespace conventions.
///
/// Cadence is a `voice:*` consumer — only prompts tagged inside that namespace
/// are surfaced in the prompt list. Other namespaces are recognised so we can
/// strip the prefix for display.
enum TagNamespace: String, CaseIterable {
    case voice
    case image
    case eval
    case app
    case lang
    case env

    func matches(_ tag: String) -> Bool {
        // A tag belongs to a namespace either as the bare namespace ("voice")
        // or with one or more sub-segments ("voice:greeting").
        tag == rawValue || tag.hasPrefix("\(rawValue):")
    }
}

extension Array where Element == String {
    func filter(namespace: TagNamespace) -> [String] {
        filter { namespace.matches($0) }
    }

    func anyIn(namespace: TagNamespace) -> Bool {
        contains { namespace.matches($0) }
    }
}
