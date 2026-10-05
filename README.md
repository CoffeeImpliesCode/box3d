# box3d

Box3D v0.1.0 — Erin Catto's 3D physics engine for games — packaged for Zig
0.16, with the complete C17 core, its eight public headers, the full public
`B3_API` surface as a raw Zig route, a typed facade over world/body/shape
creation, stepping, queries and destruction, and a runtime-loading build that
resolves that same surface from a shared object at run time.

This is the **real Box3D project**, not a substitute: the whole
49-translation-unit upstream core is compiled here, upstream's own unit-test
application is compiled and run unmodified, and nothing is stubbed,
header-only-substituted or reimplemented. One further C translation unit —
`build_support/box3d_abi_bridge.c`, fork-authored and deviation 11 below — is
compiled beside those 49; it adds no algorithm and restates no upstream type.

| | |
|---|---|
| Upstream | <https://github.com/erincatto/box3d> |
| Pin | tag `v0.1.0`, commit `8441b4a06d6d09dcfb0b0f704df4d847d1437b92` |
| Import | 349 files, 11,095,421 bytes, unmodified. See `UPSTREAM.md` and `UPSTREAM.sha256`. |
| Licence | MIT, `Copyright (c) 2026 Erin Catto`, plus two vendored MIT notices **inside the compiled library**. See `NOTICE.md`. |
| Fork additions | MIT, on the owner's authorization. See `FORK-LICENSE.md`. |

`UPSTREAM.md` has the provenance and the import inventory. `NOTICE.md` has the
per-file licence record. `FORK-NOTES.md` has the problems met while packaging
this and what was done about each. The Zig interface is documented separately, in
`README.zig.md`. Upstream's own README is preserved byte for byte as
`README.upstream.md`.

## Native-source deviations

**None.** No file under `src/`, `include/`, `test/`, `shared/`, `samples/`,
`benchmark/`, `data/`, `docs/` or `extern/` has been edited, patched,
reformatted or regenerated. `UPSTREAM.sha256` records all 349 imported files and
`tools/check-provenance.sh` verifies them, so "unmodified" is a checkable
statement rather than a promise.

An intentional native change would need, in the same change: an observed failure
that forces it, the smallest causal patch, a per-file entry in `NOTICE.md`, a
dated `CHANGELOG.md` entry, a `FORK-NOTES.md` record, and refreshed digests.

## Native-build deviations

What the compiled package does that the bare upstream project does not. Each is a
fork decision with a stated reason; none of them changes an algorithm or a
public declaration.

1. **CMake is replaced by Zig.** Upstream builds with CMake 3.22
   (`CMakeLists.txt:1`). This SDK invokes no CMake, no autotools and no Make.
   `CMakeLists.txt`, `CMakePresets.json`, `build.sh`, `build_vs2026.bat` and
   `deploy_docs.sh` are retained as upstream bytes and are not executed.
   `build.zig` is the single authoritative source list, flag list and install
   layout.

2. **Upstream's own unit tests are built and run.** All 21 C files of
   `test/CMakeLists.txt:3-26` plus `test_macros.h`, and all 12 entries of
   `shared/CMakeLists.txt:3-16`, are compiled **unmodified** into one executable
   under `zig build upstream-test`, with `src/` on the include line because those
   tests call internal functions (`test/CMakeLists.txt:37`). Upstream builds them
   only for a static library (`CMakeLists.txt:140-146`); here they are built
   against the same library the package ships.

3. **The samples, the benchmarks and the Doxygen manual are not built.** They are
   retained and digested, not compiled. `samples/CMakeLists.txt:3-28` fetches
   imgui, implot and nativefiledialog-extended over the network,
   `src/CMakeLists.txt:137-152` fetches Tracy for `BOX3D_PROFILE`, and
   `docs/CMakeLists.txt` needs Doxygen. This is why there is deliberately **no
   `-Dprofile` option**: nothing in this SDK can reach a download. No
   third-party dependency was replaced by a stub.

4. **Upstream's determinism flag is kept.** `-ffp-contract=off` on MINGW, Apple
   and Unix (`CMakeLists.txt:85-87`) is a correctness requirement behind
   upstream's own determinism tests, not a preference.

5. **Visibility and export.** Upstream compiles hidden and re-exposes the public
   declarations through `BOX3D_EXPORT` (`src/CMakeLists.txt:105-106`,
   `include/box3d/base.h:21-35`). The shared build honours all four cases:
   `__declspec(dllexport)` when building a Windows DLL, `__declspec(dllimport)`
   for its consumers, `__attribute__((visibility("default")))` elsewhere, and
   nothing for a static archive. PIC applies to every constituent object, and
   the soname series is upstream's own `VERSION 0.1.0` / `SOVERSION 0`
   (`src/CMakeLists.txt:128-129`).

