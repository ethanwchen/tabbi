import Foundation
import TabbiKitCore

/// The items with a Radiant design, each with a Subtle and a Bold effect.
/// To add an item: one entry here, built from `RadiantPieces`.
enum RadiantCatalog {
    struct Item: Sendable {
        let id: String
        let name: String
        let outfit: PetOutfit
        let accessories: [PetAccessory]
        let subtle: RadiantEffect
        let bold: RadiantEffect

        var petItem: PetItem { outfit == .none ? .accessory(accessories[0]) : .outfit(outfit) }
        var price: Int { petItem.cost }
    }

    typealias P = RadiantPieces
    typealias Shape = RadiantShape

    /// `t` within `range` maps onto `values`, else nil.
    static func during(_ range: Range<Int>, _ value: @escaping @Sendable (Int) -> Int) -> @Sendable (Int) -> Int? {
        { range.contains($0) ? value($0 - range.lowerBound) : nil }
    }

    static let items: [Item] = [sorcerer, wizardHat, crown, dinosaur, astronaut, graduation, rainCloud, whiteCoat]

    // MARK: Blindfolded Sorcerer

    static let sorcerer = Item(
        id: "blindfolded-sorcerer", name: "Blindfolded Sorcerer", outfit: .none, accessories: [.blindfoldedSorcerer],
        subtle: RadiantEffect(
            name: "Moonlit Blindfold", loop: 16,
            summary: [
                "A two-pixel sky blue glint slides along the top of the blindfold, two columns a tick, then rests off the band for three ticks.",
                "Late in the loop one sky blue mote drifts up beside the left cheek and fades.",
            ],
            pieces: [
                P.sweep([.ink], color: .sky, rows: 2) { t in let p = (t * 2 + 8) % 32; return p < 22 ? p : nil },
                P.drift(from: .pet(0, 0.4), path: [(-2, 0), (-2, -1), (-3, -2), (-3, -3), (-2, -4), (-2, -5), (-3, -6)],
                        starts: [9], loop: 16) { age, _ in age < 5 ? Shape.dot(.sky) : Shape.dot(.effectFaint) },
            ]),
        bold: RadiantEffect(
            name: "Orbiting Orb", loop: 16,
            summary: [
                "A small orb of light (a white core with sky blue arms) circles the pet at shoulder height once every 16 ticks, with a two-dot sky blue trail.",
                "On the near half of its orbit it passes in front of the chest with an outline ring, and on the far half it goes behind the head and body.",
                "A wider glint, sky blue with a white leading edge, sweeps the blindfold three columns a tick.",
            ],
            pieces: [
                P.sweep([.ink], color: .sky, width: 2, rows: 3) { t in let p = t * 3 % 48; return p < 24 ? p : nil },
                P.sweep([.ink], color: .effect, rows: 3) { t in let p = t * 3 % 48 + 2; return p < 24 ? p : nil },
                P.orbit(around: .pet(0.5, 0.56), rx: 13, ry: 5, loop: 16, phase: 4, body: Shape.star(.sky),
                        trail: [.sky, .effectFaint]),
            ]))

    // MARK: Wizard Hat

    static let tipPath = [(3, -2), (4, -2), (5, -1), (6, -1), (7, 0), (7, 1), (8, 2), (8, 3), (9, 4), (9, 5)]

    static let wizardHat = Item(
        id: "wizard-hat", name: "Wizard Hat", outfit: .none, accessories: [.wizardHat],
        subtle: RadiantEffect(
            name: "Wishing Star", loop: 12,
            summary: [
                "The center of the hat's gold star shines white for two ticks (the Reduce Motion still keeps it lit).",
                "Once a loop a single speck of stardust leaves the tip and drifts down and away: gold, then white, then faint.",
            ],
            pieces: [
                P.blink([.gold], which: [2], color: .effect, ticks: [0, 1]),
                P.drift(from: .itemTip, path: Array(tipPath.prefix(8)), starts: [3], loop: 12) { age, _ in
                    age < 4 ? Shape.dot(.gold) : age < 5 ? Shape.dot(.effect) : Shape.dot(.effectFaint)
                },
            ]),
        bold: RadiantEffect(
            name: "Stardust Stream", loop: 12,
            summary: [
                "Four stars stream off the hat's tip, one every three ticks, and arc down and away along the same path.",
                "Each is born as a small four-pointed gold star with a white heart, shrinks to a gold speck, turns white and fades out.",
                "The star on the hat twinkles white as each one leaves.",
            ],
            pieces: [
                P.blink([.gold], which: [2], color: .effect, ticks: [0, 3, 6, 9]),
                P.drift(from: .itemTip, path: tipPath, starts: [0, 3, 6, 9], loop: 12) { age, _ in
                    switch age {
                    case 0, 1: Shape.star(.gold)
                    case 2...4: Shape.dot(.gold)
                    case 5, 6, 7: Shape.dot(.effect)
                    default: Shape.dot(.effectFaint)
                    }
                },
            ]))

