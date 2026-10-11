#!/usr/bin/env python3
"""Adds or updates strings in Tabbi's String Catalog from a compact JSON file.

Usage: scripts/l10n-add.py [--merge] strings.json   (or pipe the JSON on stdin)

The input maps each English key to its comment and one translation per
language:

    {
      "Skip Setup": {
        "comment": "Onboarding button that ends setup early.",
        "de": "Überspringen", "es": "Omitir", ...
      },
      "%lld cards due": {
        "comment": "Anki progress line.",
        "en": {"one": "%lld card due", "other": "%lld cards due"},
        "de": {"one": "%lld Karte fällig", "other": "%lld Karten fällig"}, ...
      }
    }

A string value is a plain translation; an object is a plural variation
(`one`, `other`, `few`, ...). "en" is needed only for an English plural.
"shouldTranslate": false marks a string that stays as is (a brand name).
"generatesSymbol": false is for a key Xcode cannot turn into a Swift symbol:
one with no letters ("%@: %@") or one that differs from another only in case
or punctuation ("Checking" and "Checking…"); Xcode rejects those otherwise.
With --merge, each key must already be in the catalog, and only the
languages given are set; its comment, flags and other languages stay. That
is how a new language is added to every string at once.
The catalog is written back sorted, in the layout Xcode uses, so diffs stay
small, and scripts/compile-strings.sh then compiles it into the .lproj
folders the app ships. `swift test` (LocalizationTests) checks every language
is there and the compiled folders match the catalog.
"""
import json
import pathlib
import subprocess
import sys

SCRIPTS = pathlib.Path(__file__).resolve().parent
CATALOG = SCRIPTS.parent / "Sources/TabbiKitCore/Localization/Localizable.xcstrings"
LANGUAGES = ["en", "de", "es", "fr", "fil", "ja", "ko", "pt-BR", "ru", "zh-Hans", "zh-Hant"]


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def localization(value):
    if isinstance(value, str):
        return unit(value)
    return {"variations": {"plural": {form: unit(text) for form, text in value.items()}}}


def main():
    arguments = sys.argv[1:]
    merge = "--merge" in arguments
    arguments = [argument for argument in arguments if argument != "--merge"]
    source = open(arguments[0], encoding="utf-8") if arguments else sys.stdin
    entries = json.load(source)
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog["strings"]
    if merge:
        unknown = [key for key in entries if key not in strings]
        if unknown:
            sys.exit(f"--merge: not in the catalog: {unknown[:5]}")
    for key, spec in entries.items():
        if merge:
            localizations = strings[key].setdefault("localizations", {})
            for lang in LANGUAGES:
                if lang in spec:
                    localizations[lang] = localization(spec[lang])
            continue
        entry = {"extractionState": "manual"}
        if spec.get("comment"):
            entry["comment"] = spec["comment"]
        if spec.get("shouldTranslate") is False:
            entry["shouldTranslate"] = False
        if spec.get("generatesSymbol") is False:
            entry["generatesSymbol"] = False
        localizations = {lang: localization(spec[lang]) for lang in LANGUAGES if lang in spec}
        if localizations:
            entry["localizations"] = localizations
        strings[key] = entry
    text = json.dumps(catalog, indent=2, separators=(",", " : "), ensure_ascii=False, sort_keys=True)
    CATALOG.write_text(text + "\n", encoding="utf-8")
    print(f"{len(entries)} strings written, {len(strings)} in the catalog")
    subprocess.run([SCRIPTS / "compile-strings.sh"], check=True)


if __name__ == "__main__":
    main()
