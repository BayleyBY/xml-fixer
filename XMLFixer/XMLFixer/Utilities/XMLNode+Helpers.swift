import Foundation

extension XMLElement {
    /// Get a single string value at a relative XPath.
    func singleStringValue(forXPath xpath: String) -> String? {
        (try? nodes(forXPath: xpath))?.first?.stringValue
    }

    /// Get a single integer value at a relative XPath.
    func singleIntValue(forXPath xpath: String) -> Int? {
        guard let str = singleStringValue(forXPath: xpath) else { return nil }
        return Int(str)
    }

    /// Get the value of an attribute by name.
    func attributeValue(forName name: String) -> String? {
        attribute(forName: name)?.stringValue
    }
}
