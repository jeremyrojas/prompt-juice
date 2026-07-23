import Foundation

enum ClaudeUsageWindowKind: Sendable, Equatable, Hashable {
    case session
    case weeklyAllModels
    case weeklyModel(String)
}

struct ClaudeUsageQuotaWindow: Sendable, Equatable {
    let kind: ClaudeUsageWindowKind
    let usedPercent: Double
    let resetAt: Date
}

struct ClaudeUsageReading: Sendable, Equatable {
    let session: ClaudeUsageQuotaWindow
    let weekly: ClaudeUsageQuotaWindow?
    let modelSpecificWeekly: [ClaudeUsageQuotaWindow]
    let plan: String?
    let measuredAt: Date
    let isSavedReading: Bool
}

enum ClaudeUsageParseFailure: Sendable, Equatable {
    case usagePanelUnavailable
    case incompleteWindow
    case invalidPercentage
    case malformedMeasurementTimestamp
    case outputTooLarge
}

struct ClaudeUsageParseResult: Sendable, Equatable {
    let reading: ClaudeUsageReading?
    let rateLimitObserved: Bool
    let failure: ClaudeUsageParseFailure?
}

struct ClaudeUsageParser {
    static let maximumOutputBytes = 512 * 1_024

    func parse(
        _ data: Data,
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> ClaudeUsageParseResult {
        guard data.count <= Self.maximumOutputBytes else {
            return ClaudeUsageParseResult(
                reading: nil,
                rateLimitObserved: false,
                failure: .outputTooLarge
            )
        }

        let visibleText = Self.visibleTerminalText(from: data)
        let lines = visibleText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let lowercasedText = visibleText.lowercased()
        let rateLimitObserved = Self.latestUsagePanelText(in: visibleText)
            .map { Self.containsRateLimitSignal($0.lowercased()) }
            ?? false
        let containsUsagePanel = lowercasedText.contains("usage")

        let measurementLines = lines.filter { $0.lowercased().hasPrefix("as of ") }
        let measurementDate = measurementLines.last.flatMap {
            Self.parseMeasurementDate($0, calendar: calendar)
        }
        let malformedMeasurementTimestamp = !measurementLines.isEmpty && measurementDate == nil
        let referenceDate = measurementDate ?? now

        var plan: String?
        var currentKind: ClaudeUsageWindowKind?
        var pendingPercentage: PendingPercentage?
        var candidates: [WindowCandidate] = []
        var sawPercentage = false
        var sawInvalidPercentage = false
        var sawIncompleteWindow = false

        for line in lines {
            if let detectedPlan = Self.plan(in: line) {
                plan = detectedPlan
            }

            if let kind = Self.windowKind(for: line) {
                if pendingPercentage != nil {
                    sawIncompleteWindow = true
                }
                currentKind = kind
                pendingPercentage = nil
                continue
            }

            if let percentage = Self.usedPercentage(in: line) {
                sawPercentage = true
                if !(0...100).contains(percentage) {
                    sawInvalidPercentage = true
                    pendingPercentage = nil
                    continue
                }
                pendingPercentage = PendingPercentage(
                    usedPercent: Double(percentage),
                    kind: currentKind
                )
                continue
            }

            guard Self.isResetLine(line), let pending = pendingPercentage else {
                continue
            }

            guard let resetAt = Self.parseResetDate(
                line,
                referenceDate: referenceDate,
                calendar: calendar
            ) else {
                sawIncompleteWindow = true
                self.clearPending(&pendingPercentage, currentKind: &currentKind)
                continue
            }

            let normalizedReset = Self.normalizedResetLine(line)
            let kind = pending.kind
                ?? Self.inferredKind(for: normalizedReset, candidates: candidates)
            if let kind {
                candidates.append(
                    WindowCandidate(
                        window: ClaudeUsageQuotaWindow(
                            kind: kind,
                            usedPercent: pending.usedPercent,
                            resetAt: resetAt
                        ),
                        normalizedReset: normalizedReset
                    )
                )
            } else {
                sawIncompleteWindow = true
            }
            self.clearPending(&pendingPercentage, currentKind: &currentKind)
        }

        if pendingPercentage != nil {
            sawIncompleteWindow = true
        }

        if malformedMeasurementTimestamp {
            return ClaudeUsageParseResult(
                reading: nil,
                rateLimitObserved: rateLimitObserved,
                failure: .malformedMeasurementTimestamp
            )
        }

        if sawInvalidPercentage {
            return ClaudeUsageParseResult(
                reading: nil,
                rateLimitObserved: rateLimitObserved,
                failure: .invalidPercentage
            )
        }

        let latest = Self.latestWindows(from: candidates)
        guard let session = latest.session else {
            if rateLimitObserved, !sawPercentage {
                return ClaudeUsageParseResult(
                    reading: nil,
                    rateLimitObserved: true,
                    failure: nil
                )
            }

            return ClaudeUsageParseResult(
                reading: nil,
                rateLimitObserved: rateLimitObserved,
                failure: sawIncompleteWindow || sawPercentage
                    ? .incompleteWindow
                    : (containsUsagePanel ? .incompleteWindow : .usagePanelUnavailable)
            )
        }

        return ClaudeUsageParseResult(
            reading: ClaudeUsageReading(
                session: session,
                weekly: latest.weekly,
                modelSpecificWeekly: latest.modelSpecific,
                plan: plan,
                measuredAt: measurementDate ?? now,
                isSavedReading: measurementDate != nil
            ),
            rateLimitObserved: rateLimitObserved,
            failure: nil
        )
    }

    private func clearPending(
        _ pending: inout PendingPercentage?,
        currentKind: inout ClaudeUsageWindowKind?
    ) {
        pending = nil
        currentKind = nil
    }

    static func visibleTerminalText(from data: Data) -> String {
        var text = String(decoding: data, as: UTF8.self)

        text = replacingMatches(
            pattern: #"\u001B\][^\u0007\u001B]*(?:\u0007|\u001B\\)"#,
            in: text,
            replacement: "\n"
        )
        text = replacingMatches(
            pattern: #"\u001B\[[0-?]*[ -/]*[@-~]"#,
            in: text
        ) { match in
            match.last == "m" ? "" : "\n"
        }
        text = replacingMatches(
            pattern: #"\u001B[()][0-2A-Z0-9]|\u001B[78=>]"#,
            in: text,
            replacement: "\n"
        )
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        return String(text.unicodeScalars.filter {
            $0.value == 0x09 || $0.value == 0x0A || $0.value >= 0x20
        })
    }

    private static func replacingMatches(
        pattern: String,
        in text: String,
        replacement: String
    ) -> String {
        replacingMatches(pattern: pattern, in: text) { _ in replacement }
    }

    private static func replacingMatches(
        pattern: String,
        in text: String,
        replacement: (String) -> String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        var result = text
        let matches = expression.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else {
                continue
            }
            result.replaceSubrange(range, with: replacement(String(result[range])))
        }
        return result
    }

