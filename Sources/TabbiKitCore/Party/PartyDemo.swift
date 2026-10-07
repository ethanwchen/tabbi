import Foundation

extension PartyState {
    /// Sample data for `TABBI_DEMO=1` and snapshots: I host a party
    /// with two friends on a shared session, one more friend is in another
    /// party I could join, and the rest cover every status. Built relative
    /// to `now` so countdowns always read sensibly.
    public static func demo(now: Date, calendar: Calendar = .current) -> PartyState {
        let day = PartyPresenceTracker.dayString(now, calendar: calendar)
        func presence(_ status: PartyStatus, minutesLeft: Double? = nil, today: Int = 0, streak: Int = 0) -> PartyPresence {
            PartyPresence(
                status: status,
                method: status == .studying || status == .onBreak ? "pomodoro" : nil,
                phaseEndsAt: minutesLeft.map { now.addingTimeInterval($0 * 60) },
                sessionMinutes: status == .studying ? 25 : 0,
                todayMinutes: today,
                streakDays: streak,
                day: day,
                lastSeen: now.addingTimeInterval(-30)
            )
        }
        let since = now.addingTimeInterval(-14 * 86_400)

        let me = profile(code: "K7QW2MZD", name: "Sam", pet: PetProfile(name: "Mochi", breed: .orangeTabby, accessories: [.scarf]))
        let maya = profile(code: "M4YA8QRT", name: "Maya", pet: PetProfile(name: "Biscuit", breed: .goldenRetriever, accessories: [.roundGlasses]))
        let priya = profile(code: "PR1YA6KD", name: "Priya", pet: PetProfile(name: "Luna", breed: .siamese, outfit: .scrubs))
        let leo = profile(code: "LE0J9WXC", name: "Leo", pet: PetProfile(name: "Waffles", breed: .corgi, accessories: [.beanie]))
        let jonah = profile(code: "J0NAH2PF", name: "Jonah", pet: PetProfile(name: "Pepper", breed: .blackCat))

        let session = PartySession(method: "pomodoro", phaseEndsAt: now.addingTimeInterval(18 * 60 + 20), startedAt: now.addingTimeInterval(-6 * 60 - 40))
        let party = Party(
            code: "Q4RT8M",
            host: me.code,
            createdAt: now.addingTimeInterval(-40 * 60),
            lastActive: now,
            expiresAt: now.addingTimeInterval(4 * 3600),
            maxMembers: 8,
            session: session,
            members: [
                PartyMember(profile: me, joinedAt: now.addingTimeInterval(-40 * 60), host: true,
                            presence: presence(.studying, minutesLeft: 18.3, today: 95, streak: 6), online: true),
                PartyMember(profile: maya, joinedAt: now.addingTimeInterval(-35 * 60), host: false,
                            presence: presence(.studying, minutesLeft: 18.3, today: 140, streak: 12), online: true),
                PartyMember(profile: priya, joinedAt: now.addingTimeInterval(-12 * 60), host: false,
                            presence: presence(.onBreak, minutesLeft: 3.5, today: 60, streak: 3), online: true),
            ]
        )
        let friends = [
            PartyFriend(profile: maya, since: since, presence: presence(.studying, minutesLeft: 18.3, today: 140, streak: 12),
                        online: true, party: PartyRef(code: party.code, size: 3)),
            PartyFriend(profile: priya, since: since, presence: presence(.onBreak, minutesLeft: 3.5, today: 60, streak: 3),
                        online: true, party: PartyRef(code: party.code, size: 3)),
            PartyFriend(profile: leo, since: since, presence: presence(.studying, minutesLeft: 41, today: 30, streak: 2),
                        online: true, party: PartyRef(code: "ZX7M2P", size: 2)),
            PartyFriend(profile: jonah, since: since, presence: nil, online: false, party: nil),
        ]
        return PartyState(profile: me, friends: friends, party: party)
    }

