import Foundation

/// The Crews screens and states, so demo snapshots can show each one
/// (`TABBI_CREWS_PREVIEW=<raw value>`), as the Crews UI spec lists them.
public enum CrewDemoScenario: String, CaseIterable, Sendable {
    /// This week: the top 3 and the rest, my crew pinned at 12th.
    case week
    /// This week with my crew 2nd, in the top 3.
    case podium
    /// This week with two crews tied.
    case tie
    /// A quiet start to the week: no minutes yet.
    case quietWeek
    /// The board still loading.
    case loading
    /// The Hall of Fame, my crew pinned without medals.
    case hall
    /// My crew, which I own.
    case mine
    /// My crew with people asking to join.
    case requests
    /// Not in a crew yet.
    case noCrew
    /// Not in a crew, waiting for an owner to let me in.
    case requested
    /// Find with public crews.
    case find
    /// Find with nothing matching.
    case findEmpty
    /// Another crew's page.
    case crew
    /// The crest editor, making a new crew.
    case create
    /// The crest editor, the owner editing.
    case edit
    /// The party server can't be reached.
    case offline
    /// A crew invite link waiting to be confirmed.
    case invite
}

extension CrewsState {
    /// Sample crews for `TABBI_DEMO=1` and snapshots, built relative to `now`
    /// so the countdown reads sensibly.
    public static func demo(_ scenario: CrewDemoScenario, now: Date) -> CrewsState {
        let week = CrewWeek.containing(now)
        let data = CrewDemoData(now: now, week: week)
        var state = CrewsState(section: .week, week: week, mine: data.mine(), mineLoaded: true, board: data.board(),
                               hall: data.hall(), results: data.publicCrews)
        switch scenario {
        case .week: break
        case .podium:
            state.mine = data.mine(minutes: 2_940)
            state.board = data.board(myPlace: 2)
        case .tie:
            state.board = data.board(tie: true)
        case .quietWeek:
            state.board = CrewBoard(week: week, top: [], featured: data.featured(), crewCount: 0,
                                    mine: CrewStanding(rank: nil, minutes: 0))
        case .loading:
            state.board = nil
        case .hall:
            state.section = .hall
        case .mine:
            state.section = .mine
        case .requests:
            state.section = .mine
            state.mine = data.mine(requests: true)
        case .noCrew:
            state.section = .mine
            state.mine = nil
        case .requested:
            state.section = .mine
            state.mine = nil
            state.myRequest = CrewMyRequest(crew: data.crews[1], requestedAt: now.addingTimeInterval(-3600),
                                            expiresAt: now.addingTimeInterval(6 * 86_400))
        case .find:
            state.section = .find
        case .findEmpty:
            state.section = .find
            state.query = "zebra"
            state.results = []
        case .crew:
            state.pushed = .crew(data.detail(of: 0), from: .week)
        case .create:
            state.section = .find
            state.pushed = .editor(editing: false, from: .find)
        case .edit:
            state.section = .mine
            state.pushed = .editor(editing: true, from: .mine)
        case .offline:
            state.board = nil
            state.loadError = .unreachable
        case .invite:
            state.mine = nil
            state.section = .mine
            state.invite = "LQFJ7RM"
        }
        return state
    }
}

/// The demo crews and people.
public struct CrewDemoData: Sendable {
    let now: Date
    let week: CrewWeek

    /// How many crews have minutes this week in the demo.
    static let crewCount = 38
    static let myID = "PQMQDQRQ2S"

    static func pet(_ profile: PetProfile) -> CrewPet {
        let update = PartyPetAppearance.update(for: profile)
        return CrewPet(petName: update.petName ?? profile.name, species: update.species ?? "cat",
                       breed: update.breed ?? "tabby", colors: update.colors ?? [], costume: update.costume ?? "none",
                       accessories: update.accessories ?? [])
    }

    /// A little pool of pets the demo crews draw their members from.
    static let pets: [(String, CrewPet)] = [
        ("Maya", pet(PetProfile(name: "Biscuit", breed: .goldenRetriever, accessories: [.roundGlasses]))),
        ("Priya", pet(PetProfile(name: "Luna", breed: .siamese, outfit: .scrubs))),
        ("Leo", pet(PetProfile(name: "Waffles", breed: .corgi, outfit: .cozyHoodie, accessories: [.frogHat]))),
        ("Noor", pet(PetProfile(name: "Pip", breed: .scottishFold, accessories: [.chunkyHeadphones]))),
        ("Kai", pet(PetProfile(name: "Pepper", breed: .blackCat, accessories: [.wizardHat]))),
        ("Ava", pet(PetProfile(name: "Clover", breed: .beagle, accessories: [.flowerCrown]))),
        ("Omar", pet(PetProfile(name: "Nori", breed: .tuxedo))),
        ("Lena", pet(PetProfile(name: "Pudding", breed: .britishShorthair))),
        ("Ahmed", pet(PetProfile(name: "Taco", breed: .grayTabby))),
        ("Emma", pet(PetProfile(name: "Maple", breed: .dachshund, outfit: .scrubs))),
        ("Jonah", pet(PetProfile(name: "Bean", breed: .calico))),
        ("Sofia", pet(PetProfile(name: "Mocha", breed: .frenchBulldog))),
    ]