    private static func containsRateLimitSignal(_ text: String) -> Bool {
        text.contains("rate limited")
            || text.contains("rate limit reached")
            || text.contains("too many requests")
            || text.contains("http 429")
    }

    private static func latestUsagePanelText(in text: String) -> String? {
        let panelMarkers = [
            #"(?im)^[ \t]*you:[ \t]*/usage[ \t]*$"#,
            #"(?im)^[ \t]*settings[ \t]+status[ \t]+config[ \t]+usage[ \t]+stats[ \t]*$"#,
            #"(?im)^[ \t]*usage[ \t]*$"#,
        ]
        var latestStart: String.Index?

        for pattern in panelMarkers {
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let matches = expression.matches(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
            )
            for match in matches {
                guard let range = Range(match.range, in: text) else {
                    continue
                }
                if let latestStart, range.lowerBound <= latestStart {
                    continue
                }
                latestStart = range.lowerBound
            }
        }

        return latestStart.map { String(text[$0...]) }
    }

    private static func windowKind(for line: String) -> ClaudeUsageWindowKind? {
        let normalized = line.lowercased()
        if normalized.hasPrefix("current session") {
            return .session
        }
        if normalized == "current week" || normalized.hasPrefix("current week (all models)") {
            return .weeklyAllModels
        }
        if normalized.hasPrefix("current week (") && normalized.hasSuffix(")") {
            let start = line.index(line.startIndex, offsetBy: "Current week (".count)
            let label = String(line[start..<line.index(before: line.endIndex)])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty {
                return .weeklyModel(label)
            }
        }
        return nil
    }

