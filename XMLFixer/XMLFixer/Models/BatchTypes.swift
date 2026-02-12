import Foundation

enum BatchField: String, CaseIterable {
    case filename = "Filename"
    case reelName = "Reel Name"
    case pathURL = "Path URL"
}

enum BatchOperation {
    case findReplace(find: String, replace: String, useRegex: Bool)
    case prepend(String)
    case append(String)
    case setValue(String)

    func apply(to input: String) -> String {
        switch self {
        case .findReplace(let find, let replace, let useRegex):
            if useRegex, let regex = try? NSRegularExpression(pattern: find) {
                let range = NSRange(input.startIndex..., in: input)
                return regex.stringByReplacingMatches(in: input, range: range, withTemplate: replace)
            }
            return input.replacingOccurrences(of: find, with: replace)
        case .prepend(let prefix): return prefix + input
        case .append(let suffix): return input + suffix
        case .setValue(let value): return value
        }
    }
}