    // MARK: Tiny Crown

    static let haloArc = [(-7, -1), (-4, -3), (0, -4), (4, -3), (7, -1)]

    static let crown = Item(
        id: "tiny-crown", name: "Tiny Crown", outfit: .none, accessories: [.tinyCrown],
        subtle: RadiantEffect(
            name: "Gem Glints", loop: 16,
            summary: [
                "A white glint hops across the crown's three points, two ticks each.",
                "Then each pink gem flashes white for two ticks, left first, and the crown rests.",
            ],
            pieces: [
                P.hop([.gold], color: .effect, aboveRow: 0.4, group: during(0..<6) { $0 / 2 }),
                P.blink([.heart], which: [0], color: .effect, ticks: [8, 9]),
                P.blink([.heart], which: [-1], color: .effect, ticks: [11, 12]),
            ]),
        bold: RadiantEffect(
            name: "Sparkle Halo", loop: 16,
            summary: [
                "An arc of five gold sparkles floats over the crown like a second, lighter crown; it is part of the still.",
                "A white twinkle runs along the arc left to right, the middle one blooming into a small star, then all five flash white for a tick.",
                "The gems glint as in Subtle.",
            ],
            pieces: haloArc.enumerated().map { n, offset in
                P.at(.item(0.5, 0), offset) { t in
                    if t == 12 { return Shape.dot(.effect) }
                    if t / 2 == n && t < 10 { return n == 2 ? Shape.star(.gold) : Shape.dot(.effect) }
                    return Shape.dot(.gold)
                }
            } + [
                P.blink([.heart], which: [0], color: .effect, ticks: [13, 14]),
                P.blink([.heart], which: [-1], color: .effect, ticks: [14, 15]),
            ]))

    // MARK: Dinosaur Hoodie

    static let leafPath = [(-2, 0), (-2, 1), (-3, 2), (-3, 3), (-2, 4), (-2, 5), (-3, 6), (-3, 7)]

    static let dinosaur = Item(
        id: "dinosaur-hoodie", name: "Dinosaur Hoodie", outfit: .dinosaurHoodie, accessories: [],
        subtle: RadiantEffect(
            name: "Spike Ripple", loop: 16,
            summary: [
                "A white glint ripples over the hood's gold spikes, one spike every two ticks.",
                "Then a little leaf tumbles down beside the pet, turning every two ticks.",
            ],
            pieces: [
                P.hop([.gold], color: .effect, aboveRow: 0.15, group: during(0..<6) { $0 / 2 }),
                P.drift(from: .pet(0, 0.3), path: leafPath, starts: [8], loop: 16) { age, _ in
                    Shape.strip(.leaf, turn: age / 2)
                },
            ]),
        bold: RadiantEffect(
            name: "Tiny Roar", loop: 16,
            summary: [
                "Every loop the dinosaur gives a tiny roar: its spikes all flash white and two curved sound lines burst out on both sides of the head, the inner one first.",
                "Between roars four leaves tumble down on both sides.",
            ],
            pieces: [
                P.hop([.gold], color: .effect, aboveRow: 0.15, group: during(0..<6) { $0 / 2 }),
                P.blink([.gold], which: Array(0..<12), color: .effect, ticks: [8, 9]),
                P.drift(from: .pet(0, 0.45), path: [(-2, 0), (-2, 0), (-4, 0), (-4, 0), (-4, 0)], starts: [8, 8],
                        loop: 16, mirror: true) { age, _ in
                    age < 2 ? [(0, -1, .effect), (-1, 0, .effect), (0, 1, .effect)]
                        : age < 4 ? [(1, -2, .effect), (0, -1, .effect), (0, 0, .effect), (0, 1, .effect), (1, 2, .effect)]
                        : [(1, -2, .effectFaint), (0, -1, .effectFaint), (0, 0, .effectFaint), (0, 1, .effectFaint),
                           (1, 2, .effectFaint)]
                },
                P.drift(from: .pet(0, 0.2), path: leafPath, starts: [0, 2, 13, 15], loop: 16, mirror: true) { age, _ in
                    Shape.strip(.leaf, turn: age / 2)
                },
            ]))

