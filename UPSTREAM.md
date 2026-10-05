# box3d — upstream provenance

| | |
|---|---|
| Project | Box3D, "A 3D physics engine for games" |
| Upstream | <https://github.com/erincatto/box3d> |
| Pin | tag `v0.1.0`, commit `8441b4a06d6d09dcfb0b0f704df4d847d1437b92` |
| Project version | `0.1.0`, from `project(box3d VERSION 0.1.0 ...)`, `CMakeLists.txt:4-9` |
| Language | C17 with compiler extensions enabled (`C_STANDARD 17`, `C_STANDARD_REQUIRED YES`, `C_EXTENSIONS YES`), `src/CMakeLists.txt:124-131` |
| Licence | MIT, `Copyright (c) 2026 Erin Catto`, `LICENSE`. Per-file exceptions in `NOTICE.md`. |

## How this tree was acquired

The repository in this directory is a **source drop, not a clone**. `.git/`
contains `HEAD`, `config`, hooks and empty `objects/`, `objects/pack`,
`objects/info/`, `refs/heads/` and `refs/tags/`: there is no packed-refs file,
no loose ref for `refs/heads/main` (which `HEAD` names) and no object in the
pack. Those are file-level observations, and together they establish that this
working tree carries **no history and no recorded revision**.

The commit id above is therefore the pin this SDK was migrated against, taken
from the migration contract, and it is a **recorded claim, not an observation
read out of this tree**. `UPSTREAM.sha256` is the observation: it fixes the exact
bytes that were imported. If the two ever disagree, the digests are what was
compiled and the commit line is what is claimed about it. Re-establishing the
identity of the drop with Git is the driver's to run.

Upstream's own `.gitignore` (`build/`, `imgui.ini`, `settings.ini`, `.vscode/`,
`.vs/`, `.cap`, `.DS_Store`, `CMakeUserPresets.json`, `.cache/`, `.idea/`,
`.claude/`, `.tmp/`, `.fetchcontent-cache/`, `build-dp/`, `*.b3rec`) is kept
verbatim, with this fork's own entries appended after it. The pristine digest is
recorded in `UPSTREAM.sha256`'s header.

## What was imported

349 files, 11,095,421 bytes. Nothing was dropped for size and nothing was
dropped for being unusable by this build.

| Path | Files | Bytes | Role |
|---|---:|---:|---|
| `src/` | 87 | 1,770,367 | the library: the 49 `.c` translation units of `BOX3D_SOURCE_FILES` plus their 34 headers, `recording_ops.inl` and `box3d.natvis` |
| `include/box3d/` | 8 | 245,206 | the entire installed public surface |
| `test/` | 23 | 291,595 | upstream's own unit-test application |
| `shared/` | 13 | 68,026 | helpers the tests and samples share |
| `samples/` | 137 | 4,907,099 | the sokol/imgui sample application and its vendored loaders |
| `benchmark/` | 13 | 10,764 | the benchmark application |
| `docs/` | 35 | 747,151 | the Doxygen manual and its images |
| `data/` | 14 | 1,013,404 | meshes, tree bounds and a recorded dump |
| `extern/sokol/` | 6 | 2,018,953 | vendored sokol headers and their zlib licence |
| `.github/` | 4 | 6,669 | upstream's own funding, issue and PR templates and its build workflow |
| top level | 7 | 15,096 | `CMakeLists.txt`, `CMakePresets.json`, `LICENSE`, `README.upstream.md`, `build.sh`, `build_vs2026.bat`, `deploy_docs.sh` |
| dotfiles | 2 | 1,091 | `.clang-format`, `.gitattributes` |

The public surface is exactly the eight headers `src/CMakeLists.txt:92-101`
installs: `base.h`, `box3d.h`, `collision.h`, `config.h`, `constants.h`,
`id.h`, `math_functions.h`, `types.h`.

