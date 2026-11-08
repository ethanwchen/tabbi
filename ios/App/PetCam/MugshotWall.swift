import SwiftUI
import TabbiKitCore

/// Every catch as a mugshot: the pet staring into the lens in front of a
/// height chart, with its case number, the date and the charge (the dodge
/// line, or what it did). Tapping one replays its tape exactly.
struct MugshotWall: View {
    @Environment(PetCamStore.self) private var cam
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var replaying: PetCamBlockRecord?

    var body: some View {
        NavigationStack {
            ScrollView {
                if cam.mugshots.isEmpty {
                    empty
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 280 : 160), spacing: 14,
                                                 alignment: .top)],
                              alignment: .center, spacing: 14) {
                        ForEach(Array(cam.mugshots.enumerated()), id: \.element.id) { offset, record in
                            Button { replaying = record } label: {
                                MugshotCard(record: record, caseNumber: cam.mugshots.count - offset)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text(verbatim: "Plays the tape again"))
                        }
                    }
                    .padding(16)
                }
            }
            .background(CCTV.screen.ignoresSafeArea())
            .navigationTitle(Text(verbatim: "Mugshots"))
            .navigationBarTitleDisplayMode(.inline)
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
            Text(verbatim: "No mugshots yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(CCTV.burnIn)
            Text(verbatim: "Hide the camera where your pet strikes and catch it in the act. Every catch gets a mugshot here.")
                .font(.body)
                .foregroundStyle(CCTV.burnIn.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
    }
}

/// One mugshot: the pet's front and side in front of a height chart, its
/// face different from case to case, and the placard with the evidence.
struct MugshotCard: View {
    let record: PetCamBlockRecord
    let caseNumber: Int

    var body: some View {
        VStack(spacing: 0) {
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
                    Text(verbatim: charge)
                        .font(CCTV.font(.footnote, weight: .semibold))
                        .foregroundStyle(CCTV.burnIn)
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
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CCTV.burnIn.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }

    private var front: some View {
        PixelPet(canvas: PetCamPetArt.mugshot(caseNumber - 1, profile: record.pet).trimmed(margin: 1),
                 palette: record.pet.palette, pixelSize: 3)
    }

    private var side: some View {
        PixelPet(canvas: PetCamPetArt.mugshotProfile(record.pet).trimmed(margin: 1), palette: record.pet.palette,
                 pixelSize: 3)
    }
}

/// Exhibit A: the object the pet went for, whole, at a size you can read,
/// with its name.
private struct Evidence: View {
    let kind: PetCamObjectKind
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let sprite = PetCamScene.sprite(kind, wrecked: false)
        let scale = max(1, Int((3 * displayScale).rounded(.down)))
        HStack(spacing: 10) {
            if let image = PetRenderer.render(colors: sprite.colors, width: sprite.width, height: sprite.height,
                                              scale: scale) {
                Image(decorative: image, scale: max(displayScale, 1))
                    .interpolation(.none)
                    .padding(6)
                    .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 6, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "EXHIBIT A")
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
                    .foregroundStyle(CCTV.screen)
                    .padding(.horizontal, 4)
                    .background(Color(red: 0.95, green: 0.84, blue: 0.45), in: .rect(cornerRadius: 2))
                Text(verbatim: PetCamCaptions.name(of: kind))
                    .font(CCTV.font(.caption, weight: .bold))
                    .foregroundStyle(CCTV.burnIn.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Exhibit A: \(PetCamCaptions.name(of: kind).lowercased())"))
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
            }
            .navigationTitle(Text(verbatim: "Your pet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .tabbi) }
                }
            }
        }
    }
}