    // MARK: Astronaut Helmet

    /// A ringed planet: a sky blue disc with a white highlight and a gold ring.
    static let planet: [(Int, Int, PetPaletteRole)] = [
        (0, -1, .sky), (1, -1, .sky),
        (-1, 0, .sky), (0, 0, .effect), (1, 0, .sky), (2, 0, .sky),
        (-2, 1, .gold), (-1, 1, .gold), (0, 1, .gold), (1, 1, .gold), (2, 1, .gold), (3, 1, .gold),
        (0, 2, .sky), (1, 2, .sky),
    ]

    static let astronaut = Item(
        id: "astronaut-helmet", name: "Astronaut Helmet", outfit: .none, accessories: [.astronautHelmet],
        subtle: RadiantEffect(
            name: "Visor Glint", loop: 16,
            summary: [
                "The visor's white reflection slides across the glass as a two-pixel slanted glint, then returns to its place.",
                "While it rests, the red light on the antenna blinks white.",
            ],
            pieces: [
                P.blink([.effect], which: [0, 1, 2], color: .ink, ticks: Set(2..<9)),
                P.sweep([.ink, .effect], color: .effect, rows: 2, position: during(2..<9) { $0 * 2 + 3 }),
                P.blink([.heart], which: [0], color: .effect, ticks: [11, 12]),
            ]),
        bold: RadiantEffect(
            name: "Tiny Planet", loop: 24,
            summary: [
                "A ringed sky blue planet floats beside the helmet, and a white moon circles it every 12 ticks, hidden behind the planet on the far side.",
                "Two stars twinkle on the other side of the pet, and the visor glint and antenna light play as in Subtle.",
            ],
            pieces: [
                P.blink([.effect], which: [0, 1, 2], color: .ink, ticks: Set(2..<9)),
                P.sweep([.ink, .effect], color: .effect, rows: 2, position: during(2..<9) { $0 * 2 + 3 }),
                P.blink([.heart], which: [0], color: .effect, ticks: [11, 12, 23]),
                planetWithMoon(.offset(.pet(1, 0), -1, -4)),
                P.at(.pet(0, 0.12), (-2, 0)) { t in
                    t % 12 < 2 ? Shape.star(.gold) : t % 12 < 8 ? Shape.dot(.gold) : nil
                },
                P.at(.pet(0, 0.42), (-3, 0)) { t in
                    (t + 6) % 12 < 2 ? Shape.dot(.effect) : (t + 6) % 12 < 8 ? Shape.dot(.effectFaint) : nil
                },
            ]))

    /// The planet with its moon: the moon goes on before the planet on the
    /// far half of its orbit (so the planet hides it) and after it on the
    /// near half.
    static func planetWithMoon(_ anchor: RadiantAnchor) -> RadiantPiece {
        { scene, tick in
            var layer = RadiantLayer()
            guard let c = anchor.point(in: scene) else { return layer }
            let angle = 2 * Double.pi * Double(tick % 12) / 12
            let moon = PetPoint(x: c.x + 1 + Int((4 * cos(angle)).rounded()), y: c.y + 1 + Int((2 * sin(angle)).rounded()))
            let body = RadiantParticle(pixels: planet.map { (PetPoint(x: c.x + $0.0, y: c.y + $0.1), $0.2) })
            let covered = planet.contains { c.x + $0.0 == moon.x && c.y + $0.1 == moon.y }
            layer.particles.append(body)
            // On the near side the moon passes over the planet; on the far
            // side the planet hides it.
            if sin(angle) > 0 || !covered {
                layer.particles.append(RadiantParticle(pixels: [(moon, sin(angle) > 0 ? .effect : .metal)]))
            }
            return layer
        }
    }

    // MARK: Graduation Cap

    @Sendable static func tassel(_ scene: RadiantScene) -> ClosedRange<Int> {
        guard let box = scene.itemBox else { return 0...0 }
        return (box.midX + 3)...(box.maxX + 1)
    }

    static let swingSteps = [0, 1, 1, 0, 0, -1, -1, 0]

