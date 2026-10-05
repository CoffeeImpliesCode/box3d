# Fork notes — box3d

The problems met while packaging Box3D, what was done about each, and what is
still open. `CHANGELOG.md` has the dated entries, `UPSTREAM.md` the provenance
and `NOTICE.md` the licence inventory.

Status words are used as `AGENTS.md` defines them. Three gates have receipts —
they are in `README.md` §"Build, run and test matrix" and repeated in the last
table here. Every other migration item is `PENDING-VERIFICATION`, and nothing
else in this file is claimed as a verified result.

## 1. Upstream's README is Box3D's own project README, and still had to be preserved

Box3D is a whole project rather than a vendored single file, so its README
describes the samples, the CMake presets and its community — none of which
describes this SDK. The contract still requires the upstream bytes to be kept,
and `README.md` had to become the fork's README.

*What was done.* `README.upstream.md` was written first and holds upstream's
README byte for byte (4,716 bytes,
`2525d7ca5823027918c6ad7d84c1f9b946ef654d3350390e02a7dbe11aa5754e`); `README.md`
was then replaced with the fork's. The relocation is recorded in
`UPSTREAM.sha256`'s header, in `NOTICE.md` §5 and in `CHANGELOG.md`, and
`tools/check-provenance.sh` compares the file against the header's digest so
there is one source for it.

## 2. "Box3D is MIT" was not a usable answer for this tree

Three different MIT notices sit inside the *compiled* library, from three
different holders: Erin Catto's own files, Alexey Tourbin's `src/qsort.h`, and
Jackson L. Allan's `src/verstable.h`. The last two carry no SPDX tag and
would be invisible to a grep for `SPDX-License-Identifier`.

*What was done.* `NOTICE.md` inventories per file. `tools/check-provenance.sh`
checks the four licence-bearing files by their own notice text. Nothing was
added to `LICENSE`, which stays upstream's file with upstream's text.

## 3. `samples/earcut.h` carries no licence notice

The vendored mapbox earcut header in this tree begins with `#pragma once` and
contains no copyright, grant or SPDX line anywhere.

*What was done.* It is recorded as a gap in `NOTICE.md` §3, in the
obligations table, and in the provenance script as an explicit "not repaired"
case. Writing a grant into the file would be inventing one. The file is not
compiled by this SDK, so the gap does not reach the artifact.

## 4. The tree is a source drop, and the commit id in it is a claim

`.git/` contains `HEAD`, a `config` with **no remote**, and empty `objects/`,
`objects/pack/`, `refs/heads/` and `refs/tags/`. `HEAD` names
`refs/heads/main`, which does not exist. So this repository cannot state its own
revision.

*What was done.* `UPSTREAM.md` says so in those terms: the commit
`8441b4a06d6d09dcfb0b0f704df4d847d1437b92` is the pin this migration used, and
the observation is the set of per-file digests. Re-establishing the identity of
the drop with Git is the driver's, not this file's.

## 5. One imported file cannot stay byte-identical: `.gitignore`

The workspace rules require upstream's ignore conventions to be preserved and
the fork's own cache paths to be excluded. Appending to `.gitignore` is exactly
that, and it makes the file differ from upstream.

*What was done.* It is the single exclusion from the 349-record manifest, with
the pristine digest `2295f05d5e1510d1d5e459c227cc35b046097eaaa8cd92c10c7ce51a9f9144ec`
and its 150 bytes recorded as a comment in `UPSTREAM.sha256`. No other imported
file is excluded, including every `CMakeLists.txt`, the whole Doxygen tree, the
vendored sokol headers and the benchmark scenarios.

## 6. Three upstream build paths cannot be used here, for the same reason

`samples/CMakeLists.txt:3-28` fetches imgui, implot and
nativefiledialog-extended over the network; `src/CMakeLists.txt:137-152` fetches
Tracy for `BOX3D_PROFILE`; `docs/CMakeLists.txt` needs Doxygen. A source-only
SDK that downloads nothing cannot build any of them.

*What was done.* Samples, benchmarks and the Doxygen manual are retained,
digested and uncompiled, and `UPSTREAM.md` names the file and line for each.
There is deliberately **no `-Dprofile` option**, so nothing in this SDK can
reach for a download. Nothing was stubbed and no third-party dependency was
replaced.

## 7. `BOX3D_DOUBLE_PRECISION` is an ABI change, not a setting

This is the one option that a consumer can get silently wrong, so it was read
carefully rather than described as "large world mode":

* `b3Pos` becomes a three-`double` struct instead of `b3Vec3`
  (`include/box3d/math_functions.h:70-90`), and `b3WorldTransform` changes with
  it. Struct layout and the calling convention for by-value position arguments
  both change.
* `B3_HUGE` changes from `1.0e5f` to `1.0e9f` times the length scale
  (`include/box3d/constants.h:25-29`), so the sanity limit itself differs.
* `b3World_CastOutput` gets a double-precision mirror
  (`include/box3d/types.h:1429-1433`).
* The exported symbol changes: `#define b3CreateWorld b3CreateWorldDoublePrecision`
  at `include/box3d/box3d.h:25-30` renames the definition in
  `src/physics_world.c:206`, so a double-precision library exports
  `b3CreateWorldDoublePrecision` and **not** `b3CreateWorld`.

*What was done.* The option exists, defaults to `false` as upstream does, and is
documented as PUBLIC in `README.md`, `README.zig.md` and `UPSTREAM.md`. The
runtime-loading path has to resolve the macro-expanded name; that is recorded
below as an open integration point, because a descriptor written against the
header text rather than against the expanded names would fail to resolve in
exactly this configuration.

## 8. `BOX3D_VALIDATE` is a debug-mode feature wearing a compile flag

`BOX3D_VALIDATE` alone does nothing unless `NDEBUG` is absent:
`include/box3d/base.h:70-74` turns it into `B3_ENABLE_VALIDATION` only inside
`#if !defined(NDEBUG)`. Validation state is also written into the recording
header (`src/recording.h:62`).

*What was done.* The option defaults to `true`, matching upstream, and the
consequence is documented where a caller would look for it: Debug and
ReleaseSafe validate, ReleaseFast and ReleaseSmall do not, and a replay
validation result is only comparable within one of those two groups.

## 9. Only the `B3_API` surface is exported

Upstream compiles with `CMAKE_C_VISIBILITY_PRESET hidden`
(`src/CMakeLists.txt:105-106`) and `BOX3D_EXPORT` restores default visibility
for the public declarations (`include/box3d/base.h:21-35`). Internal helpers are
hidden by construction.

*What was done.* The runtime dispatch enumerates the header-declared public
surface and nothing else. This is recorded so that a missing internal symbol in
a shared object is read as upstream's visibility design and not as a packaging
fault.

## 10. Threading is not the same on every platform

`src/timer.c` uses pthreads and unnamed POSIX semaphores on Linux and Emscripten
(`src/timer.c:227-231`, `:266-297`, `:442-475`) and falls back to a
single-threaded path everywhere else (`:562`, `:651-655`).

*What was done.* Nothing was normalised. `b3World_SetWorkerCount` is documented
with upstream's own range constraint, `[1, B3_MAX_WORKERS]`, and the
platform-dependent fallback is stated rather than papered over: a worker count
above 1 is not the same thing on Windows as on Linux.

## 11. Upstream's own tests need the private headers and a helper library

`test/CMakeLists.txt:37` puts `src/` on the test compile line because the tests
call internal functions, and `test/` links `shared/`
(`test/CMakeLists.txt:43`). Upstream also only builds them when the library is
static (`CMakeLists.txt:140-146`).

*What was done.* All 21 C files of `BOX3D_TEST_FILES`
(`test/CMakeLists.txt:3-26`) plus its `test_macros.h`, and all 12 entries of
`BOX3D_SHARED_FILES` (`shared/CMakeLists.txt:3-16`), are compiled **unmodified**
into one executable under `zig build upstream-test`. That step is separate
from the fork's own `zig build test`, so a failure in either is attributable.

## 12. Upstream ships no pkg-config file, so this fork has to write one

There is no `.pc.in` in the tree; upstream installs only the headers and the
CMake export set (`src/CMakeLists.txt:223-252`).

