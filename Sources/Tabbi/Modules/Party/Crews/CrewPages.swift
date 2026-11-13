import SwiftUI
import TabbiKitCore
import TabbiKit

// MARK: - My crew

struct CrewMineScreen: View {
    @ObservedObject var crews: CrewsStore

    var body: some View {
        let state = crews.state
        if let code = state.invite {
            CrewStatus(symbol: "envelope.open.fill", title: String(localized: "Join this crew?", bundle: .tabbi),
                       detail: state.inCrew ? String(localized: "You're already in a crew. Leave it first to join another.", bundle: .tabbi)
                           : String(localized: "Someone invited you to a study crew. Your focus minutes count for it from now on.", bundle: .tabbi)) {
                if !state.inCrew {
                    CrewButton(title: String(localized: "Join Crew", bundle: .tabbi), style: .prominent, height: 24,
                               isBusy: crews.pending == .join, help: String(localized: "Join with invite code \(code)", bundle: .tabbi)) {
                        crews.join(invite: code)
                    }
                }
                CrewButton(title: String(localized: "Not Now", bundle: .tabbi), style: .quiet, height: 24,
                           help: String(localized: "Close without joining", bundle: .tabbi)) { crews.dismissInvite() }
            }
        } else if let mine = state.mine {
            CrewHeroLayout(crews: crews, crew: mine, isMine: true)
        } else if let request = state.myRequest {
            CrewStatus(pet: (crews.myPet, asleep: false),
                       title: String(localized: "Waiting to join \(request.crew.name)", bundle: .tabbi),
                       detail: String(localized: "Its owner lets you in. A request goes away after 7 days.", bundle: .tabbi)) {
                CrewButton(title: String(localized: "Cancel request", bundle: .tabbi), style: .quiet, height: 24,
                           isBusy: crews.pending == .cancelRequest,
                           help: String(localized: "Withdraw your request to join \(request.crew.name)", bundle: .tabbi)) {
                    crews.cancelRequest()
                }
                CrewButton(title: String(localized: "Find crews", bundle: .tabbi), height: 24,
                           help: String(localized: "Browse public crews to join", bundle: .tabbi)) { crews.show(.find) }
            }
        } else if state.mineLoaded {
            CrewStatus(pet: (crews.myPet, asleep: false), title: String(localized: "You're not in a crew yet", bundle: .tabbi),
                       detail: String(localized: "Study with friends and climb the board together.", bundle: .tabbi)) {
                CrewButton(title: String(localized: "Create a crew", bundle: .tabbi), style: .prominent, height: 24,
                           help: String(localized: "Make a crew and invite friends", bundle: .tabbi)) { crews.openEditor(editing: false) }
                CrewButton(title: String(localized: "Find crews", bundle: .tabbi), height: 24,
                           help: String(localized: "Browse public crews to join", bundle: .tabbi)) { crews.show(.find) }
            }
        } else {
            CrewStatus(symbol: "shield", title: String(localized: "Loading your crew…", bundle: .tabbi), detail: nil) { EmptyView() }
        }
    }
}

// MARK: - A crew page

struct CrewPageScreen: View {
    @ObservedObject var crews: CrewsStore
    let crew: CrewDetail
    let from: CrewsState.Section

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            CrewBackPill(crews: crews, from: from)
            Text(crew.summary.name)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(1)
                .help(crew.summary.description.isEmpty ? crew.summary.name : crew.summary.description)
            Spacer(minLength: Theme.Spacing.xs)
            trailing
        }
        .frame(height: CrewLayout.headHeight)
        CrewHeroLayout(crews: crews, crew: crew, isMine: crew.mine)
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 4) {
            if crew.mine {
                CrewTag(title: String(localized: "Your crew", bundle: .tabbi), accent: true)
            } else if crew.summary.visibility == .private {
                CrewTag(title: String(localized: "Private", bundle: .tabbi), symbol: "lock.fill")
                    .help(String(localized: "Private, invite only", bundle: .tabbi))
            } else if crews.state.hasRequested(crew.id) {
                CrewTag(title: String(localized: "Requested", bundle: .tabbi), symbol: "checkmark")
                    .help(String(localized: "Its owner lets you in.", bundle: .tabbi))
            } else if !crews.state.inCrew && !crew.summary.isFull {
                CrewButton(title: String(localized: "Join", bundle: .tabbi), isBusy: crews.pending == .join,
                           help: String(localized: "Ask to join \(crew.summary.name). Its owner lets you in.", bundle: .tabbi)) {
                    crews.requestToJoin(crew.summary)
                }
            }
            if !crew.mine {
                CrewIconButton(symbol: "flag", help: String(localized: "Report this crew", bundle: .tabbi)) {
                    crews.beginReport(CrewReportTarget(crew: crew.summary, member: nil))
                }
            }
        }
        .fixedSize()
    }
}