    static let confettiColors: [PetPaletteRole] = [.gold, .heart, .sky, .leaf, .violet, .effect]
    static let confettiPaths: [[(Int, Int)]] = [
        [(-3, -2), (-6, -3), (-9, -3), (-11, -2), (-12, 0), (-13, 2), (-12, 4), (-13, 6), (-12, 8), (-13, 10), (-12, 12),
         (-13, 14), (-12, 16), (-13, 18)],
        [(-2, -3), (-5, -3), (-8, -3), (-10, -2), (-12, -1), (-12, 1), (-13, 3), (-12, 5), (-13, 7), (-12, 9), (-13, 11),
         (-12, 13), (-13, 15)],
        [(-1, -2), (-3, -3), (-5, -3), (-7, -3), (-9, -2), (-11, -1), (-12, 1), (-13, 3), (-12, 5), (-13, 7), (-12, 9),
         (-13, 11), (-12, 13)],
    ]

    static let graduation = Item(
        id: "graduation-cap", name: "Graduation Cap", outfit: .none, accessories: [.graduationCap],
        subtle: RadiantEffect(
            name: "Tassel Swing", loop: 16,
            summary: [
                "The lower two pixels of the gold tassel swing a pixel to each side and back, every eight ticks.",
                "The button on top of the cap holds a white glint (baked into the still) that goes out while the tassel swings.",
            ],
            pieces: [
                P.blink([.gold], which: [0], color: .effect, ticks: [0, 3, 4, 7, 8, 11, 12, 15]),
                P.swing([.gold], column: tassel, fromRow: 1) { swingSteps[$0 % 8] },
            ]),
        bold: RadiantEffect(
            name: "Confetti Toss", loop: 16,
            summary: [
                "Six pieces of confetti (gold, pink, sky blue, green, violet and white) pop up from the cap, three to each side, and flutter down beside the pet, turning every tick.",
                "The tassel swings as in Subtle.",
            ],
            pieces: [
                P.blink([.gold], which: [0], color: .effect, ticks: [0, 3, 4, 7, 8, 11, 12, 15]),
                P.swing([.gold], column: tassel, fromRow: 1) { swingSteps[$0 % 8] },
            ] + (0..<6).map { n in
                let piece = P.drift(from: .item(0.5, 0), path: confettiPaths[n / 2], starts: [n / 2], loop: 16) { age, _ in
                    Shape.strip(confettiColors[n], turn: age)
                }
                // Every other piece goes to the right.
                return n % 2 == 0 ? piece : mirrored(piece)
            }))

    /// A drift piece sent the other way: its particles mirrored about the
    /// item's center column.
    static func mirrored(_ piece: @escaping RadiantPiece) -> RadiantPiece {
        { scene, tick in
            var layer = piece(scene, tick)
            guard let box = scene.itemBox else { return layer }
            let axis = box.minX + box.maxX
            layer.particles = layer.particles.map { particle in
                var copy = particle
                copy.pixels = particle.pixels.map { (PetPoint(x: axis - $0.0.x, y: $0.0.y), $0.1) }
                return copy
            }
            return layer
        }
    }

    // MARK: Tiny Rain Cloud

    static let rainbow = [
        "......HHHHHHH......",
        "....HHYYYYYYYHH....",
        "...HYYFFFFFFFYYH...",
        "..HYFFkkkkkkkFFYH..",
        ".HYFkk.......kkFYH.",
        ".HYFk.........kFYH.",
        "HYFk...........kFYH",
    ]

    /// The rainbow from the cloud's right side arching over toward the
    /// head, its columns up to `reveal(tick)` shown (counted from the
    /// cloud), or from `from(tick)` on as it fades.
    static func rainbowPiece(show: @escaping @Sendable (Int) -> Range<Int>?) -> RadiantPiece {
        { scene, tick in
            var layer = RadiantLayer()
            guard let columns = show(tick),
                  let origin = RadiantAnchor.itemRole(.coat, 1, 0).point(in: scene) else { return layer }
            var pixels: [(PetPoint, PetPaletteRole)] = []
            for (y, row) in rainbow.enumerated() {
                for (x, symbol) in row.enumerated() where symbol != "." && columns.contains(x) {
                    let role: PetPaletteRole = switch symbol {
                    case "H": .heart
                    case "Y": .gold
                    case "F": .leaf
                    default: .sky
                    }
                    pixels.append((PetPoint(x: origin.x - 3 + x, y: origin.y + 2 + y), role))
                }
            }
            layer.particles.append(RadiantParticle(pixels: pixels, mode: .behindItem))
            return layer
        }
    }

