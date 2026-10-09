import Foundation

/// `study-methods.json`: every study method's default parameters and copy in
/// picker order, plus the limits of the Timer and Custom steppers.
///
/// The definitions are data so the Mac app and the Windows port offer the
/// same methods from one source; `shared/schemas/study-methods.v1.schema.json`
/// describes the format. The rules that run them (`StudyMethod.nextPhase`,
/// Flowtime breaks, stepping) stay in code, pinned for both apps by
/// `shared/fixtures/study-methods/study-methods.json`.
struct StudyMethodFile: Decodable, Sendable {
    enum LoadError: Error, Equatable, CustomStringConvertible {
        case unsupportedSchema(String)
        case duplicateMethod(StudyMethodKind)
        case missingMethod(StudyMethodKind)
        case invalidValue(path: String, reason: String)

        var description: String {
            switch self {
            case .unsupportedSchema(let schema): "Unsupported schema \"\(schema)\"; expected \"\(StudyMethodFile.schemaName)\""
            case .duplicateMethod(let kind): "Method \"\(kind.rawValue)\" is defined twice"
            case .missingMethod(let kind): "methods: no method \"\(kind.rawValue)\""
            case let .invalidValue(path, reason): "\(path): \(reason)"
            }
        }
    }

    static let schemaName = "study-methods.v1"

    /// A length in minutes.
    struct Minutes: Decodable, Sendable {
        let minutes: Double
        var seconds: TimeInterval { minutes * 60 }
    }

    struct Range: Decodable, Sendable {
        let min: Double
        let max: Double
    }

    struct Stepper: Decodable, Sendable {
        let min: Int
        let max: Int
        let step: Int
    }

    struct AnkiSprint: Decodable, Sendable {
        let breakAfterCards: Int
        let breakAfterMinutes: Double
    }

    struct Timer: Decodable, Sendable {
        let minMinutes: Int
        let maxMinutes: Int
        let presetMinutes: [Int]
    }

    struct LongBreak: Decodable, Sendable {
        let minutes: Double
        let every: Int
    }

    struct Custom: Decodable, Sendable {
        let longBreak: LongBreak
        let fields: [String: Stepper]
    }

    /// `"openEnded"`, `{"minutes": n}` or `{"cards": n}`.
    enum Focus: Decodable, Sendable {
        case minutes(Double)
        case openEnded
        case cards(Int)

        private enum CodingKeys: String, CodingKey { case minutes, cards }