6. **A pkg-config file is generated.** Upstream ships none — it installs only
   headers and a CMake export set (`src/CMakeLists.txt:223-252`). The build graph
   generates `$prefix/lib/pkgconfig/box3d.pc` from real metadata, including
   `Libs.private: -lm -pthread` for upstream's own `libm` dependency
   (`src/CMakeLists.txt:218-221`) and the platform threading in `src/timer.c`,
   and `-DBOX3D_DLL` in the shared variant only, mirroring upstream's MSVC
   `INTERFACE BOX3D_DLL` (`src/CMakeLists.txt:172-175`). The Nix derivation
   copies and generates nothing, so there is one writer per installed path.

7. **An aggregate translation header.** `zig/translate.h` includes
   `<box3d/box3d.h>` and nothing else, because that header already pulls in the
   whole public surface: `box3d.h:6-10` adds `base.h`, `collision.h`, `id.h`,
   `math_functions.h` and `types.h`, `types.h:6-9` adds `constants.h`, and
   `base.h:14` adds `config.h`. One include, no invented declaration.

8. **A runtime-loading branch.** `-Druntime=true` routes the native calls
   through a run-time symbol table instead of linking the library, and is
   orthogonal to `-Dlinkage`. The native artifact is still built and installed
   either way; only the dispatch differs. Linked calls stay direct.