    /// The crews, most minutes first; mine is the eighth (12th on the board).
    public let crews: [CrewSummary]

    init(now: Date, week: CrewWeek) {
        self.now = now
        self.week = week
        func crew(_ id: String, _ name: String, _ frame: String, _ emblem: String, _ color: String, _ visibility: CrewVisibility,
                  members: Int, minutes: Int, golds: Int, trophies: Int, laurel: CrewLaurel? = nil, description: String = "") -> CrewSummary {
            CrewSummary(id: id, name: name, description: description, frame: CrewCatalog.frame(frame),
                        emblem: Self.demoEmblem(emblem, crew: id), color: CrewCatalog.color(color).id, visibility: visibility,
                        laurel: laurel, trophies: trophies, memberCount: members, weekMinutes: minutes, golds: golds)
        }
        crews = [
            crew("NGHTQWLS2K", "Night Owls", "shield", "owl", "indigo", .public, members: 18, minutes: 3_138, golds: 3, trophies: 4,
                 laurel: .gold, description: "Late study sessions, quiet focus."),
            crew("MEDSQUAD2K", "Med School Grind", "heater", "books", "coral", .public, members: 20, minutes: 2_868, golds: 3,
                 trophies: 5, laurel: .silver, description: "Anki every morning."),
            crew("BJBLRATTEN", "Bibliotheksratten", "seal", "cat", "amber", .public, members: 15, minutes: 2_646, golds: 1,
                 trophies: 3, laurel: .bronze),
            crew("LATENJGHT2", "Late Night Legends", "star", "moon", "violet", .public, members: 11, minutes: 2_376, golds: 0, trophies: 2),
            crew("DEEPWQRKDQ", "Deep Work Dojo", "hexagon", "headphones", "teal", .public, members: 9, minutes: 2_310, golds: 1,
                 trophies: 2),
            crew("QUJETHQURS", "Quiet Hours", "pennant", "lamp", "sky", .private, members: 12, minutes: 2_160, golds: 0, trophies: 1),
            crew("RAJNYDAYRD", "Rainy Day Readers", "seal", "cloud", "mint", .public, members: 7, minutes: 1_890, golds: 0, trophies: 0),
            crew(Self.myID, "Pomodoro Pals", "shield", "stopwatch", "teal", .public, members: 5, minutes: 1_464, golds: 0, trophies: 0),
            crew("EARLYB8RDS", "Early Birds", "heater", "bird", "sky", .public, members: 6, minutes: 1_320, golds: 0, trophies: 0),
            crew("LQFJBEATSX", "Lofi and Chill", "pennant", "headphones", "rose", .public, members: 14, minutes: 1_110, golds: 0,
                 trophies: 0),
        ]
    }

