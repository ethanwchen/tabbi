import SwiftUI
import TabbiKitCore

/// The case file: six object slots across the top (a silhouette until the
/// pet is first caught with that object, then three pips for its rap
/// sheet, filled at the first, second and fourth catch), then every tape
/// watched as one timeline, newest first. A catch is a mugshot (the pet
/// wearing the evidence and its rap-sheet props, its case number, the
/// charge, the wreck as Exhibit A), filed as a WANTED card when it was the
/// object the wall lacked longest. A miss is a cold case: the charge in the
/// player's own words when there were some, SUSPECT AT LARGE, the wreck, and
/// the pet as it ended the tape as the only witness, with no count of
/// unsolved cases anywhere. Tapping a card replays its tape exactly.
struct MugshotWall: View {
    @Environment(PetCamStore.self) private var cam
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var replaying: PetCamBlockRecord?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ObjectSlots(counts: cam.caughtCounts, kinds: cam.game.arrived)
                    if cam.cases.isEmpty {
                        empty
                    } else {
                        // One column in time order, so a story reads straight
                        // down and no two cards share a row.
                        LazyVStack(spacing: 14) {
                            ForEach(cam.cases) { record in
                                Button { replaying = record } label: {
                                    if let number = cam.caseNumber(of: record) {
                                        MugshotCard(record: record, caseNumber: number)
                                    } else {
                                        ColdCaseCard(record: record)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(Text(verbatim: "Plays the tape again"))
                            }
                        }
                    }
                }
                .padding(CCTV.gutter)
            }
            .background(CCTV.screen.ignoresSafeArea())
            .navigationTitle(Text(verbatim: "Case file"))
            .navigationBarTitleDisplayMode(.inline)
            // An opaque header, so cards never ghost behind the title.
            .toolbarBackground(CCTV.panel, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .tabbi) }
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $replaying) { record in TapePlayer(record: record) }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 44))
                .foregroundStyle(CCTV.burnIn.opacity(0.5))
                .accessibilityHidden(true)
            Text(verbatim: "No cases yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(CCTV.burnIn)
            Text(verbatim: "Hide the camera where your pet strikes and catch it in the act. Every tape is filed here.")
                .font(.body)
                .foregroundStyle(CCTV.burnIn.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }
}

/// The six objects the pet can be caught with: each one drawn once it has
/// been, a dark silhouette until then.
/// One slot per object that has arrived in the room, so the file grows
/// as the room does and never looks finished.
private struct ObjectSlots: View {
    let counts: [PetCamObjectKind: Int]
    let kinds: [PetCamObjectKind]
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The rap-sheet marks: filled at the first, second and fourth catch.
    static let pips = [1, 2, 4]

    var body: some View {
        let caught = Set(counts.keys)
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "CAUGHT WITH \(caught.count) OF \(kinds.count)")
                .font(CCTV.font(.caption, weight: .heavy))
                .foregroundStyle(CCTV.burnIn.opacity(0.7))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
                                     count: typeSize.isAccessibilitySize ? 2 : 3),
                      spacing: 8) {
                ForEach(kinds, id: \.self) { kind in
                    let known = caught.contains(kind)
                    VStack(spacing: 6) {
                        ObjectSprite(kind: kind, wrecked: false, silhouette: !known, points: 3)
                            .frame(height: 54)
                        Text(verbatim: known ? PetCamCaptions.name(of: kind) : "???")
                            .font(CCTV.font(.caption2, weight: .bold))
                            .foregroundStyle(CCTV.burnIn.opacity(known ? 0.85 : 0.4))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 5) {
                            ForEach(Self.pips, id: \.self) { mark in
                                Circle()
                                    .fill((counts[kind] ?? 0) >= mark ? CCTV.rec : CCTV.burnIn.opacity(0.15))
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(CCTV.panel, in: .rect(cornerRadius: 10, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: known
                        ? "\(PetCamCaptions.name(of: kind).lowercased()), caught \(counts[kind] ?? 0) times"
                        : "Not caught with this one yet"))
                }
            }
        }
    }
}

