import SwiftUI
import TabbiKitCore
import TabbiKit

/// One place on a board, whichever board: the weekly hours or the Hall of
/// Fame's medals.
struct CrewBoardItem: Identifiable {
    enum Value {
        case minutes(Int)
        case medals(CrewMedals)
    }

    let rank: Int
    let crew: CrewSummary
    let value: Value
    let pets: [CrewPet]
    var tiedWith: [String] = []

    var id: String { crew.id }

    init(_ entry: CrewBoardEntry) {
        rank = entry.rank
        crew = entry.crew
        value = .minutes(entry.minutes)
        pets = entry.pets
        tiedWith = entry.tiedWith
    }

    init(_ entry: CrewHallEntry) {
        rank = entry.rank
        crew = entry.crew
        value = .medals(entry.medals)
        pets = entry.pets
    }
}

// MARK: - This week

struct CrewWeekScreen: View {
    @ObservedObject var crews: CrewsStore

    var body: some View {
        let state = crews.state
        if let board = state.board {
            if state.isQuietWeek {
                CrewStatus(pet: (crews.myPet, asleep: true), title: String(localized: "A quiet start to the week", bundle: .tabbi),
                           detail: String(localized: "Hours show up after the first focus session. Last week's top 3 keep their laurels until Sunday.", bundle: .tabbi)) {
                    EmptyView()
                }
            } else {
                CrewBoardBody(crews: crews, items: state.weekEntries.map(CrewBoardItem.init), mine: state.mine?.summary,
                              mineValue: state.mine.map { .minutes(board.mine?.minutes ?? $0.summary.weekMinutes) },
                              mineRank: board.mine?.rank, nearEnd: { crews.loadMoreBoard() })
            }
        } else {
            CrewBoardSkeleton()
        }
    }
}

// MARK: - Hall of Fame

struct CrewHallScreen: View {
    @ObservedObject var crews: CrewsStore

    var body: some View {
        let state = crews.state
        if let hall = state.hall {
            if hall.isEmpty {
                CrewStatus(symbol: "medal", title: String(localized: "No medals yet", bundle: .tabbi),
                           detail: String(localized: "Every Sunday's top 3 earn a medal", bundle: .tabbi)) { EmptyView() }
            } else {
                CrewBoardBody(crews: crews, items: hall.map(CrewBoardItem.init), mine: state.mine?.summary,
                              mineValue: state.mine.map { .medals(state.hallMine?.medals ?? state.myHallEntry?.medals ?? $0.medals) },
                              mineRank: state.hallMine?.rank ?? state.myHallEntry?.rank, nearEnd: { crews.loadMoreHall() })
            }
        } else {
            CrewBoardSkeleton()
        }
    }
}

// MARK: - The board's layout

/// The top 3 as tiles beside the rest as a list (Regular and Large), or one
/// list whose first rows carry the place chip and two pets (Compact), with
/// my crew pinned under the list when it is not already in view.
struct CrewBoardBody: View {
    @ObservedObject var crews: CrewsStore
    let items: [CrewBoardItem]
    let mine: CrewSummary?
    let mineValue: CrewBoardItem.Value?
    let mineRank: Int?
    let nearEnd: () -> Void
    @Environment(\.crewIsCompact) private var isCompact

    private var myIndex: Int? { mine.flatMap { mine in items.firstIndex { $0.id == mine.id } } }

