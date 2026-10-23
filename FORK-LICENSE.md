# Fork licence — box3d

## Upstream material

Erin Catto's Box3D is MIT (`LICENSE`, `Copyright (c) 2026 Erin Catto`). `src/qsort.h` is MIT (Alexey Tourbin); `src/verstable.h` is MIT (Jackson L. Allan); vendored sokol headers carry the zlib/libpng terms. This grant does not cover those upstream files. Erin Catto granted nothing about fork-authored files. `NOTICE.md` lists the files.

## Fork-authored material

It covers every file this fork wrote: build graph, Zig translation header, typed module, runtime graph, tests, smoke example, consumer package, provenance script, Nix packaging and this documentation.

**Those fork-authored files are released under the MIT License.**

The repository owner directly authorized a per-project licence for fork-authored additions.

### SPDX identifier

`MIT`

Fork-authored source, build and packaging files carry `SPDX-License-Identifier: MIT`.

## Exclusions

* It does not re-license, sublicense or add a condition to any imported file, including the two vendored MIT headers inside the compiled library and the zlib/libpng sokol headers.
* It does not assert that Erin Catto, Alexey Tourbin, Jackson L. Allan, Serge Zaitsev, Syoyo Fujita or Andre Weissflog authored, reviewed or approved any fork-authored file.
* It does not extend to a consumer's own code, to the compiled output's link metadata, or to anything outside this repository.
* It does not grant anything for `samples/earcut.h`, which carries no notice.
