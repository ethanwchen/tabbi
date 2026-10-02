import Foundation

extension PartyState {
    /// Sample data for `NOTCHDECK_DEMO=1` and snapshots: I host a party
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