    var body: some View {
        if isCompact {
            let pinned = mine != nil && (myIndex.map { $0 >= 2 } ?? true)
            CrewRowList(count: items.count, row: { index in
                let item = items[index]
                if index < 3 && item.rank <= 3 {
                    CrewFeaturedRow(crews: crews, item: item, isMine: item.id == mine?.id)
                } else {
                    CrewBoardRow(crews: crews, item: item, isMine: item.id == mine?.id)
                }
            }, pinned: pinned ? pinnedRow : nil, slimPinned: pinned ? slimPinnedRow : nil, minimumRows: 3, nearEnd: nearEnd)
        } else {
            let top = Array(items.prefix { $0.rank <= 3 }.prefix(3))
            let rest = Array(items.dropFirst(top.count))
            let pinned = mine != nil && (myIndex.map { $0 >= top.count + 2 } ?? true)
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                HStack(spacing: 6) {
                    ForEach(top) { item in
                        CrewFeaturedTile(crews: crews, item: item, isMine: item.id == mine?.id)
                    }
                }
                CrewRowList(count: rest.count, row: { index in
                    CrewBoardRow(crews: crews, item: rest[index], isMine: rest[index].id == mine?.id)
                }, pinned: pinned ? pinnedRow : nil, nearEnd: nearEnd)
            }
        }
    }

    /// My crew in one caption line, under a Compact list that shows the
    /// top 3 whole: "Your crew", its place and its hours or medals.
    private var slimPinnedRow: AnyView? {
        guard mine != nil, let mineValue else { return nil }
        let rank = myIndex.map { items[$0].rank } ?? mineRank
        return AnyView(HStack(spacing: 6) {
            Rectangle().fill(PartyStyle.accent).frame(width: 2, height: 12)
            Text("Your crew", bundle: .tabbi).foregroundStyle(PartyStyle.accent).fixedSize()
            Text(verbatim: rank.map { CrewFormat.ordinal($0) } ?? "-").foregroundStyle(Theme.Palette.secondaryText).fixedSize()
            Spacer(minLength: 4)
            switch mineValue {
            case .minutes(let minutes):
                Text(CrewFormat.hours(minutes: minutes)).foregroundStyle(Theme.Palette.primaryText).fixedSize()
            case .medals(let medals):
                CrewTally(medals: medals)
            }
        }
        .font(Theme.Typography.caption.monospacedDigit())
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine))
    }

    /// My crew under the list: its place, or a dash before it has one.
    private var pinnedRow: CrewBoardRow? {
        guard let mine, let mineValue else { return nil }
        if let index = myIndex { return CrewBoardRow(crews: crews, item: items[index], isMine: true) }
        return CrewBoardRow(crews: crews, item: CrewBoardItem(pinned: mine, rank: mineRank, value: mineValue), isMine: true)
    }
}

extension CrewBoardItem {
    /// My crew when it is not on the loaded part of the board.
    init(pinned crew: CrewSummary, rank: Int?, value: Value) {
        self.rank = rank ?? 0
        self.crew = crew
        self.value = value
        pets = []
    }
}

/// A featured tile: the place chip and crest, the crew's most active pets,
/// the name on up to two lines, and the value.
struct CrewFeaturedTile: View {
    @ObservedObject var crews: CrewsStore
    let item: CrewBoardItem
    let isMine: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .top) {
                CrewPlaceChip(place: item.rank)
                Spacer(minLength: 0)
                CrewCrestView(crew: item.crew)
            }
            CrewPetGroup(pets: Array(item.pets.prefix(3)), overlap: 13)
                .frame(height: 29, alignment: .bottom)
                .frame(maxWidth: .infinity)
                .clipped()
            Text(CrewHyphenation.hyphenated(item.crew.name))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            CrewBoardValue(value: item.value, compactTally: true)
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(width: CrewLayout.tileWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
            .fill(isMine ? PartyStyle.accent.opacity(0.09) : hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
            .strokeBorder(item.rank == 1 ? CrewPlaceChip.metal(1).opacity(0.45) : Theme.Palette.stroke, lineWidth: item.rank == 1 ? 1 : 0.5))
        .contentShape(Rectangle())
        .onTapGesture { crews.open(crew: item.crew.id) }
        .onHover { hovering = $0 }
        .help(CrewBoardItem.lead(item))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CrewBoardItem.accessibility(item))
        .accessibilityAddTraits(.isButton)
    }
}

/// A Compact board's first rows: the tile's content in a row.
struct CrewFeaturedRow: View {
    @ObservedObject var crews: CrewsStore
    let item: CrewBoardItem
    let isMine: Bool

    var body: some View {
        HStack(spacing: 6) {
            CrewPlaceChip(place: item.rank).frame(minWidth: CrewLayout.rankWidth)
            CrewCrestView(crew: item.crew)
            CrewRowName(name: item.crew.name,
                        caption: isMine ? String(localized: "Your crew", bundle: .tabbi) : CrewFormat.members(item.crew.memberCount),
                        captionIsAccent: isMine)
            CrewPetGroup(pets: Array(item.pets.prefix(2)), overlap: 12)
                .frame(height: 30, alignment: .bottom)
            CrewBoardValue(value: item.value)
        }
        .crewRow(isMine: isMine) { crews.open(crew: item.crew.id) }
        .help(CrewBoardItem.lead(item))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CrewBoardItem.accessibility(item))
    }
}