*What was done.* The build graph generates `$prefix/lib/pkgconfig/box3d.pc`
from real metadata: upstream's own project `DESCRIPTION` and `VERSION`, an empty
`Requires`, `Libs.private: -lm -pthread` for the `libm` dependency at
`src/CMakeLists.txt:218-221` and the platform threading above, and `-DBOX3D_DLL`
in the shared variant only, which mirrors upstream's MSVC
`INTERFACE BOX3D_DLL` (`src/CMakeLists.txt:172-175`). `package.nix` copies
nothing and generates nothing, so there is one writer per installed path.

## 13. Packaging must not become a second build graph

*What was done.* `package.nix` is one uncurried derivation taking `linkage`
(validated against `""|"static"|"dynamic"`) and `optimize`; it runs exactly one
`zig build install --prefix "$out" -j NIX_BUILD_CORES -Dcpu=baseline
-Doptimize=…`, puts both Zig caches under `$TMPDIR`, sets `dontBuild`/`dontConfigure`
so the Zig setup hook cannot run a differently-flagged first build, and does not
set `dontInstall`. It never uses `builtins.getEnv` or
`builtins.currentSystem`; the cross-compilation refusal compares
`stdenv.buildPlatform.system` with `stdenv.hostPlatform.system`, which stays
correct on a remote builder. `flake.nix` exposes `.static`, `.shared` and a
`default` that preserves the static policy; `devenv.nix` names the same
derivation in lazy `outputs.*` and keeps its shell tools-only.

## 14. A Windows shared variant needs an export story this header does not have

`BOX3D_EXPORT` resolves from `_WIN32`, `box3d_EXPORTS` and `BOX3D_DLL`
(`include/box3d/base.h:21-35`). Upstream's own `config.h:26-30` says a single
value cannot switch between `dllexport` and `dllimport`, so the macro suits
embedding better than shipping Box3D as its own DLL.

*What was done.* No Windows package is exposed by the flake, and the reason is
recorded in `flake.nix` and in `README.md` as a packaging decision rather than
as a claim about the source. The Windows row of the compile matrix is a
different question and is still attempted by `zig build check`.

## 15. Upstream's determinism flag is a correctness requirement

`CMakeLists.txt:85-87` adds `-ffp-contract=off` for MINGW, Apple and Unix, and
links it to upstream's own determinism posts and its `test/test_determinism.c`.

*What was done.* The flag is kept on those platforms. It is not extended to
targets upstream does not put it on, and no floating-point flag appears in
`package.nix`; `build.zig` is the only place a C flag is written.

## 16. A collector that stops at the slice reports the wrong number

`overlapAabbCollect` and `castShapeCollect` exist because a query answers more
than one shape and a caller wants them in a slice. The first version wrote until
the slice was full and returned how much it had written — the same shape as
upstream's own capacity-taking calls, and wrong for a query, because how many
shapes a query finds is a property of the world and not of the caller's buffer.

*What was done.* Both keep counting after the slice is full and return
`ctx.count`, the total the traversal produced. The valid prefix of the slice is
`min(returned, out.len)`, so a return larger than the slice is the answer rather
than a truncation notice, and `slice.len == 0` is a legitimate "how many are
there" query. The order of the ids is still whatever the traversal produced;
upstream does not define it (`include/box3d/box3d.h:85`).

*Observed.* A two-shape overlap query given a one-slot slice answered `1`, and
`tests.zig:486` failed with `expected 2, found 1`
(`local://foundation-contract-box3d-real-stale-parent-errors-and-geometric-state-full-smoke-test.log`).
The overlap form's zero-length and overflow cases are probed
(`tests.zig:481`, `:485-486`) and pass.
**`castShapeCollect` is not probed at all** — nothing in `tests.zig` or
`smoke.zig` calls it — so the same change on that path is unexercised. It is
open below.

## 17. A stale parent is an assertion upstream, not a null id

`b3CreateBody`, the nine joint creators and `b3CreateShape` resolve their parent
before anything else, and that resolution asserts: `B3_ASSERT( id.generation ==
world->generation )` in `b3GetUnlockedWorldFromId` (`src/physics_world.c:96`)
and `B3_ASSERT( b3Body_IsValid( bodyId ) )` in `b3GetBodyFullId`
(`src/body.c:30`). The null-id answers at `src/body.c:171-174` and
`src/physics_world.c:101-104` sit **behind** those assertions, so a caller that
passes a destroyed parent gets a stopped process in a Debug build and cannot be
reached at all in one where `B3_ASSERT` compiled away.

*What was done.* Every typed creator asks the same public predicate upstream
exposes before it calls: `world.isValid` for `body.create` and the nine joint
creators, `body.isValid` for the seven shape creators. A gone parent comes back
as `error.InvalidWorld` or `error.ShapeCreationFailed`. The check after the call
is kept and is not redundant — it is what reports a locked world in a build whose
assertions were compiled out or whose assert handler skipped the break.

*Observed.* Without the preflight all three stale-parent tests died on
`B3_BREAKPOINT`, reached through `src/physics_world.c:96`, `src/body.c:30` and
`src/joint.c:439`
(`local://foundation-contract-box3d-initial-pose-ray-and-filtered-scene-caller-repair-smoke-test.log`).
They answer errors instead now and are in the recorded linked run
(`tests.zig:739`, `:757`, `:775`).

## 18. A full native pool cannot be turned into an error

`B3_MAX_WORLDS` is 128 (`include/box3d/constants.h:62-65`) and `B3_MAX_SHAPES` is
`1 << 22` (`include/box3d/constants.h:120-122`). Running out of either is an
assertion in upstream (`src/physics_world.c:223-228`, `src/shape.c:270-274`),
not a value it returns.

*What was done.* Nothing was pre-empted, because pre-empting it would mean
inventing a limit the caller did not ask about. `world.create` checks the id
after the call, so `error.WorldLimitExceeded` is reported only on the branch
where upstream survives to be asked; the shape pool has no error case at all. A
caller that must not abort keeps its own tally, against `base.maxWorlds` for
worlds and its own count for shapes.

*Observed.* A Debug run that filled the world pool stopped inside
`b3CreateWorld` at `B3_ASSERT( worldId != B3_NULL_INDEX )`
(`src/physics_world.c:226`) — the same receipt as §17 — before the null id on
`:227` existed to be checked. The test that filled it is not in `tests.zig`, and
no test fills either pool, so neither assertion is covered by a run.

## 19. Zig emits the wrong call for ten by-value signatures, and Box3D's bytes are right

Zig 0.16.0's x86-64 argument lowering consumes one vector-register pair for a
by-value float aggregate of at most 24 bytes that the System V ABI then passes in
memory. Ten `B3_API` signatures in `include/box3d/box3d.h` take a `b3Pos` by
value ahead of a floating-point argument or a floating-point return, so with
`-Ddouble-precision=true` — where a `b3Pos` is three `double`s, 24 bytes
(`include/box3d/math_functions.h:74-77`) — the floating-point argument after it
is allocated one register pair too high. Measured on this package's own
artifacts: the native `b3World_CastRayClosest` reads `translation` from
`XMM0`/`XMM1` and the Zig caller writes `XMM2`/`XMM3`, while the hidden return
pointer, the world id and the stack-passed `origin` and `filter` all agree. The
symptom is a valid `origin` reaching the callee beside an unreadable
`translation`, and it is what trips `B3_ASSERT( b3IsValidVec3( translation ) )`
at `src/physics_world.c:2995`.

The ten are `b3World_CastRay`, `b3World_CastRayClosest`, `b3World_CastShape`,
`b3World_CastMover`, `b3Body_CastRay`, `b3Body_CastShape`,
`b3Body_SetTransform`, `b3Body_GetLocalPoint`, `b3Body_GetWorldPointVelocity`
and `b3Shape_RayCast`.

*What was done.* `build_support/box3d_abi_bridge.c`, compiled into the same
module as the 49 upstream units and under the same `BOX3D_*` settings
(`build.zig:447-471`), exports `box3dAbi_*` functions that take pointers to the
same nominal types and forward to the unchanged by-value entry points, one call
each. Unlike Box2D's inline bridge this one cannot reuse an upstream name: the
symbol is present and correct and what is wrong is the call Zig emits for it, so
there is nothing upstream to shadow. The ten typed wrappers now pass their `b3Pos`
by address; every other wrapper still calls `c` directly, and the raw route's
declarations are untouched — reading them stays correct, calling them by value
on x86-64 does not.

