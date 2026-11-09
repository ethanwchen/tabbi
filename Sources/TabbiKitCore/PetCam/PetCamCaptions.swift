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
    /// The struck object's age. "LEFT OUT SINCE 14:02", the form every
    /// object placed within the last two hours gets, runs at most one tape
    /// in three, so this is often nil.
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
    /// The lines only some tape shapes use: a cold open on the aftermath,
    /// the rewind, the push-in, the double take, a cold open on the alibi,
    /// and the miss's last look at what really happened.
    public var aftermath, rewind, enhance, reaction, alibi, reveal: String?
    /// When the visible exception decided the strike, the line that says so
    /// ("IT WAS ALREADY WOBBLING."), which teaches the read after a miss.
    public var tell: String?
    /// The beat before the act when there is no age line ("WAIT FOR IT.").
    public var windUp: String?
    /// On a catch with the WANTED object, how long it was wanted
    /// ("WANTED FOR 3 DAYS.").
    public var wanted: String?
    /// A miss's line under the off-camera sound ("SOMEWHERE ELSE").
    public var offCamera: String?
    /// The walk-by miss: the suspect strolls past the camera wearing the
    /// evidence ("JUST PASSING THROUGH."), then stops and denies it
    /// ("CIRCUMSTANTIAL.").
    public var walkBy, denial: String?

    public init(opener: String, watch: String, strike: String, age: String? = nil, callback: String? = nil,
                turn: String, closer: String, charge: String? = nil, publicCharge: String? = nil, priors: String? = nil,
                aftermath: String? = nil, rewind: String? = nil, enhance: String? = nil, reaction: String? = nil,
                alibi: String? = nil, reveal: String? = nil, tell: String? = nil, windUp: String? = nil,
                wanted: String? = nil, offCamera: String? = nil, walkBy: String? = nil, denial: String? = nil) {
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
        self.aftermath = aftermath
        self.rewind = rewind
        self.enhance = enhance
        self.reaction = reaction
        self.alibi = alibi
        self.reveal = reveal
        self.tell = tell
        self.windUp = windUp
        self.wanted = wanted
        self.offCamera = offCamera
        self.walkBy = walkBy
        self.denial = denial
    }
}

/// The grammar file, as written.
struct PetCamCaptionGrammar: Decodable, Sendable {
    struct ObjectWords: Decodable, Sendable {
        let name, plural, sound, remains, charge: String
    }

    struct Callbacks: Decodable, Sendable {
        let leftOutDays, leftOutYesterday: String
        let lastedMinutes, lastedMinute, lastedHours, lastedHour: String
        let repeatToday, repeatWeek, sameSpot, besideWreck, lastSeen: String
    }

    let schema: String
    let language: String
    let objects: [String: ObjectWords]
    let spots: [String: String]
    let opener, openerDays, motion, quiet, act, eaten, offCamera, noticed, innocent, returns: [String]
    let aftermath, rewind, enhance, alibiOpen, windUp, meanwhile, walkBy, denial: [String]
    let caught, charge, obstruction, firstOffense, offense, repeatOffender, frozen, noTape, ownerAway, atLarge: String
    let stamps: [String]
    let wantedDays, wantedYesterday, wantedSince: String
    let tells: [String: String]
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

    /// The spot a line names ("THE COUNTER AGAIN"), if it names one, so a
    /// callback rides only on a still filmed there or on CAM 1.
    public static func spotNamed(in line: String) -> PetCamSpot? {
        PetCamSpot.allCases.first { line.contains("THE " + grammar.name($0)) }
    }

    /// The stamp over a catch's last still.
    public static var caughtStamp: String { grammar.caught }

    /// The stamp for a catch at rap-sheet `tier` (1 to 3): CAUGHT, CAUGHT
    /// AGAIN, HABITUAL.
    public static func stamp(tier: Int) -> String {
        grammar.stamps[min(max(tier, 1), grammar.stamps.count) - 1]
    }

