import Foundation

/// Release version numbers such as "1.2.0" or GitHub tags such as "v1.2.0".
public enum AppVersion {
    /// "v1.2.0" → "1.2.0"; whitespace and a leading "v" are dropped.
    public static func normalized(_ tag: String) -> String {
        var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" { value.removeFirst() }
        return value
    }
    /// Numeric parts, ignoring any suffix such as "-beta": "1.10.2-rc1" → [1, 10, 2].
    static func parts(_ version: String) -> [Int] {
        normalized(version).split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
    }
    /// Whether `candidate` is a later release than `current` (1.10.0 is later than 1.9.9; 1.2 equals 1.2.0).
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