The boundary is measured rather than assumed. `b3Transform` at 28 bytes and
`b3Mat3` at 36 bytes were checked on the same binary and agree with the native
callee, which is why nothing above 24 bytes is in the set; and
`b3Body_ApplyForce`, `b3Body_ApplyLinearImpulse`, `b3World_OverlapShape`,
`b3World_CollideMover`, `b3Body_OverlapShape`, `b3Body_CollideMover` and
`b3IsValidPosition` are out because nothing vector-classified follows their
`b3Pos`.

*Provenance.* `build_support/` is this fork's own directory. `UPSTREAM.sha256`
names it in the list of files deliberately absent from the 349-record upstream
manifest (header line 19), and `NOTICE.md:100` lists it among the fork's
`NativeDelivery` material, so the two new files are covered by directory and
need no record added to either. `FORK-LICENSE.md` §2 grants every file this fork
wrote, of which these are two.

*Not verified here.* The measurement is recorded in
`build_support/box3d_abi_bridge.h` and in `build.zig`. A gate at
`-Ddouble-precision=true` now exists and is green in `Debug` for both linkages —
run `box3d-double-type-values-after`, `9/9 steps; 19/19 tests passed` per loaded
row — but **this entry's own claim about the ten signatures at double
precision is still unverified here.** That run exercises the tests and the
smoke program at that setting; it does not exercise the ten by-value wrappers
in isolation, and §19's measurement is of exactly those. The open table says
what is outstanding.

## 20. Box3D's ARM path calls two intrinsics 32-bit ARM does not have

**Condition.** Compiling the 49 core units for any 32-bit ARM target.

**Symptom.** Four errors in one unit, `src/contact_solver.c:872` and `:877`:
`call to undeclared function 'vdivq_f32'`, `returning 'int' from a function
with incompatible result type 'b3FloatW' (aka 'float32x4_t')`, and the same
pair for `vsqrtq_f32`. Nothing else in the core fails.

**Cause.** `src/core.h:41-42` defines `B3_CPU_ARM` for `__arm__` and `_M_ARM`
as well as `__aarch64__` and `_M_ARM64`, so `src/core.h:59-61` selects
`B3_SIMD_NEON` for a 32-bit ARM target exactly as it does for AArch64, and
`src/contact_solver.c:777` includes `<arm_neon.h>` for it. On the pinned
toolchain `lib/include/arm_neon.h` declares `vdivq_f32` at `:50216` and
`vsqrtq_f32` at `:64883`, and both sit inside the block opened at `:44308`,
`#if defined(__aarch64__) || defined(__arm64ec__)`. That is not an oversight in
the header: the single-instruction float divide and the single-instruction
float square root are AArch64 NEON instructions. 32-bit NEON has integer
`vdivq` and no float divide or square root at all, so on 32-bit ARM there is no
set of compiler flags that makes this arm compile — `-march`, `-mfpu` and
every other spelling of "more SIMD" answer a question about which instructions
exist, and these two do not.

*What was done.* `BOX3D_DISABLE_SIMD` became the default **on those targets
only**, resolved per resolved target rather than once per build:
`Options.disable_simd` is a `?bool`, `resolveDisableSimd` answers it per
graph, and `targetLacksArmNeonFloatMath` is the rule — `std.Target.Cpu.Arch`
`.arm`, `.armeb`, `.thumb` or `.thumbeb`. `thumb` and `thumbeb` are
architectures of their own, not CPU features on `.arm`/`.armeb`:
`std/Target.zig:1374-1375` declares them as enum values, `std/Target.zig:1067`
gives all four the same `.ARM` ABI family, and `std/zig/system.zig:407-409`
*adds* `arm.thumb_mode` to the `thumb` architectures as a feature. The first
version of this rule matched `.arm` and `.armeb` only, on the opposite
reading of `:138-141`; that left every `thumb-*` target on the NEON arm.

Three things make this a correction rather than a second convention:

  * It is upstream's own option. `CMakeLists.txt:89` and
    `src/CMakeLists.txt:159-162` already offer it, and `src/core.h:50-53`
    already implements it.
  * It changes nothing a consumer sees. `B3_SIMD_NONE` keeps
    `B3_SIMD_WIDTH 4` (`src/core.h:51-52`), the same width `B3_SIMD_NEON`
    uses, so no struct grows, no field moves, no declaration changes and the
    `c` module is identical. The only difference is arithmetic width.
  * An explicit answer still wins. `-Ddisable-simd=false` on `arm-linux`
    selects the NEON arm and still fails to compile; that is a caller's choice
    made explicitly, and turning it into a success would be answering a
    question they did not ask.

The option is resolved against the target rather than in `build()` because
`check` walks six graphs of its own, none of which is the host: a single value
computed for the host would silently apply the host's SIMD answer to all six.
The configure-time line prints the *resolved* value, and prints the reason too
when the default was the one that decided it, so a bare `disable-simd=true` in
the output is not mistaken for somebody's configuration choice.

*Observed before the change.* The driver's 53-platform run
`cross-8/box3d/runs/20261004-164517-9067-28500` reports exactly four errors
and one failing unit on all nine 32-bit ARM cells — `arm-linux`,
`armeb-linux`, `arm-freebsd`, `arm-openbsd`, `arm-netbsd`, `armeb-netbsd`,
`thumb-linux`, `thumbeb-linux`, `thumb-windows` — and the same four errors on
no other target (`build-arm-linux.log:9-21`;
`build-arm-netbsd.log:65-77` shows them beneath the independent NetBSD
failure). Upstream's own `github/workflows/build.yml:53-54` passes
`-DBOX3D_DISABLE_SIMD=TRUE` for its `windows-11-arm` job, which is a data point
about upstream's own matrix rather than a fact about ARM32.

*Observed since.* The run `20261004-191759-29759-503` (53 targets, Zig
0.16.0, `test` step) compiles `arm-linux` and `armeb-linux` and runs all 19
tests on both, so the `.arm`/`.armeb` half of the rule is observed working.
The three `thumb-*` cells were still red on the same four errors at
`src/contact_solver.c:872`/`:877`, and their configure line reads
`disable-simd=false` (`build-thumb-linux.log:3-21`), which is the gap this
entry's rule had; `thumb`/`thumbeb` are now in it. `arm-freebsd`,
`arm-openbsd`, `arm-netbsd` and `armeb-netbsd` build and have no runner in
that run. Upstream's own `github/workflows/build.yml:53-54` passes
`-DBOX3D_DISABLE_SIMD=TRUE` for its `windows-11-arm` job, which remains a data
point about upstream's own matrix rather than a fact about ARM32.

*Not verified here.* No gate has observed the corrected default on a
`thumb-*` target.

## 21. Eleven targets break at the Zig-to-C boundary, at four different points in the call

**Condition.** A Zig root — `addTest` or `addExecutable` — that calls this
package's translated C surface. The first form of this entry named Zig 0.16.0's
default self-hosted backend as the cause; the receipt cited under *Observed
since* removes that, so the condition is restated as what the evidence still
supports.

**Symptom, and the four boundaries this is not one of.** The build succeeds and
the run does not. Eleven cells fail at run time, at four different boundaries
rather than at one. This entry's first form said eleven cells hand the C callee
a garbage pointer; the receipts do not support that for the world-ID rows,
where the payload arrives intact and what comes back is wrong. Each row is
named by the **earliest** boundary that breaks, not by the last error printed,
and each target has a passing C control on the same headers and the same
sources.

