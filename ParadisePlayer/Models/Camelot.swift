import Foundation

/// Liest Tonarten aus Tags und rechnet sie in Camelot-Notation um.
/// Unterstützt: Camelot ("8A", "08B"), Open Key ("1m", "6d")
/// und klassische Notation ("Am", "F#m", "Bb", "A minor").
nonisolated enum Camelot {

    /// - Parameter allowMusicalNotation: Nur für das eigentliche Tonart-Feld auf `true` setzen.
    ///   Im Kommentarfeld würde z. B. "A great track" sonst als A-Dur erkannt.
    static func parse(_ raw: String, allowMusicalNotation: Bool) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // Camelot, z. B. "8A", "08B", "8A - Energy 6"
        if let m = match(#"(?<![0-9])(1[0-2]|0?[1-9])\s?([ABab])(?![A-Za-z])"#, in: s), let n = Int(m[1]) {
            return "\(n)\(m[2].uppercased())"
        }

        // Open Key, z. B. "1m" (= 8A), "1d" (= 8B)
        if let m = match(#"(?<![0-9])(1[0-2]|0?[1-9])([dmDM])(?![A-Za-z])"#, in: s), let n = Int(m[1]) {
            let number = (n + 6) % 12 + 1
            return "\(number)\(m[2].lowercased() == "m" ? "A" : "B")"
        }

        guard allowMusicalNotation else { return nil }

        // Klassisch, z. B. "Am", "F#m", "Ebm", "Bb", "C major"
        if let m = match(#"^([A-G])\s*([#♯b♭]?)\s*((?i:minor|moll|min|major|dur|maj|m))?(?![A-Za-z])"#, in: s) {
            let base: [String: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
            guard var pc = base[m[1]] else { return nil }
            switch m[2] {
            case "#", "♯": pc += 1
            case "b", "♭": pc -= 1
            default: break
            }
            pc = (pc + 12) % 12
            let isMinor = ["m", "min", "minor", "moll"].contains(m[3].lowercased())
            return fromPitchClass(pc, minor: isMinor)
        }
        return nil
    }

    /// Tonhöhenklasse (C = 0 … B = 11) nach Camelot.
    static func fromPitchClass(_ pc: Int, minor: Bool) -> String {
        let majorPC = minor ? (pc + 3) % 12 : pc
        let number = ((majorPC * 7) % 12 + 7) % 12 + 1
        return "\(number)\(minor ? "A" : "B")"
    }

    static func components(_ key: String) -> (number: Int, letter: Character)? {
        guard let letter = key.last, letter == "A" || letter == "B",
              let n = Int(key.dropLast()), (1...12).contains(n) else { return nil }
        return (n, letter)
    }

    /// Harmonisch passend: gleiche Zahl, oder ±1 mit gleichem Buchstaben.
    static func isCompatible(_ a: String, _ b: String) -> Bool {
        guard let x = components(a), let y = components(b) else { return false }
        if x.number == y.number { return true }
        guard x.letter == y.letter else { return false }
        let d = abs(x.number - y.number)
        return d == 1 || d == 11
    }

    static func sortKey(_ key: String?) -> Int {
        guard let key, let c = components(key) else { return Int.max }
        return c.number * 2 + (c.letter == "B" ? 1 : 0)
    }

    private static func match(_ pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            guard let r = Range(m.range(at: i), in: s) else { return "" }
            return String(s[r])
        }
    }
}
