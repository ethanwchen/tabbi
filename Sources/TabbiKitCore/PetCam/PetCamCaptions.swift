import Foundation

/// The words a tape burns in, chosen once when its block resolves.
///
/// Content comes from the player's own history rather than a script: the
/// grammar (`PetCamData/captions.json`) holds a handful of templates, and
/// the room and the log fill them in ("MUG, LEFT OUT 3 DAYS AGO", "2ND MUG
/// THIS WEEK", "RIGHT NEXT TO THE PETALS FROM TUESDAY"), so the tapes keep
/// saying new things for as long as the room keeps changing.
public struct PetCamCaptionSet: Codable, Hashable, Sendable {
    /// Over the wide opening shot.
    public var opener: String
    /// Over the first spot-camera still: motion on a catch, quiet on a miss.
    public var watch: String
    /// The strike itself (catch) or the off-camera sound (miss).
    public var strike: String
    /// The struck object's age: the callback every tape has.
    public var age: String?
    /// A callback to earlier blocks, when the history has one.
    public var callback: String?
    /// After the strike: the pet notices the lens (catch) or strolls in (miss).
    public var turn: String
    /// The last word: "CAUGHT" or the alibi.
    public var closer: String
    /// The mugshot's charge: the dodge line, or what the pet did.
    public var charge: String?
    /// The mugshot's charge without the dodge line, for sharing.
    public var publicCharge: String?
    /// "PRIOR OFFENSES: 2" from the wall, or "FIRST OFFENSE".
    public var priors: String?

    public init(opener: String, watch: String, strike: String, age: String? = nil, callback: String? = nil,
                turn: String, closer: String, charge: String? = nil, publicCharge: String? = nil, priors: String? = nil) {
        self.opener = opener
        self.watch = watch
        self.strike = strike
        self.age = age
        self.callback = callback
        self.turn = turn
        self.closer = closer
        self.charge = charge
        self.publicCharge = publicCharge
        self.priors = priors
    }
}

/// The grammar file, as written.
struct PetCamCaptionGrammar: Decodable, Sendable {
    struct ObjectWords: Decodable, Sendable {
        let name, plural, sound, remains, charge: String
    }

    struct Callbacks: Decodable, Sendable {
        let leftOutDays, leftOutYesterday, leftOutHours, leftOutSince: String
        let repeatToday, repeatWeek, sameSpot, besideWreck, lastSeen: String
    }

    let schema: String
    let language: String
    let objects: [String: ObjectWords]
    let spots: [String: String]
    let opener, openerDays, motion, quiet, act, eaten, offCamera, noticed, innocent, returns: [String]
    let caught, charge, priors, firstOffense, frozen, noTape: String
    let callbacks: Callbacks
    let ordinals: [String]
    let ordinalMore: String

    static let schemaName = "petcam.captions.v1"

    func words(_ kind: PetCamObjectKind) -> ObjectWords {
        guard let words = objects[kind.rawValue] else { preconditionFailure("No caption words for \(kind)") }
        return words
    }

    func name(_ spot: PetCamSpot) -> String {
        guard let name = spots[spot.rawValue] else { preconditionFailure("No caption name for \(spot)") }
        return name
    }

    func ordinal(_ count: Int) -> String {
        count >= 1 && count <= ordinals.count ? ordinals[count - 1] : PetCamCaptions.fill(ordinalMore, ["count": "\(count)"])
    }
}

public enum PetCamCaptions {
    /// The shipped grammar. It is part of the app, so a broken file stops
    /// with the reason, like the pet art.
    static let grammar: PetCamCaptionGrammar = {
        guard let url = KitResources.bundle?.url(forResource: "captions", withExtension: "json",
                                                  subdirectory: PetCamData.subdirectory) else {
            preconditionFailure("Missing \(PetCamData.subdirectory)/captions.json")
        }
        do {
            let grammar = try JSONDecoder().decode(PetCamCaptionGrammar.self, from: Data(contentsOf: url))
            precondition(grammar.schema == PetCamCaptionGrammar.schemaName, "Unknown caption schema \(grammar.schema)")
            return grammar
        } catch {
            preconditionFailure("Invalid captions.json: \(error)")
        }
    }()

    /// The object's name as captions write it ("MUG").
    public static func name(of kind: PetCamObjectKind) -> String { grammar.words(kind).name }

    /// The spot's name as captions write it ("SIDE TABLE").
    public static func name(of spot: PetCamSpot) -> String { grammar.name(spot) }

    /// The sound a miss hears from off camera ("[SPLASH]").
    public static func sound(of kind: PetCamObjectKind) -> String { grammar.words(kind).sound }

