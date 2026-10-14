import Foundation

/// Polish text templates with `{placeholder}` substitution.
public struct ExplainTemplates: Sendable {
    public let texts: [String: String]

    public init(texts: [String: String]) {
        self.texts = texts
    }

    public func render(_ key: String, _ values: [String: String] = [:], overrides: [String: String] = [:]) -> String {
        let template = overrides[key] ?? texts[key] ?? key
        return values.reduce(template) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }
}

public enum PolishNumber {
    public static func format(_ value: Double, decimals: Int = 1) -> String {
        let text = String(format: "%.\(decimals)f", value)
        return text.replacingOccurrences(of: ".", with: ",")
    }

    public static func integer(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
