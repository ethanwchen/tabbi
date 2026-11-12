import Foundation

/// The Crew section's screens, so demo snapshots can show each one
/// (`TABBI_CREWS_PREVIEW=<raw value>`).
public enum CrewDemoScenario: String, CaseIterable, Sendable {
    /// My crew, which I own, second on the board and wearing last week's gold.
    case mine
    /// Not in a crew yet.
    case noCrew
    /// The New crew form.
    case create
    /// The owner editing the crew.
    case edit
    /// Find with a list of public crews.
    case find
    /// Last week's frozen winners in the top 3 card.
    case lastWeek
    /// A featured crew's page with its members' pets.
    case viewing
    /// An invite link waiting to be confirmed.
    case invite
}

extension CrewsState {
    /// Sample crews for `TABBI_DEMO=1` and snapshots, built relative to `now`
    /// so the countdown reads sensibly. The pets are the Party demo's, and
    /// one member hid theirs, so the silhouette shows too.
    public static func demo(_ scenario: CrewDemoScenario, now: Date) -> CrewsState {
        let week = CrewWeek.containing(now)
        let lastWeek = CrewWeek.containing(week.startsAt.addingTimeInterval(-3600))
        let mine = CrewDemoData.nightOwls(now: now)
        let board = CrewBoard(
            week: week,
            top: [
                CrewBoardEntry(rank: 1, minutes: 9_120, crew: CrewDemoData.medSquad.summary),
                CrewBoardEntry(rank: 2, minutes: mine.summary.weekMinutes, crew: mine.summary),
                CrewBoardEntry(rank: 3, minutes: 5_340, crew: CrewDemoData.lofi.summary),
            ],
            featured: CrewFeatured(week: lastWeek, entries: [
                CrewBoardEntry(rank: 1, minutes: 11_460, crew: CrewDemoData.won(mine.summary, .gold)),
                CrewBoardEntry(rank: 2, minutes: 10_020, crew: CrewDemoData.won(CrewDemoData.medSquad.summary, .silver)),
                CrewBoardEntry(rank: 3, minutes: 4_410, crew: CrewDemoData.won(CrewDemoData.bookworms, .bronze)),
            ])
        )
        let results = [CrewDemoData.medSquad.summary, CrewDemoData.lofi.summary, CrewDemoData.bookworms,
                       CrewDemoData.earlyBirds, CrewDemoData.quietCorner]
        var state = CrewsState(section: .mine, week: week, mine: mine, mineLoaded: true, board: board, results: results)
        switch scenario {
        case .mine:
            break
        case .noCrew:
            state.mine = nil
        case .create:
            state.mine = nil
            state.section = .create
        case .edit:
            state.editing = true
        case .find:
            state.section = .find
        case .lastWeek:
            state.showsLastWeek = true
        case .viewing:
            state.viewing = CrewDemoData.medSquad
        case .invite:
            state.mine = nil
            state.invite = "LQFJ7RM"
        }
        return state
    }
}

/// The demo crews and people.
public enum CrewDemoData {
    static func pet(_ profile: PetProfile) -> CrewPet {
        let update = PartyPetAppearance.update(for: profile)
        return CrewPet(petName: update.petName ?? profile.name, species: update.species ?? "cat",
                       breed: update.breed ?? "tabby", colors: update.colors ?? [], costume: update.costume ?? "none",
                       accessories: update.accessories ?? [])
    }