9. **The compile-time options are named in Zig's spelling.**
   `-Ddouble-precision`, `-Ddisable-simd` and `-Dvalidate` (default `true`,
   matching upstream's `BOX3D_VALIDATE`) carry upstream's three options across.
   `-Dtarget` and `-Doptimize` are the standard ones. There is no system-library
   mode: Box3D has no system mode in this wave, so `b.systemIntegrationOption` is
   not exposed and the rule is vacuous rather than satisfied.

10. **Windows is not exposed as a Nix package.** `flake.nix` exposes four Unix
    systems. Two separate reasons, neither a workaround: `package.nix` builds for
    the compiler's native target rather than a hand-assembled cross triple, and
    on Windows `BOX3D_EXPORT` resolves from `box3d_EXPORTS`/`BOX3D_DLL` with no
    way to select `dllexport` and `dllimport` from one value
    (`include/box3d/base.h:21-35`; upstream says so itself at
    `include/box3d/config.h:26-30`). That is a statement about packaging and
    about a shared PE/COFF export story. It is **not** a claim that Box3D's
    source cannot compile for Windows — the Windows row of the compile matrix
    below is still attempted.

11. **One fork-authored C translation unit is compiled beside the core.**
    `build_support/box3d_abi_bridge.c` is compiled into the same module as the
    49 upstream units, with the same `BOX3D_*` settings, so each call it makes
    is laid out by the same compiler invocation as the `src/` unit it reaches
    (`build.zig:447-471`). It exists because Zig 0.16.0's x86-64 argument
    lowering consumes one vector-register pair for a by-value float aggregate of
    at most 24 bytes that the System V ABI then passes in memory. Under
    `-Ddouble-precision=true` a `b3Pos` is 24 bytes
    (`include/box3d/math_functions.h:74-77`), so the ten `B3_API` signatures
    that take a `b3Pos` by value ahead of a floating-point argument or a
    floating-point return hand that later argument one register pair too high —
    measured on this package's own artifacts as the native
    `b3World_CastRayClosest` reading `translation` from `XMM0`/`XMM1` against a
    Zig caller's `XMM2`/`XMM3`, which trips
    `B3_ASSERT( b3IsValidVec3( translation ) )` at `src/physics_world.c:2995`.
    The unit exports `box3dAbi_*` functions that take pointers to the same
    nominal types and forward to the unchanged by-value entry points; no upstream
    byte changes and no upstream signature is patched. The boundary is measured,
    not guessed: `b3Transform` at 28 bytes and `b3Mat3` at 36 bytes were checked
    on the same binary, agree with the native callee, and are deliberately not in
    the set (`build_support/box3d_abi_bridge.h`). `README.zig.md` §"The raw route"
    says which ten, and what a caller who goes past the facade should call.

### History of these deviations

`FORK-NOTES.md` records each one with the evidence that shaped it, and
`CHANGELOG.md` carries the dated entries. Two matter more than the rest:

* **2026-10-04 — this SDK's import.** Box3D v0.1.0 landed as a 349-file
  unmodified source drop. The working tree carries no history, so the commit id
  is a recorded pin and the per-file digests are the observation;
  `UPSTREAM.md` says exactly that.
* **2026-10-04 — contract migration.** The Zig build graph, the typed module, the
  runtime-loading branch, the standalone Nix/devenv packaging and the licence
  and provenance records were added. No native file changed. Entries are under
  `[Unreleased]` in `CHANGELOG.md`; which of them has been run is the matrix
  below, and anything not in it is still `PENDING-VERIFICATION`.

## Build, run and test matrix

### What was observed, and when

Five driver runs on 2026-10-04, on `x86_64-linux-gnu`, each against the tree as
it stood for that run. Each row is a real run and each carries its receipt.
Nothing else in this section has been run, and the two failures below are part
of the record because each one is why a line of the interface looks the way it
does.

| Gate | Command | Mode / target | Result | Receipt |
|---|---|---|---|---|
| Linked: the SDK's own tests and the deterministic smoke | `zig build smoke test --prefix DIR` | Debug / native, default static linkage | `18/18 tests passed`, `9/9 steps` | `local://foundation-contract-box3d-real-overflow-total-count-full-smoke-test-recovered-output.log` |
| Shared native delivery | `zig build install -Dlinkage=dynamic` | Debug / native | `13/13 steps`; soname `libbox3d.so.0` for version `0.1.0` | `local://foundation-contract-box3d-primary-shared-complete-native-closure-repaired.log` |
| Runtime-loaded dispatch, provider supplied from outside this repository | `zig build smoke -Druntime=true -- --provider PATH` | Debug / native | `6/6 steps`; nothing linked into the module; every checked smoke answer matched | `local://foundation-contract-box3d-current-canonical-runtime-static-real-provider-smoke.log` |
| Double-precision shared delivery | `zig build install -Ddouble-precision=true -Dlinkage=dynamic -Doptimize=Debug` | Debug / native | `exit 0`, `13/13 steps` | `/home/tmp2/gertullj/scratch/foundation-libs/contract-physics-lua/baselines-and-configs/box3d-double-type-values-after/index.json`, row `secondary-box3d-double-provider` |
| Double precision, shared object loaded as a provider | `zig build test smoke -Ddouble-precision=true -Dlinkage=dynamic -Doptimize=Debug -Druntime=true` | Debug / native, shared | `exit 0`, `9/9 steps`, `19/19 tests passed` | the same index, row `secondary-box3d-double-loaded-dynamic-test-smoke` |
| Double precision, static archive loaded as a provider | `zig build test smoke -Ddouble-precision=true -Dlinkage=static -Doptimize=Debug -Druntime=true` | Debug / native, static | `exit 0`, `9/9 steps`, `19/19 tests passed` | the same index, row `secondary-box3d-double-loaded-static-test-smoke` |
| Devenv environment, task names and shell | `devenv info`, `devenv tasks list`, `devenv shell -- zig version`, `devenv shell -- zig env` | n/a | `exit 0` each; `BOX3D_SDK_VERSION: 0.1.0`; banner `sdk root:` and `cache:` lines naming this SDK and its caches; `zig version` `0.16.0` from the store compiler | `/home/tmp2/gertullj/scratch/foundation-libs/contract-physics-lua/nix-acceptance-evidence/20261004T214803Z/box3d-index.json` |
| Consumer package, through `sdk:consumer` | `devenv tasks run --mode single … sdk:consumer`, body `cd consumer && zig build run --summary all` | Debug / native, default static | `exit 0`, `Build Summary: 6/6 steps succeeded`, `run exe box3d-consumer success 64ms`; the first build and run of `consumer/` here | the same index |
| Provenance integrity, through `sdk:provenance` | `devenv tasks run --mode single … sdk:provenance` | n/a | `exit 0` in 215 ms; `tools/check-provenance.sh` passed | the same index |
| Nested `consumer` step, four routes | `zig build consumer` nine times: static and dynamic, linked and runtime-loaded, defaults omitted and stated | Debug / native | nine of nine as expected: eight `exit 0` with `Build Summary: 6/6 steps succeeded`, and a no-provider refusal `exit 1` with the program's own message; the nested `--prefix` is byte-identical to the outer one | run `20261004T223101687849Z-e3904589dead` |
| Native matrix, both linkages and four optimize modes | `zig build test smoke install`, static and dynamic, `Debug`, ReleaseSafe, ReleaseFast, ReleaseSmall | Debug and Release, native | eight of eight `exit 0`, each `Build Summary: 18/18 steps succeeded; 19/19 tests passed`; 15 installed files static, 17 shared | run `contract-final-after-20261004` |

What those rows do not say, stated rather than left to be inferred:

* The build rows are `Debug` on one native target except the native matrix row,
  which also covers ReleaseSafe, ReleaseFast and ReleaseSmall. No other target
  and no cross-built binary has run.
* The first shared row **built and installed**; it did not execute the shared
  object. A C or Zig consumer linked against the installed `libbox3d.so` is
  still outstanding.
* The runtime row loaded one provider named on the command line. It did not try
  a fallback, a system basename, or a second provider, so it says nothing about
  the failure, retry or idempotence paths of the loader.
* The three double-precision rows ran at `-Ddouble-precision=true` in `Debug`,
  once per linkage, and both loaded a provider built from this tree. They add no
  ReleaseSafe, ReleaseFast or ReleaseSmall run, no NetBSD cell, and no
  `consumer` step. Each named an explicit cache pair and prefix and ran at `-j8
  --summary all`.
* The three devenv rows are one acceptance run, `20261004T214803Z`, and all eight
  of its gates passed. Its consumer row is the manual `cd consumer && zig build
  run --summary all`, which is the first build and run of `consumer/` in this SDK
  and not the `consumer` step. The one gate its `gates_not_run` names is
  `nix:build`, so both Nix outputs stay outstanding, and the other ten `sdk:*`
  task bodies have not run.
* The linked row is what exercises the SDK's own behavioural tests. Their
  nineteen cases are the ones listed in `tests.zig`, including the stale-parent
  errors, the total-count overflow assertion and the resting, sleeping and
  ray-geometry checks.

Two observed failures, kept because they are the evidence for two decisions:

* `local://foundation-contract-box3d-real-stale-parent-errors-and-geometric-state-full-smoke-test.log`
  — with a collector that stopped at the end of the slice, a two-shape overlap
  query asked to fill one slot returned `1` and `tests.zig:486` failed with
  `expected 2, found 1`. That is what made the two `collect` forms return a
  total rather than a written count.
* `local://foundation-contract-box3d-initial-pose-ray-and-filtered-scene-caller-repair-smoke-test.log`
  — with no parent-liveness preflight, all three stale-parent tests died on
  upstream's own assertions (`src/physics_world.c:96`, `src/body.c:30`,
  `src/joint.c:439`), and a test that filled the world pool died inside
  `b3CreateWorld` at `src/physics_world.c:226`. Filling a native pool is
  therefore a caller precondition and not a reported error; that test is not in
  `tests.zig`, and `README.zig.md` says why.

