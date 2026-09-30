public enum ActivatorAssignment {
    public static let reservedLetters: Set<Character> = ["d", "j", "k"]

    public static func keys(for entries: [String]) -> [String] {
        var taken = Set<String>()
        var result: [String] = []
        for (offset, entry) in entries.enumerated() {
            let key: String
            switch offset {
            case 0: key = "Space"
            case 1: key = "d"
            default: key = firstFreeKey(forName: entry, taken: taken)
            }
            taken.insert(key)
            result.append(key)
        }
        return result
    }

    private static func firstFreeKey(forName name: String, taken: Set<String>) -> String {
        for ch in name.lowercased() where ch.isLetter {
            let candidate = String(ch)
            if !reservedLetters.contains(ch) && !taken.contains(candidate) { return candidate }
        }
        for digit in 1...9 where !taken.contains(String(digit)) { return String(digit) }
        return ""
    }
}
