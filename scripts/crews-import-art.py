#!/usr/bin/env python3
"""Drops a new set of crew crest emblems (and optionally frame slots) into Tabbi.

Usage: scripts/crews-import-art.py emblems.json [frames-patch.json] [--translations names.json]

Crew crests are data: `Sources/TabbiKitCore/Pets/PetArt/crew.json` (format
crewCrests.v1) holds the frames, emblems, palette, crew colors and laurels,
the Mac and Windows apps compose crests from it at run time, and the server
accepts the ids listed in `backend/shared/crews.json`. Swapping the emblem
set therefore changes only data, and this script does all of it:

1. `emblems.json` (a designer's crewEmblems.vN file: `palette` and an
   ordered `emblems` list of `{id, name, grid}`, each grid at most the
   slot's size) replaces the emblems in crew.json in its order; palette
   characters it adds are merged in, and one that means something else in
   crew.json stops the import.
2. `frames-patch.json`, when given, moves frame slots or replaces frame
   grids: `{"frames": {"shield": {"slot": [4, 3]}, ...}}`, a plain
   `{id: {...}}` map or a list of `{id, ...}`. Only `slot` and `grid` are
   read, and only for frames crew.json already has.
3. `backend/shared/crews.json` gets the same frame and emblem ids, in order.
4. Every emblem and frame name is a key in Localizable.xcstrings (the
   builder's tooltips read their titles from the catalog by name). Names
   missing there are written to `crew-art-names.json` beside the input as a
   template for scripts/l10n-add.py; with `--translations`, that filled
   file is added to the catalog and the strings are compiled.

Afterwards re-record the crest fixture the ports replay and run the tests:

    TABBI_RECORD_FIXTURES=1 swift test --filter CrewsGoldenTests
    swift test --filter "Crew|PetArt|Localization"

Crews in the field keep their stored ids: an emblem id that is no longer in
the set draws as the first emblem until the owner picks a new one, so ids
of a set that has shipped should be kept, not renamed.
"""
import argparse
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CREST = ROOT / "Sources/TabbiKitCore/Pets/PetArt/crew.json"
SERVER = ROOT / "backend/shared/crews.json"
CATALOG = ROOT / "Sources/TabbiKitCore/Localization/Localizable.xcstrings"
LANGUAGES = ["ar", "de", "es", "fil", "fr", "ja", "ko", "pt-BR", "ru", "zh-Hans", "zh-Hant"]


def fail(message):
    sys.exit(f"crews-import-art: {message}")


def frame_patches(patch):
    frames = patch.get("frames", patch) if isinstance(patch, dict) else patch
    if isinstance(frames, list):
        return {f["id"]: f for f in frames}
    if isinstance(frames, dict):
        return frames
    fail("frames-patch.json holds no frames")


def check_grid(kind, item, width, height):
    grid = item.get("grid")
    if not isinstance(grid, list) or not grid or any(not isinstance(r, str) for r in grid):
        fail(f"{kind} {item.get('id')} has no grid")
    if len({len(r) for r in grid}) != 1:
        fail(f"{kind} {item.get('id')}: rows of different lengths")
    if len(grid) > height or len(grid[0]) > width:
        fail(f"{kind} {item.get('id')} is {len(grid[0])} x {len(grid)}, more than {width} x {height}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("emblems")
    parser.add_argument("frames_patch", nargs="?")
    parser.add_argument("--translations")
    args = parser.parse_args()

    crest = json.loads(CREST.read_text())
    source = json.loads(pathlib.Path(args.emblems).read_text())
    slot = crest["slot"]

    # Palette: merge, never redefine.
    palette = crest["palette"]
    for char, entry in source.get("palette", {}).items():
        if char in palette and palette[char] != entry:
            fail(f"palette {char!r} is {palette[char]} in crew.json but {entry} in {args.emblems}")
        palette.setdefault(char, entry)

    emblems = []
    seen = set()
    for item in source.get("emblems", []):
        if item.get("id") in seen:
            fail(f"emblem {item.get('id')} twice")
        seen.add(item.get("id"))
        check_grid("emblem", item, slot, slot)
        unknown = {c for row in item["grid"] for c in row if c != "."} - set(palette)
        if unknown:
            fail(f"emblem {item['id']} uses {''.join(sorted(unknown))}, which the palette lacks")
        emblems.append({"id": item["id"], "name": item.get("name", item["id"]), "grid": item["grid"]})
    if not emblems:
        fail(f"{args.emblems} has no emblems")
    crest["emblems"] = emblems

    if args.frames_patch:
        patches = frame_patches(json.loads(pathlib.Path(args.frames_patch).read_text()))
        known = {f["id"]: f for f in crest["frames"]}
        for frame_id, patch in patches.items():
            if frame_id not in known:
                fail(f"frames-patch names {frame_id}, which crew.json does not have")
            if "grid" in patch:
                check_grid("frame", {"id": frame_id, **patch}, crest["grid"], crest["grid"])
                known[frame_id]["grid"] = patch["grid"]
            if "slot" in patch:
                x, y = patch["slot"]
                if x < 0 or y < 0 or x + slot > crest["grid"] or y + slot > crest["grid"]:
                    fail(f"frame {frame_id}: slot {patch['slot']} puts the emblem off the canvas")
                known[frame_id]["slot"] = [x, y]

    CREST.write_text(json.dumps(crest, indent=1, ensure_ascii=False) + "\n")

    server = json.loads(SERVER.read_text())
    server["frames"] = [f["id"] for f in crest["frames"]]
    server["emblems"] = [e["id"] for e in emblems]
    SERVER.write_text(json.dumps(server, indent=2, ensure_ascii=False) + "\n")
    print(f"{len(emblems)} emblems and {len(crest['frames'])} frames in {CREST.relative_to(ROOT)} and {SERVER.relative_to(ROOT)}")

    if args.translations:
        subprocess.run([sys.executable, str(ROOT / "scripts/l10n-add.py"), args.translations], check=True)

    strings = json.loads(CATALOG.read_text())["strings"]
    names = [("emblem", e["name"]) for e in emblems] + [("frame", f["name"]) for f in crest["frames"]]
    missing = {}
    for kind, name in names:
        localized = strings.get(name, {}).get("localizations", {})
        if any(language not in localized for language in LANGUAGES):
            missing[name] = {"comment": f"A crew crest {kind}, named in the crest builder's tooltip.",
                             **{language: "" for language in LANGUAGES}}
    if missing:
        template = pathlib.Path(args.emblems).with_name("crew-art-names.json")
        template.write_text(json.dumps(missing, indent=2, ensure_ascii=False) + "\n")
        print(f"{len(missing)} names need translations: fill {template} and run again with --translations {template}")
    else:
        print("Every name is translated.")
    print("Next: TABBI_RECORD_FIXTURES=1 swift test --filter CrewsGoldenTests")


if __name__ == "__main__":
    main()