### The 53-target matrix and the six-target `check` baseline

Two further gates ran over this tree with the harness's own `--jobs 8
--build-jobs 8`. Each holds one source stamp for the whole run, so each is
evidence about the tree at that stamp and about nothing later.

`zig build check` over the six declared compile targets exited 0 with `Build
Summary: 37/37 steps succeeded` and no failing step. Label
`baseline-box3d-check`, baseline run `20261005T014547Z-797a73f2`, 2026-10-05.
It compiles and links and runs nothing, so it is compile evidence.

`cross-test` over the published 53-target table exited 1. Run
`20261004T221720228710Z-45046`, receipt `box3d-53-target-8.json`, source stamp
`88106c0349…` before and after. Of the 53 cells, **9 pass**, **33 are
build-only**, **none fail to build** and **11 fail their run**. A build-only
cell compiled and had no runner. It is not a passing test. Every one of the 11
executed 19 tests.

All 11 failures are on one boundary, the call from Zig into the C library, and
none is the scene-shape defect this SDK already fixed. Three signatures, read
off the run's own logs:

* `error.WorldLimitExceeded`, raised at `zig/world.zig:197` when
  `b3World_IsValid(id)` answers false, on `aarch64_be-linux`, `mips64-linux`,
  `powerpc64-linux` and `x86-linux`. The C side rejected a world handle the
  caller had just been given.
* A pointer the C library reads as a definition, `member access within
  misaligned address 0x1 for type 'const b3BodyDef'` at `B3_CHECK_DEF( def )`
  in `src/body.c:159` and `src/physics_world.c:208`, and on `riscv32-linux`
  `member access within misaligned address 0xaaaaaaaa for type 'const
  b3HullData'` at `src/hull.c:1658`. The addresses differ per test, on
  `powerpc64le-linux` running from `0xf1` through `0xff`, so the value is not a
  fixed sentinel.
* `Segmentation fault` on `powerpc-linux` and `s390x-linux`.

Every struct this SDK exchanges is an alias of the translated one, so no
hand-written layout in this tree can disagree with C. What the run shows is
that on these eleven targets the argument did not arrive intact. **This file
claims no cause.** Resolving it needs a run against the tree as it stands now,
which is a different stamp.

**What these receipts do not cover.** Each run holds one source stamp. Every
build-graph, header, helper and normalisation edit made after a run describes a
tree that run never saw. Nothing above is a platform-support claim for a cell
that did not execute.

Two eight-cell waves from the same night, native and linked against this tree's
own provider: `native-final-evidence/20261004T233628757747Z-69351` gives **8 of
8 `exit 0`**, each `18/18 steps succeeded` and `19/19 tests passed`, with
`-Druntime=false` because nothing was opened through the platform loader.
`loaded-final-evidence/20261004T232823091897Z-23133` gives the same eight shapes
under `-Druntime=true`: **8 of 8 `pass`**, each `19/19 steps succeeded` and
`19/19 tests passed`.

