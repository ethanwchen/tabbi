import Foundation

/// A focus sound blend the user saved under a name, so a favorite scene
/// ("Rainy cafe") comes back with one tap.
public struct FocusMixPreset: Codable, Equatable, Sendable {
    /// Long enough for a word or two, short enough for a small chip.
    public static let maxNameLength = 18

    public var name: String
    public var mix: FocusMix

    /// A blank name falls back to `defaultName(for:)`; a long one is cut.
    public init(name: String, mix: FocusMix) {
        self.mix = mix
        self.name = Self.cleaned(name) ?? Self.defaultName(for: mix)
    }

    /// The name a fresh preset gets: its loudest sound, plus how many others
    /// play with it ("Rain +1"), so three presets still read apart at a glance.
    public static func defaultName(for mix: FocusMix) -> String {
        guard let main = mix.layers.max(by: { $0.level < $1.level }) else { return "Off" }
        let others = mix.layers.count - 1
        return others > 0 ? "\(main.sound.displayName) +\(others)" : main.sound.displayName
    }

    /// `name` trimmed and cut to `maxNameLength`, or nil when nothing is left.
    static func cleaned(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
    }

    private enum CodingKeys: String, CodingKey { case name, mix }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
                  mix: try container.decode(FocusMix.self, forKey: .mix))
    }
}

/// The user's saved blends: `slotCount` fixed slots, each empty or holding
/// a preset. Slots keep their place, so deleting the first preset leaves a
/// gap rather than moving the others under the pointer.
///
/// A preset never holds an Off mix: there is nothing to bring back.
public struct FocusMixPresets: Codable, Equatable, Sendable {
    /// Three is enough for a few favorite scenes and keeps the row tiny.
    public static let slotCount = 3

    public static let empty = FocusMixPresets()

    /// Always `slotCount` long.
    public private(set) var slots: [FocusMixPreset?]

    /// Pads or cuts `slots` to `slotCount` and empties any slot whose mix is Off.
    public init(_ slots: [FocusMixPreset?] = []) {
        let kept = slots.prefix(Self.slotCount).map { $0?.mix.isOff == false ? $0 : nil }
        self.slots = kept + Array(repeating: nil, count: Self.slotCount - kept.count)
    }

    public var isEmpty: Bool { slots.allSatisfy { $0 == nil } }

    /// The first slot holding `mix` exactly, for marking the preset in use.
    public func slot(matching mix: FocusMix) -> Int? {
        guard !mix.isOff else { return nil }
        return slots.firstIndex { $0?.mix == mix }
    }

    /// Saves `mix` into the empty `slot` under its default name. Returns
    /// false (and changes nothing) when the slot is taken or out of range,
    /// or the mix is Off.
    @discardableResult
    public mutating func save(_ mix: FocusMix, into slot: Int) -> Bool {
        guard slots.indices.contains(slot), slots[slot] == nil, !mix.isOff else { return false }
        slots[slot] = FocusMixPreset(name: "", mix: mix)
        return true
    }

    /// Renames the preset in `slot`. A blank name restores the default, so a
    /// preset never ends up as an unlabeled chip.
    public mutating func rename(_ slot: Int, to name: String) {
        guard slots.indices.contains(slot), let preset = slots[slot] else { return }
        slots[slot] = FocusMixPreset(name: name, mix: preset.mix)
    }

    /// Empties `slot`.
    public mutating func delete(_ slot: Int) {
        guard slots.indices.contains(slot) else { return }
        slots[slot] = nil
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey { case slots }

    /// Lenient: a slot that can't be read comes back empty and the others
    /// survive.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let slots = try container.decodeIfPresent([LenientSlot].self, forKey: .slots) ?? []
        self.init(slots.map(\.preset))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slots, forKey: .slots)
    }

    private struct LenientSlot: Decodable {
        let preset: FocusMixPreset?
        init(from decoder: Decoder) throws {
            preset = try? FocusMixPreset(from: decoder)
        }
    }
}