| Target | First boundary | What the receipt shows |
|---|---|---|
| `aarch64_be-linux` | world ID, wrong **return** | `b3WorldDef` marker matched; `b3CreateWorld` returned `index1=0 gen=51`, `worldvalid=false`; the C control returned `index1=1 gen=0`, `worldvalid=1` |
| `mips64-linux` | world ID, wrong **return** | same shape: returned `index1=0 gen=0`, `worldvalid=false`; control `index1=1 gen=0`, valid |
| `powerpc64-linux` | world ID, wrong **return** | returned `index1=0 gen=40755`, `worldvalid=false`; control `index1=1 gen=0`, valid |
| `x86-linux` | world ID, wrong **argument** | the returned `index1=1 gen=0` looks native, and `consumer-worldvalid=false`: the id is right and the later `b3World_IsValid` argument is not |
| `powerpc-linux` | `b3WorldDef` pointer | raw `misaligned address 0x6f0d5052 for 'const b3WorldDef' requires 4` at `src/physics_world.c:208`; typed `0x119417`. No world ID is ever returned |
| `s390x-linux` | `b3WorldDef` pointer | raw fires the C assert `def->internalValue == B3_SECRET_COOKIE` at `src/physics_world.c:208`, then `Illegal instruction at address 0x1091a42` via `src/core.c:88`; typed `Segmentation fault at address 0x7fc000000000` at the same site. No world ID is returned |
| `hexagon-linux` | `b3BodyDef` pointer | world ID accepted (`index1=1 gen=2851`, valid) and body marker matched, then `misaligned 0x1 for 'const b3BodyDef' requires 4` at `src/body.c:159` |
| `loongarch64-linux` | `b3BodyDef` pointer | world ID valid, then `misaligned 0x1 requires 8` at `src/body.c:159` |
| `mips64el-linux` | `b3BodyDef` pointer | world ID valid, then `misaligned 0x4 requires 8` at `src/body.c:159` |
| `powerpc64le-linux` | `b3BodyDef` pointer | raw `misaligned 0x45 requires 8`; typed `0x72 requires 8` |
| `riscv32-linux` | trailing shape arguments | raw-direct, reported as it stands: world ID and body valid, `native-scalar-valid=1`; registered `def=0x2b2ab328 hull=0x2b2ab170`, adapter received `body 1/0/1` correct with `def=0x1 hull=0x10000`; `matches body=1 def=0 hull=0`, `exit 70`. The `0x1` and `0x10000` are the body's own words. Typed, reported as it stands: registered `def=0x2b2ab368 hull=0x2b2ab1b0`, adapter received `def=0x8f74d8 hull=0x8f74d8`; `exit 70`. The typed facade builds its own `native_def` before calling `b3CreateHullShape` (`zig/shape.zig:247-253`), so its registered-def difference alone proves nothing about corruption; its hull pointer is wrong against its own registered hull |

The typed stage reports the first four as `error.WorldLimitExceeded` at
`zig/world.zig:197`, which is `b3World_IsValid` answering for an id the run did
not keep: the same four targets as the world-ID rows, not four more failures.
The `riscv32` row is not a crash either, because the adapter exits `70` on a
mismatch: the boundary is entered with a wrong argument and reported rather than
dereferenced. Five cells of the same cross-test run — `x86_64-linux`,
`aarch64-linux`, `mips-linux`, `mipsel-linux`, `riscv64-linux` — pass all 19
tests from the same sources and the same headers.

**What these receipts establish, and what they leave open.** Every row's C
control passes on the same headers and the same sources: all ten foreign
`c-native` stages, the eleventh on `x86-linux`, and on the other side
`x86_64-linux` passes all three stages. The C-to-C boundary is therefore intact
on each of them, and the failure is specific to the Zig-to-C crossing. Each
probe also verified the payload before the crossing: `marker_matches=1` on the
`b3WorldDef` and the `b3BodyDef`, `native-scalar-valid=1` on the hull. What the
table does **not** establish is one cause behind the eleven rows. They are four
distinct first boundaries with four distinct observed values; whether the
compiler-level defect behind them is one thing is unresolved, and this entry
claims the boundaries and the values, not a shared mechanism. No backend and no
root cause is attributed to any row, and no instruction-level claim is made
about any of them. That is what
replaces the undifferentiated reading of these eleven cells in *Observed since*
below, which the dated run itself still records as it saw it.

**Cause.** Not narrowed past the boundary, and deliberately not claimed
narrower. What the tree already knows is §19: Zig 0.16.0's backend lowers a C
ABI argument list differently from the compiler that built the core, measured
at register level on this package's own artifacts, with the symptom being a
valid argument reaching the callee beside an unreadable one. The ten wrappers
in `build_support/box3d_abi_bridge.h` exist for the by-value subset of that;
the observed failures above are the same shape on signatures that take a
pointer, which is why they were not caught by it. That the same toolchain's
default backend mis-passes a C-ABI call is independently recorded for ERFA in
this workspace with a two-run discriminator — same archive, same facade, same
two argument vectors, differing only in `-fllvm`
(`erfa/FORK-NOTES.md` entry 18).

*What was done.* `.use_llvm = true` on every Zig root this package owns: the
`test` root, the published `smoke` root, and the two roots `check` creates per
matrix target (`build.zig`), plus the consumer's own executable root
(`consumer/build.zig`). The C archive and upstream's C unit-test program are
deliberately left alone: neither has a Zig root, and the backend buys a
correct call made *from* Zig.

The part that is easy to get wrong is that a module cannot enforce this. The
backend is a property of the `addExecutable`/`addTest` root, which belongs to
whoever writes the build file. A published module cannot reach a dependent's
root, so the package's own consumer states it, and every external dependent
has to state it too. That is recorded in `build.zig`'s header note and in
`consumer/build.zig`'s, and it is why `consumer/build.zig` was changed rather
than only `build.zig`.

*What this does not do.* It does not retire
`build_support/box3d_abi_bridge.h`. With LLVM selected, the ten by-value
signatures the bridge exists for are no longer mis-lowered, so the bridge is a
workaround for a backend this build no longer selects — but it is also part of
the published `c` module and of the generated runtime dispatch, and removing
it is a cutover decision with its own gate, not a side effect of this entry.
Flagging it here so the decision is made rather than inherited.

*Observed before the change.* The eleven cells named above in the run
`20261004-164517-9067-28500`, `build` status `pass` and `run` status `fail`
with 19 tests each.

*Observed since, and it changes the diagnosis.* In the run
`20261004-191759-29759-503` those eleven cells are red again with the same
shape — 19 of 19 tests each, seven crashing inside `b3CreateBody`/
`b3CreateWorld`/`b3IsValidHull` on an argument that is not the one the caller
passed, four answering `error.WorldLimitExceeded` at `zig/world.zig:197` — and
the flag *was* in force: the two NetBSD cells' inner compile line is
`zig test -fllvm … -Mroot=tests.zig` (`build-aarch64-netbsd.log:11`), which is
the LLVM backend on the root module. So this entry's stated cause is not
supported by the evidence it now has: selecting LLVM did not change the
outcome, so the default backend is not the discriminator. Two other
candidates are also excluded by receipts in this workspace. The runner is
not: `gmp` runs all 47 tests and `htscodecs` all 42 on `hexagon-linux`,
`loongarch64-linux`, `mips64-linux`, `mips64el-linux`, `powerpc-linux`,
`powerpc64-linux`, `powerpc64le-linux`, `riscv32-linux` and `s390x-linux`
through the same `qemu-*` runners, on the same toolchain. Nor is the shape
Box3D's own: `box2d`, a different C library behind a different facade and
different headers, fails the same way on the same targets
(`misaligned address 0x1 for type 'const b2BodyDef'`,
`0x94d464fd for 'const b2WorldDef'`), in a run of its own.

What is left is the Zig→C call boundary for this pair of packages on those
targets, and the tree has not narrowed it further than that. Two things
would: a two-run discriminator on the same archive and the same facade
differing only in `-fllvm`/`-fno-llvm` (the one ERFA already ran, and this
run is not it, because both backends are being selected by this build), and
a disassembly of the caller and callee pair for one failing target against
one passing target. Until one of those lands, this entry claims the symptom
and the boundary, not the backend.

## 22. Aro cannot read NetBSD's `_Pragma`, and one preprocessor can

**Condition.** `zig translate-c` on any NetBSD target.

**Symptom.** `error: translation failure` with five errors, all at
`generic-netbsd/math.h:607`: `unknown type name 'pragma'`, `expected ';',
found 'an identifier'`, `unknown type name 'visibility'`, `expected ';', found
''`, and `error: 5 compilation errors`. The C archive itself compiles: on
`aarch64-netbsd` the build summary shows `compile lib box3d Debug aarch64-netbsd
success 10s` next to the failing `translate-c`.

**Cause.** `generic-netbsd/sys/cdefs.h:411-416` defines
`__END_PUBLIC_DECLS` as `__END_EXTERN_C _Pragma("GCC visibility pop")` and
`:432` routes `__END_DECLS` through it; `generic-netbsd/math.h:607` closes
its declaration block with `__END_DECLS`, and `include/box3d/math_functions.h:11`
is the line that reaches `<math.h>`. Aro destringizes each `_Pragma` into a
`#pragma` line and then hands that line to the parser as C. It is the one
bundled C library in this matrix whose `__END_DECLS` is not made of plain
tokens.

