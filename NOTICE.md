# box3d — licence and provenance inventory

This file records, per file or per identified group, which terms apply to which
material. `UPSTREAM.md` records where the material came from;
`FORK-LICENSE.md` records the terms this fork applies to what it wrote.

A single label does not describe this repository. The core library is MIT, and
so is almost everything around it, but the notices differ in **holder**, in
**form** and in **one case in whether they exist at all**. The inventory below
is per file for that reason.

## 1. The native library: MIT, Erin Catto

| | |
|---|---|
| Term | MIT |
| Holder | `Copyright (c) 2026 Erin Catto` |
| Full text | `LICENSE`, 1,067 bytes, reproduced verbatim upstream; installed with the package as `$out/share/licenses/box3d/LICENSE` |
| Files | `src/*.c` and the internal `src/*.h` that carry `// SPDX-License-Identifier: MIT`, all eight `include/box3d/*.h`, `test/*.c`, `shared/*.c`, `benchmark/main.c` |
220 files in this repository carry `SPDX-License-Identifier: MIT` with an
`SPDX-FileCopyrightText` line naming Erin Catto: 109 say 2026, 102 say 2025,
5 say 2023, 2 say 2024 and 2 say 2022. **Every SPDX identifier in the tree is
`MIT`** — there is no Apache, BSD, zlib or copyleft identifier anywhere in the
imported source, and no file with an SPDX tag names a holder other than Erin
Catto.

## 2. Per-file exceptions inside the compiled library

Two headers in `src/` are compiled into the library and are **not** Erin
Catto's files. Each carries its own MIT text, and each must travel with any
redistribution of the compiled artifact.

| File | Holder | Notice | Form |
|---|---|---|---|
| `src/qsort.h` | `Copyright (c) 2013, 2017 Alexey Tourbin` | MIT, `src/qsort.h:1-21` | Comment block at the top of the file; no SPDX tag |
| `src/verstable.h` | `Copyright (c) 2023-2025 Jackson L. Allan` (VERSTABLE v2.2.1) | MIT, `src/verstable.h:412-427` | Comment block inside the file's header comment; no SPDX tag |

Both are vendored header-only utilities. `samples/gfx/qsort.h` is the same
Alexey Tourbin file (`:1-21`), with the fetch it replaced recorded at `:24-26`.

The MIT obligation "the above copyright notice ... shall be included in all
copies or substantial portions" therefore has **three** copyright holders in the
compiled closure: Erin Catto, Alexey Tourbin and Jackson L. Allan. Shipping
`LICENSE` alone does not discharge it.

## 3. Vendored material retained in the tree but not compiled

Upstream's sample application pulls some of its dependencies over the network
at configure time and this SDK builds no samples, so these files are carried as
bytes and are not part of the compiled artifact.

| File | Holder | Term | Notice location |
|---|---|---|---|
| `samples/jsmn.h` | `Copyright (c) 2010 Serge Zaitsev` | MIT | `:1-23` |
| `samples/tiny_obj_loader.h` | `Copyright (c) 2012-Present, Syoyo Fujita and many contributors` | MIT | `:1-23` |
| `samples/earcut.h` | not stated in the file | **none present** | — see below |
| `samples/gfx/qsort.h` | `Copyright (c) 2013, 2017 Alexey Tourbin` | MIT | `:1-21` |
| `extern/sokol/sokol_app.h`, `sokol_gfx.h`, `sokol_glue.h`, `sokol_imgui.h` | `Copyright (c) 2018 Andre Weissflog` | zlib/libpng | in-file, near each file's end |
| `extern/sokol/sokol_log.h` | `Copyright (c) 2023 Andre Weissflog` | zlib/libpng | `sokol_log.h:79-...` |
| `extern/sokol/LICENSE` | `Copyright (c) 2018 Andre Weissflog` | zlib/libpng | whole file |

**`samples/earcut.h` carries no licence notice at all.** It is a vendored copy
of mapbox's earcut header and the file begins with `#pragma once`. That is a
fact about the import, recorded here rather than repaired: writing a grant into
the file would be inventing one, and this fork has no authority to do so. The
zlib/libpng licence of the sokol headers **requires** that its notice is not
removed or altered and that altered versions are marked as such; those two
conditions are the reason the notice is copied rather than summarised
anywhere.

## 4. Material with no per-file notice, covered by the repository licence

120 imported files carry no notice of their own. They are Box3D's own files,
distributed by Box3D under `LICENSE`:

* `samples/host/` (`camera.cpp`, `camera.h`, `gui.cpp`, `gui.h`,
  `imgui_impl.cpp`, `sokol_app_impl.c`) and `samples/gfx/projection.h`;