    /// The line under a charge for a catch that is the pet's `offense`th
    /// with that object: FIRST OFFENSE, 2ND OFFENSE, 3RD OFFENSE, then
    /// REPEAT OFFENDER.
    public static func rapSheet(_ offense: Int) -> String {
        if offense <= 1 { return grammar.firstOffense }
        if offense >= 4 { return grammar.repeatOffender }
        return fill(grammar.offense, ["ordinal": grammar.ordinal(offense)])
    }

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
            // A cut line never ends on a word that needs the next one
            // ("PRACTICE PROBLEMS FOR"), nor on a comma.
            var words = upper.split(separator: " ").map(String.init)
            while words.count > 2, let last = words.last,
                  danglingWords.contains(last.trimmingCharacters(in: .punctuationCharacters)) || last.hasSuffix(",") {
                words.removeLast()
            }
            upper = words.joined(separator: " ")
        }
        return upper
    }

    /// Words a shortened dodge never ends on.
    static let danglingWords: Set<String> = [
        "A", "AN", "THE", "MY", "OUR", "YOUR", "HIS", "HER", "THEIR", "ITS", "OF", "FOR", "TO", "AND", "OR",
        "BUT", "BEFORE", "AFTER", "WITH", "IN", "ON", "AT", "BY", "FROM", "INTO", "ABOUT", "THAT", "THIS",
        "SO", "IF", "UNTIL", "WHILE", "AS", "&",
    ]

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

    /// How long `object` sat out before `date`: from another day, when it
    /// was left out ("LEFT OUT 3 DAYS AGO"); the same day, said from the
    /// pet's side as how long it lasted ("THE VASE LASTED 2 MINUTES.").
    static func age(of object: PetCamObject, at date: Date, calendar: Calendar) -> String {
        let name = grammar.words(object.kind).name
        let days = calendarDays(from: object.placedAt, to: date, calendar: calendar)
        let lines = grammar.callbacks
        if days >= 2 { return fill(lines.leftOutDays, ["object": name, "days": "\(days)"]) }
        if days == 1 { return fill(lines.leftOutYesterday, ["object": name]) }
        let minutes = max(Int(date.timeIntervalSince(object.placedAt) / 60), 1)
        if minutes < 60 {
            return minutes == 1 ? fill(lines.lastedMinute, ["object": name])
                : fill(lines.lastedMinutes, ["object": name, "minutes": "\(minutes)"])
        }
        let hours = minutes / 60
        return hours == 1 ? fill(lines.lastedHour, ["object": name])
            : fill(lines.lastedHours, ["object": name, "hours": "\(hours)"])
    }

    /// Whether an age line is a same-day "LASTED" line, which (like any
    /// line) runs at most once in four tapes.
    static func isLastedForm(_ age: String?) -> Bool {
        guard let age else { return false }
        let lines = grammar.callbacks
        return [lines.lastedMinutes, lines.lastedMinute, lines.lastedHours, lines.lastedHour]
            .contains { matches(age, template: $0) }
    }

    /// The strongest callback to earlier blocks, or nil on a fresh history.
    /// A repeat of the same kind today, the same spot as last time, and (on
    /// a miss) where the pet was last caught come first; a repeat this week
    /// or a strike right beside an old wreck only when none of those is
    /// true, and the wreck only when `camera` can see it. Ties go to the
    /// seed.
    static func callback(strike: PetCamSpot, struck: PetCamObject, room: PetCamRoom, camera: PetCamSpot,
                         outcome: PetCamBlockRecord.Outcome, history: [PetCamBlockRecord], at date: Date, seed: UInt64,
                         calendar: Calendar) -> String? {
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
        var weak: [String] = []
        let midnight = calendar.startOfDay(for: date)
        let today = sameKind.filter { $0.endedAt >= midnight }
        if !today.isEmpty {
            strong.append(fill(lines.repeatToday, ["ordinal": grammar.ordinal(today.count + 1), "object": name]))
        } else if !sameKind.isEmpty {
            weak.append(fill(lines.repeatWeek, ["ordinal": grammar.ordinal(sameKind.count + 1), "object": name]))
        }
        if let last = finished.last, last.strike == strike {
            strong.append(fill(lines.sameSpot, ["spot": grammar.name(strike)]))
        }
        if outcome == .missed, let caught = finished.last(where: { $0.outcome == .caught }), let spot = caught.strike {
            strong.append(fill(lines.lastSeen, ["spot": grammar.name(spot),
                                                "when": when(caught.endedAt, from: date, calendar: calendar)]))
        }
        if let old = room.visibleWrecks(at: strike).last, PetCamScene.shows(old, in: .spot(camera)) {
            weak.append(fill(lines.besideWreck, ["remains": grammar.words(old.object.kind).remains,
                                                 "when": when(old.wreckedAt, from: date, calendar: calendar)]))
        }
        let tier = strong.isEmpty ? weak : strong
        guard !tier.isEmpty else { return nil }
        var roll = PetCamRandom(seed: seed, stream: "callback")
        return tier[Int(roll.next() % UInt64(tier.count))]
    }

    /// Whether `text` was filled in from `template`: every fixed part of the
    /// template is in it, in order.
    static func matches(_ text: String, template: String) -> Bool {
        var parts: [String] = []
        for (index, piece) in template.split(separator: "{", omittingEmptySubsequences: false).enumerated() {
            if index == 0 {
                parts.append(String(piece))
            } else if let close = piece.firstIndex(of: "}") {
                parts.append(String(piece[piece.index(after: close)...]))
            }
        }
        var rest = Substring(text)
        for part in parts where !part.isEmpty {
            guard let range = rest.range(of: part) else { return false }
            rest = rest[range.upperBound...]
        }
        return true
    }

    /// How long the WANTED object was wanted when the pet was caught with
    /// it at `date`.
    static func wanted(since: Date, at date: Date, calendar: Calendar) -> String {
        let days = calendarDays(from: since, to: date, calendar: calendar)
        if days >= 2 { return fill(grammar.wantedDays, ["days": "\(days)"]) }
        if days == 1 { return grammar.wantedYesterday }
        return fill(grammar.wantedSince, ["time": clock(since, calendar: calendar)])
    }

    /// A charge as the wall files it: the phrase without its "CHARGE:"
    /// label, the player's own words kept together (`keepingDodgeTogether`).
    public static func filedCharge(_ caption: String) -> String {
        let label = fill(grammar.charge, ["charge": ""])
        return keepingDodgeTogether(caption.hasPrefix(label) ? String(caption.dropFirst(label.count)) : caption)
    }

    /// A charge with the player's own words (after "OBSTRUCTION OF") on one
    /// line when they are short, so it wraps before them and MY TAX never
    /// splits from RETURN; any other text as it is.
    public static func keepingDodgeTogether(_ text: String) -> String {
        let lead = fill(grammar.obstruction, ["dodge": ""])
        guard let range = text.range(of: lead) else { return text }
        let dodge = text[range.upperBound...]
        guard dodge.count <= 22 else { return text }
        return String(text[..<range.upperBound]) + dodge.replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// A still's caption and the smaller line under it as one sentence for
    /// VoiceOver: joined with a space after closing punctuation, or with a
    /// period, never ".," as a plain join would make.
    public static func spoken(_ caption: String, _ detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return caption }
        guard let last = caption.last else { return detail }
        return caption + (".!?:".contains(last) ? " " : ". ") + detail
    }

    /// The label the wall prints over a charge ("CHARGE").
    public static var chargeLabel: String {
        fill(grammar.charge, ["charge": ""]).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
    }

    /// "OWNER AWAY 25:00" for a block that ran `seconds` of focus.
    public static func ownerAway(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let length = total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
        return fill(grammar.ownerAway, ["length": length])
    }

    /// The share clip's burn-in, on every frame so the brand and the brag
    /// survive a crop or a screen recording: "TABBI CAM 4  OWNER AWAY 25:00".
    public static func clipHUD(camera: String, worked: TimeInterval) -> String {
        "TABBI \(camera)  \(ownerAway(worked))"
    }

    /// A case in one line: a catch's charge (the player's words only when
    /// `includeDodge`), or a miss filed as at large, as in "OBSTRUCTION OF MY
    /// TAX RETURN. SUSPECT AT LARGE." Nil for a block without a tape.
    public static func caseLine(_ record: PetCamBlockRecord, includeDodge: Bool) -> String? {
        guard record.outcome.hasTape, let strike = record.strike, let kind = record.struck?.kind else { return nil }
        if record.outcome == .caught {
            return (includeDodge ? record.captions.charge : record.captions.publicCharge) ?? record.captions.charge
        }
        let action = fill(grammar.words(kind).charge, ["spot": grammar.name(strike)])
        let charge = (includeDodge ? cleanDodge(record.dodge) : nil).map { fill(grammar.obstruction, ["dodge": $0]) }
            ?? action
        return fill(grammar.atLarge, ["charge": charge])
    }

    /// One line from `choices`, picked by the seed's `stream` roll, leaving
    /// out any line already said in `recent` (the same beat of the last
    /// three tapes that used it) while another is left.
    static func one(_ choices: [String], seed: UInt64, stream: String, _ values: [String: String] = [:],
                    recent: [String?] = []) -> String {
        guard !choices.isEmpty else { return "" }
        let said = recent.compactMap { $0 }
        let fresh = choices.filter { template in !said.contains { matches($0, template: template) } }
        let pool = fresh.isEmpty ? choices : fresh
        var roll = PetCamRandom(seed: seed, stream: stream)
        return fill(pool[Int(roll.next() % UInt64(pool.count))], values)
    }

    /// How many earlier tapes that use a beat a line stays out of it for.
    static let freshness = 3

    /// Every caption of a block that ran to its end.
    static func tape(outcome: PetCamBlockRecord.Outcome, setup: PetCamSetup, camera: PetCamSpot, strike: PetCamSpot,
                     struck: PetCamObject, room: PetCamRoom, dodge: String?, history: [PetCamBlockRecord],
                     offense: Int, at date: Date, calendar: Calendar) -> PetCamCaptionSet {
        let seed = setup.seed
        let words = grammar.words(struck.kind)
        // The last few tapes, newest first, for the age line's own rule.
        var recent: [PetCamCaptionSet] = []
        for record in history.reversed() where record.outcome.hasTape && record.endedAt <= date {
            recent.append(record.captions)
            if recent.count == freshness { break }
        }
        // No line comes back to its beat until three more tapes that use the
        // beat have played: every tape opens and rewinds, but only a miss
        // has an alibi, so a miss's lines count misses only.
        func line(_ choices: [String], _ stream: String, _ beat: (PetCamCaptionSet) -> String?,
                  _ values: [String: String] = [:], everyTape: Bool = false) -> String {
            var said: [String] = []
            for record in history.reversed() where record.outcome.hasTape && record.endedAt <= date
                && (everyTape || record.outcome == outcome) {
                guard let text = beat(record.captions) else { continue }
                said.append(text)
                if said.count == freshness { break }
            }
            return one(choices, seed: seed, stream: stream, values, recent: said)
        }
        // Days since the first tape, counting today: day 1 is the first.
        let days = (history.first(where: \.outcome.hasTape)).map {
            calendarDays(from: $0.endedAt, to: date, calendar: calendar) + 1
        } ?? 1
        let opener = days >= 2
            ? line(grammar.openerDays, "opener", \.opener, ["days": "\(days)"], everyTape: true)
            : line(grammar.opener, "opener", \.opener, everyTape: true)
        let cam = "\(camera.cameraNumber)"
        let lasted = age(of: struck, at: date, calendar: calendar)
        let age = isLastedForm(lasted) && recent.contains(where: { isLastedForm($0.age) }) ? nil : lasted
        let shapeLines = (
            aftermath: line(grammar.aftermath, "aftermath", \.aftermath, ["cam": cam]),
            rewind: line(grammar.rewind, "rewind", \.rewind, everyTape: true),
            enhance: line(grammar.enhance, "enhance", \.enhance),
            alibi: line(grammar.alibiOpen, "alibi", \.alibi, ["cam": cam]),
            reveal: line(grammar.meanwhile, "reveal", \.reveal, ["spot": grammar.name(strike), "remains": words.remains]),
            tell: setup.tell.flatMap { $0.spot == strike ? grammar.tells[$0.exception.rawValue] : nil }
        )
        let callback = callback(strike: strike, struck: struck, room: room, camera: camera, outcome: outcome,
                                history: history, at: date, seed: seed, calendar: calendar)
        let windUp = line(grammar.windUp, "windUp", \.windUp)
        let object = words.name
        if outcome == .caught {
            let action = fill(words.charge, ["spot": grammar.name(strike)])
            let wanted = setup.wanted == strike
                ? Self.wanted(since: PetCamSetup.wantedSince(struck.kind, history: history, before: date) ?? date,
                              at: date, calendar: calendar)
                : nil
            return PetCamCaptionSet(
                opener: opener,
                watch: line(grammar.motion, "watch", \.watch, ["cam": cam]),
                strike: line(struck.kind.isEaten ? grammar.eaten : grammar.act, "strike", \.strike, ["object": object]),
                age: age, callback: callback,
                turn: line(grammar.noticed, "turn", \.turn),
                closer: stamp(tier: PetCamBlockRecord.tier(offense)),
                charge: fill(grammar.charge, ["charge": cleanDodge(dodge).map { fill(grammar.obstruction, ["dodge": $0]) }
                    ?? action]),
                publicCharge: fill(grammar.charge, ["charge": action]),
                priors: rapSheet(offense),
                aftermath: shapeLines.aftermath, rewind: shapeLines.rewind, enhance: shapeLines.enhance,
                tell: shapeLines.tell, windUp: windUp, wanted: wanted
            )
        }
        return PetCamCaptionSet(
            opener: opener,
            watch: line(grammar.quiet, "watch", \.watch, ["cam": cam]),
            strike: words.sound,
            age: age, callback: callback,
            turn: line(grammar.returns, "turn", \.turn),
            closer: line(grammar.innocent, "closer", \.closer),
            rewind: shapeLines.rewind, enhance: shapeLines.enhance,
            alibi: shapeLines.alibi, reveal: shapeLines.reveal, tell: shapeLines.tell,
            offCamera: line(grammar.offCamera, "offCamera", \.offCamera),
            walkBy: line(grammar.walkBy, "walkBy", \.walkBy), denial: line(grammar.denial, "denial", \.denial)
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