*What was done.* The build now chooses its front end per target. On
`os.tag == .netbsd`, `zig/translate.h` is expanded first by the compiler running
this build script — `zig cc -E -dD`, `-target` the resolved triple when it is
not native, `-I include`, the same two macro definitions
`addTranslateMacros` puts on the translation line, and `-MD -MF` so the
discovered headers are this step's real declared inputs — and Aro parses what
that produced. Every other target keeps the route it had, and the whole
aggregate still arrives: nothing is stubbed, narrowed, renamed or dropped.

`-dD` is load-bearing, not decoration. Without it the expansion carries no
macro definitions, and Box3D's public surface is largely macros
(`include/box3d/constants.h` and the `B3_*` limits in
`include/box3d/base.h`), so a macro-only dump would take the constant set with
it and this route would describe a different `c` module from the one every
other target gets. `-MD` is equally load-bearing: the eight public headers are
reached only through `#include`, and a `-I` directory argument contributes
nothing but its own resolved path to a run step's manifest, so without a
depfile a later revision of `include/box3d/base.h` would be served from the run
cache while the translation went on describing the previous one.

The condition is the OS tag rather than a list of nine triples. The whole family
shares one header and one cause, so a list would cover today's nine
architectures and silently stop covering the next one.

This is the convention ERFA already uses for the same header
(`erfa/build.zig`, `aggregateRoute`/`preprocessedAggregate`), so the two SDKs
now read the same way; Box2D has the same pair under the same names.

*Observed before the change.* All nine NetBSD cells of the run
`20261004-164517-9067-28500` and no other cell
(`build-aarch64-netbsd.log:10-58`, `:66`).

*Observed since.* The run `20261004-191759-29759-503` translates all nine
NetBSD targets — the `_Pragma` failure is gone, `translate-c success` appears
in every one of their build summaries, and the seven non-AArch64 cells build.
The follow-on predicted here is now an observation, on the two cells that take
the `__ARM_PCS_AAPCS64` branch: `aarch64-netbsd` and `aarch64_be-netbsd` fail
to compile the translated module with one error each,
`box3d-translate.zig:5208:43: error: use of undeclared identifier
'__int128_t'` under `pub const __ALIGNBYTES = __helpers.sizeof(__int128_t) -
@as(c_int, 1);` (`build-aarch64-netbsd.log:5-9`, `build-aarch64_be-netbsd.log:5-9`),
and their C archives compile (`compile lib box3d Debug aarch64-netbsd success
20s` beside the failing step).

The correction is the one ERFA, LMDB and PCRE2 already carry in this
workspace: under the compiler's own `__SIZEOF_INT128__`, `zig/translate.h`
restates `typedef __int128 __int128_t;` and `typedef unsigned __int128
__uint128_t;` ahead of its one real include. That declares a compiler builtin
no libc header declares; it touches no upstream file and restates nothing of
the C library. `zig/translate.h` is the API role's file, not this one's, so it
was proposed there rather than edited from here.

*Applied, and the pattern verified rather than assumed.* `zig/translate.h:118-122`
now carries the guarded pair ahead of its one real include, under the
compiler's own `__SIZEOF_INT128__`. The sibling pattern was re-checked in each
package before applying it here, because the choice is between two private
options and only the evidence decides which: ERFA
(`erfa/zig/translate.h:139-143`) and PCRE2 (`pcre2/zig/translate.h:113-117`) put
the same two typedefs in their own `zig/translate.h`, LMDB carries the identical
three lines (`lmdb/translate.h:44-47`), and LuaJIT generates the same completion
and pulls it in with `-include` on its preprocessed route
(`luajit/build_support/graph.zig:1217-1222`), guarded additionally by
`!defined(__int128_t)`. Every one of them declares a **compiler builtin** and
touches no upstream `.c` or `.h` byte and no libc declaration; the one place a
target might already spell the name itself (LuaJIT) adds the second guard for
that reason, and C's permission to restate a typedef for the type it already
denotes is what makes the unguarded form safe either way. This package reads the
whole aggregate itself on both routes — `build.zig` hands `zig translate-c` this
file, or hands it what `zig cc -E -dD` already wrote from it — so the inline form
is the one that applies here, and no `-include` and no `build.zig` line is
needed. **Not verified here:** the two cells have not been re-run, so this is
`PENDING-VERIFICATION` and the eleven boundary cells and the two AArch64 cells
keep whatever state their last run left them in.

## 23. The canonical devenv could not be entered, and its tasks ran in the project directory

Box3D's `devenv.yaml` declared `flake: false` on its `nixpkgs` input, and every
task body in `devenv.nix` named files relative to the caller's working
directory. Both are one mistake wearing two coats: the environment assumed it
was used the way its author had it, and nothing in it said otherwise.

*Symptom, observed in siblings and not here.* The three SDKs that carried the
identical `flake: false` line — Box2D, fast_float and Lua — lost all seven of
their devenv gates to one byte-identical error before evaluating anything:
`x Failed to get attribute 'config.cachix.enable':` at
`.devenv/bootstrap/bootstrapLib.nix:54:13`, `53| inherit (inputs) nixpkgs;` /
`54| lib = nixpkgs.lib;`, `error: attribute 'lib' missing` (run
`20261004T175328Z`; `box2d-devenv-info.log`, `fast_float-devenv-info.log`,
`lua-devenv-info.log`). With that key devenv's `nixpkgs` is a plain source path,
a path carries no `lib`, and the module system never bootstraps. The 14 SDKs in
that run that declare no `flake:` key are unaffected.

*Symptom, same class, same run.* For the ten SDKs that did bootstrap, every
`devenv:integrity` and `devenv:consumer` gate failed on a relative path —
`sha256sum: UPSTREAM.sha256: No such file or directory`, `cd: consumer: No such
file or directory`, `error: no build.zig file found, in the current directory or
any parent directories`. devenv materialises a task and a script as a generated
shell program that inherits the caller's cwd, and that cwd is the devenv
*project*: it holds `.devenv/` and `devenv.lock` and none of this SDK's files.
`$DEVENV_ROOT` names that same directory, so reaching for it would have
reproduced the failure exactly.

*What was done.* `devenv.yaml` keeps its pin and loses the `flake:` key.
`devenv.nix` resolves `sdkRoot = builtins.toString ./.` — `./.` is relative to
the module writing it, so it is this SDK's directory whatever the caller started
from — and every task body naming a file here begins `cd "$sdkRoot"`. The
integrity checker is handed that path instead of assuming it, because
`tools/check-provenance.sh:24` resolves its own repository from its own `$0`.
The two default `zig build` tasks pass `--prefix` into
`$ZIG_LOCAL_CACHE_DIR/box3d/{static,shared}`, which `enterShell` fills from
`TMPDIR`; the default install step of `build.zig` makes that necessary, since a
default `zig build` installs the artifact, the generated pkg-config file and the
licence records, and would otherwise write `zig-out/` into this tree. A caller's
own `--prefix`/`-p` is detected in every spelling and passed through untouched
rather than overridden, and this file's prefix is written before `"$@"` so even
an unrecognised spelling wins by being last instead of being silently replaced.
`sdk:package_static` and `sdk:package_shared` deliberately do *not* `cd`: a
`devenv build` started inside this SDK would make the SDK the project root and
leave `.devenv/` and `devenv.lock` in the tree, so they address the module with
`--from "path:$sdkRoot"` and leave the project root with the caller. Five task
names lost their `.` — devenv requires `namespace:name` and rejects anything
outside alphanumerics, `:`, `-` and `_` — so `sdk:build.shared`,
`sdk:test.release-safe`, `sdk:check.shared`, `sdk:package.static` and
`sdk:package.shared` are now `sdk:build_shared`, `sdk:test_release_safe`,
`sdk:check_shared`, `sdk:package_static` and `sdk:package_shared`.

*Targets bound.* The `flake:` key and the task cwd are devenv behaviour, not a
platform and not a Zig version. The prefix rule is bound to a build graph whose
default step installs — this one, and not `test`, `smoke`, `check`,
`upstream-test` or `consumer`, none of which depends on the install step: each
is a `b.step` in `build.zig` wired to its own run step.