    /// The emblem a demo crew wears: the named one while the set has it,
    /// else one picked from the crew's id, so a new emblem set still shows
    /// varied crests with no code change.
    static func demoEmblem(_ preferred: String, crew id: String) -> String {
        let emblems = CrewCatalog.emblems
        if emblems.contains(preferred) { return preferred }
        let seed = id.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }
        return emblems[abs(seed) % emblems.count]
    }

    /// Members for a crew: `count` from the pool, most minutes first.
    func members(of crew: CrewSummary, count: Int, mine: Bool = false) -> [CrewMember] {
        let seed = crew.id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 7
        var members: [CrewMember] = (0..<count).map { index in
            let (name, pet) = Self.pets[(seed + index * 5) % Self.pets.count]
            return CrewMember(ref: "\(crew.id.prefix(6))RF\(index)\(index)", name: name, pet: pet,
                              studyLevel: 52 - index * 7, weekMinutes: max(0, crew.weekMinutes / max(count, 1) - index * 25),
                              owner: index == 0 && !mine)
        }
        if mine {
            let me = CrewMember(ref: "SAMREF2K7Q", name: "Sam",
                                pet: Self.pet(PetProfile(name: "Mochi", breed: .orangeTabby, accessories: [.scarf])),
                                studyLevel: 37, badges: [PartyBadge.founding], weekMinutes: 570, owner: true, me: true)
            members = [me] + members.dropLast()
            members.sort { $0.weekMinutes > $1.weekMinutes }
        }
        return members
    }

    func pets(of crew: CrewSummary) -> [CrewPet] {
        members(of: crew, count: 3).compactMap(\.pet)
    }

    /// My crew, Pomodoro Pals, which I own.
    public func mine(minutes: Int? = nil, requests: Bool = false) -> CrewDetail {
        var summary = crews[7]
        if let minutes { summary.weekMinutes = minutes }
        let pending = requests ? [
            CrewJoinRequest(ref: "AVAREQ7K3R", name: "Ava", pet: Self.pets[5].1, requestedAt: now.addingTimeInterval(-5400),
                            expiresAt: now.addingTimeInterval(6 * 86_400)),
            CrewJoinRequest(ref: "QMARREQ8M2", name: "Omar", pet: Self.pets[6].1, requestedAt: now.addingTimeInterval(-600),
                            expiresAt: now.addingTimeInterval(7 * 86_400)),
        ] : []
        return CrewDetail(summary: summary, createdAt: now.addingTimeInterval(-40 * 86_400), medals: CrewMedals(),
                          rank: minutes == nil ? 12 : 2, members: members(of: summary, count: 5, mine: true), mine: true,
                          owner: true, inviteCode: "W4LNUT7", history: history(places: [14, 18, 21]), crewCount: Self.crewCount,
                          requests: pending)
    }

    /// Another crew's page.
    public func detail(of index: Int) -> CrewDetail {
        let summary = crews[index]
        return CrewDetail(summary: summary, createdAt: now.addingTimeInterval(-120 * 86_400),
                          medals: CrewMedals(gold: summary.golds, silver: 1, bronze: summary.trophies - summary.golds - 1 > 0 ? 1 : 0),
                          rank: index + 1, members: members(of: summary, count: min(summary.memberCount, 8)), mine: false,
                          owner: false, history: history(places: [1, 2, 1], minutes: [3_210, 3_120, 3_390]),
                          crewCount: Self.crewCount)
    }

    func history(places: [Int], minutes: [Int] = [1_380, 1_102, 980]) -> [CrewWeekResult] {
        places.enumerated().map { index, place in
            let start = week.startsAt.addingTimeInterval(-Double(index + 1) * 7 * 86_400)
            let finished = CrewWeek.containing(start)
            return CrewWeekResult(week: finished, place: place, minutes: minutes[index], medal: CrewLaurel(rank: place))
        }
    }

    /// The weekly board; `myPlace` moves my crew up, `tie` ties fifth and sixth.
    public func board(myPlace: Int? = nil, tie: Bool = false) -> CrewBoard {
        var ordered = crews
        if let myPlace {
            var mine = ordered.remove(at: 7)
            mine.weekMinutes = 2_940
            ordered.insert(mine, at: myPlace - 1)
        }
        if tie { ordered[5].weekMinutes = ordered[4].weekMinutes }
        var entries: [CrewBoardEntry] = []
        for (index, crew) in ordered.enumerated() {
            var rank = index + 1
            if let previous = entries.last, previous.minutes == crew.weekMinutes { rank = previous.rank }
            // Ranks past the shown crews jump, as on a board of 38.
            if index >= 7 && myPlace == nil { rank = index + 5 }
            entries.append(CrewBoardEntry(rank: rank, minutes: crew.weekMinutes, crew: crew,
                                          pets: index < 3 ? pets(of: crew) : []))
        }
        for index in entries.indices {
            entries[index].tiedWith = entries.filter { $0.rank == entries[index].rank && $0.id != entries[index].id }.map(\.crew.name)
        }
        let top = Array(entries.prefix(3)), rows = Array(entries.dropFirst(3))
        let mine = entries.first { $0.id == Self.myID }
        return CrewBoard(week: week, top: top, featured: featured(), rows: rows, next: nil, crewCount: Self.crewCount,
                         mine: mine.map { CrewStanding(rank: $0.rank, minutes: $0.minutes) })
    }

    func featured() -> CrewFeatured {
        let last = CrewWeek.containing(week.startsAt.addingTimeInterval(-3600))
        return CrewFeatured(week: last, entries: crews.prefix(3).enumerated().map { index, crew in
            CrewBoardEntry(rank: index + 1, minutes: 3_400 - index * 200, crew: crew, pets: pets(of: crew))
        })
    }

    /// The Hall of Fame: the medalled crews in Olympic order.
    public func hall() -> [CrewHallEntry] {
        let medals: [(Int, CrewMedals)] = [(0, CrewMedals(gold: 3, silver: 1, bronze: 0)), (1, CrewMedals(gold: 3, silver: 0, bronze: 2)),
                                          (4, CrewMedals(gold: 1, silver: 2, bronze: 1)), (2, CrewMedals(gold: 1, silver: 1, bronze: 1)),
                                          (3, CrewMedals(gold: 0, silver: 2, bronze: 0)), (5, CrewMedals(gold: 0, silver: 0, bronze: 1))]
        return medals.enumerated().map { place, pair in
            let crew = crews[pair.0]
            return CrewHallEntry(rank: place + 1, medals: pair.1, reachedAt: week.startsAt.addingTimeInterval(-Double(place) * 7 * 86_400),
                                 crew: crew, pets: place < 3 ? pets(of: crew) : [])
        }
    }

    /// Find's list: the public crews.
    var publicCrews: [CrewSummary] { crews.filter { $0.visibility == .public && $0.id != Self.myID } }
}
