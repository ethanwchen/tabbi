#!/bin/sh
# Builds and runs site/_pet_sprites.swift against the app's TabbiKitCore,
# which writes the demo's pet sprites to site/img/demo. Run from the repo root.
set -eu
swift build --product PetGallery
bin=$(swift build --show-bin-path)
# The tool sits beside TabbiKitCore's resource bundle, where it finds the pet art.
swiftc -O -I "$bin" "$bin/TabbiKitCore.o" site/_pet_sprites.swift -o "$bin/tabbi-pet-sprites"
"$bin/tabbi-pet-sprites" site/img/demo