/// A board row: place, crest, name over the members, value.
struct CrewBoardRow: View {
    @ObservedObject var crews: CrewsStore
    let item: CrewBoardItem
    let isMine: Bool

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                Text(item.rank > 0 ? item.rank.formatted() : "-")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.Palette.secondaryText)
                if !item.tiedWith.isEmpty {
                    Text(verbatim: "=").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.Palette.tertiaryText)
                        .baselineOffset(4)
                }
            }
            .frame(minWidth: CrewLayout.rankWidth, alignment: .trailing)
            .fixedSize()
            .environment(\.layoutDirection, .leftToRight)
            CrewCrestView(crew: item.crew)
            CrewRowName(name: item.crew.name,
                        caption: isMine ? String(localized: "Your crew", bundle: .tabbi) : CrewFormat.members(item.crew.memberCount),
                        captionIsAccent: isMine)
            CrewBoardValue(value: item.value)
        }
        .crewRow(isMine: isMine) { crews.open(crew: item.crew.id) }
        .help(item.tiedWith.isEmpty ? item.crew.name
              : "\(item.crew.name) · \(CrewBoardItem.tie(item))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CrewBoardItem.accessibility(item))
    }
}

/// Hours, or the medal tally.
struct CrewBoardValue: View {
    let value: CrewBoardItem.Value
    var compactTally = false

    var body: some View {
        switch value {
        case .minutes(let minutes):
            Text(CrewFormat.hours(minutes: minutes))
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(1)
                .fixedSize()
        case .medals(let medals):
            CrewTally(medals: medals)
        }
    }
}

extension CrewBoardItem {
    /// "Night Owls leads the week" and friends, the tile's tooltip.
    static func lead(_ item: CrewBoardItem) -> String {
        if case .medals = item.value { return accessibility(item) }
        switch item.rank {
        case 1: return String(localized: "\(item.crew.name) leads the week", bundle: .tabbi)
        case 2: return String(localized: "\(item.crew.name) is second this week", bundle: .tabbi)
        case 3: return String(localized: "\(item.crew.name) is third this week", bundle: .tabbi)
        default: return item.crew.name
        }
    }

    static func tie(_ item: CrewBoardItem) -> String {
        guard case .minutes(let minutes) = item.value else { return "" }
        let names = item.tiedWith.formatted(.list(type: .and))
        return String(localized: "Tied with \(names) at \(CrewFormat.hours(minutes: minutes))", bundle: .tabbi)
    }

    static func accessibility(_ item: CrewBoardItem) -> String {
        switch item.value {
        case .minutes(let minutes):
            let base = String(localized: "Rank \(item.rank), \(item.crew.name), \(CrewFormat.hours(minutes: minutes)) this week, \(CrewFormat.members(item.crew.memberCount))", bundle: .tabbi)
            return item.tiedWith.isEmpty ? base : base + ", " + tie(item)
        case .medals(let medals):
            return String(localized: "Rank \(item.rank), \(item.crew.name), \(CrewTally.label(medals))", bundle: .tabbi)
        }
    }
}

/// The board while it loads: the tiles and rows as placeholder shapes.
struct CrewBoardSkeleton: View {
    @Environment(\.crewIsCompact) private var isCompact

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            if !isCompact {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(spacing: 6) {
                            HStack { bar(24, 14); Spacer(minLength: 0); bar(32, 32) }
                            bar(66, 26)
                            bar(56, 10)
                            bar(36, 12)
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .frame(width: CrewLayout.tileWidth)
                        .frame(maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous).fill(Theme.Palette.surface.opacity(0.5)))
                    }
                }
            }
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 6) {
                        bar(12, 12); bar(32, 32)
                        VStack(alignment: .leading, spacing: 4) { bar(90, 10); bar(50, 8) }
                        Spacer(minLength: 0)
                        bar(34, 12)
                    }
                    .padding(.horizontal, 4)
                    .frame(height: CrewLayout.rowHeight)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Loading the board", bundle: .tabbi))
    }

    private func bar(_ width: CGFloat, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.Palette.surface).frame(width: width, height: height)
    }
}