    public static func nightOwls(now: Date) -> CrewDetail {
        let members = [
            CrewMember(ref: "SAMREF2K7Q", name: "Sam",
                       pet: pet(PetProfile(name: "Mochi", breed: .orangeTabby, accessories: [.scarf, .graduationCap])),
                       badges: [PartyBadge.founding], weekMinutes: 1_140, owner: true, me: true),
            CrewMember(ref: "MAYAREF4QR", name: "Maya",
                       pet: pet(PetProfile(name: "Biscuit", breed: .goldenRetriever, accessories: [.roundGlasses, .cowboyHat])),
                       badges: [PartyBadge.founding], weekMinutes: 1_720),
            CrewMember(ref: "PRJYAREF6K", name: "Priya",
                       pet: pet(PetProfile(name: "Luna", breed: .siamese, outfit: .scrubs, accessories: [.surgicalCap])),
                       weekMinutes: 2_210),
            CrewMember(ref: "LEQREF9WXC", name: "Leo",
                       pet: pet(PetProfile(name: "Waffles", breed: .corgi, outfit: .cozyHoodie, accessories: [.frogHat])),
                       weekMinutes: 870),
            CrewMember(ref: "JQNAHREF2P", name: "Jonah", pet: nil, weekMinutes: 1_360),
        ]
        let summary = CrewSummary(id: "NGHTQWLS2K", name: "Night Owls",
                                  description: "Late study sessions, quiet focus, good snacks.", frame: "shield", emblem: "owl",
                                  color: "indigo", visibility: .private, laurel: .gold, trophies: 3,
                                  memberCount: members.count, weekMinutes: members.reduce(0) { $0 + $1.weekMinutes })
        return CrewDetail(summary: summary, createdAt: now.addingTimeInterval(-40 * 86_400),
                          medals: CrewMedals(gold: 2, silver: 1), rank: 2, members: members, mine: true, owner: true,
                          inviteCode: "W4LNUT7")
    }

    public static let medSquad: CrewDetail = {
        let members = [
            CrewMember(ref: "AVAREF7K3R", name: "Ava",
                       pet: pet(PetProfile(name: "Clover", breed: .beagle, accessories: [.flowerCrown])),
                       weekMinutes: 2_640, owner: true),
            CrewMember(ref: "NQQRREF7HV", name: "Noor",
                       pet: pet(PetProfile(name: "Pip", breed: .scottishFold, accessories: [.chunkyHeadphones])),
                       weekMinutes: 2_380),
            CrewMember(ref: "KAJREF8M2D", name: "Kai",
                       pet: pet(PetProfile(name: "Pepper", breed: .blackCat, accessories: [.wizardHat])),
                       weekMinutes: 2_150),
            CrewMember(ref: "EMMAREF5TB", name: "Emma",
                       pet: pet(PetProfile(name: "Maple", breed: .dachshund, outfit: .scrubs)),
                       weekMinutes: 1_950),
        ]
        let summary = CrewSummary(id: "MEDSQUAD2K", name: "Med School Squad", description: "Anki every morning.",
                                  frame: "seal", emblem: "cat", color: "coral", visibility: .public, laurel: .silver, trophies: 5,
                                  memberCount: 14, weekMinutes: 9_120)
        return CrewDetail(summary: summary, createdAt: Date(timeIntervalSince1970: 1_790_000_000),
                          medals: CrewMedals(gold: 1, silver: 3, bronze: 1), rank: 1, members: members, mine: false,
                          owner: false)
    }()

    public static let lofi: CrewDetail = {
        let summary = CrewSummary(id: "LQFJBEATSX",
                                  name: "Lofi and Chill", frame: "pennant", emblem: "headphones", color: "mint", visibility: .public, trophies: 1,
                                  memberCount: 9, weekMinutes: 5_340)
        return CrewDetail(summary: summary, createdAt: Date(timeIntervalSince1970: 1_790_000_000), members: [],
                          mine: false, owner: false)
    }()

    static let bookworms = CrewSummary(id: "BQQKWQRMS2", name: "Bookworms", description: "One more chapter.", frame: "hexagon", emblem: "books",
                                       color: "amber", visibility: .public, laurel: .bronze, trophies: 1,
                                       memberCount: 20, weekMinutes: 3_980)
    static let earlyBirds = CrewSummary(id: "EARLYB8RDS", name: "Early Birds", frame: "heater", emblem: "bird", color: "sky",
                                        visibility: .public, memberCount: 6, weekMinutes: 2_210)
    static let quietCorner = CrewSummary(id: "QUJETC6RNR", name: "Quiet Corner", frame: "star", emblem: "moon", color: "violet",
                                         visibility: .public, memberCount: 3, weekMinutes: 640)

    static func won(_ summary: CrewSummary, _ laurel: CrewLaurel) -> CrewSummary {
        var won = summary
        won.laurel = laurel
        return won
    }
}