/// One mugshot: the pet's front and side in front of a height chart,
/// wearing the evidence, and the placard with the case. A WANTED catch
/// gets the poster's yellow band and says how long it was wanted.
struct MugshotCard: View {
    let record: PetCamBlockRecord
    let caseNumber: Int

    private var wanted: Bool { record.strike != nil && record.setup.wanted == record.strike }

    var body: some View {
        VStack(spacing: 0) {
            if wanted {
                Text(verbatim: "WANTED")
                    .font(CCTV.font(.headline, weight: .heavy))
                    .kerning(2)
                    .foregroundStyle(CCTV.screen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(CCTV.wanted)
            }
            ZStack(alignment: .bottom) {
                HeightChart()
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 6) { front; side }
                    front
                }
                .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 124)
            .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: String(format: "CASE %03d", caseNumber))
                    .font(CCTV.font(.headline, weight: .heavy))
                    .foregroundStyle(CCTV.rec)
                Text(verbatim: CCTV.timestamp(record.endedAt))
                    .font(CCTV.font(.caption2, weight: .medium))
                    .foregroundStyle(CCTV.burnIn.opacity(0.7))
                if let charge = record.captions.charge {
                    Text(verbatim: PetCamCaptions.chargeLabel)
                        .font(CCTV.font(.caption2, weight: .heavy))
                        .foregroundStyle(CCTV.burnIn.opacity(0.55))
                        .padding(.top, 2)
                    Text(verbatim: PetCamCaptions.filedCharge(charge))
                        .font(CCTV.font(.footnote, weight: .semibold))
                        .foregroundStyle(CCTV.burnIn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let rap = record.captions.priors {
                    Text(verbatim: rap)
                        .font(CCTV.font(.caption2, weight: .bold))
                        .foregroundStyle(record.tier >= 2 ? CCTV.rec : CCTV.burnIn.opacity(0.7))
                }
                if wanted, let line = record.captions.wanted {
                    Text(verbatim: line)
                        .font(CCTV.font(.caption2, weight: .bold))
                        .foregroundStyle(CCTV.wanted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let kind = record.struck?.kind {
                    Evidence(kind: kind)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(CCTV.panel, in: .rect(cornerRadius: 14, style: .continuous))
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(wanted ? CCTV.wanted.opacity(0.6) : CCTV.burnIn.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }

    /// The face that froze under the stamp: the same look, evidence and
    /// rap-sheet props as the tape's last frame.
    private var front: some View {
        let look: Int = if let kind = record.struck?.kind,
                           case .mugshot(_, let look, _) = PetCamTape.mugshotPose(record, kind) { look } else { caseNumber - 1 }
        return PixelPet(canvas: PetCamPetArt.mugshot(look, profile: record.pet, evidence: record.struck?.kind,
                                                     tier: record.tier).trimmed(margin: 1),
                        palette: record.pet.palette, pixelSize: 3)
    }

    private var side: some View {
        PixelPet(canvas: PetCamPetArt.mugshotProfile(record.pet).trimmed(margin: 1), palette: record.pet.palette,
                 pixelSize: 3)
    }
}

/// A miss, filed: the charge in the player's own words when there were
/// some, no suspect, the wreck nobody filmed, and the pet as it ended the
/// tape, set beside the exhibit as the only witness.
struct ColdCaseCard: View {
    let record: PetCamBlockRecord

    /// The pet's last pose on the tape (lying down, or the double take).
    private var witness: PetCamPose {
        PetCamTape(record: record)?.stills.last(where: { $0.shot.pet != nil })?.shot.pet ?? .lieDown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "COLD CASE")
                .font(CCTV.font(.headline, weight: .heavy))
                .foregroundStyle(CCTV.standby)
            Text(verbatim: CCTV.timestamp(record.endedAt))
                .font(CCTV.font(.caption2, weight: .medium))
                .foregroundStyle(CCTV.burnIn.opacity(0.7))
            if let line = PetCamCaptions.caseLine(record, includeDodge: true) {
                Text(verbatim: PetCamCaptions.keepingDodgeTogether(line))
                    .font(CCTV.font(.footnote, weight: .semibold))
                    .foregroundStyle(CCTV.burnIn)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 16) { exhibit; witnessView }
                VStack(alignment: .leading, spacing: 8) { exhibit; witnessView }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(CCTV.panel.opacity(0.7), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(CCTV.burnIn.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var exhibit: some View {
        if let kind = record.struck?.kind { Evidence(kind: kind) }
    }

    private var witnessView: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PixelPet(canvas: PetCamPetArt.canvas(witness, profile: record.pet).trimmed(margin: 1),
                     palette: record.pet.palette, pixelSize: 2)
            Text(verbatim: "WITNESS")
                .font(.system(.caption2, design: .monospaced).weight(.heavy))
                .foregroundStyle(CCTV.burnIn.opacity(0.6))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Witness: \(record.pet.name)"))
    }
}

/// An object from the room as crisp pixel art: whole, wrecked, or (not
/// caught with yet) as a dark silhouette.
private struct ObjectSprite: View {
    let kind: PetCamObjectKind
    let wrecked: Bool
    var silhouette = false
    var points: CGFloat = 3
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let sprite = PetCamScene.sprite(kind, wrecked: wrecked)
        let colors = silhouette ? sprite.colors.map { $0.map { _ in PetColor(red: 46, green: 52, blue: 50) } } : sprite.colors
        let scale = max(1, Int((points * displayScale).rounded(.down)))
        if let image = PetRenderer.render(colors: colors, width: sprite.width, height: sprite.height, scale: scale) {
            Image(decorative: image, scale: max(displayScale, 1))
                .interpolation(.none)
        }
    }
}

/// Exhibit A: what the pet left of the object, at a size you can read,
/// with its name.
private struct Evidence: View {
    let kind: PetCamObjectKind

    var body: some View {
        HStack(spacing: 10) {
            ObjectSprite(kind: kind, wrecked: true)
                .padding(6)
                .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "EXHIBIT A")
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
                    .foregroundStyle(CCTV.screen)
                    .padding(.horizontal, 4)
                    .background(CCTV.wanted, in: .rect(cornerRadius: 2))
                Text(verbatim: PetCamCaptions.name(of: kind))
                    .font(CCTV.font(.caption, weight: .bold))
                    .foregroundStyle(CCTV.burnIn.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Exhibit A: what is left of the \(PetCamCaptions.name(of: kind).lowercased())"))
    }
}

/// The lined wall behind a mugshot, a line every few points and a taller
/// one with a mark every fourth.
private struct HeightChart: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.17)))
            var y = size.height - 6
            var index = 0
            while y > 0 {
                let major = index % 4 == 0
                let rect = CGRect(x: 0, y: y, width: size.width, height: major ? 2 : 1)
                context.fill(Path(rect), with: .color(.white.opacity(major ? 0.22 : 0.09)))
                y -= 9
                index += 1
            }
        }
        .accessibilityHidden(true)
    }
}

/// The breed picker: the starter British Shorthair or any other breed.
struct PetPicker: View {
    @Environment(StudyStore.self) private var study
    @Environment(PetCamStore.self) private var cam
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List(PetBreed.allCases, id: \.self) { breed in
                Button {
                    study.setBreed(breed)
                    cam.petChanged(study.pet)
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        PixelPet(canvas: PetComposer.sitting(breed).trimmed(margin: 1),
                                 palette: PetProfile(name: "", breed: breed).palette, pixelSize: 2)
                            .frame(width: 56)
                        Text(breed.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if study.pet.breed == breed {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 52)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(study.pet.breed == breed ? .isSelected : [])
                .id(breed)
            }
            // Opaque, so nothing on the home screen glows through the rows,
            // and opened on the current pet with its checkmark in view.
            .scrollContentBackground(.hidden)
            .background(CCTV.panel)
            .onAppear { proxy.scrollTo(study.pet.breed, anchor: .center) }
            }
            .navigationTitle(Text(verbatim: "Your pet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(CCTV.panel, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .tabbi) }
                }
            }
        }
        .presentationBackground(CCTV.panel)
    }
}