    private static func plan(in line: String) -> String? {
        if line.lowercased().hasPrefix("plan:") {
            let value = line.dropFirst(line.firstIndex(of: ":").map {
                line.distance(from: line.startIndex, to: $0) + 1
            } ?? 0)
            let plan = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return plan.isEmpty ? nil : plan
        }

        guard let expression = try? NSRegularExpression(
            pattern: #"\bClaude\s+(Pro|Max|Team|Enterprise)\b"#,
            options: [.caseInsensitive]
        ),
              let match = expression.firstMatch(
                in: line,
                range: NSRange(line.startIndex..<line.endIndex, in: line)
              ),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range]).capitalized
    }

    private static func usedPercentage(in line: String) -> Int? {
        guard line.lowercased().contains("used"),
              let expression = try? NSRegularExpression(pattern: #"\b([0-9]{1,3})%"#) else {
            return nil
        }

        let matches = expression.matches(
            in: line,
            range: NSRange(line.startIndex..<line.endIndex, in: line)
        )
        guard let match = matches.last,
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return Int(line[range])
    }

    private static func isResetLine(_ line: String) -> Bool {
        line.lowercased().hasPrefix("resets")
    }

    private static func normalizedResetLine(_ line: String) -> String {
        line.lowercased().filter { !$0.isWhitespace }
    }

    private static func inferredKind(
        for normalizedReset: String,
        candidates: [WindowCandidate]
    ) -> ClaudeUsageWindowKind? {
        candidates.last(where: { $0.normalizedReset == normalizedReset })?.window.kind
    }

    private static func latestWindows(
        from candidates: [WindowCandidate]
    ) -> (
        session: ClaudeUsageQuotaWindow?,
        weekly: ClaudeUsageQuotaWindow?,
        modelSpecific: [ClaudeUsageQuotaWindow]
    ) {
        var session: ClaudeUsageQuotaWindow?
        var weekly: ClaudeUsageQuotaWindow?
        var modelOrder: [String] = []
        var models: [String: ClaudeUsageQuotaWindow] = [:]

        for candidate in candidates {
            switch candidate.window.kind {
            case .session:
                session = candidate.window
            case .weeklyAllModels:
                weekly = candidate.window
            case .weeklyModel(let label):
                if models[label] == nil {
                    modelOrder.append(label)
                }
                models[label] = candidate.window
            }
        }

        return (
            session,
            weekly,
            modelOrder.compactMap { models[$0] }
        )
    }

    private static func parseMeasurementDate(
        _ line: String,
        calendar: Calendar
    ) -> Date? {
        let value = String(line.dropFirst("As of ".count))
        let formats = [
            "MMM d, yyyy 'at' h:mm:ss a zzz",
            "MMM d, yyyy 'at' h:mm a zzz",
            "yyyy-MM-dd HH:mm:ss Z",
        ]
        return parse(value, formats: formats, timeZone: calendar.timeZone)
    }

    private static func parseResetDate(
        _ line: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.lowercased().hasPrefix("resets") else {
            return nil
        }
        value = String(value.dropFirst("Resets".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var timeZone = calendar.timeZone
        if value.hasSuffix(")"), let open = value.lastIndex(of: "(") {
            let identifier = String(value[value.index(after: open)..<value.index(before: value.endIndex)])
            if let detected = TimeZone(identifier: identifier) {
                timeZone = detected
                value = String(value[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if value.lowercased().hasPrefix("at ") {
            value = String(value.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var workingCalendar = calendar
        workingCalendar.timeZone = timeZone

        if value.range(of: #"^[0-9]{1,2}(?::[0-9]{2})?\s*(?:AM|PM|am|pm)?$"#, options: .regularExpression) != nil {
            guard let parsedTime = parse(
                value,
                formats: ["h:mm a", "h:mma", "ha", "h a", "HH:mm"],
                timeZone: timeZone
            ) else {
                return nil
            }
            let time = workingCalendar.dateComponents([.hour, .minute, .second], from: parsedTime)
            var components = workingCalendar.dateComponents([.year, .month, .day], from: referenceDate)
            components.hour = time.hour
            components.minute = time.minute
            components.second = time.second
            guard var result = workingCalendar.date(from: components) else {
                return nil
            }
            if result <= referenceDate {
                result = workingCalendar.date(byAdding: .day, value: 1, to: result) ?? result
            }
            return result
        }

        let year = workingCalendar.component(.year, from: referenceDate)
        let formats = [
            "MMM d 'at' h:mm a yyyy",
            "MMM d 'at' h:mma yyyy",
            "MMM d 'at' ha yyyy",
            "MMM d 'at' h a yyyy",
            "MMM d 'at' HH:mm yyyy",
        ]
        guard var result = parse("\(value) \(year)", formats: formats, timeZone: timeZone) else {
            return nil
        }
        if result <= referenceDate {
            result = workingCalendar.date(byAdding: .year, value: 1, to: result) ?? result
        }
        return result
    }

    private static func parse(
        _ value: String,
        formats: [String],
        timeZone: TimeZone
    ) -> Date? {
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}

private struct PendingPercentage {
    let usedPercent: Double
    let kind: ClaudeUsageWindowKind?
}

private struct WindowCandidate {
    let window: ClaudeUsageQuotaWindow
    let normalizedReset: String
}