### What is pending for this migration

Everything in this table has **not** been run. The driver owns every result
field.

| Gate | Command | State |
|---|---|---|
| Native build, default step | `zig build` | not run; the linked row above installs to an explicit prefix and runs more than this does |
| Shared native build | `zig build -Dlinkage=dynamic` | builds and installs; nothing in that run executed the shared object |
| Tests, Debug | `zig build test` | pass, `18/18` |
| Tests, ReleaseSafe | `zig build test -Doptimize=ReleaseSafe` | pass with the native matrix row: `19/19 tests`, static and dynamic |
| Tests, ReleaseFast / ReleaseSmall | `zig build test -Doptimize=ReleaseFast`, `…=ReleaseSmall` | pass with the same row, static and dynamic |
| Upstream's own unit tests | `zig build upstream-test` | not run |
| Deterministic example | `zig build smoke` | pass, linked and runtime-loaded — the first and third rows above |
| Compile-only cross check | `zig build check` | not run |
| Compile-only cross check, shared | `zig build check -Dlinkage=dynamic` | not run |
| Consumer package | `zig build consumer`, or `cd consumer && zig build run --summary all` | pass: nine `consumer` cases in the nested row, and `6/6 steps` through `sdk:consumer` |
| Installed C consumer | against `$out` | not run |
| Fetched filtered consumer | fetched copy from `build.zig.zon` | not run |
| Runtime-loaded consumer | `-Druntime=true`, own and external provider | one external provider, `6/6 steps`; no in-tree provider, no system basename, no failed attempt and no retry |
| Nix, static | `nix build .#static` / `devenv build outputs.static` | not run |
| Nix, shared | `nix build .#shared` / `devenv build outputs.shared` | not run |
| Canonical devenv shell | `devenv shell` | pass: banner printed, `zig version` `0.16.0` from the store compiler, both caches outside this tree |
| Provenance integrity | `tools/check-provenance.sh` | pass through `sdk:provenance`, `exit 0` in 215 ms |
| `castShapeCollect` with a slice shorter than the hit count | a probe, as `tests.zig:485` does for the overlap form | not run: no caller of `castShapeCollect` exists in `tests.zig` or `smoke.zig` |

Build status, run status and test status are separate things here. The eleven
rows in the first table are what has been observed on one native target across
these four optimize modes, and the subsection above adds one source-bound
six-target `check` and one source-bound 53-target matrix. None of the three is a
claim about the installed C consumer or either Nix output.

### What `zig build consumer` runs

`consumer/` is a separate `zig build` graph. The `consumer` step drives it from
this SDK's root through one `Step.Run` — `runConsumer` in `build.zig`, whose only
caller is that step's `dependOn` — and that run forwards:

* the target query, as `-Dtarget=` and `-Dcpu=`;
* this build's mode: `-Doptimize=`, `-Druntime=`, `-Ddouble-precision=`,
  `-Dvalidate=`, `-Dlinkage=`, and `-Ddisable-simd=` as this build's own target
  resolves it;
* the selected executor: `-fdarling`, `-fqemu`, `-frosetta`, `-fwasmtime`,
  `-fwine`, and `--libc-runtimes` when this build was configured with one;
* `-j8` and `--summary all`;
* this build's local cache as `--cache-dir` plus a `/consumer` subdirectory, and
  the external global cache as `--global-cache-dir` — each only when this build
  has a path to name, and with no invented fallback;
* `--prefix` with this build's actual install prefix, only when you named one. A
  relative value is resolved against this build's root first, because the nested
  graph runs in `consumer/`;
* your own arguments, last and behind `--`; the nested graph hands them to the
  consumer program itself.

It runs the consumer when an enabled executor can execute the selected target,
and installs it otherwise, which is build-only evidence rather than a consumer
exchange. The step itself has
now run: nine cases, four routes with the SDK's defaults omitted and stated plus
a no-provider refusal. All nine are `Debug` on one native host, and the four
explicit-target cases name `x86_64-linux-gnu` and nothing else.

### What `zig build smoke` actually checks

The scene is upstream's own `HelloWorld` (`test/test_world.c:21-101`), and every
answer is derived from that geometry rather than from a value the program once
printed:

* A static ground box of half-extents `(50, 10, 50)` centred at `y = -10`, so its
  top face is at `y = 0`, and a unit cube dropped from `y = 4` at density 1.
  The cube's mass is therefore exactly 8, and the observed run printed `8.000000`.
* A downward ray from `y = 10`, 20 long. Over the cube it meets the top face at
  `y = 5` a quarter of the way along; clear of the cube it meets the ground half
  way along with normal `(0, 1, 0)`. Observed: `0.250000`, `0.500000`, and
  `1.000000`.