/// My crew and a crew page share one layout: the hero side column and the members.
struct CrewHeroLayout: View {
    @ObservedObject var crews: CrewsStore
    let crew: CrewDetail
    let isMine: Bool
    @Environment(\.crewIsCompact) private var isCompact

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            side
                .frame(width: CrewLayout.sideWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            CrewMembersColumn(crews: crews, crew: crew)
        }
    }

    /// The side column at the most detail that fits the panel's height:
    /// history weeks go first, then "No medals yet", then the
    /// place caption at the tightest size; the crest, the sentence and the
    /// tally always stay.
    private var side: some View {
        let weeks = showsHistory ? min(crew.history.count, isCompact ? 2 : 3) : 0
        let caption = crew.medals == CrewMedals() && !isCompact
        return ViewThatFits(in: .vertical) {
            ForEach(Array(stride(from: weeks, through: 0, by: -1)), id: \.self) { count in
                side(weeks: count, noMedalsCaption: caption)
            }
            side(weeks: 0, noMedalsCaption: false)
            side(weeks: 0, noMedalsCaption: false, shortSentence: true)
            side(weeks: 0, noMedalsCaption: false, shortSentence: true, placeCaption: false)
        }
    }

    private var showsHistory: Bool { !(isMine && crews.state.pushed == nil) && !crew.history.isEmpty }

    private func side(weeks: Int, noMedalsCaption: Bool, shortSentence: Bool = false, placeCaption: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                CrewCrestView(crew: crew.summary, hero: true)
                CrewPetGroup(pets: Array(crew.members.compactMap(\.pet).prefix(4)), overlap: 9)
                    .frame(height: 48, alignment: .bottom)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
            }
            if isMine && crews.state.pushed == nil {
                Text(crew.summary.name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(sentence(short: shortSentence))
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if placeCaption {
                    Text(placeLine)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            CrewTally(medals: crew.medals)
            if noMedalsCaption {
                Text("No medals yet", bundle: .tabbi)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
            if weeks > 0 {
                history(weeks: weeks)
                    .padding(.top, 2)
            }
        }
        .frame(width: CrewLayout.sideWidth, alignment: .topLeading)
    }

    /// The week in a sentence; `short` drops "Your crew studied" when the
    /// column is tight.
    private func sentence(short: Bool) -> String {
        let minutes = crew.summary.weekMinutes
        guard minutes > 0 else { return String(localized: "No hours yet this week", bundle: .tabbi) }
        let hours = CrewFormat.hours(minutes: minutes)
        return isMine && !short ? String(localized: "Your crew studied \(hours) this week", bundle: .tabbi)
            : String(localized: "\(hours) this week", bundle: .tabbi)
    }

    private var placeLine: String {
        let privacy = crew.summary.visibility == .public ? String(localized: "Public", bundle: .tabbi)
            : String(localized: "Private, invite only", bundle: .tabbi)
        guard crew.summary.weekMinutes > 0, let rank = crew.rank, crew.crewCount > 0 else { return privacy }
        return String(localized: "\(CrewFormat.ordinal(rank)) of \(crew.crewCount) crews · \(privacy)", bundle: .tabbi)
    }

    /// The last finished weeks: week, medal if any, place, hours.
    private func history(weeks: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(crew.history.prefix(weeks)) { week in
                HStack(spacing: 6) {
                    Text(CrewFormat.weekLabel(week.week))
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .frame(width: 46, alignment: .leading)
                    Group {
                        if let medal = week.medal { CrewMedalView(metal: medal) } else { Color.clear.frame(width: 9, height: 10) }
                    }
                    Text(week.place.map { CrewFormat.ordinal($0) } ?? "-")
                        .fontWeight(.semibold)
                        .foregroundStyle(week.place.map { $0 <= 3 ? CrewPlaceChip.metal($0) : Theme.Palette.primaryText }
                                         ?? Theme.Palette.tertiaryText)
                        .frame(minWidth: 22, alignment: .leading)
                    Text(CrewFormat.hours(minutes: week.minutes)).foregroundStyle(Theme.Palette.tertiaryText)
                }
                .font(Theme.Typography.caption.monospacedDigit())
                .lineLimit(1)
                .fixedSize()
            }
        }
        .help(String(localized: "Last weeks", bundle: .tabbi))
    }
}

/// The members, most hours first, with their pets and Study Level; for the
/// owner, the people asking to join sit on top with approve and decline.
struct CrewMembersColumn: View {
    @ObservedObject var crews: CrewsStore
    let crew: CrewDetail

    private enum Item: Identifiable {
        case request(CrewJoinRequest)
        case member(CrewMember)

