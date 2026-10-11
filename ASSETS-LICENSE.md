# Asset license

This file explains how Tabbi's artwork is licensed.
It does not change the license of anything that already exists.

## Everything shipped so far stays MIT

All of Tabbi's code, and all of its artwork, is licensed under the [MIT License](LICENSE).
That includes every pet, breed, costume, limited edition item (the Founder's Pin among them), theme, icon, sound, screenshot and image in this repository up to and including the commit that added this file.
Anything added later stays MIT too, unless it is marked as paid content in the way described below.
Nothing in this file takes back, narrows or adds conditions to the rights the MIT License already gave anyone.

## Paid artwork added later

Tabbi may one day offer an optional supporter tier, Tabbi Plus, with cosmetic items.
Artwork made for it is licensed separately:

- Copyright (c) Ethan Chen. All rights reserved.
- It is not covered by the MIT License, even though it sits in the same repository as MIT code.
- You may view it here and build Tabbi from source with it for your own personal use.
- You may not copy, redistribute, sell, sublicense or reuse it in other projects, or ship it in a build or fork that you distribute, without written permission.

The code that draws, loads or unlocks paid artwork is still MIT.
Only the paid artwork itself is reserved.

## How paid artwork is marked

Paid artwork is marked by where it lives: only files inside a directory named `Plus` (for example `Sources/TabbiKitCore/Pets/PetArt/Plus/`) are paid artwork.
Each such directory will also hold a `LICENSE.md` that points back to this file.
A file outside every `Plus` directory is MIT, whatever it depicts.
No `Plus` directory exists yet, so today there is no paid artwork at all.

## Questions

Ask in a [GitHub issue](https://github.com/ethanwchen/tabbi/issues) or write to support@tabbinotch.com.
