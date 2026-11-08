import CoreGraphics
import Foundation
import ImageIO
import TabbiKitCore
import UniformTypeIdentifiers

// `swift run PetGallery out/ petcam` writes the Pet Cam review sheets:
// every breed in every Pet Cam pose (in the demo look and bare) at 1x and
// 4x, and the frozen frame plus a catch tape and a miss tape, still by
// still, at the size the iPhone draws them.

enum PetCamSheets {
    static let poses: [(String, PetCamPose, Bool)] = [
        ("stare counter", .stare(.counter), false),
        ("stare shelf", .stare(.shelf), false),
        ("stare table", .stare(.table), true),
        ("sneak", .sneak(step: 0), false),
        ("sneak 2", .sneak(step: 1), false),
        ("swipe", .swipe, false),
        ("mid-act", .midAct, false),
        ("mid-act right", .midAct, true),
        ("lens stare", .lensStare, false),
        ("lie down", .lieDown, false),
        ("stroll", .stroll(step: 1), false),
    ]

    static func write(to folder: URL) throws {
        let demo = PetCloset.demo.profile
        for (name, dressed) in [("demo", true), ("bare", false)] {
            for scale in [1, 4] {
                var rows: [[(PetCanvas, PetPalette)]] = []
                for breed in PetBreed.allCases {
                    var profile = PetProfile(name: "", breed: breed, outfit: dressed ? demo.outfit : .none,
                                             accessories: dressed ? demo.accessories : [])
                    profile.bondLook = .none
                    rows.append(poses.map { _, pose, right in
                        (PetCamPetArt.canvas(pose, profile: profile, facingRight: right), profile.palette)
                    })
                }
                try sheet(rows, columns: poses.map(\.0), rowLabels: PetBreed.allCases.map(\.displayName), scale: scale,
                          to: folder.appendingPathComponent("petcam-poses-\(name)-\(scale)x.png"))
            }
        }
        try scenes(to: folder, pet: demo)
    }

    /// A grid of pet frames on a dark ground, one row per breed.
    static func sheet(_ rows: [[(PetCanvas, PetPalette)]], columns: [String], rowLabels: [String], scale: Int,
                      to url: URL) throws {
        let side = PetComposer.frameSize * scale
        let pad = max(4, 4 * scale), label = scale > 1 ? 110 : 0, header = scale > 1 ? 24 : 0
        let width = label + columns.count * (side + pad) + pad
        let height = header + rows.count * (side + pad) + pad
        let context = try canvas(width: width, height: height)
        if scale > 1 {
            for (index, title) in columns.enumerated() {
                draw(title, size: 11, color: CGColor(gray: 1, alpha: 0.7),
                     at: CGPoint(x: label + pad + index * (side + pad), y: height - 16), in: context)
            }
        }
        for (r, row) in rows.enumerated() {
            let y = height - header - (r + 1) * (side + pad)
            if scale > 1 {
                draw(rowLabels[r], size: 11, color: CGColor(gray: 1, alpha: 0.6), at: CGPoint(x: 6, y: y + side / 2),
                     in: context)
            }
            for (c, cell) in row.enumerated() {
                guard let image = PetRenderer.render(cell.0, palette: cell.1, scale: scale) else { continue }
                context.draw(image, in: CGRect(x: label + pad + c * (side + pad), y: y, width: side, height: side))
            }
        }
        try save(context, to: url)
    }

    /// The frozen frame and every still of a catch and a miss.
    static func scenes(to folder: URL, pet: PetProfile) throws {
        let start = Date(timeIntervalSince1970: 1_793_653_200) // a Monday, 21:00 UTC
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var shots: [(String, PetCamShot, Bool)] = []
        for (label, daylight) in [("night", false), ("day", true)] {
            for seed: UInt64 in [3, 5] {
                let game = PetCamGame(seed: seed, at: start)
                shots.append(("home \(label) \(seed)", PetCamShot.frozenFrame(room: game.room, setup: game.setup), daylight))
            }
        }
        // Plays until it has one catch and one miss on every spot.
        var game = PetCamGame(seed: 0x9E7, at: start)
        var seen: Set<String> = []
        var index = 0
        while seen.count < 6, index < 200 {
            let begin = start.addingTimeInterval(Double(index) * 1800)
            let pick = PetCamSpot.allCases[index % 3]
            game.start(id: "g\(index)", pick: pick, dodge: "the tax forms", dare: false, plannedLength: 1500, pet: pet,
                       at: begin)
            if let record = game.finish(endedAt: begin.addingTimeInterval(1500), worked: 1500, calendar: calendar),
               let tape = PetCamTape(record: record) {
                let key = "\(record.outcome.rawValue) \(record.camera.rawValue)"
                if seen.insert(key).inserted {
                    for (n, still) in tape.stills.enumerated() {
                        shots.append(("\(key) \(n + 1)", still.shot, false))
                    }
                }
            }
            index += 1
        }
        for scale in [1, 4] {
            let cellWidth = 100 * scale, cellHeight = 160 * scale, pad = 6 * scale, header = scale > 1 ? 20 : 0
            let columns = 6
            let rows = (shots.count + columns - 1) / columns
            let context = try canvas(width: columns * (cellWidth + pad) + pad, height: rows * (cellHeight + pad + header) + pad)
            for (n, (title, shot, daylight)) in shots.enumerated() {
                let frame = PetCamScene.frame(shot, pet: pet, daylight: daylight)
                // Spot shots are half the size, so they draw at twice the scale.
                let zoom = frame.width == 100 ? scale : scale * 2
                guard let image = frame.image(scale: zoom) else { continue }
                let x = pad + (n % columns) * (cellWidth + pad)
                let y = context.height - (n / columns + 1) * (cellHeight + pad + header)
                context.draw(image, in: CGRect(x: x, y: y, width: frame.width * zoom, height: frame.height * zoom))
                if scale > 1 {
                    draw(title, size: 12, color: CGColor(gray: 1, alpha: 0.7), at: CGPoint(x: x, y: y + cellHeight + 5),
                         in: context)
                    // Each shot on its own too, for a close look.
                    let one = try canvas(width: cellWidth, height: cellHeight)
                    one.draw(image, in: CGRect(x: 0, y: 0, width: cellWidth, height: cellHeight))
                    let slug = title.replacingOccurrences(of: " ", with: "-")
                    try save(one, to: folder.appendingPathComponent("petcam-shot-\(String(format: "%02d", n))-\(slug).png"))
                }
            }
            try save(context, to: folder.appendingPathComponent("petcam-scenes-\(scale)x.png"))
        }
    }

    static func canvas(width: Int, height: Int) throws -> CGContext {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw GalleryError.context
        }
        context.interpolationQuality = .none
        context.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    static func save(_ context: CGContext, to url: URL) throws {
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw GalleryError.encode }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GalleryError.encode }
        print("wrote \(url.path)")
    }
}
