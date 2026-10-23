# Box3D licence inventory

| Path | Terms and attribution |
|---|---|
| `src/*.c`, internal `src/*.h` with SPDX, `include/box3d/*.h`, `test/*.c`, `shared/*.c`, `benchmark/main.c` | MIT; Copyright (c) 2026 Erin Catto; `LICENSE` |
| `src/qsort.h`, `samples/gfx/qsort.h` | MIT; Copyright (c) 2013, 2017 Alexey Tourbin; notices in the files |
| `src/verstable.h` | MIT; Copyright (c) 2023-2025 Jackson L. Allan; notice in the file |
| `samples/jsmn.h` | MIT; Copyright (c) 2010 Serge Zaitsev; notice in the file |
| `samples/tiny_obj_loader.h` | MIT; Copyright (c) 2012-Present, Syoyo Fujita and contributors; notice in the file |
| `samples/earcut.h` | No licence notice is present; no licence is asserted here. |
| `extern/sokol/sokol_app.h`, `sokol_gfx.h`, `sokol_glue.h`, `sokol_imgui.h`, `sokol_log.h`, `LICENSE` | zlib/libpng; Copyright (c) 2018 Andre Weissflog, except `sokol_log.h` (2023); notices are in the headers and `LICENSE`. |
| 120 imported files without per-file notices | Box3D files distributed under `LICENSE`: `samples/host/`, `samples/gfx/projection.h`, all `CMakeLists.txt`, `samples/shaders/`, `.gitkeep`, `src/box3d.natvis`, `docs/`, `data/`, benchmark scenario CSVs, build scripts, `.clang-format`, `.gitattributes`, `.gitignore`, and `.github/` funding, issue and pull-request templates. |
| Fork-authored files | MIT, as authorized in `FORK-LICENSE.md`: `build.zig`, `build.zig.zon`, `build_support/`, `zig/`, `runtime/`, `tests.zig`, `smoke.zig`, `consumer/`, `cross-test.profile.sh`, `tools/check-provenance.sh`, `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`, `README.md`, `README.zig.md`, `NOTICE.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `FORK-LICENSE.md`, `CHANGELOG.md` and `FORK-NOTES.md`. |

`README.upstream.md` is upstream's `README.md`, preserved byte for byte; its SHA-256 is `2525d7ca5823027918c6ad7d84c1f9b946ef654d3350390e02a7dbe11aa5754e`.

Fork-authored source, build and packaging files carry `SPDX-License-Identifier: MIT`. The zlib/libpng notice must not be removed or altered. Altered source versions must be plainly marked. The compiled library includes `src/qsort.h` and `src/verstable.h`; their notices remain required.

The package installs `LICENSE`, `README.upstream.md`, `NOTICE.md`, `UPSTREAM.md` and `FORK-LICENSE.md` under `share/licenses/box3d/`.