* every `CMakeLists.txt`, `samples/shaders/**` including the 30 generated
  `*.glsl.h` files, `.gitkeep`, and `src/box3d.natvis`;
* `docs/**` — 14 manual pages, `layout.xml`, `extra.css` and 18 images;
* `data/**` — 10 `.obj` meshes, 3 tree-bound `.txt` files, one recorded dump;
* `benchmark/amd7950x_scalar/`, `benchmark/amd7950x_sse2/` and their 11 `.csv`
  scenario files;
* `build.sh`, `deploy_docs.sh`, `build_vs2026.bat`, `CMakePresets.json`,
  `.clang-format`, `.gitattributes`, `.gitignore`;
* `.github/` funding, issue and pull-request templates and `workflows/build.yml`.

The zlib/libpng clause "altered source versions must be plainly marked as such"
applies to anything here that this fork edits. Nothing in this list is edited:
`UPSTREAM.sha256` covers all of it.

## 5. Fork-authored material

Everything else in this repository was written for this fork and is released
under **MIT**, on the authorization recorded in `FORK-LICENSE.md`. No upstream
copyright attaches to it and none is claimed.

| File | Written by |
|---|---|
| `build.zig`, `build.zig.zon`, `build_support/` | NativeDelivery |
| `zig/translate.h` | NativeDelivery |
| `zig/root.zig`, `zig/math.zig`, `zig/base.zig`, `zig/world.zig`, `zig/body.zig`, `zig/shape.zig`, `zig/joint.zig`, `zig/query.zig` | ApiConsumer |
| `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h` | driver, reviewed shared runtime core, copied in unmodified |
| `runtime/graph.zig`, `runtime/library.zig` | ApiConsumer |
| `tests.zig`, `smoke.zig`, `consumer/src/main.zig` | ApiConsumer |
| `consumer/build.zig`, `consumer/build.zig.zon` | NativeDelivery |
| `cross-test.profile.sh`, `.github/workflows/verify.yml` | NativeDelivery |
| `tools/check-provenance.sh` | ProvenanceNix |
| `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc` | ProvenanceNix |
| `README.md`, `README.zig.md`, `README.upstream.md`, `NOTICE.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `FORK-LICENSE.md`, `CHANGELOG.md`, `FORK-NOTES.md` | ProvenanceNix |

`README.upstream.md` is the exception inside that table: it is upstream's own
`README.md`, preserved byte for byte under a new name, and it stays under
upstream's terms. Its digest is `2525d7ca5823027918c6ad7d84c1f9b946ef654d3350390e02a7dbe11aa5754e`.

Fork-authored source, build and packaging files carry
`SPDX-License-Identifier: MIT`.

## 6. What the install carries

`build.zig` installs, under `--prefix`:

* `$out/include/box3d/` — the eight public headers, unmodified;
* `$out/lib/libbox3d.a`, or the shared variant with its soname `libbox3d.so.0`;
* `$out/lib/pkgconfig/box3d.pc`;
* `$out/share/licenses/box3d/` — `LICENSE`, `README.upstream.md`, `NOTICE.md`,
  `UPSTREAM.md`, `FORK-LICENSE.md`.

The two compiled vendored headers in section 2 are **inside** `libbox3d.a` and
inside the shared object, and are not installed as separate files. Their MIT
notices are therefore carried by `LICENSE` and by this file rather than by a
per-file copy in `$out/include`, which is the layout upstream's own install
produces. A downstream that redistributes only `$out/include` and
`$out/lib` should carry `NOTICE.md` and `LICENSE` with it; that is what
section 2 obliges, and it is why this file is installed at all.

No data, tool or shader is installed: `data/`, `samples/` and `docs/` are
sample and manual material that neither the library nor the upstream unit-test
application links.

## 7. Obligations in one place

| Holder | Term | Where the notice must appear |
|---|---|---|
| Erin Catto | MIT | `LICENSE`, in every copy or substantial portion |
| Alexey Tourbin | MIT | `src/qsort.h:1-21`, and `NOTICE.md` §2 |
| Jackson L. Allan | MIT | `src/verstable.h:412-427`, and `NOTICE.md` §2 |
| Serge Zaitsev | MIT | `samples/jsmn.h:1-23` |
| Syoyo Fujita and contributors | MIT | `samples/tiny_obj_loader.h:1-23` |
| mapbox (earcut) | not stated in the file | none present; `NOTICE.md` §3 |
| Andre Weissflog | zlib/libpng | `extern/sokol/LICENSE` and each header; notice must not be removed or altered |
| This fork's authors | MIT | `FORK-LICENSE.md`, SPDX headers |