    /// The frozen frame in words, for VoiceOver: where the pet stares and
    /// what (if anything) wobbles or smells good. English only for now.
    public static func describe(_ setup: PetCamSetup, room: PetCamRoom, petName: String) -> String {
        func thing(_ spot: PetCamSpot) -> String {
            let object = room.object(at: spot).map { grammar.words($0.kind).name.lowercased() } ?? "nothing"
            return "the \(object) on the \(grammar.name(spot).lowercased())"
        }
        var line = "\(petName) is staring at \(thing(setup.stare))."
        if let tell = setup.tell {
            let verb = tell.exception == .appetite ? "smells too good" : "is wobbling"
            line += " " + thing(tell.spot).prefix(1).uppercased() + thing(tell.spot).dropFirst() + " \(verb)."
        }
        return line
    }

    /// "OFF CAMERA", under the sound.
    public static var offCamera: String { grammar.offCamera.first ?? "" }

    /// The stamp over a catch's last still.
    public static var caughtStamp: String { grammar.caught }

    /// Replaces each `{key}` in `template`.
    static func fill(_ template: String, _ values: [String: String]) -> String {
        var text = template
        for (key, value) in values { text = text.replacingOccurrences(of: "{\(key)}", with: value) }
        return text
    }

    /// The most a dodge line may say in a caption; longer ones are cut at
    /// a word.
    public static let maximumDodgeLength = 40

    /// A dodge line as captions show it: trimmed, uppercased, one line,
    /// at most `maximumDodgeLength` characters; nil when empty.
    public static func cleanDodge(_ text: String?) -> String? {
        guard let text else { return nil }
        let line = text.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        var upper = line.uppercased()
        if upper.count > maximumDodgeLength {
            upper = String(upper.prefix(maximumDodgeLength))
            if let space = upper.lastIndex(of: " "), upper.distance(from: upper.startIndex, to: space) > 12 {
                upper = String(upper[..<space])
            }
        }
        return upper
    }

    /// 24-hour clock time, the way a camera burns it in ("14:02").
    static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// "TODAY AT 14:02", "YESTERDAY", or the weekday ("TUESDAY") within a
    /// week, else the date ("NOV 3").
    static func when(_ date: Date, from now: Date, calendar: Calendar) -> String {
        let days = calendarDays(from: date, to: now, calendar: calendar)
        if days <= 0 { return clock(date, calendar: calendar) }
        if days == 1 { return "YESTERDAY" }
        // Fixed English names: the grammar is English, and a camera's
        // burn-in does not follow the phone's locale.
        let parts = calendar.dateComponents([.weekday, .month, .day], from: date)
        if days < 7, let weekday = parts.weekday, (1...7).contains(weekday) { return weekdays[weekday - 1] }
        let month = months[max(0, min(11, (parts.month ?? 1) - 1))]
        return "\(month) \(parts.day ?? 1)"
    }