*Not verified here.* **One devenv evaluation of this file has run, and it is
the cause rather than the proof.** Run `20261004T212645Z` took gate
`devenv:info` — `devenv info --no-impure --no-reload --no-tui --max-jobs 2
--cores 8`, `exit 1` after 2.138 s — and died converting the `env` attribute to
JSON, at `devenv.nix:222`, reporting `error: expected a set but found a string:
"static"` with the caret under `box3d "static".version`: application bound
tighter than the select, so `linkage` reached `package.nix:25` as
`"static".version`. `devenv:shell-zig-version`, `devenv:shell-zig-env`,
`devenv:consumer` and `devenv:integrity` failed at the same line,
`devenv:tasks-list` passed because a task list does not force `env`, and no
`zig build` ran. The receipt is that run's `box3d-index.json` under
`/home/tmp2/gertullj/scratch/foundation-libs/contract-physics-lua/nix-acceptance-evidence/20261004T212645Z`,
with that gate's output in `box3d-devenv-info.log` beside it. `devenv.nix:222`
now reads `(box3d "static").version`, which is source-only and unrun since.

An evaluation that stops inside `config.env` enters no shell and runs no task
body, so that run proves none of this section. The task names, the directory
the bodies now `cd` into, the `buildFlags` tail and the cache preamble are all
still `PENDING-VERIFICATION`, and the `flake:` diagnosis is still read out of
three sibling receipts — Box3D was not one of the 18 SDKs in run
`20261004T175328Z` either. Two things the driver's next run settles and no
reading of the source can: whether `./.` renders as this working tree or as a
`/nix/store` copy — a store copy is read-only, so `cd "$sdkRoot"` would then
fail — and whether `devenv build` accepts `--from`, which affects only the two
packaging tasks.

## 24. The nested `consumer` build was given no prefix, and resolved its own under `consumer/`

**Condition.** `zig build consumer`, which builds the independent
`dep.module("box3d")` package in `consumer/` from this SDK's root.

**Cause.** The one `Step.Run` that drives it, `runConsumer` in `build.zig`,
wrote the target query, the CPU, every mode option, the executor switches,
`-j8`, `--summary all`, the local cache with a `/consumer` subdirectory, the
external global cache and the caller's own arguments behind `--`. It did not
write an install prefix. The nested build then resolved its own default, which
is `<its build root>/zig-out`, and its build root is `consumer/` because that is
the working directory `runConsumer` sets. The prefix the caller named on the
outer `zig build` therefore stopped at the outer graph, so any install the
nested graph performed went to a `zig-out` inside this SDK's tree rather than to
the directory the caller asked for.

**What was done.** `runConsumer` now writes `--prefix` and this graph's actual
`b.install_prefix`, and writes them only when the caller named one. The guard is
the default itself: `b.install_prefix` equals `<this build root>/zig-out` when
nothing was named, and the nested build resolves the same `zig-out` under
`consumer/` by itself in that case, so forwarding it would name nothing. A
relative value is joined against `b.graph.cache.cwd` first, because a relative
`--prefix` would resolve against the nested working directory. `DESTDIR` is not
forwarded: the nested build inherits this one's environment. Nothing else moved
— same signature, same single caller, same two optional cache captures with no
fallback, same `--` handoff — and `consumer/build.zig` did not change.

`b.step("consumer", "Build the independent dep.module(\"box3d\") consumer,
`and run it when this host can execute it").dependOn(&runConsumer(b, target,
`optimize, opts).step)` depends on, and that `dependOn` is its only caller.
The run forwards:

* the caller's target **query**, as `-Dtarget=` from
  `Target.Query.zigTriple` and `-Dcpu=` from
  `Target.Query.serializeCpuAlloc`;
* the mode, as `-Doptimize=`, `-Druntime=`, `-Ddouble-precision=`,
  `-Dvalidate=` and `-Dlinkage=`, plus `-Ddisable-simd=` as `resolveDisableSimd`
  answers it for **this** graph's target rather than as the optional the caller
  typed;
* the selected executor: `-fdarling`, `-fqemu`, `-frosetta`, `-fwasmtime` and
  `-fwine` when the matching `b.enable_*` is set, and `--libc-runtimes` with
  `b.libc_runtimes_dir` when that is set;
* `-j8` and `--summary all`;
* `b.cache_root.path` as `--cache-dir` plus a `/consumer` subdirectory, and
  `b.graph.global_cache_root.path` as `--global-cache-dir` — both captured
  rather than defaulted, so a run with no path to name invents no directory;
* `--prefix` with `b.install_prefix`, as above;
* `b.args`, last and behind `--`.

The caller's arguments cross both hops. `runConsumer` writes `--` and then
`b.args`, which is where the build runner stops parsing options and starts
recording arguments (`lib/compiler/build_runner.zig:428-430`), and
`consumer/build.zig` hands its own `b.args` to `run_exe`, the
`addRunArtifact` of the consumer executable. So
`zig build consumer -- ARGS` reaches the consumer program rather than the
nested build graph. The step runs the consumer when an enabled executor can
execute the selected target, and installs it otherwise, so a foreign
installation is build-only evidence and never a passing consumer exchange.

**Observed, and it is the evidence this entry asked for.** Run
`20261004T223101687849Z-e3904589dead` drove this step nine times and passed all
nine: four routes, static and dynamic linkage each linked and each
runtime-loaded, with the SDK's own defaults omitted in four cases and stated in
four. Every nested command carried `-Dtarget`, `-Dcpu`, `-Doptimize`,
`-Druntime`, `-Ddouble-precision`, `-Ddisable-simd`, `-Dvalidate`, `-Dlinkage`,
`-j8`, `--summary all`, this graph's local cache with the `/consumer`
subdirectory, and the external global cache. The routing answers are in the
argv: `-Dtarget=native -Dcpu=native` where the caller named no target, and
`-Dtarget=x86_64-linux-gnu -Dcpu=baseline` where it named one, which is
`Target.Query.zigTriple` and `serializeCpuAlloc` written out unchanged.

The prefix forward is one fact in all nine: the nested `--prefix` is
byte-identical to the outer one. The caller's arguments crossed both hops in
the four loaded cases — `--provider PATH` reached the consumer program, with
every provider environment variable absent from the child, so there is no
fallback to read the path out of and no handoff to disambiguate. The ninth case
is the refusal: `-Druntime=true` with no provider at all, and the program printed
the refusal its own source declares and exited 1, with the nested build
reporting `Build Summary: 4/6 steps succeeded (1 failed)`. The eight passing
cases each reported `Build Summary: 6/6 steps succeeded`.

**What is still not claimed.** All nine are `Debug` on one native host, and the
four explicit-target cases name `x86_64-linux-gnu` and nothing else, so no
foreign target has driven this step. The relay of `-Ddisable-simd` is observed
only where `resolveDisableSimd` answered `false`, and no case names a target
where it answers otherwise. No case names a directory the nested graph installed
into, because the nested `run` step depends on no install step: what these
cases show is the prefix reaching the nested build, not a populated prefix.

## Open, and not yet resolved by this role