        var id: String {
            switch self {
            case .request(let request): "r-" + request.id
            case .member(let member): "m-" + member.id
            }
        }
    }

    private var items: [Item] {
        (crew.owner ? crew.requests.map(Item.request) : [])
            + crew.members.sorted { $0.weekMinutes > $1.weekMinutes }.map(Item.member)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "this week" goes first, then the waiting count, before anything is cut.
            ViewThatFits(in: .horizontal) {
                caption(requests: true, thisWeek: true)
                caption(requests: true, thisWeek: false)
                caption(requests: false, thisWeek: false)
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.tertiaryText)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(height: 16)
            let items = items
            CrewRowList(count: items.count, row: { index in
                switch items[index] {
                case .request(let request): CrewRequestRow(crews: crews, request: request)
                case .member(let member): CrewMemberRow(crews: crews, crew: crew, member: member)
                }
            })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func caption(requests: Bool, thisWeek: Bool) -> some View {
        HStack(spacing: 6) {
            Text(CrewFormat.members(crew.summary.memberCount, of: crew.summary.maxMembers)).fixedSize()
            if requests && crew.owner && !crew.requests.isEmpty {
                Text(String(localized: "· \(crew.requests.count) want to join", bundle: .tabbi)).foregroundStyle(PartyStyle.accent)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            if thisWeek { Text("this week", bundle: .tabbi).fixedSize() }
        }
    }
}

struct CrewMemberRow: View {
    @ObservedObject var crews: CrewsStore
    let crew: CrewDetail
    let member: CrewMember

    var body: some View {
        HStack(spacing: 6) {
            CrewPetView(pet: member.pet, name: member.name)
                .frame(width: CrewLayout.petColumn, height: 30, alignment: .bottom)
                .clipped()
            CrewRowName(name: member.pet?.petName ?? member.name,
                        caption: member.me ? String(localized: "You", bundle: .tabbi) : (member.pet == nil ? nil : member.name),
                        captionIsAccent: member.me)
            if let level = member.studyLevel {
                Text(String(localized: "Lv \(level)", bundle: .tabbi))
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize()
                    .help(String(localized: "Study Level \(level)", bundle: .tabbi))
            }
            Text(CrewFormat.hours(minutes: member.weekMinutes))
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.Palette.primaryText)
                .frame(minWidth: 44, alignment: .trailing)
                .fixedSize()
        }
        .crewRow(isMine: member.me)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let who = member.me ? String(localized: "You", bundle: .tabbi) : member.name
        let hours = CrewFormat.hours(minutes: member.weekMinutes)
        return String(localized: "\(member.pet?.petName ?? member.name) with \(who), \(hours) this week", bundle: .tabbi)
    }

    @ViewBuilder
    private var menu: some View {
        if member.me {
            Button(member.pet == nil ? String(localized: "Show My Pet on Crew Pages", bundle: .tabbi)
                   : String(localized: "Hide My Pet on Crew Pages", bundle: .tabbi)) { crews.setShowsPet(member.pet == nil) }
        } else {
            if crew.owner && crew.mine {
                Button(String(localized: "Remove \(member.name) from Crew", bundle: .tabbi)) { crews.remove(member) }
                Divider()
            }
            Button(String(localized: "Report \(member.name)…", bundle: .tabbi)) {
                crews.beginReport(CrewReportTarget(crew: crew.summary, member: member))
            }
            Button(String(localized: "Block \(member.name)", bundle: .tabbi), role: .destructive) { crews.block(member, in: crew) }
        }
    }
}

/// Someone asking to join my crew: their pet and name, with approve and decline.
struct CrewRequestRow: View {
    @ObservedObject var crews: CrewsStore
    let request: CrewJoinRequest

    var body: some View {
        HStack(spacing: 6) {
            CrewPetView(pet: request.pet, name: request.name)
                .frame(width: CrewLayout.petColumn, height: 30, alignment: .bottom)
                .clipped()
            CrewRowName(name: request.name, caption: String(localized: "Wants to join", bundle: .tabbi), captionIsAccent: true)
            CrewIconButton(symbol: "checkmark", help: String(localized: "Let \(request.name) into the crew", bundle: .tabbi),
                           filled: true, isBusy: crews.pending == .approve(request.ref)) { crews.approve(request) }
            CrewIconButton(symbol: "xmark", help: String(localized: "Decline. \(request.name) isn't told.", bundle: .tabbi),
                           isBusy: crews.pending == .decline(request.ref)) { crews.decline(request) }
        }
        .padding(.horizontal, 4)
        .frame(height: CrewLayout.rowHeight)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous).fill(PartyStyle.accent.opacity(0.08)))
    }
}