* After 90 steps of `1/60 s` with 4 sub-steps the cube rests one half-extent
  above the ground's top face. The check is `1.0 ± 0.01`, upstream's own
  tolerance for this scene (`test/test_world.c:96-98`); the observed resting
  height was `0.999930`. Resting is a tolerance, not an exact value, and the
  tilt about x and z was `0.000000` in the same run.
* An AABB in the gap between the two bodies, above the ground's top face and
  clear of the cube's half-extent, is inside neither and finds `0` shapes.
* After 300 further steps the island is asleep: the run printed `awake bodies: 0`
  and `cube awake: no`. Those two are printed, not asserted — the sleep
  threshold and the timing that reaches it are the solver's business, not a
  promise this package makes.

### The six-target compile matrix

`zig build check` compiles and links without running any target binary. A target
that compiles is compile evidence, not a claim that a cross-built binary
executed. All six rows are attempted by the step, in this order:

| Target | `zig build check`, default static linkage |
|---|---|
| `x86_64-linux-gnu` | not run |
| `aarch64-linux-gnu` | not run |
| `aarch64-macos-none` | not run |
| `x86_64-windows-gnu` | not run |
| `riscv64-linux-gnu` | not run |
| `wasm32-wasi` | not run |

No target is dropped and none is relabelled. Two real boundaries are known from
the source and are stated here so the matrix is read correctly rather than as a
promise:

* **Threading is platform-dependent.** `src/timer.c` uses pthreads and unnamed
  POSIX semaphores on Linux and Emscripten and falls back to a single-threaded
  path everywhere else, so `b3World_SetWorkerCount` above 1 does not mean the
  same thing on every target.
* **The shared variant on a PE/COFF target** would need the `BOX3D_DLL`
  import/export split that one macro value cannot express (deviation 10). That is
  a property of the header and of PE/COFF export rules, and it is why the flake
  exposes no Windows package. It is not a prediction that a compile will fail;
  the driver runs the row.

## Consumption

### From Zig

```zig
const box3d = @import("box3d");

pub fn main() !void {
    var world_def = box3d.c.b3DefaultWorldDef();
    world_def.gravity = .{ .x = 0, .y = -9.8, .z = 0 };

    const world = box3d.c.b3CreateWorld(&world_def);
    defer box3d.c.b3DestroyWorld(world);

    var body_def = box3d.c.b3DefaultBodyDef();
    body_def.type = box3d.c.b3_dynamicBody;
    body_def.position = .{ .x = 0, .y = 10, .z = 0 };
    const ball = box3d.c.b3CreateBody(world, &body_def);

    var shape_def = box3d.c.b3DefaultShapeDef();
    const sphere = box3d.c.b3Sphere{
        .center = .{ .x = 0, .y = 0, .z = 0 },
        .radius = 0.5,
    };
    _ = box3d.c.b3CreateSphereShape(ball, &shape_def, &sphere);

    box3d.c.b3World_Step(world, 1.0 / 60.0, 4);
    _ = box3d.c.b3Body_GetPosition(ball);
}
```

That is the raw route, deliberately: it is upstream's own spelling, translated,
and it is the route that stays complete. The typed route wraps the same calls
with flat types on the module root and seven operation namespaces — `math`,
`base`, `world`, `body`, `shape`, `joint`, `query` — and is enumerated in
`README.zig.md`.

The same scene through the typed route — this is the geometry, resting and
sleeping behaviour `zig build smoke` checks, in the spelling a consumer writes:

```zig
const std = @import("std");
const box3d = @import("box3d");

pub fn main() !void {
    // Upstream's own HelloWorld scene: a ground box whose top face is at y = 0,
    // and a unit cube dropped from y = 4. `.{}` is upstream's default world —
    // gravity (0, -10, 0), sleeping on (`src/types.c:10-30`).
    const world = try box3d.world.create(.{});
    defer box3d.world.destroy(world);

    const ground = try box3d.body.create(world, .{
        .position = .{ .x = 0, .y = -10, .z = 0 },
    });
    const ground_hull = box3d.shape.boxHull(50, 10, 50);
    _ = try box3d.shape.createHull(ground, .{}, &ground_hull.base);

    const cube = try box3d.body.create(world, .{
        .bodyType = box3d.dynamicBody,
        .position = .{ .x = 0, .y = 4, .z = 0 },
    });
    const cube_hull = box3d.shape.cubeHull(1);
    // Density 1, so a unit cube has a mass of exactly 8. The default shape
    // definition is water's 1000 kg/m³ (`src/types.c:66-80`), so the mass of
    // any other shape is a choice the caller makes rather than a constant.
    _ = try box3d.shape.createHull(cube, .{ .density = 1.0 }, &cube_hull.base);

    // 90 steps: the cube rests one half-extent above the ground's top face.
    // Resting is a tolerance, not an exact height — upstream's own fixture
    // allows 0.01 (`test/test_world.c:96-98`) and the observed run gave 0.999930.
    for (0..90) |_| box3d.world.step(world, 1.0 / 60.0, 4);
    std.debug.assert(std.math.approxEqAbs(f32, 1.0, box3d.body.position(cube).y, 0.01));

    // Long after that the island is asleep. Sleeping is on by default;
    // `body.setSleepThreshold` and `world.enableSleeping` move it. *When* it
    // happens is the solver's business, so this asks a question rather than
    // counting steps.
    for (0..300) |_| box3d.world.step(world, 1.0 / 60.0, 4);
    std.debug.assert(box3d.world.awakeBodyCount(world) == 0);
}
```