    /// A profile as the server would return it for `pet`.
    private static func profile(code: String, name: String, pet: PetProfile) -> PartyProfile {
        let update = PartyPetAppearance.update(for: pet)
        return PartyProfile(
            code: code,
            name: name,
            petName: update.petName ?? pet.name,
            species: update.species ?? "cat",
            breed: update.breed ?? "tabby",
            colors: update.colors ?? [],
            costume: update.costume ?? "none",
            accessories: update.accessories ?? [],
            points: 0,
            level: 1
        )
    }
}

/// The Party tab's screens, so demo snapshots can show each one
/// (`TABBI_PARTY_PREVIEW=<raw value>`).
public enum PartyDemoScenario: String, CaseIterable, Sendable {
    /// I host a party with a shared session running (the default demo).
    case hosting
    /// A friend hosts and hasn't started a session: I wait.
    case guest
    /// A friend hosts and their shared session is running: I'm in it.
    case member
    /// A friend's shared session just ran to its end with me in it: the
    /// team celebrates (`PartyTeamCelebration.demo`).
    case celebrating
    /// A full party of eight with no session, so I can start one.
    case crowded
    /// Not in a party; friends are around and one party is joinable.
    case lobby
    /// Just registered: no friends and no party yet.
    case noFriends
    /// Waiting for the server's first answer.
    case connecting
    /// The server never answered.
    case unreachable
    /// The server setting can't be used.
    case invalidServer
}

extension PartyState {
    /// `demo(now:)` reshaped into `scenario`.
    public static func demo(_ scenario: PartyDemoScenario, now: Date, calendar: Calendar = .current) -> PartyState {
        let base = demo(now: now, calendar: calendar)
        guard let me = base.profile, var party = base.party else { return base }
        switch scenario {
        case .hosting:
            return base
        case .guest, .member, .celebrating:
            let host = party.members[1].profile.code
            party.host = host
            if scenario != .member { party.session = nil }
            party.members = party.members.map { member in
                var member = member
                member.host = member.profile.code == host
                return member
            }
            return PartyState(profile: me, friends: base.friends, party: party)
        case .crowded:
            party.session = nil
            let names = [("Ana", "Pretzel", PetBreed.corgi), ("Ben", "Olive", .tuxedo), ("Chloe", "Noodle", .beagle),
                         ("Dev", "Tofu", .frenchBulldog), ("Eli", "Smudge", .grayTabby)]
            party.members += names.enumerated().map { index, entry in
                let code = "CRWD\(index + 2)ABZ"
                let profile = profile(code: code, name: entry.0, pet: PetProfile(name: entry.1, breed: entry.2))
                var member = party.members[1]
                member.profile = profile
                member.host = false
                member.presence?.status = index.isMultiple(of: 2) ? .idle : .studying
                member.presence?.phaseEndsAt = index.isMultiple(of: 2) ? nil : now.addingTimeInterval(Double(10 + index) * 60)
                return member
            }
            return PartyState(profile: me, friends: base.friends, party: party)
        case .lobby:
            return PartyState(profile: me, friends: base.friends, party: nil)
        case .noFriends:
            return PartyState(profile: me, friends: [], party: nil)
        case .connecting:
            return PartyState(settings: PartySettings())
        case .unreachable:
            var state = PartyState(settings: PartySettings())
            state.didFailToConnect(.unreachable)
            return state
        case .invalidServer:
            return PartyState(settings: PartySettings(serverText: "http://tabbi.example.com"))
        }
    }
}

extension PartyTeamCelebration {
    /// The celebration the `celebrating` demo scenario shows: a 25-minute
    /// session with two friends, just finished.
    public static func demo(now: Date) -> PartyTeamCelebration {
        let completion = PartySessionCompletion(method: "pomodoro", joinedAt: now.addingTimeInterval(-25 * 60),
                                                endedAt: now, friendCount: 2, hostName: "Maya")
        return PartyTeamCelebration(completion: completion,
                                    points: PetPointsRules.sharedPoints(forMinutes: 25, friends: 2),
                                    petName: "Mochi", date: now)
    }
}