    private static let weekdays = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    static func calendarDays(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    /// How long `object` sat out before `date`: days, yesterday, hours, or
    /// the time it was left out.
    static func age(of object: PetCamObject, at date: Date, calendar: Calendar) -> String {
        let name = grammar.words(object.kind).name
        let days = calendarDays(from: object.placedAt, to: date, calendar: calendar)
        let lines = grammar.callbacks
        if days >= 2 { return fill(lines.leftOutDays, ["object": name, "days": "\(days)"]) }
        if days == 1 { return fill(lines.leftOutYesterday, ["object": name]) }
        let hours = Int(date.timeIntervalSince(object.placedAt) / 3600)
        if hours >= 2 { return fill(lines.leftOutHours, ["object": name, "hours": "\(hours)"]) }
        return fill(lines.leftOutSince, ["object": name, "time": clock(object.placedAt, calendar: calendar)])
    }

    /// The strongest callback to earlier blocks, or nil on a fresh history:
    /// a repeat of the same kind today or this week, a strike right beside
    /// an old wreck, the same spot as last time, or (on a miss) where the
    /// pet was last caught. Ties go to the seed.
    static func callback(strike: PetCamSpot, struck: PetCamObject, room: PetCamRoom, outcome: PetCamBlockRecord.Outcome,
                         history: [PetCamBlockRecord], at date: Date, seed: UInt64, calendar: Calendar) -> String? {
        let lines = grammar.callbacks
        // Only the last week matters to a callback, and the log is sorted,
        // so this stays cheap however long the history grows.
        var finished: [PetCamBlockRecord] = []
        for record in history.reversed() where record.endedAt <= date {
            if date.timeIntervalSince(record.endedAt) >= 7 * 86400 { break }
            if record.outcome.hasTape { finished.append(record) }
        }
        finished.reverse()
        let sameKind = finished.filter { $0.struck?.kind == struck.kind }
        let name = grammar.words(struck.kind).name
        var strong: [String] = []
        let midnight = calendar.startOfDay(for: date)
        let today = sameKind.filter { $0.endedAt >= midnight }
        let week = sameKind
        if !today.isEmpty {
            strong.append(fill(lines.repeatToday, ["ordinal": grammar.ordinal(today.count + 1), "object": name]))
        } else if !week.isEmpty {
            strong.append(fill(lines.repeatWeek, ["ordinal": grammar.ordinal(week.count + 1), "object": name]))
        }
        if let old = room.visibleWrecks(at: strike).last {
            strong.append(fill(lines.besideWreck, ["remains": grammar.words(old.object.kind).remains,
                                                   "when": when(old.wreckedAt, from: date, calendar: calendar)]))
        }
        if let last = finished.last, last.strike == strike {
            strong.append(fill(lines.sameSpot, ["spot": grammar.name(strike)]))
        }
        if outcome == .missed, let caught = finished.last(where: { $0.outcome == .caught }), let spot = caught.strike {
            strong.append(fill(lines.lastSeen, ["spot": grammar.name(spot),
                                                "when": when(caught.endedAt, from: date, calendar: calendar)]))
        }
        guard !strong.isEmpty else { return nil }
        var roll = PetCamRandom(seed: seed, stream: "callback")
        return strong[Int(roll.next() % UInt64(strong.count))]
    }

    /// One line from `choices`, picked by the seed's `stream` roll.
    static func one(_ choices: [String], seed: UInt64, stream: String, _ values: [String: String] = [:]) -> String {
        guard !choices.isEmpty else { return "" }
        var roll = PetCamRandom(seed: seed, stream: stream)
        return fill(choices[Int(roll.next() % UInt64(choices.count))], values)
    }

    /// Every caption of a block that ran to its end.
    static func tape(outcome: PetCamBlockRecord.Outcome, setup: PetCamSetup, camera: PetCamSpot, strike: PetCamSpot,
                     struck: PetCamObject, room: PetCamRoom, dodge: String?, history: [PetCamBlockRecord],
                     at date: Date, calendar: Calendar) -> PetCamCaptionSet {
        let seed = setup.seed
        let words = grammar.words(struck.kind)
        // Days since the first tape, counting today: day 1 is the first.
        let days = (history.first(where: \.outcome.hasTape)).map {
            calendarDays(from: $0.endedAt, to: date, calendar: calendar) + 1
        } ?? 1
        let opener = days >= 2
            ? one(grammar.openerDays, seed: seed, stream: "opener", ["days": "\(days)"])
            : one(grammar.opener, seed: seed, stream: "opener")
        let cam = "\(camera.cameraNumber)"
        let age = age(of: struck, at: date, calendar: calendar)
        let callback = callback(strike: strike, struck: struck, room: room, outcome: outcome, history: history,
                                at: date, seed: seed, calendar: calendar)
        let object = words.name
        if outcome == .caught {
            let action = fill(words.charge, ["spot": grammar.name(strike)])
            let priors = history.filter { $0.outcome == .caught && $0.endedAt <= date }.count
            return PetCamCaptionSet(
                opener: opener,
                watch: one(grammar.motion, seed: seed, stream: "watch", ["cam": cam]),
                strike: one(struck.kind.isEaten ? grammar.eaten : grammar.act, seed: seed, stream: "strike",
                            ["object": object]),
                age: age, callback: callback,
                turn: one(grammar.noticed, seed: seed, stream: "turn"),
                closer: grammar.caught,
                charge: fill(grammar.charge, ["charge": cleanDodge(dodge) ?? action]),
                publicCharge: fill(grammar.charge, ["charge": action]),
                priors: priors > 0 ? fill(grammar.priors, ["count": "\(priors)"]) : grammar.firstOffense
            )
        }
        return PetCamCaptionSet(
            opener: opener,
            watch: one(grammar.quiet, seed: seed, stream: "watch", ["cam": cam]),
            strike: words.sound,
            age: age, callback: callback,
            turn: one(grammar.returns, seed: seed, stream: "turn"),
            closer: one(grammar.innocent, seed: seed, stream: "closer")
        )
    }

    /// The single still of a block stopped early.
    static func frozen(setup: PetCamSetup, at date: Date, calendar: Calendar) -> PetCamCaptionSet {
        PetCamCaptionSet(opener: fill(grammar.frozen, ["time": clock(date, calendar: calendar)]), watch: "", strike: "",
                         turn: "", closer: grammar.noTape)
    }
}

/// Where the Pet Cam's data files live in the core's resource bundle.
enum PetCamData {
    static let subdirectory = "PetCamData"
}