Every name in that block is in `zig/` and wraps the same upstream call the raw
route spells; the observations behind each line are in *What `zig build smoke`
actually checks*, above.

`dep.module("box3d")` carries the compiled C with it, so there is nothing to
install and nothing to find on the system. The dependency line, the build
snippet, the whole typed surface, the raw route and the runtime-loading contract
are in **`README.zig.md`**.

### From C

`dep.artifact("box3d")` is the compiled library and `box3d/` is already on its
include path, because the artifact installs the headers. From a Nix output the
same files are at `$out/include/box3d` and `$out/lib`.

```
$out/include/box3d/{base,box3d,collision,config,constants,id,math_functions,types}.h
$out/lib/libbox3d.a                    # -Dlinkage=static
$out/lib/libbox3d.so.0.1.0 + .so.0 + .so   # -Dlinkage=dynamic
$out/lib/pkgconfig/box3d.pc
$out/share/licenses/box3d/{LICENSE,README.upstream.md,NOTICE.md,UPSTREAM.md,FORK-LICENSE.md}
```

The two vendored MIT headers inside the library (`src/qsort.h` and
`src/verstable.h`) are compiled into the artifact and are not installed as
separate files, which is upstream's own install layout. A downstream
redistributing only `$out/include` and `$out/lib` should carry `LICENSE` and
`NOTICE.md` with it; `NOTICE.md` §6 says why.

### With Nix

`package.nix` is the single source-only derivation; `flake.nix` and `devenv.nix`
both call it, so they cannot describe different packages.

```
nix build .#static    # the SDK's default linkage, also the default attribute
nix build .#shared    # the same derivation built with -Dlinkage=dynamic
```

Nothing is downloaded at build time, no sibling checkout is referenced, and no
host path, user name or store path appears in any committed file.
`devenv shell` is the canonical development environment and installs tools only —
entering the shell does not require building this SDK. Its `outputs.static` and
`outputs.shared` name the same derivation lazily; `devenv build outputs.static`
and `devenv build outputs.shared` are the real packaging route.

Its `sdk:*` tasks (`devenv tasks run sdk:build`, `sdk:test`, `sdk:smoke`,
`sdk:check`, `sdk:consumer`, `sdk:provenance`, `sdk:package_static` and the
rest) each resolve this SDK's own directory before they run, so they name the
right files from whatever directory the shell was entered from. `sdk:build` and
`sdk:build_shared` install to a prefix under `$ZIG_LOCAL_CACHE_DIR`, which the
shell fills from `TMPDIR`, so a delivery never lands in this tree; pass your own
`--prefix` and that one is used instead. A variant needing a second word carries
it with `_`, not `.`, because devenv's task names are `namespace:name`.

## Commands

```
zig build                       # compile and install, then compile the smoke example
zig build -Dlinkage=dynamic     # the shared variant
zig build -Druntime=true       # runtime-loaded dispatch; nothing is linked into the module
zig build smoke -Druntime=true -- --provider PATH   # the runtime route, with a real provider
zig build test                  # the fork's behavioural tests
zig build test -Doptimize=ReleaseSafe
zig build upstream-test         # Box3D's own unit tests, unmodified
zig build smoke                 # the deterministic example
zig build check                 # compile-only, six targets
zig build check -Dlinkage=dynamic
zig build consumer               # the same proof, driven from this SDK's root
cd consumer && zig build run     # the consumer graph on its own
tools/check-provenance.sh       # 349 digests, four licence notices, the preserved README
```

## Notes for every caller

**A count is not always a written count.** `query.overlapAabbCollect` and
`query.castShapeCollect` return the **total** number of hits the query found, and
the valid prefix of the slice is `min(returned, out.len)`; a return larger than
the slice is the answer, not a truncation error. Every other buffer-taking
entry point — `body.shapes`, `body.joints`, `body.contactData`,
`shape.contactData`, `shape.sensorData` — returns upstream's own **written**
count instead. `README.zig.md` §"The two slice-filling collectors" names which is
which, and treating one as the other silently drops hits.