| Item | State |
|---|---|
| Every gate | **Six build-gate runs have receipts, one devenv acceptance run has all eight of its gates, one nested-delivery run has nine of nine, and one native-final run has eight of eight.** Observed: `zig build smoke test --prefix DIR` (`18/18 tests`, `9/9 steps`), `zig build install -Dlinkage=dynamic` (`13/13 steps`), `zig build smoke -Druntime=true -- --provider PATH` (`6/6 steps`), the three `-Ddouble-precision=true` rows of `box3d-double-type-values-after` (`13/13 steps`, then `9/9 steps` and `19/19 tests` twice), run `20261004T214803Z`'s eight devenv gates (`BOX3D_SDK_VERSION: 0.1.0`, the banner's `sdk root:` and `cache:` lines, `zig version` `0.16.0` from the store compiler, `sdk:consumer` and `sdk:provenance` green), run `20261004T223101687849Z-e3904589dead`'s nine `consumer`-step cases (§24: four routes, defaults omitted and stated, and the no-provider refusal), and run `contract-final-after-20261004`'s eight native cells — static and dynamic in `Debug`, ReleaseSafe, ReleaseFast and ReleaseSmall, each `Build Summary: 18/18 steps succeeded; 19/19 tests passed` with 15 or 17 installed files. That last run is this SDK's first Release-mode evidence; it is native, and the run as a whole reported 144 passes and 32 skipped tests of 176 and exited 1. Outstanding: the bare `zig build`, `zig build upstream-test`, `zig build check` for both linkages and all six compile targets, the installed C consumer, the fetched consumer, an in-tree runtime provider, both Nix derivations (`nix:build` was the one gate `gates_not_run` named), the ten `devenv` task bodies other than `sdk:consumer` and `sdk:provenance`, and any foreign target through the `consumer` step. The driver owns every one of those result fields. |
| The 53-platform `cross-test` run | **Red in 16 of 53 cells.** Observed, run `20261004-191759-29759-503`, Zig 0.16.0, `test` step, `-Dtarget=TARGET` per cell, 18 target executions, source unchanged: 7 cells ran all 19 tests (`x86_64-linux`, `aarch64-linux`, `arm-linux`, `armeb-linux`, `mips-linux`, `mipsel-linux`, `riscv64-linux`), 30 compiled with no available runner and are `build_only`, which is coverage and not a pass, and 16 are red — 5 build failures and 11 run failures. The 5 build failures are three `thumb-*` cells failing on `src/contact_solver.c:872`/`:877` (§20: the rule omitted `.thumb`/`.thumbeb`, now corrected and unobserved) and `aarch64-netbsd`/`aarch64_be-netbsd` on the translated module naming an undeclared `__int128_t` (§22's follow-on, now observed, correction proposed in the API role's `zig/translate.h`). The 11 run failures are §21's, unchanged in shape and with `.use_llvm` in force, so §21's stated cause is withdrawn. §20's `.arm`/`.armeb` half and §22's preprocessed route are both observed working in this run. |
| The 53-platform `cross-test` run, current epoch | **Red in 11 of 53 cells, and no build failure at all.** Observed, run `20261004T221720228710Z-45046`, receipt `box3d-53-target-8.json`, `--jobs 8 --build-jobs 8`, source stamp `88106c0349…` identical before and after: 9 cells ran all 19 tests, 33 compiled with no available runner and are `build_only`, which is coverage and not a pass, and 11 failed their run. All 11 sit on the Zig-to-C boundary: `error.WorldLimitExceeded` raised at `zig/world.zig:197` on `aarch64_be-linux`, `mips64-linux`, `powerpc64-linux` and `x86-linux`; a misaligned or null `const b3BodyDef` at `B3_CHECK_DEF( def )` and a misaligned `const b3HullData` at `src/hull.c:1658` on `hexagon-linux`, `loongarch64-linux`, `mips64el-linux`, `powerpc64le-linux` and `riscv32-linux`; and `Segmentation fault` on `powerpc-linux` and `s390x-linux`. Every one of the 53 cells built, so the five build failures the row above records are absent from this run. This run predates every build-graph, header, helper and normalisation edit made after it, and no cause is claimed for the 11. |
| `zig build check` | **Observed over the default linkage only.** Label `baseline-box3d-check`, baseline run `20261005T014547Z-797a73f2`, 2026-10-05: `exit 0`, `Build Summary: 37/37 steps succeeded`, no failing step, all six declared compile targets seen. It compiles and links and runs nothing. `zig build check -Dlinkage=dynamic` is still unobserved, so no compile claim is made for `wasm32-wasi` under a shared delivery. |
| `build_support/box3d_abi_bridge.h` under `.use_llvm = true` | **Open, and deliberately not resolved here.** §21 selects LLVM on every Zig root, and the ten by-value signatures the bridge exists for (§19) are exactly the ones that defect was measured on. That makes the bridge a workaround for a backend this build no longer selects. It is also part of the published `c` module and of the generated runtime dispatch, so retiring it is a cutover with its own gate and its own record — not a side effect of §21. Nobody may read §21 as having removed it; it is still compiled, still installed and still what the ten wrappers call. |
| `flake.lock` and `devenv.lock` | **Do not exist and were not invented.** `flake.nix` pins `github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f` and `devenv.yaml` pins `github:cachix/devenv-nixpkgs/c2f38fe7f9e04d9aadd354d380f2bd40531d9737`; creating a lock from a pin is a resolution this fork has not performed. |
| `.fingerprint` | **Absent, deliberately.** It is a compiler-provided value; leaving it absent is correct, and inventing one would be a fabricated identifier. |
| Typed-surface names in `README.zig.md` | **Resolved.** Documented against the API role's landed decisions: flat types on the root and the seven namespaces `math`, `base`, `world`, `body`, `shape`, `joint`, `query`; `load`/`loadedSource`/`runtime_loaded` and the eight `LoadError` cases; `createModule`/`createCoreModule`; the `box3d_rt_*` sync symbols. The raw route is documented from the pinned headers; the raw-route snippet in `README.md` uses only names read out of `include/box3d/`, and the typed snippet beside it only names that exist in `zig/` and sets up the scene `smoke.zig` runs. |
| Double-precision symbol names in the runtime descriptor | **Requirement met, and now exercised.** A source requirement on the generated dispatch: the library exports `b3CreateWorldDoublePrecision`, not `b3CreateWorld`, when `BOX3D_DOUBLE_PRECISION` is on, so resolving the header text instead of the expanded names would fail in that configuration only. The run `20261004T200055Z-092d7677` is a runtime-loaded build at `-Ddouble-precision=true` that resolved every symbol — the refusal its two loaded rows record is the precision guard's, not `error.MissingSymbol` — and the provider it was given exports `b3CreateWorldDoublePrecision` and no `b3CreateWorld` (`nm -D --defined-only` on the installed object). |
| A gate at `-Ddouble-precision=true` | **Observed green in `Debug` and in both linkage choices, after a guard defect this tree carried and fixed.** **Before**, run `20261004T200055Z-092d7677`: the provider row `zig build install -Ddouble-precision=true -Dlinkage=dynamic` was green (`13/13 steps`), and the two `loaded` rows — `-Dlinkage=static` and `-Dlinkage=dynamic` — both exited 1 refusing a correctly-built double provider, `box3d: refusing this provider: b3IsDoublePrecision() disagrees with the precision mode these headers were translated for`, printed 20 times per row from `runtime/loader.zig:508`, then `0/19 tests passed (19 crashed)` and the smoke executable exiting 1 on `error.ValidationFailed`. **Cause, at source.** The guard computed `translated_single_precision` as `@TypeOf(dispatch.b3Pos) == @TypeOf(dispatch.b3Vec3) and @TypeOf(dispatch.b3WorldTransform) == @TypeOf(dispatch.b3Transform)`. Both names are type-valued declarations (`pub const b3Pos = c_native.struct_b3Pos;` in the generated dispatch), so `@TypeOf` of either is `type`: that compared `type == type`, true for every pair. It folded to true for the double translation, `headers_are_double` to false, and a correct provider was refused. The row's own generated sources show the two types are genuinely distinct (`struct_b3Vec3` three `f32` against `struct_b3Pos` three `f64`; `struct_b3Transform.p: b3Vec3` against `struct_b3WorldTransform.p: b3Pos`), so the answer was there to be read and was not read. **Fix, two lines in `runtime/library.zig`.** The comparison is now between the two type values themselves, `dispatch.b3Pos == dispatch.b3Vec3 and dispatch.b3WorldTransform == dispatch.b3Transform`, which is the header's own answer and the same reading in both precision modes. The reused cache epoch was never a candidate cause: the defect was in the source those rows compiled. **After**, run `box3d-double-type-values-after`: three rows, all `exit 0` — the provider `zig build install -Ddouble-precision=true -Dlinkage=dynamic` (`13/13 steps`), and both `zig build test smoke -Ddouble-precision=true -Druntime=true -Doptimize=Debug` rows, `-Dlinkage=static` and `-Dlinkage=dynamic`, each `9/9 steps succeeded; 19/19 tests passed` against a provider built from this tree. **What this row does and does not establish.** It establishes that the guard compares the two type values, and that the `-Ddouble-precision=true` runtime path — provider install, load, 19 tests and the smoke program — ran end to end in `Debug` for both linkages for the first time. It does not retroactively make the guard sound before the fix, and it does not cover ReleaseSafe, ReleaseFast or ReleaseSmall, any of the six cross targets, or §19's ten by-value signatures at double precision, which this configuration's earlier refusals never reached. Those remain as the open table says. |
| `castShapeCollect`'s total-count behaviour | **Unprobed.** The overlap collector's zero-length and overflow cases are in `tests.zig` and pass; nothing calls the cast collector at all, so §16's contract on that path rests on reading `zig/query.zig`. What would close it is a cast of a proxy through both bodies with a one-slot slice, asserting a return of the full hit count — the shape of the case `tests.zig:485` already makes for the overlap form. |
| Which Nix systems the flake exposes | Four Unix systems. Extending that list is a driver decision once a gate says a system builds. |
| The devenv task runner's spelling | **Changed by §23, and now observed on two bodies.** `devenv.nix` declares `namespace:name` tasks with real `exec` bodies, each naming the five dotted variants it once spelled with `_`, each body resolving its own SDK root rather than the caller's cwd. That the pinned devenv accepts the names, and that a body resolves its own SDK root from another directory, is observed: in run `20261004T214803Z` `devenv tasks list` and `devenv info` listed all twelve `sdk:*` names, and `sdk:consumer` and `sdk:provenance` ran under `--mode single` with a working directory outside this tree and `sdk root:` naming this SDK. The other ten bodies are still `PENDING-VERIFICATION`. |
| The gate flags and cache preamble in `devenv.nix` | **Documented; one row of it observed, no gate covers the rest.** One `buildFlags` value ends all nine `zig build` invocations this file can reach: `-j8 --summary all --cache-dir "${cacheDir}" "$@"` (`devenv.nix:118`), covering the two `deliveryBuild` lines (`:153`, `:156`) that serve `sdk:build` and `sdk:build_shared` and the seven task bodies `sdk:test` (`:244`), `sdk:test_release_safe` (`:252`), `sdk:upstream-test` (`:260`), `sdk:smoke` (`:268`), `sdk:check` (`:276`), `sdk:check_shared` (`:284`) and `sdk:consumer` (`:293`). `"$@"` stays last, so a caller naming its own `-j`, `--cache-dir` or step name still wins by being after them. Of the three flags, `-j8` is this workspace's floor and `--summary all` is what `AGENTS.md:157-159` asks of every library and consumer gate; the explicit `--cache-dir` is the one that keeps state out of the checkout. The consequence worth stating is negative and complete: **nothing in this SDK can now reach the SDK default `.zig-cache`**, because every compiler-reaching route both exports both Zig cache variables and passes an explicit `--cache-dir`. Three routes reach no compiler and are deliberately untouched: `sdk:provenance` (absolute path to the script, which self-locates from its own `$0`), and `sdk:package_static` / `sdk:package_shared`, which call `devenv build` and must not `cd` into the SDK (§23). The cache fill now lives in the bodies as `cdSdkRoot` (`devenv.nix:85-105`) as well as in `enterShell`, because `devenv tasks run --mode single` runs a body without the shell hooks; `cdSdkRoot` `cd`s to `$sdkRoot`, fills a missing `ZIG_GLOBAL_CACHE_DIR`/`ZIG_LOCAL_CACHE_DIR` from `$XDG_CACHE_HOME` first and `$TMPDIR` second — the order `libunibreak`, `lua`, `tzdata`, `geographiclib-c` and `lmdb` already use — never overwriting a caller-exported value, and **`exit 1`s with the reason on stderr when neither is available** (`:98`), before the compiler runs. That fail-closed path is new: the `enterShell`-only version warned and continued, so a body run under `--mode single` could reach the compiler with no cache outside the checkout. `enterShell` keeps the same order for an interactive shell and hands it the same `cacheDir`. The new cache path is `$ZIG_LOCAL_CACHE_DIR/box3d-cache` (`devenv.nix:69`), beside the unmoved install prefixes `$ZIG_LOCAL_CACHE_DIR/box3d/<variant>`; no environment variable alias was introduced. The prefix rule §23 established is unchanged and was re-checked against the source: the default install step of `build.zig` hangs `installArtifact`, `addPkgConfig`, `installLicenceRecords` and the smoke executable off `getInstallStep()`, and the `smoke`, `test`, `upstream-test`, `check` and `consumer` steps depend on no install step; `consumer/build.zig:129` calls `b.installArtifact(exe)` but `zig build run` reaches only `run_step` (`:134-135`), so `sdk:consumer` correctly takes no prefix. Nothing else changed shape: all twelve task names are byte-identical, `-Dlinkage=dynamic` for the two `_shared` tasks and the static default are untouched, every compiler-reaching body still opens `cdSdkRoot`, and no `scripts` block was added because box3d has none. No `-Druntime` wiring changed; `build.zig` has since gained the `consumer` step's prefix forward (§24), and the two rows below name its symbols rather than its line numbers, so they survive that change. **Observed on one route.** Run `20261004T214803Z` ran `sdk:consumer` under `--mode single`, where `cdSdkRoot` ran without the shell hooks and did not `exit 1`, and the `Build Summary: 6/6 steps succeeded` line is the `--summary all` the body passed. The shell route printed the two banner lines this row used to demand — `sdk root: /vol/fob-vol7/mi19/gertullj/foundation-libs/box3d` and `cache: /home/tmp2/gertullj/cache/zig-local (global /home/tmp2/gertullj/cache/zig)` — and `zig env` put both cache variables outside this tree, which is the self-location and cache choice that a green build from the right directory by accident would not show. Still unobserved: the other ten task bodies, any body other than `sdk:consumer` passing the tail to a compiler, and `devenv build outputs.static` and `outputs.shared`, so §23's prefix rule is exercised by no receipt in this file. |
| The `load` guard's linked-build path | **Refuted for Box3D by a probe, not only by a sibling. No rewrite is warranted.** `zig/root.zig:263-273` panics inside a `comptime`-taken branch and reaches `c.load(source)` after it; `zig/root.zig:279-282` is the same shape for `c.loadedSource()` (`:281`). In a linked build `c` is the translated header itself (the `translate.createModule()` import in `build.zig`'s linked branch), which declares no `load` and no `loadedSource` — only the generated dispatch publishes them, from the template at `runtime/generate.zig:951-960` reached through `graph.createModule` (the runtime-loaded branch of the same `build.zig`, whose output carries `pub const rt_runtime_loaded = true` at its line 17). The names really are absent, and the probe then showed what that does **not** mean: Zig 0.16.0 does not analyse the two statements after the taken branch. **Observed:** `review-contract-probes/evidence/before-20261004T200332Z/box3d-linked-load.json` compiled and reached the documented panic (`exit 1`), and `box3d-linked-loaded-source.json` compiled and answered null (`exit 0`), both on the pinned compiler. So `zig/root.zig:258-259` describes what this compiler does, the guard is source-correct as written, and this row is closed rather than outstanding. The box2d probe of the byte-identical shape (`box2d/zig/root.zig:275-284`) reached the same answer in the earlier epoch `before-20261004T195312Z`, and that is corroboration rather than the basis: this row rests on box3d's own receipts. Note what is still not covered: no gate calls `load` unconditionally in a *runtime-loaded* build either, so the success path of the guard (`return c.load(source)`) is exercised only by `smoke`, `tests` and the consumer under `-Druntime=true`, which all reach it through their own `if (comptime runtime_loaded)` gates. |
| `MotionLocks`' "all six fields default to false" promise (`zig/body.zig:51-55`) | **Observed and refuted, twice over.** `MotionLocks` is `c.b3MotionLocks`, and the translate-c output the pinned compiler produced gives all six fields `= false` (`linearX` … `angularZ`); the same rendering is in the double-precision translation, and the generated dispatch re-exports that declaration rather than restating it (`pub const struct_b3MotionLocks = c_native.struct_b3MotionLocks;`), so one nominal type serves both configurations and the `setMotionLocks`/`motionLocks` crossings need no conversion. A reviewer asserted the opposite from `extern struct` semantics; the translation read is `box3d-standalone-linked-static/o/8a9a8830e2a72bc62d9a596f86498d0b/translate.zig:3190-3198`. **Then it was measured:** `review-contract-probes/evidence/before-20261004T200332Z/box3d-motion-locks.json` (`exit 0`, `6/6 steps`) ran three bodies on one world and six physical checks. Both documented constructions compiled — the empty literal through `BodyDef.motionLocks` and the partial literal through the same field — and the locks moved only what they named: locked along x the body drifted `0.000000 m` from its start while falling `5.020831 m`, and the same body with the empty literal advanced `1.999998 m` in x over the identical fall. `setMotionLocks` after creation gave the same `0.000000 m` drift. So `.{ .{} }` locks nothing, a partial literal locks exactly its named axis, and the setter agrees with the definition. **The type therefore stays the translated one**; a restated six-defaulted-bool Zig struct would have split the nominal type that `body.zig:530/535` passes across the C boundary, and there is nothing to fix. **History, bounded:** the first probe run in the earlier epoch `before-20261004T195312Z` reported `fail`, and it said nothing about this SDK — the diagnostic was in the probe's own scratch source (`src/main.zig:56:26: error: expected '}', found ':'` in a `const start_x = .{ locked: … }` initializer). That run is superseded by the receipt above and is kept only to show the failure was the probe's, not the facade's. |