    static let rainCloud = Item(
        id: "tiny-rain-cloud", name: "Tiny Rain Cloud", outfit: .none, accessories: [.rainCloud],
        subtle: RadiantEffect(
            name: "Silver Lining", loop: 16,
            summary: [
                "A white glint runs along the cloud's grey underside, a pixel a tick, then rests at its left end.",
                "Once a loop the top of the cloud catches a white glint for two ticks.",
                "The drops keep falling as on the normal cloud.",
            ],
            pieces: [
                P.sweep([.coatShade], color: .effect, rows: 2, slope: 0) { t in t < 8 ? t : 0 },
                P.blink([.coat], which: [1], color: .effect, ticks: [11, 12]),
            ]),
        bold: RadiantEffect(
            name: "Rainbow After Rain", loop: 24,
            summary: [
                "A four-band rainbow (pink, gold, green, sky blue) arches from the cloud over toward the pet's head and passes behind it; the still shows it whole.",
                "It holds, dissolves from the cloud outward, the cloud flickers with a tiny gold bolt of lightning, and the rainbow grows back from the cloud.",
            ],
            pieces: [
                rainbowPiece { t in
                    switch t {
                    case 0..<12: 0..<19
                    case 12..<16: min((t - 11) * 5, 19)..<19
                    case 16..<18: nil
                    default: 0..<((t - 17) * 4)
                    }
                },
                P.blink([.coatShade], which: Array(0..<9), color: .effect, ticks: [16]),
                P.at(.itemRole(.coat, 0.5, 1), (0, 2), mode: .behindItem) { t in
                    t == 16 || t == 17 ? [(0, 0, .gold), (-1, 1, .gold), (0, 2, .gold), (-1, 3, .gold)] : nil
                },
            ]))

    // MARK: White Coat

    static let pulse = [0, 0, 0, 0, 0, 0, -1, -3, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    /// A heartbeat trace written left to right above the head, `window`
    /// columns long, with a bright pen at its head.
    static func heartbeat(window: Int, step: Int, loop: Int) -> RadiantPiece {
        { scene, tick in
            var layer = RadiantLayer()
            guard let pet = scene.petBox else { return layer }
            let baseline = pet.minY - 3
            let left = pet.minX + 1
            let pen = tick * step % (loop * step)
            var pixels: [(PetPoint, PetPaletteRole)] = []
            for i in max(0, pen - window)...pen where i < pulse.count {
                let y = baseline + pulse[i]
                let previous = i > 0 ? baseline + pulse[i - 1] : y
                let role: PetPaletteRole = i == pen ? .effect : i < pen - window / 2 ? .effectFaint : .leaf
                // A vertical run joins a jump, so the trace stays one line.
                for row in min(y, previous)...max(y, previous) {
                    pixels.append((PetPoint(x: left + i, y: row), role))
                }
            }
            layer.particles.append(RadiantParticle(pixels: pixels, mode: .behind))
            return layer
        }
    }

    static let coatGlint = P.sweep([.coatShade], color: .sky, slope: 1, slant: 0, near: 1) { t in t < 5 ? t : 0 }

    static let whiteCoat = Item(
        id: "white-coat", name: "White Coat", outfit: .whiteCoat, accessories: [],
        subtle: RadiantEffect(
            name: "Lapel Glint", loop: 16,
            summary: [
                "A sky blue gleam runs down the coat's lapel seam, a row a tick, and rests at the collar (white on the white coat would not show).",
                "While it rests a small pink plus sign pops up beside the pet, rises two pixels and fades.",
            ],
            pieces: [
                coatGlint,
                P.drift(from: .pet(1, 0.45), path: [(2, 0), (2, -1), (2, -2), (2, -3)], starts: [10], loop: 16) { age, _ in
                    age == 0 ? Shape.dot(.heart) : age < 3 ? Shape.plus(.heart) : Shape.dot(.effectFaint)
                },
            ]),
        bold: RadiantEffect(
            name: "Heartbeat", loop: 24,
            summary: [
                "A green heartbeat trace is written left to right above the head with a white pen at its tip, its tail fading out, and its pulse spikes once on the way.",
                "Pink and sky blue plus signs rise on both sides of the pet, and the lapel glint plays as in Subtle.",
            ],
            pieces: [
                coatGlint,
                heartbeat(window: 8, step: 1, loop: 24),
                P.drift(from: .pet(0, 0.55), path: [(-2, 0), (-2, -1), (-2, -2), (-2, -3), (-2, -4), (-2, -5)],
                        starts: [2, 8, 14, 20], loop: 24, mirror: true) { age, n in
                    let role: PetPaletteRole = n % 2 == 0 ? .heart : .sky
                    return age == 0 ? Shape.dot(role) : age < 4 ? Shape.plus(role) : Shape.dot(.effectFaint)
                },
            ]))
}
