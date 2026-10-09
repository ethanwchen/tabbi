import Foundation
import XCTest
@testable import TabbiKitCore

/// The JSON Schema files in `shared/schemas/` for formats that were already
/// data (kits, editions, the Party catalog) agree with the Swift that reads
/// them, so a TypeScript client validating with them accepts the files the
/// Mac app accepts. The bundled files themselves are checked against the
/// schemas with a JSON Schema validator (see `shared/README.md`).
final class SharedSchemaTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func json(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent(path))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], path)
    }

    private func schema(_ name: String) throws -> [String: Any] {
        try json("shared/schemas/\(name).v1.schema.json")
    }

    /// Whether `value` matches a schema `pattern` (unanchored, as JSON
    /// Schema reads it).
    private func matches(_ pattern: Any?, _ value: String) throws -> Bool {
        let regex = try NSRegularExpression(pattern: XCTUnwrap(pattern as? String))
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    // MARK: Kits

    private func object(_ node: Any?, _ key: String) -> [String: Any] {
        (node as? [String: Any])?[key] as? [String: Any] ?? [:]
    }

    private func properties(_ node: Any?) -> Set<String> {
        Set(object(node, "properties").keys)
    }

    private func encodedKeys(_ value: some Encodable) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]
        return Set(try XCTUnwrap(object).keys)
    }

    /// A kit that sets every field the format has.
    private var fullKit: KitManifest {
        let answer = KitAnswer(id: "yes", label: "Yes", symbol: "checkmark", enables: ["anki"],
                               disables: ["system"], tasks: ["Sync Anki"])
        return KitManifest(
            version: "1.0", requires: KitRequirements(modules: ["study"]), id: "full", name: "Full",
            summary: "Every field.", symbol: "star", accent: "study",
            modules: [KitModuleEntry("study"), KitModuleEntry("anki", enabled: false)],
            defaults: KitDefaults(ticker: ["focus"], theme: "midnight", moduleSettings: ["study": ["method": "pomodoro"]]),
            onboarding: [KitQuestion(id: "anki", prompt: "Anki?", allowsMultiple: true, options: [answer])],
            starterTasks: ["Plan the week"], pickerOrder: 3
        )
    }

    /// Every field Swift reads is in the schema, and the schema names no
    /// field Swift ignores; old `defaults` names are marked deprecated.
    func testKitSchemaHasTheFieldsSwiftReads() throws {
        let schema = try schema("kit")
        let defs = schema["$defs"]
        let kit = fullKit
        XCTAssertEqual(properties(schema), try encodedKeys(kit))
        XCTAssertEqual(properties(object(schema, "properties")["requires"]), try encodedKeys(kit.requires))
        XCTAssertEqual(properties(object(defs, "question")), try encodedKeys(kit.onboarding[0]))
        XCTAssertEqual(properties(object(defs, "answer")), try encodedKeys(kit.onboarding[0].options[0]))
        let entry = try XCTUnwrap(((object(schema, "properties")["modules"] as? [String: Any])?["items"]
            as? [String: Any])?["oneOf"] as? [[String: Any]])
        XCTAssertEqual(properties(entry[1]), try encodedKeys(kit.modules[1]))

        let defaults = object(defs, "defaults")
        let legacy = Set(KitLegacyField.all.map(\.name))
        XCTAssertEqual(properties(defaults), try encodedKeys(kit.defaults).union(legacy))
        for name in legacy {
            XCTAssertEqual(object(defaults, "properties")[name].flatMap { ($0 as? [String: Any])?["deprecated"] as? Bool },
                           true, name)
        }
        XCTAssertEqual(Set(schema["required"] as? [String] ?? []), ["formatVersion", "id", "name", "modules"])
    }

    /// The schema's limits are `KitLimits` and its version range is the
    /// one this build reads.
    func testKitSchemaLimitsMatchSwift() throws {
        let schema = try schema("kit")
        let top = object(schema, "properties")
        let defs = schema["$defs"]
        func number(_ node: Any?, _ key: String) -> Int? { (node as? [String: Any])?[key] as? Int }
        XCTAssertEqual(number(top["formatVersion"], "minimum"), 1)
        XCTAssertEqual(number(top["formatVersion"], "maximum"), KitManifest.currentFormatVersion)
        XCTAssertEqual(number(top["version"], "maxLength"), KitLimits.maxVersionLength)
        XCTAssertEqual(number(top["summary"], "maxLength"), KitLimits.maxTextLength)
        XCTAssertEqual(number(top["modules"], "maxItems"), KitLimits.maxModules)
        XCTAssertEqual(number(top["onboarding"], "maxItems"), KitLimits.maxQuestions)
        XCTAssertEqual(number(object(defs, "name"), "maxLength"), KitLimits.maxNameLength)
        XCTAssertEqual(number(object(defs, "tasks"), "maxItems"), KitLimits.maxTasks)
        XCTAssertEqual(number(object(object(defs, "tasks"), "items"), "maxLength"), KitLimits.maxTaskLength)
        let question = object(object(defs, "question"), "properties")
        XCTAssertEqual(number(question["prompt"], "maxLength"), KitLimits.maxTextLength)
        XCTAssertEqual(number(question["options"], "maxItems"), KitLimits.maxOptions)
        XCTAssertEqual(number(object(object(defs, "answer"), "properties")["label"], "maxLength"),
                       KitLimits.maxNameLength)
    }

    /// The id and name patterns accept exactly what `KitManifest.decode`
    /// accepts.
    func testKitSchemaPatternsMatchSwift() throws {
        let top = object(try schema("kit"), "properties")
        let namePattern = object(try schema("kit")["$defs"], "name")["pattern"]
        func decodes(id: String = "deck", name: String = "Deck") -> Bool {
            let kit = ["formatVersion": 1, "id": id, "name": name, "modules": ["study"]] as [String: Any]
            return (try? KitManifest.decode(from: JSONSerialization.data(withJSONObject: kit))) != nil
        }
        let ids = ["deep-work", "a", "law-school-2", "-", String(repeating: "a", count: 64),
                   String(repeating: "a", count: 65), "", "Deep", "deep_work", "deep work", "d\u{E9}ep", "deep.work"]
        for id in ids {
            XCTAssertEqual(try matches(object(top, "id")["pattern"], id), decodes(id: id), id)
        }
        for name in ["Deep Work", " x ", "x", "", " ", "\t\n", "\u{00A0}"] {
            XCTAssertEqual(try matches(namePattern, name), decodes(name: name), name.debugDescription)
        }
    }

    // MARK: Editions

    /// The edition schema's patterns and reserved Info.plist keys accept
    /// exactly what `Edition.decode` accepts.
    func testEditionSchemaMatchesSwift() throws {
        let schema = try schema("edition")
        let top = object(schema, "properties")
        XCTAssertEqual(object(schema, "properties")["formatVersion"].flatMap { ($0 as? [String: Any])?["maximum"] as? Int },
                       Edition.formatVersion)
        func decodes(_ field: String, _ value: Any) -> Bool {
            var edition: [String: Any] = ["formatVersion": 1, "id": "tabbi", "name": "Tabbi",
                                          "bundleIdentifier": "dev.tabbi.Tabbi", "defaultKitID": "essentials"]
            edition[field] = value
            return (try? Edition.decode(from: JSONSerialization.data(withJSONObject: edition))) != nil
        }
        let samples: [String: [String]] = [
            "id": ["tabbi", "med-school", "a1", "Tabbi", "-tabbi", "tabbi-", "med--school", "", "med_school"],
            "name": ["Tabbi", "Tabbi Med", "T", "", " Tabbi", "Tabbi ", "Tab/bi", ".Tabbi", "Tab.bi"],
            "bundleIdentifier": ["dev.tabbi.Tabbi", "a.b", "dev.tabbi-med.App", "Tabbi", "dev..tabbi", "dev.tabbi.", "dev.tab bi"],
            "icon": ["AppIcon.icns", "Med.icns", "a.b.icns", ".icns", "Icon.png", "Icons/Med.icns", ".Med.icns"],
        ]
        for (field, values) in samples {
            for value in values {
                XCTAssertEqual(try matches(object(top, field)["pattern"], value), decodes(field, value), "\(field) \(value)")
            }
        }
        XCTAssertFalse(decodes("defaultKitID", ""))

        let reserved = try XCTUnwrap((object(object(top, "infoPlist"), "propertyNames")["not"]
            as? [String: Any])?["enum"] as? [String])
        XCTAssertTrue(reserved.contains(Edition.infoKey))
        for key in reserved { XCTAssertFalse(decodes("infoPlist", [key: "x"]), key) }
        XCTAssertTrue(decodes("infoPlist", ["NSCalendarsUsageDescription": "x"]))
    }

    // MARK: Catalog

    /// The schema requires every field the catalog has and every limit the
    /// Worker reads, so a field dropped from either side fails here.
    func testCatalogSchemaCoversTheCatalog() throws {
        let schema = try schema("catalog")
        let catalog = try json("backend/shared/catalog.json")
        XCTAssertEqual(Set(schema["required"] as? [String] ?? []), Set(catalog.keys))
        XCTAssertEqual(properties(schema), Set(catalog.keys))
        let limits = object(object(schema, "properties"), "limits")
        let fileLimits = try XCTUnwrap(catalog["limits"] as? [String: Any])
        XCTAssertEqual(Set(limits["required"] as? [String] ?? []), Set(fileLimits.keys))
        XCTAssertEqual(properties(limits), Set(fileLimits.keys))
        let id = object(schema["$defs"], "id")["pattern"]
        for key in ["species", "costumes", "accessories", "statuses", "studyMethods"] {
            for value in try XCTUnwrap(catalog[key] as? [String], key) {
                XCTAssertTrue(try matches(id, value), "\(key) \(value)")
            }
        }
    }
}
