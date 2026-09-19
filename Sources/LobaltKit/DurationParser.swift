import Foundation

/// What the user asked for, whether they spoke it or typed it.
public enum VoiceIntent: Equatable {
    /// Begin a new timer.
    case start(seconds: Int, label: String?)
    /// Extend the running timer ("give me five more minutes").
    case add(seconds: Int)
    case pause
    case resume
    case stop
    case restart
    /// Heard words, found no timer meaning in them.
    case unrecognized(String)
}

/// Turns loose human phrasing into a duration and a task label.
///
/// The same parser backs the microphone and the type-to-start field, so it has
/// to cope with both dictated sentences ("set a timer for twenty five minutes
/// to write the essay") and terse typing ("25m write essay").
public enum DurationParser {

    // MARK: - Public entry points

    /// Full intent parse. Use this for voice and for the quick-entry field.
    public static func intent(_ input: String) -> VoiceIntent {
        let tokens = tokenize(input)
        guard !tokens.isEmpty else { return .unrecognized(input) }

        let words = Set(tokens.map(\.text))
        let addWord = words.contains("add") || words.contains("plus")
            || words.contains("more") || words.contains("another")
            || words.contains("extend") || words.contains("extra")

        if let match = findDuration(in: tokens) {
            if addWord { return .add(seconds: match.seconds) }
            return .start(seconds: match.seconds, label: extractLabel(tokens, consuming: match.consumed))
        }

        // No duration — fall back to bare transport commands.
        if words.contains("pause") || words.contains("hold") || words.contains("wait") { return .pause }
        if words.contains("resume") || words.contains("continue") || words.contains("unpause") { return .resume }
        if words.contains("stop") || words.contains("cancel") || words.contains("reset")
            || words.contains("clear") || words.contains("quit") || words.contains("abort") { return .stop }
        if words.contains("restart") || words.contains("again") || words.contains("redo") { return .restart }
        if words.contains("start") || words.contains("go") || words.contains("resume") { return .resume }

        return .unrecognized(input.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Just the duration, in seconds. `nil` when nothing time-shaped was found.
    public static func seconds(_ input: String) -> Int? {
        findDuration(in: tokenize(input))?.seconds
    }

    // MARK: - Tokenizing

    struct Token {
        var text: String        // normalized, lowercased
        var original: String    // as the user said/typed it, for label rebuilding
        var number: Double?     // set once number words are folded into values
    }

    /// Splits on whitespace, peels punctuation, breaks terse forms like `25m`
    /// or `1h30m` apart, then folds number words ("twenty five") into values.
    static func tokenize(_ input: String) -> [Token] {
        var out: [Token] = []
        let rough = input.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let originals = input.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "-" || $0 == "_" })
        let normals = rough.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })

        for (i, chunk) in normals.enumerated() {
            let originalChunk = i < originals.count ? String(originals[i]) : String(chunk)
            let cleaned = String(chunk).trimmingCharacters(in: CharacterSet(charactersIn: ",.!?;\"'()"))
            guard !cleaned.isEmpty else { continue }
            let pieces = splitTerse(cleaned)
            for (j, piece) in pieces.enumerated() {
                // Only the first piece carries the original spelling; the rest are
                // unit suffixes that never appear in a label anyway.
                out.append(Token(text: piece,
                                 original: pieces.count == 1 ? stripEdgePunctuation(originalChunk) : piece,
                                 number: Double(piece)))
                _ = j
            }
        }
        return foldNumberWords(out)
    }

    private static func stripEdgePunctuation(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: ",.!?;\"'()"))
    }

    /// `25m` → `["25", "m"]`, `1h30m` → `["1","h","30","m"]`, `3:30` → `["3:30"]`.
    static func splitTerse(_ word: String) -> [String] {
        // Leave colon/decimal times intact.
        if word.contains(":") { return [word] }
        if Double(word) != nil { return [word] }
        var pieces: [String] = []
        var current = ""
        var currentIsDigit: Bool? = nil
        for ch in word {
            let isDigit = ch.isNumber || ch == "."
            if let prev = currentIsDigit, prev != isDigit {
                pieces.append(current)
                current = ""
            }
            current.append(ch)
            currentIsDigit = isDigit
        }
        if !current.isEmpty { pieces.append(current) }
        // Only treat it as a terse compound if it really was digits + a unit word.
        let looksCompound = pieces.count > 1 && pieces.contains { Double($0) != nil }
            && pieces.allSatisfy { Double($0) != nil || unit(for: $0) != nil }
        return looksCompound ? pieces : [word]
    }

    private static let smallNumbers: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
        // Speech recognition sometimes returns these spellings.
        "to": 2, "too": 2, "for": 4, "fore": 4,
    ]
    private static let tensNumbers: [String: Double] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fourty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    /// Collapses "twenty five" into a single numeric token. Homophones like
    /// "to"/"for" only count as numbers when a unit word follows them.
    static func foldNumberWords(_ tokens: [Token]) -> [Token] {
        var out: [Token] = []
        var i = 0
        while i < tokens.count {
            var t = tokens[i]
            let next: Token? = i + 1 < tokens.count ? tokens[i + 1] : nil
            let nextIsUnit = next.map { unit(for: $0.text) != nil } ?? false
            let nextIsHalf = next.map { $0.text == "half" || $0.text == "quarter" } ?? false

            if t.number == nil {
                if let tens = tensNumbers[t.text] {
                    // "twenty five" → 25
                    if let n = next, let u = smallNumbers[n.text], u < 10, unit(for: n.text) == nil,
                       !["to", "too", "for", "fore"].contains(n.text) {
                        t.number = tens + u
                        t.text = String(Int(tens + u))
                        out.append(t); i += 2; continue
                    }
                    t.number = tens; t.text = String(Int(tens))
                    out.append(t); i += 1; continue
                }
                if let v = smallNumbers[t.text] {
                    // Homophone guard: "for" is only 4 when a unit follows.
                    let risky = ["to", "too", "for", "fore"].contains(t.text)
                    if !risky || nextIsUnit {
                        t.number = v; t.text = String(Int(v))
                        out.append(t); i += 1; continue
                    }
                } else if t.text == "a" || t.text == "an" {
                    if nextIsUnit || nextIsHalf { t.number = 1 }
                } else if t.text == "couple" {
                    t.number = 2; t.text = "2"
                } else if t.text == "few" {
                    t.number = 3; t.text = "3"
                }
            }
            out.append(t); i += 1
        }
        return out
    }

    // MARK: - Units

    enum Unit: Double {
        case hour = 3600, minute = 60, second = 1
        var smaller: Unit? { self == .hour ? .minute : (self == .minute ? .second : nil) }
    }

    static func unit(for word: String) -> Unit? {
        switch word {
        case "h", "hr", "hrs", "hour", "hours", "hourse": return .hour
        case "m", "min", "mins", "minute", "minutes", "minuts": return .minute
        case "s", "sec", "secs", "second", "seconds": return .second
        default: return nil
        }
    }

    // MARK: - Duration scanning

    struct Match { var seconds: Int; var consumed: Set<Int> }

    static func findDuration(in tokens: [Token]) -> Match? {
        if let m = matchUntil(tokens) { return m }
        if let m = matchColon(tokens) { return m }
        if let m = matchUnitPairs(tokens) { return m }
        if let m = matchPreset(tokens) { return m }
        if let m = matchBareNumber(tokens) { return m }
        return nil
    }

    /// "until 3pm", "till 4:15", "until noon" — timebox to a wall-clock moment.
    static func matchUntil(_ tokens: [Token], now: Date = Date()) -> Match? {
        guard let idx = tokens.firstIndex(where: { ["until", "til", "till", "untill"].contains($0.text) })
        else { return nil }
        var consumed: Set<Int> = [idx]
        var hour: Int? = nil
        var minute = 0
        var meridiem: String? = nil
        var i = idx + 1

        while i < tokens.count, i <= idx + 4 {
            let t = tokens[i]
            if t.text == "noon" { hour = 12; meridiem = "pm"; consumed.insert(i); i += 1; break }
            if t.text == "midnight" { hour = 0; meridiem = "am"; consumed.insert(i); i += 1; break }
            if t.text == "o'clock" || t.text == "oclock" { consumed.insert(i); i += 1; continue }

            // "3pm" and "3:30pm" arrive as one token when typed; dictation tends
            // to split them. Handle both by peeling the suffix off first.
            let (body, mer) = peelMeridiem(t.text)
            if let mer { meridiem = mer }
            if body.isEmpty, mer != nil { consumed.insert(i); i += 1; continue }

            if body.contains(":"), let (h, m) = parseColonClock(body) {
                hour = h; minute = m; consumed.insert(i); i += 1; continue
            }
            if hour == nil, let n = Double(body), n >= 0, n <= 24 {
                hour = Int(n); consumed.insert(i); i += 1; continue
            }
            if mer != nil { consumed.insert(i); i += 1; continue }
            break
        }

        guard var h = hour else { return nil }
        if meridiem == "pm", h < 12 { h += 12 }
        if meridiem == "am", h == 12 { h = 0 }

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = h % 24; comps.minute = minute; comps.second = 0
        guard var target = cal.date(from: comps) else { return nil }
        if target <= now {
            // "until 3" at 4pm most likely means 3am tomorrow, but "until 3" at
            // 1am means 3am today — so only roll forward when we must.
            if meridiem == nil, let bumped = cal.date(byAdding: .hour, value: 12, to: target), bumped > now {
                target = bumped
            } else if let bumped = cal.date(byAdding: .day, value: 1, to: target) {
                target = bumped
            }
        }
        let secs = Int(target.timeIntervalSince(now).rounded())
        guard secs > 0 else { return nil }
        return Match(seconds: secs, consumed: consumed)
    }

    /// Splits a trailing am/pm marker off a clock token: `3pm` -> ("3", "pm").
    private static func peelMeridiem(_ s: String) -> (String, String?) {
        for suffix in ["a.m.", "p.m.", "a.m", "p.m", "am", "pm"] where s.hasSuffix(suffix) {
            return (String(s.dropLast(suffix.count)), suffix.hasPrefix("a") ? "am" : "pm")
        }
        return (s, nil)
    }

    private static func parseColonClock(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) else { return nil }
        return (a, b)
    }

    /// `12:30` → 12 min 30 s. `1:02:03` → 1 h 2 m 3 s.
    /// Two-part colon forms read as mm:ss, matching how the timer itself displays.
    static func matchColon(_ tokens: [Token]) -> Match? {
        for (i, t) in tokens.enumerated() where t.text.contains(":") {
            let parts = t.text.split(separator: ":").map(String.init)
            let nums = parts.compactMap { Int($0) }
            guard nums.count == parts.count else { continue }
            if nums.count == 2 {
                return Match(seconds: nums[0] * 60 + nums[1], consumed: [i])
            }
            if nums.count == 3 {
                return Match(seconds: nums[0] * 3600 + nums[1] * 60 + nums[2], consumed: [i])
            }
        }
        return nil
    }

    /// The main path: one or more `<number> <unit>` groups, with support for
    /// "and a half", "half an hour", "quarter of an hour", and trailing bare
    /// numbers that inherit the next-smaller unit ("1 hour 30").
    static func matchUnitPairs(_ tokens: [Token]) -> Match? {
        var total: Double = 0
        var consumed: Set<Int> = []
        var found = false
        var lastUnit: Unit? = nil
        var i = 0

        while i < tokens.count {
            let t = tokens[i]

            // "half an hour" / "quarter of an hour" with no leading count.
            if t.text == "half" || t.text == "quarter" {
                let frac = t.text == "half" ? 0.5 : 0.25
                if let (u, idxs) = unitAfter(tokens, from: i + 1, maxSkip: 2) {
                    total += frac * u.rawValue
                    consumed.insert(i); consumed.formUnion(idxs)
                    lastUnit = u; found = true
                    i = (idxs.max() ?? i) + 1
                    continue
                }
            }

            guard let n = t.number else { i += 1; continue }

            // "two and a half hours"
            var value = n
            var span: Set<Int> = [i]
            var cursor = i + 1
            if cursor + 1 < tokens.count, tokens[cursor].text == "and",
               tokens[cursor + 1].text == "a" || tokens[cursor + 1].text == "half"
                || tokens[cursor + 1].text == "quarter" {
                var probe = cursor + 1
                if tokens[probe].text == "a" { probe += 1 }
                if probe < tokens.count, tokens[probe].text == "half" || tokens[probe].text == "quarter" {
                    value += tokens[probe].text == "half" ? 0.5 : 0.25
                    for k in cursor...probe { span.insert(k) }
                    cursor = probe + 1
                }
            }

            if let (u, idxs) = unitAfter(tokens, from: cursor, maxSkip: 1) {
                total += value * u.rawValue
                span.formUnion(idxs)
                var after = (idxs.max() ?? cursor) + 1
                // "an hour and a half" — here the fraction trails the unit.
                if let (frac, fracIdxs) = trailingFraction(tokens, from: after) {
                    total += frac * u.rawValue
                    span.formUnion(fracIdxs)
                    after = (fracIdxs.max() ?? after) + 1
                }
                consumed.formUnion(span)
                lastUnit = u; found = true
                i = after
                continue
            }

            // Bare number right after a unit group: "1 hour 30" → 30 minutes.
            if found, let smaller = lastUnit?.smaller, i == (consumed.max() ?? -2) + 1 {
                total += value * smaller.rawValue
                consumed.formUnion(span)
                lastUnit = smaller
                i = cursor
                continue
            }
            i += 1
        }
        guard found, total > 0 else { return nil }
        return Match(seconds: Int(total.rounded()), consumed: consumed)
    }

    /// Finds a unit word at or shortly after `from`, skipping filler like "of an".
    private static func unitAfter(_ tokens: [Token], from: Int, maxSkip: Int) -> (Unit, Set<Int>)? {
        var idxs: Set<Int> = []
        var i = from
        var skipped = 0
        while i < tokens.count, skipped <= maxSkip {
            if let u = unit(for: tokens[i].text) {
                idxs.insert(i)
                return (u, idxs)
            }
            if ["of", "a", "an"].contains(tokens[i].text) {
                idxs.insert(i); skipped += 1; i += 1; continue
            }
            return nil
        }
        return nil
    }

    /// Matches a trailing "and a half" / "and a quarter" after a unit word.
    private static func trailingFraction(_ tokens: [Token], from: Int) -> (Double, Set<Int>)? {
        guard from < tokens.count, tokens[from].text == "and" else { return nil }
        var i = from + 1
        var idxs: Set<Int> = [from]
        if i < tokens.count, tokens[i].text == "a" || tokens[i].text == "an" {
            idxs.insert(i); i += 1
        }
        guard i < tokens.count else { return nil }
        switch tokens[i].text {
        case "half": idxs.insert(i); return (0.5, idxs)
        case "quarter": idxs.insert(i); return (0.25, idxs)
        default: return nil
        }
    }

    /// Spoken shorthand people actually use.
    static let presets: [(phrase: [String], seconds: Int)] = [
        (["pomodoro"], 25 * 60),
        (["long", "break"], 15 * 60),
        (["short", "break"], 5 * 60),
        (["deep", "work"], 90 * 60),
        (["coffee", "break"], 10 * 60),
        (["break"], 5 * 60),
        (["power", "nap"], 20 * 60),
    ]

    static func matchPreset(_ tokens: [Token]) -> Match? {
        let texts = tokens.map(\.text)
        for preset in presets {
            guard preset.phrase.count <= texts.count else { continue }
            for start in 0...(texts.count - preset.phrase.count) {
                if Array(texts[start..<(start + preset.phrase.count)]) == preset.phrase {
                    let consumed = Set(start..<(start + preset.phrase.count))
                    return Match(seconds: preset.seconds, consumed: consumed)
                }
            }
        }
        return nil
    }

    /// A number on its own means minutes — "45" is 45 minutes, not 45 seconds.
    static func matchBareNumber(_ tokens: [Token]) -> Match? {
        for (i, t) in tokens.enumerated() {
            guard let n = t.number, n > 0 else { continue }
            return Match(seconds: Int((n * 60).rounded()), consumed: [i])
        }
        return nil
    }

    // MARK: - Label extraction

    private static let leadingPhrases: [[String]] = [
        ["set", "a", "timer", "for"], ["set", "a", "timer", "to"], ["set", "timer", "for"],
        ["start", "a", "timer", "for"], ["start", "timer", "for"], ["set", "a", "timer"],
        ["give", "me"], ["i", "want", "to"], ["i", "need", "to"], ["i", "want"], ["i", "need"],
        ["let", "s", "do"], ["lets", "do"], ["let", "me"], ["make", "it"], ["count", "down"],
        ["hey", "lobalt"], ["can", "you"], ["could", "you"], ["start", "a"], ["put", "on"],
        ["i", "m", "going", "to"], ["im", "going", "to"], ["going", "to"], ["time", "me"],
    ]
    private static let leadingWords: Set<String> = [
        "for", "to", "a", "an", "the", "and", "of", "please", "just", "now", "my",
        "set", "timer", "start", "okay", "ok", "um", "uh", "so", "then", "on", "in",
        "spent", "spend", "next", "another", "more", "add", "plus", "extra", "extend",
    ]
    private static let trailingWords: Set<String> = [
        "for", "to", "of", "and", "the", "a", "an", "please", "now", "timer",
        "more", "long", "in", "on", "left", "from", "then", "up", "starting", "start",
    ]

    /// Everything the user said that wasn't the duration, cleaned of scaffolding.
    static func extractLabel(_ tokens: [Token], consuming: Set<Int>) -> String? {
        var words = tokens.enumerated()
            .filter { !consuming.contains($0.offset) }
            .map { $0.element }
            .filter { !$0.original.isEmpty }

        // Greedy strip of known opening scaffolding.
        var changed = true
        while changed {
            changed = false
            for phrase in leadingPhrases where words.count >= phrase.count {
                if Array(words.prefix(phrase.count)).map(\.text) == phrase {
                    words.removeFirst(phrase.count); changed = true; break
                }
            }
        }
        while let first = words.first, leadingWords.contains(first.text) { words.removeFirst() }
        while let last = words.last, trailingWords.contains(last.text) { words.removeLast() }

        let label = words.map(\.original).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return nil }
        // Speech gives back lowercase; a leading capital just reads better.
        return label.prefix(1).uppercased() + label.dropFirst()
    }
}