        init(from decoder: Decoder) throws {
            if let word = try? decoder.singleValueContainer().decode(String.self) {
                guard word == "openEnded" else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown focus \"\(word)\""))
                }
                self = .openEnded
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let cards = try container.decodeIfPresent(Int.self, forKey: .cards) {
                self = .cards(cards)
            } else {
                self = .minutes(try container.decode(Double.self, forKey: .minutes))
            }
        }
    }

    /// `"none"`, `{"minutes": n}` or `{"flowtime": scheme}`.
    enum Break: Decodable, Sendable {
        case minutes(Double)
        case flowtime(FlowtimeBreakScheme)
        case none

        private enum CodingKeys: String, CodingKey { case minutes, flowtime }

        init(from decoder: Decoder) throws {
            if let word = try? decoder.singleValueContainer().decode(String.self) {
                guard word == "none" else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown break \"\(word)\""))
                }
                self = .none
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let scheme = try container.decodeIfPresent(FlowtimeBreakScheme.self, forKey: .flowtime) {
                self = .flowtime(scheme)
            } else {
                self = .minutes(try container.decode(Double.self, forKey: .minutes))
            }
        }
    }

    /// One method: its default parameters and its info copy.
    struct Method: Decodable, Sendable {
        let kind: StudyMethodKind
        let focus: Focus
        let `break`: Break
        let longBreak: LongBreak?
        let review: Minutes?
        let questionCount: Int?
        let name: String
        let tagline: String
        let howTo: String
        let evidence: String
        let evidenceLevel: StudyEvidenceLevel?

        var method: StudyMethod {
            let focus: StudyFocusTarget = switch self.focus {
            case .minutes(let minutes): .duration(minutes * 60)
            case .openEnded: .openEnded
            case .cards(let cards): .cards(cards)
            }
            let breakRule: StudyBreakRule = switch self.break {
            case .minutes(let minutes): .fixed(minutes * 60)
            case .flowtime(let scheme): .proportional(scheme)
            case .none: .none
            }
            return StudyMethod(
                kind: kind, focus: focus, breakRule: breakRule,
                longBreak: longBreak.map { StudyLongBreak(duration: $0.minutes * 60, every: $0.every) },
                review: review?.seconds, questionCount: questionCount
            )
        }

        var info: StudyMethodInfo {
            StudyMethodInfo(kind: kind, name: name, tagline: tagline, howTo: howTo, evidence: evidence, evidenceLevel: evidenceLevel)
        }
    }

    let schema: String
    let phaseMinutes: Range
    let footnote: String
    let evidenceLevels: [StudyEvidenceLevel: String]
    let ankiSprint: AnkiSprint
    let timer: Timer
    let custom: Custom
    let methods: [Method]

    private enum CodingKeys: String, CodingKey {
        case schema, phaseMinutes, footnote, evidenceLevels, ankiSprint, timer, custom, methods
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        phaseMinutes = try container.decode(Range.self, forKey: .phaseMinutes)
        footnote = try container.decode(String.self, forKey: .footnote)
        // A [String: _] keyed by an enum decodes as an array, so read the
        // object's string keys and map them.
        var levels: [StudyEvidenceLevel: String] = [:]
        for (key, label) in try container.decode([String: String].self, forKey: .evidenceLevels) {
            guard let level = StudyEvidenceLevel(rawValue: key) else {
                throw LoadError.invalidValue(path: "evidenceLevels.\(key)", reason: "no evidence level \"\(key)\"")
            }
            levels[level] = label
        }
        evidenceLevels = levels
        ankiSprint = try container.decode(AnkiSprint.self, forKey: .ankiSprint)
        timer = try container.decode(Timer.self, forKey: .timer)
        custom = try container.decode(Custom.self, forKey: .custom)
        methods = try container.decode([Method].self, forKey: .methods)
    }

    /// Reads the bundled file. It ships inside the app, so a missing or
    /// broken file is a build mistake: this stops with the reason instead of
    /// running timers on made-up lengths.
    static func load() -> StudyMethodFile {
        guard let url = KitResources.bundle?.url(forResource: "study-methods", withExtension: "json") else {
            preconditionFailure("Missing study-methods.json")
        }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            preconditionFailure("Invalid study-methods.json: \(error)")
        }
    }

    /// Parses and checks a file: its schema version, one method per kind,
    /// positive lengths and counts, a label per evidence level, and stepper
    /// ranges that hold their defaults.
    static func decode(_ data: Data) throws -> StudyMethodFile {
        let file = try JSONDecoder().decode(StudyMethodFile.self, from: data)
        guard file.schema == schemaName else { throw LoadError.unsupportedSchema(file.schema) }
        func require(_ condition: Bool, _ path: String, _ reason: String) throws {
            if !condition { throw LoadError.invalidValue(path: path, reason: reason) }
        }
        try require(file.phaseMinutes.min > 0 && file.phaseMinutes.min < file.phaseMinutes.max,
                    "phaseMinutes", "min must be above 0 and below max")
        for level in StudyEvidenceLevel.allCases {
            try require(file.evidenceLevels[level] != nil, "evidenceLevels", "no label for \"\(level.rawValue)\"")
        }
        try require(file.ankiSprint.breakAfterCards > 0, "ankiSprint.breakAfterCards", "must be above 0")
        try require(file.ankiSprint.breakAfterMinutes > 0, "ankiSprint.breakAfterMinutes", "must be above 0")
        let timer = file.timer
        try require(timer.minMinutes > 0 && timer.minMinutes <= timer.maxMinutes, "timer", "minMinutes must be 1...maxMinutes")
        for (index, minutes) in timer.presetMinutes.enumerated() {
            try require((timer.minMinutes...timer.maxMinutes).contains(minutes), "timer.presetMinutes[\(index)]", "outside the timer range")
        }
        for field in StudyCustomRhythm.Field.allCases {
            guard let stepper = file.custom.fields[field.rawValue] else {
                throw LoadError.invalidValue(path: "custom.fields", reason: "no field \"\(field.rawValue)\"")
            }
            try require(stepper.min > 0 && stepper.min <= stepper.max && stepper.step > 0,
                        "custom.fields.\(field.rawValue)", "needs 0 < min <= max and a positive step")
        }

        var seen = Set<StudyMethodKind>()
        for (index, entry) in file.methods.enumerated() {
            let path = "methods[\(index)]"
            guard seen.insert(entry.kind).inserted else { throw LoadError.duplicateMethod(entry.kind) }
            for (name, minutes) in [("focus", entry.focus.minutes), ("break", entry.break.minutes),
                                    ("longBreak", entry.longBreak?.minutes), ("review", entry.review?.minutes)] {
                guard let minutes else { continue }
                try require(minutes >= file.phaseMinutes.min && minutes <= file.phaseMinutes.max,
                            "\(path).\(name).minutes", "outside phaseMinutes")
            }
            if case .cards(let cards) = entry.focus { try require(cards > 0, "\(path).focus.cards", "must be above 0") }
            if let every = entry.longBreak?.every { try require(every >= 2, "\(path).longBreak.every", "must be 2 or more") }
            if let count = entry.questionCount { try require(count > 0, "\(path).questionCount", "must be above 0") }
        }
        for kind in StudyMethodKind.allCases where !seen.contains(kind) {
            throw LoadError.missingMethod(kind)
        }
        try file.checkDefaults()
        return file
    }

    /// The Timer and Custom methods start the steppers, so their lengths
    /// must be values the steppers can show.
    private func checkDefaults() throws {
        guard let timerEntry = methods.first(where: { $0.kind == .timer }),
              case .minutes(let timerMinutes) = timerEntry.focus, case .none = timerEntry.break,
              timerMinutes == timerMinutes.rounded(), (timer.minMinutes...timer.maxMinutes).contains(Int(timerMinutes)) else {
            throw LoadError.invalidValue(path: "methods.timer", reason: "needs whole focus minutes in the timer range and break \"none\"")
        }
        guard let customEntry = methods.first(where: { $0.kind == .custom }),
              case .minutes(let focus) = customEntry.focus, case .minutes(let pause) = customEntry.break,
              customEntry.longBreak == nil, customEntry.review == nil, customEntry.questionCount == nil,
              fits(focus, "focus"), fits(pause, "shortBreak"),
              fits(custom.longBreak.minutes, "longBreak"), fits(Double(custom.longBreak.every), "longBreakEvery") else {
            throw LoadError.invalidValue(path: "methods.custom", reason: "needs focus and break minutes inside custom.fields, and no long break, review or questions")
        }
    }

    private func fits(_ value: Double, _ field: String) -> Bool {
        guard let stepper = custom.fields[field], value == value.rounded() else { return false }
        return (stepper.min...stepper.max).contains(Int(value))
    }
}

private extension StudyMethodFile.Focus {
    var minutes: Double? {
        if case .minutes(let minutes) = self { return minutes }
        return nil
    }
}

private extension StudyMethodFile.Break {
    var minutes: Double? {
        if case .minutes(let minutes) = self { return minutes }
        return nil
    }
}

/// The bundled definitions, read once. `StudyMethod`, `StudyMethodInfo`,
/// `StudyTimerLength` and `StudyCustomRhythm` take their defaults from here.
enum StudyMethodDefinitions {
    static let file = StudyMethodFile.load()
}