`samples/`, `benchmark/` and `docs/` are retained and recorded but **not
compiled by this SDK**. That is upstream's own structure, not an omission:
`samples/CMakeLists.txt:3-28` fetches imgui, implot and
nativefiledialog-extended over the network, and `docs/CMakeLists.txt` needs
Doxygen. See "Native-build deviations" in `README.md`.

## Integrity

`UPSTREAM.sha256` is the SHA-256 of every imported file, computed on 2026-10-04
with no Git command involved. It establishes:

* that a file in this tree still has the bytes the manifest recorded;
* which files this SDK considers imported and therefore does not edit.

It does **not** establish that those bytes are what GitHub served for
`8441b4a0`, that the drop corresponds to tag `v0.1.0`, or that the manifest is
authentic. It is a checksum of a working tree, not a signature and not a Git
object id. Only a re-fetch and a comparison establishes the first two.

`tools/check-provenance.sh` verifies the manifest and the licence notices.
Re-run it after any intentional native change, together with the record that
change requires.

## Native-source deviations

**None.** No file under `src/`, `include/`, `test/`, `shared/`, `samples/`,
`benchmark/`, `data/`, `docs/` or `extern/` has been edited, reformatted or
patched. `UPSTREAM.sha256` is the check that keeps it that way.

An intentional native change would need, in the same change: an observed
failure that forces it, the smallest causal patch, a per-file entry in
`NOTICE.md`, a dated `CHANGELOG.md` entry, a `FORK-NOTES.md` record of the
evidence, and refreshed digests in `UPSTREAM.sha256`. None of that exists
today.

## Upstream build versus this SDK's build

Upstream builds with CMake 3.22 and no autotools. This SDK builds with
Zig 0.16.0 and invokes no upstream build system; `CMakeLists.txt`,
`CMakePresets.json`, `build.sh`, `build_vs2026.bat` and `deploy_docs.sh` are
retained as upstream bytes and are not executed.

| Upstream CMake option | Default | This SDK |
|---|---|---|
| `BOX3D_DOUBLE_PRECISION` | `OFF`, `PUBLIC` | `-Ddouble-precision`, default `false` |
| `BOX3D_DISABLE_SIMD` | `OFF`, `PRIVATE` | `-Ddisable-simd`, default `false` |
| `BOX3D_VALIDATE` | `ON`, `PRIVATE` | `-Dvalidate`, default `true` |
| `BOX3D_SANITIZE` | `OFF` | not exposed; a sanitized build is a driver's choice, not a package default |
| `BOX3D_PROFILE` | `OFF` | **not exposed**: it pulls Tracy through `FetchContent` (`src/CMakeLists.txt:137-152`) and this SDK downloads nothing |
| `BUILD_SHARED_LIBS` | CMake's default | `-Dlinkage=static\|dynamic`, default `static` |

Upstream's determinism flag `-ffp-contract=off` (`CMakeLists.txt:85-87`) is
kept, because upstream's determinism tests depend on it.

Compiled here: the 49 translation units of `src/`, upstream's `test/`
application together with the 12 files of `shared/`, and this fork's own
`tests.zig`, `smoke.zig` and consumer package. Not compiled: `samples/`,
`benchmark/`, `docs/`, `data/` and `extern/`.

## Sync procedure

Box3D is a Git project upstream and this repository has the same shape, so the
procedure is the ordinary one, and no patch file is kept:

1. Add the upstream remote to this repository and fetch it. Point `origin` at
   the private downstream before the first push and `upstream` at
   `https://github.com/erincatto/box3d.git`.
2. Merge the new tag into this branch as a separate commit, keeping the fork's
   build, packaging, API and documentation in their own region.
3. Regenerate `UPSTREAM.sha256` over the new import, update the pin in this
   file, in `README.md` and in `build.zig.zon`.
4. Re-run the full gate set for the SDK. The upstream unit-test application is
   part of that set (`zig build upstream-test`), and a Box3D release that
   changes an ABI-affecting option needs its own note in "Native-build
   deviations" in `README.md`.

For an upstream with history the merge, not a patch, is the record. This
repository's import is a drop, so step 1 is also the first moment the commit
identity becomes an observation rather than a claim.