**Precision is part of the ABI, not a setting.** With `-Ddouble-precision=true`,
`b3Pos` becomes a three-`double` struct instead of `b3Vec3` and `b3WorldTransform`
changes with it (`include/box3d/math_functions.h:70-93`), so struct layout and the
calling convention for by-value positions both change; `B3_HUGE` changes from
`1.0e5f` to `1.0e9f` times the length scale
(`include/box3d/constants.h:25-29`); and the library exports
**`b3CreateWorldDoublePrecision`**, not `b3CreateWorld`, because upstream renames
it on purpose so a mismatched application gets a link error
(`include/box3d/box3d.h:25-30`). The define is `PUBLIC` upstream
(`src/CMakeLists.txt:164-168`) for the same reason: a consumer must agree with
the library, and the shared variant's `box3d.pc` carries `-DBOX3D_DLL` for the
same kind of reason. The default is single precision, which is upstream's default.

**Ten entry points cannot be called by value on x86-64 in that mode.** Because a
`b3Pos` is 24 bytes under `-Ddouble-precision=true`, Zig's argument lowering
reserves a vector-register pair for the aggregate it then passes in memory, and a
floating-point argument after it arrives one pair too high — `translation` read
from `XMM2`/`XMM3` where the native callee reads `XMM0`/`XMM1`, which is what
trips `B3_ASSERT( b3IsValidVec3( translation ) )` at `src/physics_world.c:2995`.
The symbols are present and correct; the call Zig emits for them is not, so
`box3dAbi_*` pointer forms (deviation 11) are the route for
`b3World_CastRay`, `b3World_CastRayClosest`, `b3World_CastShape`,
`b3World_CastMover`, `b3Body_CastRay`, `b3Body_CastShape`,
`b3Body_SetTransform`, `b3Body_GetLocalPoint`, `b3Body_GetWorldPointVelocity`
and `b3Shape_RayCast`. The typed route already goes that way, and a C caller is
unaffected — the miscompilation is in how Zig emits the call, not in what Box3D
was built to expect.

**Validation depends on the optimize mode, not just the flag.**
`BOX3D_VALIDATE` only takes effect when `NDEBUG` is absent
(`include/box3d/base.h:70-74`), so Debug and ReleaseSafe validate and
ReleaseFast and ReleaseSmall do not, and validation state is recorded into the
recording header (`src/recording.h:62`). A replay-validation result is only
comparable within one of those two groups.

**Allocator ownership crosses the boundary.** `b3SetAllocator` takes
`b3AllocFcn`/`b3FreeFcn` whose `alignment` argument is a guaranteed power of two
(`include/box3d/base.h:85-102`). Memory allocated through those functions is
Box3D's to free through the same pair, and a test framework's leak oracle does
not cover it. The default allocator is used until the application installs its
own, and the pairing must be installed during startup, before any world exists.

**Ids, not pointers.** Worlds, bodies, shapes and joints are opaque integer ids,
not pointers; `b3World_IsValid`, `b3Body_IsValid` and `b3Shape_IsValid` exist for
exactly this and are provided to up to 64K allocations. Event payloads are
transient: `b3World_GetBodyEvents`, `b3World_GetContactEvents`,
`b3World_GetSensorEvents` and `b3World_GetJointEvents` return data that is only
valid until the next step.

**Worlds are independent.** Up to 128 worlds may exist at once and each is
completely independent and simulable in parallel (`include/box3d/box3d.h:32-34`).

**Only the public surface is exported.** Upstream compiles hidden
(`src/CMakeLists.txt:105-106`), so a shared object exports the `B3_API`
declarations and not the internal helpers. An internal symbol missing from
`libbox3d.so` is upstream's visibility design, not a packaging fault.
  The fork's `box3dAbi_*` pointer forms are declared `B3_API` in
  `build_support/box3d_abi_bridge.h`, so a shared build exports those ten too;
  their header is deliberately not installed and is on no consumer's include
  path, which is consistent — a C consumer has no reason to name them, since
  the defect is in how Zig emits a call, not in what the library expects.

**What upstream does not promise.** `b3World_RebuildStaticTree` and
`b3World_EnableSpeculative` are documented in the header as being for internal
testing (`include/box3d/box3d.h:242-246`), and the recording/replay group is
upstream's own development-facing surface with its own format. Neither is
presented here as a stable API, and this package adds no compatibility promise
for either.

**A version string is not compatibility.** `b3GetVersion` and
`b3IsDoublePrecision` report what the library was built as. They are not an ABI
proof: the boundaries that matter are the precision mode, the exported surface,
the allocator pairing and the layout above.