# Changelog

Fork-only history. Everything upstream did to Box3D is upstream's and is not
recorded here; this file records what changed around the import in this
repository. `UPSTREAM.md` has the source provenance, `NOTICE.md` has the
per-file licence inventory and `FORK-LICENSE.md` has the terms the owner
authorized for fork-authored files.

The format follows Keep a Changelog. Versions are this package's own.

Nothing in this file is a gate result. Every migration entry below is
`PENDING-VERIFICATION` until the driver runs it; the three that have been run
are listed with their receipts under *Observed* rather than claimed here.

## [Unreleased] — contract migration

### Added

* **Native delivery.** `build.zig`, `build.zig.zon` and `build_support/` compile
  the complete upstream C17 core — all 49 translation units of `src/` — with
  Zig, invoking no CMake, no autotools and no build-time download. Upstream's
  own unit-test application (`test/` plus `shared/`, both unmodified) is built
  and run by the `upstream-test` step. `-Dlinkage=static|dynamic` selects the
  delivery artifact and defaults to `static`. `-Druntime=true` selects the
  runtime-loading dispatch and is orthogonal to linkage. The shared delivery
  and the runtime route are rows under *Observed*.
* **A fork-authored ABI bridge for ten entry points Zig cannot call by value.**
  `build_support/box3d_abi_bridge.c` and `.h`, compiled into the same module as
  the 49 upstream units, export `box3dAbi_*` pointer forms of the ten `B3_API`
  signatures that take a `b3Pos` by value ahead of a floating-point argument or
  return. Under `-Ddouble-precision=true` a `b3Pos` is 24 bytes and Zig 0.16.0's
  x86-64 lowering reserves a vector-register pair for an aggregate the System V
  ABI passes in memory, so the argument after it arrives one pair too high
  (`XMM2`/`XMM3` where the native callee reads `XMM0`/`XMM1`, tripping
  `B3_ASSERT( b3IsValidVec3( translation ) )` at `src/physics_world.c:2995`).
  Each bridge body is one call into the unchanged upstream entry point; no
  upstream byte, type or signature changes. `b3Transform` (28 bytes) and `b3Mat3`
  (36 bytes) were measured on the same binary, agree with the native callee, and
  are not in the set.
* **Install closure.** Public headers, the artifact, a generated
  `lib/pkgconfig/box3d.pc` and `LICENSE`, `README.upstream.md`, `NOTICE.md`,
  `UPSTREAM.md` and `FORK-LICENSE.md` under `share/licenses/box3d/`. The layout
  belongs to the build graph alone.
* **Build options for the four upstream compile-time switches:**
  `-Ddouble-precision`, `-Ddisable-simd`, `-Dvalidate` (default `true`,
  matching upstream's `BOX3D_VALIDATE`) and, deliberately, no `-Dprofile`,
  because upstream's `BOX3D_PROFILE` pulls Tracy through `FetchContent`.
* **API and consumers.** `zig/root.zig` publishes a documented typed surface
  over the translated native route plus the complete raw route;
  `zig/translate.h` includes `<box3d/box3d.h>` alone, which is already the
  whole public surface. `runtime/graph.zig` implements `createModule` and
  `createCoreModule` against the driver's shared runtime core. `tests.zig`,
  `smoke.zig` and the separate `consumer/` package. `tests.zig` and `smoke.zig`
  are the linked row under *Observed*; `consumer/` has nine receipts of its own,
  four routes with defaults omitted and stated plus a refusal case.
* **Provenance, licence and packaging.** `UPSTREAM.sha256` (349 records over
  every imported file), `UPSTREAM.md`, `NOTICE.md`, `FORK-LICENSE.md`,
  `tools/check-provenance.sh`, `package.nix`, `flake.nix`, `devenv.nix`,
  `devenv.yaml` and `.envrc`. The fork's licence is MIT, matching upstream's own
  term, on the owner's direct authorization.

### Changed

* `README.md` was upstream's README and is now this fork's README, restructured
  into the canonical order: native-source deviations, native-build deviations
  and their history, the build/run/test matrix, consumption. Upstream's bytes
  were preserved first as `README.upstream.md`, digest
  `2525d7ca5823027918c6ad7d84c1f9b946ef654d3350390e02a7dbe11aa5754e`, and
  `UPSTREAM.sha256` carries that digest under the relocated name.
* `NOTICE.md` replaced a single "MIT" label with a per-file inventory, because
  the label is not one thing: two vendored MIT headers sit **inside** the
  compiled library (`src/qsort.h`, Alexey Tourbin; `src/verstable.h`, Jackson
  L. Allan), two more sit in the retained sample material, the sokol headers are
  zlib/libpng, and `samples/earcut.h` carries no notice at all.
* `package.nix` is one uncurried derivation called by both entry points, with
  `linkage` as an injected argument rather than a second convention.
  `devenv.nix` names the same derivation in lazy `outputs.static` and
  `outputs.shared`, and its shell stays tools-only.
* `.gitignore` keeps upstream's fifteen lines verbatim with this fork's entries
  appended after them. It is the one imported file excluded from
  `UPSTREAM.sha256`; the pristine digest is recorded in that file's header.
* **Ten typed wrappers now reach Box3D through `box3dAbi_*`.**
  `query.castRay`, `query.castRayClosest` (and therefore `castRayClosestShape`),
  `query.castShape`, `query.castMover`, `query.castRayAgainstBody`,
  `query.castShapeAgainstBody`, `body.setTransform`, `body.localPoint`,
  `body.worldPointVelocity` and `shape.rayCast` pass their `b3Pos` by address to
  the bridge, which forwards to the same by-value native entry points and returns
  the same types. Every other wrapper still calls `c` directly, and the raw
  route's declarations are unchanged — they are upstream's, and reading them
  remains correct. `README.zig.md` §"The raw route" states which ten and why.
* **The two slice-filling collectors return a total, not a written count.**
  `query.overlapAabbCollect` and `query.castShapeCollect` used to stop writing
  at the end of the caller's slice and return how much they had written, which
  dropped the overflow silently and made a zero-length slice useless as a "how
  many are there" query. They now keep counting past the end and return the
  number of hits the query found; the valid prefix is `min(returned, out.len)`.
  Observed before the change: a two-shape overlap query given a one-slot slice
  answered `1` and `tests.zig:486` failed with `expected 2, found 1`
  (`local://foundation-contract-box3d-real-stale-parent-errors-and-geometric-state-full-smoke-test.log`).
  The overflow case is probed for the overlap form (`tests.zig:481`, `:485-486`);
  `castShapeCollect` has no caller in `tests.zig` or `smoke.zig`, so its side of
  this change is **not** covered by any run.
* **Every typed creator asks whether its parent is alive before calling
  upstream.** `body.create` and the nine joint creators check `world.isValid`;
  the seven shape creators check `body.isValid`. A destroyed parent reaches
  `B3_ASSERT( id.generation == world->generation )` inside
  `b3GetUnlockedWorldFromId` (`src/physics_world.c:96`) or
  `B3_ASSERT( b3Body_IsValid( bodyId ) )` inside `b3GetBodyFullId`
  (`src/body.c:30`) before upstream can return the null id it would otherwise
  answer with, and in a Debug build that assertion is `B3_BREAKPOINT`. All
  three cases died that way before the check existed
  (`local://foundation-contract-box3d-initial-pose-ray-and-filtered-scene-caller-repair-smoke-test.log`);
  they now answer `error.InvalidWorld` or `error.ShapeCreationFailed`, and they
  are in the recorded linked run (`tests.zig:739`, `:757`, `:775`).
* **The finite native capacities stay caller preconditions.** `B3_MAX_WORLDS` is
  128 (`include/box3d/constants.h:62-65`) and `B3_MAX_SHAPES` is `1 << 22`
  (`include/box3d/constants.h:120-122`), and reaching either is an upstream
  assertion (`src/physics_world.c:223-228`, `src/shape.c:270-274`) rather than
  a value it returns. `error.WorldLimitExceeded` is therefore reported only on
  the branch where upstream survives to be asked — the same receipt shows a
  Debug run stopping at `src/physics_world.c:226` before it does. Nothing here
  pre-empts it, and no test fills either pool.
* `README.md`, `README.zig.md` and `FORK-NOTES.md` were corrected to match the
  above: the observed-runs matrix, the collector's total-count contract, the
  creator preflight, and the geometry, resting and sleeping answers the smoke
  actually checks, with the observed values rather than exact ones.
* **`devenv.nix` gives every gate one flag tail and a fail-closed cache
  preamble.** One `buildFlags` value ends all nine `zig build` invocations the
  file can reach — `-j8 --summary all --cache-dir "${cacheDir}" "$@"`
  (`devenv.nix:118`) — covering the two `deliveryBuild` lines (`:153`, `:156`)
  that serve `sdk:build` and `sdk:build_shared`, and the seven task bodies
  `sdk:test` (`:244`), `sdk:test_release_safe` (`:252`), `sdk:upstream-test`
  (`:260`), `sdk:smoke` (`:268`), `sdk:check` (`:276`), `sdk:check_shared`
  (`:284`) and `sdk:consumer` (`:293`). `"$@"` stays last, so a caller's own
  `-j`, `--cache-dir` or step name still wins. `-j8` is this workspace's floor,
  `--summary all` is what `AGENTS.md:157-159` asks of every gate, and the
  explicit `--cache-dir` (`$ZIG_LOCAL_CACHE_DIR/box3d-cache`, `devenv.nix:69`)
  means **nothing in this SDK can reach the default `.zig-cache` in the working
  tree**. The cache fill moved into the bodies as `cdSdkRoot`
  (`devenv.nix:85-105`) as well as `enterShell`, because
  `devenv tasks run --mode single` runs a body without the shell hooks;
  `cdSdkRoot` `cd`s to `$sdkRoot`, fills a missing `ZIG_GLOBAL_CACHE_DIR` or
  `ZIG_LOCAL_CACHE_DIR` from `$XDG_CACHE_HOME` first and `$TMPDIR` second — the
  order `libunibreak`, `lua`, `tzdata`, `geographiclib-c` and `lmdb` already
  use — never overwriting a caller-exported value, and now **`exit 1`s with the
  reason on stderr when neither is set**, before the compiler runs. The
  `enterShell`-only version warned and continued, so a body run under
  `--mode single` could have reached the compiler with no cache outside the
  checkout. The three routes that reach no compiler are deliberately untouched:
  `sdk:provenance` (the script self-locates from its own `$0`) and
  `sdk:package_static` / `sdk:package_shared`, which call `devenv build` and
  must not `cd` into the SDK (§23). The install prefixes stay where §23 put
  them, `$ZIG_LOCAL_CACHE_DIR/box3d/<variant>`, and no environment variable
  alias was introduced. All twelve task names, the `-Dlinkage=dynamic` shared
  tasks, the static default and the §23 prefix rule are otherwise unchanged,
  and no `build.zig` or `-Druntime` line was touched. One devenv evaluation of
  this SDK failed before any task body — run `20261004T212645Z`, gate
  `devenv:info`, `exit 1` at `devenv.nix:222` with `error: expected a set but
  found a string: "static"` — and `FORK-NOTES.md` §23 carries that receipt and
  its cause. The corrected state is now partly exercised: run
  `20261004T214803Z` passed all eight of its gates, `devenv:info` reported
  `BOX3D_SDK_VERSION: 0.1.0` and the pinned devenv listed all twelve task names,
  and `sdk:consumer` and `sdk:provenance` ran green under `--mode single`. The
  other ten task bodies, both Nix outputs and the `devenv build` route are still
  `PENDING-VERIFICATION`; the rows under *Observed* carry the receipt.

### Fixed

Three of the six are now observed in part — the first, the third and, since the
re-run below, the fourth. (The second's stated cause was withdrawn in its own
entry, so it is not counted here.) The 53-platform failures the ARM-SIMD,
`.use_llvm` and NetBSD entries answer were observed by the driver in
`cross-8/box3d/runs/20261004-164517-9067-28500`; the run `20261004-191759-29759-503`
has since exercised those same three, and what it shows is recorded per entry below.
The fourth was observed later, in a different run and in a different
configuration; what it showed and what is still unverified is recorded in its own
entry. The fifth has no gate behind it at all and says so in its own entry, and
the sixth is the nested `consumer` forwarding, observed on nine cases in one run.

* **`BOX3D_DISABLE_SIMD` now defaults on 32-bit ARM, and only there.**
  `build.zig` — `Options.disable_simd` is now `?bool` and is resolved per
  resolved target by the new `resolveDisableSimd`, which reads the new
  `targetLacksArmNeonFloatMath` — `std.Target.Cpu.Arch` `.arm`, `.armeb`,
  `.thumb` or `.thumbeb`, the four 32-bit ARM architectures; `thumb` and
  `thumbeb` are architectures in their own right, not CPU features on
  `.arm`/`.armeb` (`std/Target.zig:1374-1375`; `std/zig/system.zig:407-409`
  *adds* `arm.thumb_mode` to them). `addConfigMacros` takes the target and
  resolves against it, so the core and upstream's C test program agree; the
  configure-time line prints the resolved value and, when the default was
  taken, why; `runConsumer` forwards the resolved value rather than the
  optional. `consumer/build.zig` is unchanged here and states no default, which
  is what lets the nested build reach the same answer from its own
  `-Dtarget`.

  **Cause, from source.** `src/core.h:41-42` makes `B3_CPU_ARM` cover `__arm__`
  as well as `__aarch64__`, so `src/core.h:59-61` hands 32-bit ARM the same
  `B3_SIMD_NEON` arm, and `src/contact_solver.c:777` includes `<arm_neon.h>`
  for it. That header declares `vdivq_f32` (`lib/include/arm_neon.h:50216`) and
  `vsqrtq_f32` (`:64883`) inside the block opened at `:44308`,
  `#if defined(__aarch64__) || defined(__arm64ec__)`; the single-instruction
  float divide and square root are AArch64 NEON instructions and 32-bit NEON
  has neither. Observed on the pinned toolchain as four errors per target —
  `call to undeclared function 'vdivq_f32'` / `'vsqrtq_f32'` and the two
  matching `returning 'int' from a function with incompatible result type
  'b3FloatW'` — on all nine 32-bit ARM targets of the run (`arm-linux`,
  `armeb-linux`, `arm-freebsd`, `arm-openbsd`, `arm-netbsd`, `armeb-netbsd`,
  `thumb-linux`, `thumbeb-linux`, `thumb-windows`) and on no other target.
  `build-arm-linux.log:9-21` is the receipt; `build-arm-netbsd.log:65-77`
  shows the same four errors underneath the independent NetBSD failure.

  **Observed, and the first version of this fix was incomplete.** In
  `20261004-191759-29759-503`, `arm-linux` and `armeb-linux` compile and run
  all 19 tests, and the other four 32-bit ARM cells build; the three `thumb-*`
  cells were still red on the same four errors, with `disable-simd=false`
  printed in their configure line (`build-thumb-linux.log:3-21`). That was the
  rule matching `.arm`/`.armeb` on the reading that `thumb`/`thumbeb` are CPU
  features; they are architectures (`std/Target.zig:1374-1375`,
>  `std/Target.zig:1067`, `std/zig/system.zig:407-409`), and they are now in it.
  No gate has yet run a `thumb-*` cell against the corrected rule.

  **Why this default is narrow.** `B3_SIMD_NONE` keeps `B3_SIMD_WIDTH 4`
  (`src/core.h:51-52`), the same width `B3_SIMD_NEON` uses, so the C ABI, the
  struct layouts and every published declaration are byte-identical either way
  and the only thing that changes is arithmetic width. Every other target keeps
  upstream's own default, and `-Ddisable-simd=false` still forces the NEON arm
  on and still fails to compile — an explicit request is answered, not
  overridden. No C source, no C header and no declaration changed.
* **`.use_llvm = true` on every Zig root this package owns.**
  `build.zig` — the `test` root, the published `smoke` root and both roots
  `check` creates (the matrix test and the matrix smoke).
  `consumer/build.zig` — the consumer's own executable root. The C archive and
  upstream's C unit-test program are deliberately left without it: neither has
  a Zig root, and the backend choice buys a correct C-ABI call made *from* Zig.

  **Cause, from this repository's own source.** `build_support/box3d_abi_bridge.h`
  is ten wrappers that exist for one measured reason, stated at its own
  `:1-36`: "Zig 0.16's x86_64 backend lowers [a C ABI argument list] differently
  from the compiler that built the core", with the register-level measurement
  (`vmovlpd %xmm0` against `vmovq %xmm2`) and the resulting symptom — a valid
  argument reaching the callee beside an unreadable one. The observed run is
  the same defect one step further out, on targets the ten wrappers never
  covered: eleven targets built and then failed at run time with a caller
  pointer arriving inside the C callee as garbage — `member access within
  misaligned address 0x1` for `const b3BodyDef` at `src/body.c:159` in
  `b3CreateBody`, `0xaaaaaaaa` for `const b3HullData` at `src/hull.c:1658` in
  `b3IsValidHull`, a fault at `0x7f8e00000000` at `src/physics_world.c:208` in
  `b3CreateWorld`, and the four big-endian targets reporting
  `error.WorldLimitExceeded` at `zig/world.zig:197` because
  `b3World_IsValid` answered for an argument it did not receive. Five targets
  of the same fifty-three passed all 19 tests on the same sources and the same
  headers. That the same toolchain's default backend mis-passes a C-ABI call is
  also recorded, with a two-run discriminator, for ERFA in this workspace
  (`erfa/FORK-NOTES.md` entry 18), whose remedy was the same flag.

  **What this does not claim, and what has since been measured.** That the flag
  removes every pointer-taking failure on those eleven targets is not
  established here; it is the fix this workspace has already applied and
  measured for the same defect class. The run `20261004-191759-29759-503` has
  since exercised it with the flag in force — the NetBSD cells' inner compile
  line is `zig test -fllvm … -Mroot=tests.zig`
  (`build-aarch64-netbsd.log:11`) — and the eleven cells are red again with the
  same shape. So the flag is not what decides these eleven, and the cause
  stated in this entry is withdrawn; what the run excludes is the backend
  (`gmp` and `htscodecs` pass 47 and 42 tests through the same `qemu-*` runners
  on nine of those targets) and the shape of this particular library (Box2D
  fails identically on hexagon, loongarch64, mips64, powerpc and powerpc64).
  What is left is the Zig→C call boundary for this pair of packages, which this
  tree has not narrowed further. It also does not retire
  `build_support/box3d_abi_bridge.h`: with LLVM selected the ten by-value
  signatures the bridge exists for are no longer mis-lowered, but the bridge is
  a published part of the `c` module and removing it is a cutover decision for
  the header's owner, not a side effect of this entry.
* **NetBSD targets no longer hand `cdefs.h`'s `_Pragma` to Aro.**
  `build.zig` — new `TranslateRoute`, `translateRoute` and
  `preprocessedTranslateHeader`; `addGraph` picks the root source file from
  the route. On `os.tag == .netbsd` the translate header is expanded first by
  the compiler running this build script (`zig cc -E -dD`, `-target` the
  resolved triple when it is not native, `-I include`, the same two macro
  definitions `addTranslateMacros` uses, `-MD -MF` so the discovered headers are
  this step's real inputs) and Aro parses what that produced. Every other
  target keeps the route it had.

  **Cause, from source.** `generic-netbsd/sys/cdefs.h:411-416` defines
  `__END_PUBLIC_DECLS` as `__END_EXTERN_C _Pragma("GCC visibility pop")` and
  `:432` routes `__END_DECLS` through it; `generic-netbsd/math.h:607` closes
  its declaration block with `__END_DECLS`, and `include/box3d/math_functions.h:11`
  is what reaches `<math.h>`. Aro destringizes each `_Pragma` into a `#pragma`
  line it then hands to the parser as C. Observed on all nine NetBSD targets
  and no other: five errors at `math.h:607`, `unknown type name 'pragma'`,
  `expected ';', found 'an identifier'`, `unknown type name 'visibility'`,
  `expected ';', found ''`, `error: translation failure`
  (`build-aarch64-netbsd.log:10-58`), with the C archive itself compiled
  (`build-aarch64-netbsd.log:66`). The condition is the OS tag rather than a
  list of nine triples, so the next NetBSD architecture is covered rather than
  silently missed. This is the same convention ERFA already uses for the same
  header (`erfa/build.zig`, `aggregateRoute`), so the two SDKs read the same
  way; `-dD` keeps the `#define` lines, which is what makes this route
  describe the same `c` module the Aro route describes instead of a
  macro-stripped one.

  **Observed, and what remains.** In `20261004-191759-29759-503` the route
  translates all nine NetBSD targets — the `_Pragma` failure is gone, and the
  seven non-AArch64 cells build. The two AArch64 cells fail to compile the
  translated module with one error each, `box3d-translate.zig:5208: error: use
  of undeclared identifier '__int128_t'` under `pub const __ALIGNBYTES =
  __helpers.sizeof(__int128_t) - @as(c_int, 1);`
  (`build-aarch64-netbsd.log:5-9`): `-dD` carries NetBSD's spelling of
  `__ALIGNBYTES` through `generic-netbsd/arm/cdefs.h:62-63`, and no header
  declares the typedef because Clang declares `__int128_t` next to the
>  `__int128` primitive rather than in a libc header. The correction is the
>  bridge ERFA, LMDB and PCRE2 already carry — under `__SIZEOF_INT128__`,
>  `zig/translate.h` restates `typedef __int128 __int128_t;` and `typedef
>  unsigned __int128 __uint128_t;` ahead of its one real include, declaring a
>  compiler builtin and touching no upstream declaration.
>
>  **That bridge has now landed here**, in `zig/translate.h:118-122`. The
>  sibling pattern was checked in each package before applying it rather than
>  copied on memory: ERFA (`erfa/zig/translate.h:139-143`), PCRE2
>  (`pcre2/zig/translate.h:113-117`) and LMDB (`lmdb/translate.h:44-47`) put the
>  same two typedefs inline in their own `zig/translate.h`, and LuaJIT generates
>  the same completion and pulls it in with `-include`
>  (`luajit/build_support/graph.zig:1217-1222`) with `!defined(__int128_t)`
>  added. Both forms declare a compiler builtin and touch no upstream `.c` or
>  `.h` byte; the inline form is the one that applies here because `build.zig`
>  hands this aggregate to `zig translate-c` on the Aro route and to
>  `zig cc -E -dD` on the preprocessed one, so no `-include` and no `build.zig`
>  line is needed. **The two AArch64 cells have not been re-run, so this is
>  `PENDING-VERIFICATION`** and no `thumb`- or NetBSD-shaped claim above is a
>  gate result.

* **The runtime precision guard compared the wrong things.**
  `runtime/library.zig` — `translated_single_precision` was
  `@TypeOf(dispatch.b3Pos) == @TypeOf(dispatch.b3Vec3) and
  @TypeOf(dispatch.b3WorldTransform) == @TypeOf(dispatch.b3Transform)`.
  `dispatch.b3Pos` and `dispatch.b3Vec3` are type-valued declarations, so
  `@TypeOf` of either is `type`: the expression compared `type == type`, which
  is true for every pair, and `headers_are_double` was therefore always false.

  **Observed.** The run `20261004T200055Z-092d7677` put two runtime-loaded rows
  at `-Ddouble-precision=true` — `-Dlinkage=static` and `-Dlinkage=dynamic` —
  and both exited 1 refusing a correctly-built double provider: `box3d:
  refusing this provider: b3IsDoublePrecision() disagrees with the precision
  mode these headers were translated for`, printed 20 times per row from
  `runtime/loader.zig:508`, then `0/19 tests passed (19 crashed)` and the smoke
  executable exiting 1 on `error.ValidationFailed`. Its provider row
  (`zig build install -Ddouble-precision=true -Dlinkage=dynamic`, `13/13 steps`)
  was green, and no native call was reached, so this was never a
  native-validity result. The row's own generated sources show the two types are
  genuinely distinct (`struct_b3Vec3` three `f32` against `struct_b3Pos` three
  `f64`; `struct_b3Transform.p: b3Vec3` against `struct_b3WorldTransform.p:
  b3Pos`), so the answer was in the translation and was not being read.

  **Change.** The comparison is now between the two type values themselves,
  `dispatch.b3Pos == dispatch.b3Vec3 and dispatch.b3WorldTransform ==
  dispatch.b3Transform`, which is the header's own answer and the same reading
  in both precision modes. No build graph, no dispatch and no upstream byte
  changed. The reused cache epoch is not a candidate cause — the defect was in
  the source those rows compiled — and needs no rerun to exclude.

  **Observed since, and what it does not reach.** Run
  `box3d-double-type-values-after` re-ran exactly those two rows and both are
  green: `exit 0`, `rows_failing: 0`, `refusals_observed: 0`, `Debug` on
  `x86_64-linux-gnu` under the pinned compiler
  (`…/baselines-and-configs/box3d-double-type-values-after/index.json`).
  `secondary-box3d-double-provider` (`zig build install
  -Ddouble-precision=true -Dlinkage=dynamic -Doptimize=Debug`) is
  `Build Summary: 13/13 steps succeeded`; `secondary-box3d-double-loaded-static-test-smoke`
  and `secondary-box3d-double-loaded-dynamic-test-smoke` (each `zig build test
  smoke -Ddouble-precision=true -Dlinkage=… -Doptimize=Debug -Druntime=true`)
  are each `Build Summary: 9/9 steps succeeded; 19/19 tests passed`, with no
  refusal line in either. So the guard compares the two type values, and the
  `-Ddouble-precision=true` runtime path ran end to end for the first time.

  What that run does **not** establish: it does not make the guard
  retroactively sound before the change, it proves neither ReleaseSafe nor
  ReleaseFast nor ReleaseSmall, it proves none of the six cross targets, and it
  does not exercise the ten by-value signatures the ABI bridge exists for — see
  the `.use_llvm` entry above — because running the tests and smoke at that
  precision is a different claim from calling those ten wrappers in isolation.
  The NetBSD `__int128_t` bridge above is untouched by it and stays
  `PENDING-VERIFICATION` until the two AArch64 cells re-run.
* **The canonical devenv shell could not be entered, and every task in it ran
  in the wrong directory.** `devenv.yaml` carried `flake: false` on the
  `nixpkgs` input; that key is what stopped Box2D, fast_float and Lua before
  they evaluated anything, because devenv's `nixpkgs` becomes a plain source
  path with no `lib` and every subcommand then dies in bootstrap at
  `lib = nixpkgs.lib` with `error: attribute 'lib' missing`
  (`box2d-devenv-info.log`, `fast_float-devenv-info.log`, `lua-devenv-info.log`
  of run `20261004T175328Z`). The pin itself is unchanged; only the `flake:`
  key is gone. Separately, every task body in `devenv.nix` now begins
  `cd "$sdkRoot"`, where `sdkRoot` is `builtins.toString ./.` — devenv runs a
  task as a generated shell program that inherits the working directory of the
  project the shell was entered from, and that project holds `.devenv/` and
  `devenv.lock` and none of `build.zig`, `consumer/` or `tools/`. The two
  delivery tasks additionally pass `--prefix` into a subdirectory of the
  `ZIG_LOCAL_CACHE_DIR` that `enterShell` exports, so a default `zig build` no
  longer writes `zig-out/` into this tree, and a caller's own `--prefix`/`-p`
  is passed through untouched instead of being overridden. The five task names
  that carried a `.` — `sdk:build.shared`, `sdk:test.release-safe`,
  `sdk:check.shared`, `sdk:package.static`, `sdk:package.shared` — are now
  `sdk:build_shared`, `sdk:test_release_safe`, `sdk:check_shared`,
  `sdk:package_static`, `sdk:package_shared`, because devenv requires
  `namespace:name` and rejects a `.` in a task name.

  **What this does not claim.** A devenv evaluation of this SDK has now run —
  `20261004T212645Z` — and it is not this entry's proof: it failed at
  `devenv.nix:222` while converting `env`, so it entered no shell and ran no
  task body. Box3D was also not one of the 18 SDKs in run `20261004T175328Z`, so
  the `flake:` line has still never been exercised here: the diagnosis and the
  deletion are read out of three sibling receipts, and both this change and the
  directory the task bodies now `cd` into are `PENDING-VERIFICATION` until a
  devenv command runs against this directory and succeeds.
* **The nested `consumer` build was handed this graph's resolved target, and was
  given no CPU, no global cache, no job count and no step summary.**
  `build.zig` — `runConsumer` now serialises the caller's **query** rather than
  this graph's resolved result, adds `-Dcpu`, and passes `--global-cache-dir`,
  `-j8` and `--summary all`. Nothing else moved: `-Doptimize`, `-Druntime`,
  `-Ddouble-precision`, `-Ddisable-simd`, `-Dvalidate`, `-Dlinkage`, the five
  executor switches, `--libc-runtimes`, the `--cache-dir` `/consumer`
  subdirectory, the caller's own `--` arguments, `has_side_effects` and the
  unconditional `run` step are exactly what they were, the signature is
  unchanged, and its one caller — the `consumer` step's `dependOn` — did not
  move. The 32-bit-ARM `resolveDisableSimd` default is untouched and is still
  resolved against this graph's target before it is written out.

  **Observed, and no longer source-only.** Run `20261004T223101687849Z-e3904589dead`
  drove this step nine times and passed all nine: four routes (static and
  dynamic, each linked and each runtime-loaded) with the SDK's own defaults
  omitted in four cases and stated in four, plus a no-provider refusal that
  exits 1 with the program's own message. Every nested command carried
  `-Dtarget`, `-Dcpu`, `-Doptimize`, `-Druntime`, `-Ddouble-precision`,
  `-Ddisable-simd`, `-Dvalidate`, `-Dlinkage`, `-j8`, `--summary all`, this
  graph's local cache with the `/consumer` subdirectory, the external global
  cache, and a `--prefix` byte-identical to the outer one. `-Dcpu=native` where
  the caller named no target and `-Dcpu=baseline` with
  `-Dtarget=x86_64-linux-gnu` where it named one. `FORK-NOTES.md` §24 carries the
  run and what it does not cover.

  **Why the query and not the result.** `ResolvedTarget` carries both
  (`lib/std/Build.zig:2697-2700`) precisely because the query records which
  parts of the target were "native" (`:2695-2696`), and `Target.Query.zigTriple`
  writes the literal string `native` for a query that named nothing
  (`lib/std/Target/Query.zig:421-422`). That is the same pair `std.Build` hands a
  dependency — `zigTriple` and `serializeCpuAlloc`, and nothing else
  (`lib/std/Build.zig:451-462`) — so both halves of the nested build parse
  exactly what this one resolved.

  `target.result.zigTriple` was the wrong source. It spells the *resolved*
  target, whose host CPU carries this machine's own feature range, and a triple
  has no field for a dynamic linker at all; the nested build therefore resolved
  an explicitly named target against the ABI's defaults rather than against this
  machine and asked for a dynamic linker this host does not use, and its `run`
  then refused its own artifact — `Step.Run` compares the host's dynamic linker
  with the target's and fails the step
  (`lib/std/Build/Step/Run.zig:1337-1348`). The dynamic linker still rides the
  native route rather than travelling as an argument, because `b.dependency`
  forwards no `-Ddynamic-linker` for the library half either
  (`lib/std/Build.zig:439-461`): an argument carried to the nested build alone
  would give its consumer executable a linker the library it links against never
  received. Same rule, same reason and same wording as
  `utf8proc/build.zig:1386-1416`, which is where it was read out of first.

  **Why `-Dcpu` travels beside it.** `serializeCpu` writes `native` for a query
  that named no CPU and `baseline` for a cross query that named none, and
  otherwise the model name followed by its added and subtracted features
  (`lib/std/Target/Query.zig:488-533`); `-Dcpu` is read from exactly that string
  by the four options `standardTargetOptions` registers
  (`lib/std/Build.zig:1473-1493`). A triple cannot carry a CPU model, so a
  nested build given only `-Dtarget` compiled the consumer against the ABI
  baseline while this graph compiled the library against the host's features.
  The consumer already declares the option — `consumer/build.zig:54` calls
  `standardTargetOptions` — and already hands both halves on to the library, so
  nothing in `consumer/` changed.

  **Why the global cache is named at all.** The working directory above is
  `consumer/`, so a global cache the nested build resolved for itself would be
  resolved from there rather than from where this build was told to put it. Every
  compiler invocation the nested graph makes already carries the global cache its
  own build script names — that is the stdlib's own shape, at
  `lib/std/Build/Step/Compile.zig:1477-1479`,
  `lib/std/Build/Step/TranslateC.zig:178-180` and
  `lib/std/Build/WebServer.zig:576-577` — so forwarding it here is what makes
  those invocations and this one agree instead of splitting one build across two
  global caches. The field is `Graph.global_cache_root`
  (`lib/std/Build.zig:112-122`), not `Build.cache_root` (`:57-58`), which is this
  graph's own manifest directory and already has its `/consumer` subdirectory
  above. Two arguments, for the same reason as the local flag:
  `--global-cache-dir [path]` is the documented two-token form
  (`lib/compiler/build_runner.zig:1675`), and the `=`-joined spelling arrives as a
  `-` argument the runner does not enumerate (`:160`) and is fatal there
  (`:432-433`). The path is guarded rather than defaulted: the build runner
  builds that `Directory` with `.path` set unconditionally
  (`lib/compiler/build_runner.zig:73-76`), so no run takes the guard, and a null
  must not be answered by naming a directory nobody chose.

  **Why `-j8` and `--summary all`.** Nothing can append a `-j` or a `--summary`
  to a `Run` step's command. A nested build left to derive its own width takes
  `cpu_count - 1` (`lib/std/Io/Threaded.zig:1639`), so the consumer this step
  proves would compile at a different width from the build that asked for it, and
  again on whichever machine runs the gate. `-j8` is what every `zig build` body
  in this SDK's `devenv.nix` already carries (`devenv.nix:118`) and what this
  workspace asks of every gate (`AGENTS.md:157-159`); `--summary` is two tokens
  for the same reason the two cache flags are
  (`lib/compiler/build_runner.zig:262-267`). Both sit ahead of the caller's `--`,
  because `--` is where the build runner stops parsing options and starts
  recording `b.args` (`:428-430`) — the caller's own argument still reaches the
  consumer program itself, last and unchanged.

  **The prefix was still unnamed.** `runConsumer` now emits `--prefix` and this
  graph's actual `b.install_prefix`, and it emits them only when the caller
  named a prefix. The guard is the default itself: `b.install_prefix` equals
  `<this build root>/zig-out` when no prefix was given, and that is what the
  nested build resolves for itself under `consumer/` in any case, so forwarding
  it would name nothing the caller chose. A relative value is joined against
  `b.graph.cache.cwd` before it is written out, because the nested working
  directory is `consumer/` and a relative path would resolve there rather than
  against this build's root. `DESTDIR` is not forwarded: the nested build
  inherits the environment this one ran with. This is the same guarded shape
  `tzdata/build.zig` uses.

  **Current record of that helper.** `runConsumer` returns the one `Step.Run`
  the `consumer` step depends on, and that `dependOn` is its only caller:
  `b.step("consumer", …).dependOn(&runConsumer(b, target, optimize, opts).step)`.
  What it forwards today is:

  * the caller's target **query**, as `-Dtarget=` from
    `Target.Query.zigTriple` and `-Dcpu=` from
    `Target.Query.serializeCpuAlloc`;
  * the mode this graph was configured with, as `-Doptimize=`, `-Druntime=`,
    `-Ddouble-precision=`, `-Dvalidate=` and `-Dlinkage=` under the names
    `b.option` took them, and `-Ddisable-simd=` as `resolveDisableSimd` answers
    it for this graph's target rather than as the optional the caller typed;
  * the selected executor, as `-fdarling`, `-fqemu`, `-frosetta`,
    `-fwasmtime` and `-fwine` when the matching `b.enable_*` is set, and
    `--libc-runtimes` with `b.libc_runtimes_dir` when that is set;
  * `-j8` and `--summary all`;
  * this graph's own local cache, as `--cache-dir` plus a `/consumer`
    subdirectory, when `b.cache_root.path` is set;
  * `b.graph.global_cache_root.path`, as `--global-cache-dir`, when it is set;
  * `--prefix` with this graph's actual `b.install_prefix`, only when the caller
    named one;
  * the caller's own arguments, last and behind `--`.

  Both caches are the external ones this graph was itself given, and neither
  capture falls back to a directory: with no path there is nothing to name, and
  the nested build is left to resolve its own rather than handed a place nobody
  chose. The local cache gets a subdirectory because two build graphs must not
  write one manifest directory; the global cache does not, because it is the
  package cache both graphs read, and sharing it is the point. The step always
  asks to run the consumer and never falls back to a compile-only build, so a
  target with no available executor cannot report a passing consumer exchange.

  **The caller's arguments cross both hops.** `runConsumer` writes `--` and
  then `b.args`, and `--` is where the build runner stops parsing options and
  starts recording arguments (`lib/compiler/build_runner.zig:428-430`). Inside
  the nested graph, `consumer/build.zig` hands its own `b.args` to the
  `addRunArtifact` of the consumer executable. So
  `zig build consumer -- ARGS` reaches the consumer program and not the
  nested build graph. Both hops now have receipts and neither is source-only:
  run `20261004T223101687849Z-e3904589dead` passed `--provider PATH` through
  both hops in four runtime-loaded cases, with every provider environment
  variable absent from the child.
* **The nested `consumer` build asked to run a target no executor could run.**
  `runConsumer` now selects `install` when `hostCanExecute` — the predicate
  `std.Build.Step.Run` itself uses — says this host cannot execute the
  selected target. An executor counts only when the build runner was told it
  may use one, so a foreign target with no enabled executor installs rather
  than runs; a native target, or any foreign target with an enabled executor,
  still runs. Foreign installation is build-only evidence.

### Observed

Six gate runs and four review-contract probe rows have receipts, one devenv
acceptance run adds eight passing gates, one nested-delivery run adds nine
passing `consumer` cases, and one native-final run adds eight passing cells. The
build rows are `Debug` on `x86_64-linux-gnu` under the pinned compiler, except
the native-final run, which covers ReleaseSafe, ReleaseFast and ReleaseSmall too.
The three double-precision rows are one driver run, `box3d-double-type-values-after`,
whose index is
`/home/tmp2/gertullj/scratch/foundation-libs/contract-physics-lua/baselines-and-configs/box3d-double-type-values-after/index.json`.
The devenv rows are run `20261004T214803Z` and the nested-delivery rows run
`20261004T223101687849Z-e3904589dead`, both under
`/home/tmp2/gertullj/scratch/foundation-libs/contract-physics-lua/` and
`/home/tmp2/gertullj/scratch/foundation-libs/nested-delivery-proof/evidence/`.

| Gate | Command | Result | Receipt |
|---|---|---|---|
| Linked tests and smoke | `zig build smoke test --prefix DIR` | `18/18 tests passed`, `9/9 steps` | `local://foundation-contract-box3d-real-overflow-total-count-full-smoke-test-recovered-output.log` |
| Shared native delivery | `zig build install -Dlinkage=dynamic` | `13/13 steps`, soname `libbox3d.so.0` for version `0.1.0` | `local://foundation-contract-box3d-primary-shared-complete-native-closure-repaired.log` |
| Runtime-loaded dispatch, provider supplied from outside | `zig build smoke -Druntime=true -- --provider PATH` | `6/6 steps`; nothing linked into the module; every checked answer matched | `local://foundation-contract-box3d-current-canonical-runtime-static-real-provider-smoke.log` |
| Double-precision shared delivery | `zig build install -Ddouble-precision=true -Dlinkage=dynamic -Doptimize=Debug` | `exit 0`, `13/13 steps` | that index, row `secondary-box3d-double-provider` |
| Double precision, shared object loaded as a provider | `zig build test smoke -Ddouble-precision=true -Dlinkage=dynamic -Doptimize=Debug -Druntime=true` | `exit 0`, `9/9 steps`, `19/19 tests passed` | that index, row `secondary-box3d-double-loaded-dynamic-test-smoke` |
| Double precision, static archive loaded as a provider | `zig build test smoke -Ddouble-precision=true -Dlinkage=static -Doptimize=Debug -Druntime=true` | `exit 0`, `9/9 steps`, `19/19 tests passed` | that index, row `secondary-box3d-double-loaded-static-test-smoke` |
| Devenv environment, task names and shell | `devenv info`, `devenv tasks list`, `devenv shell -- zig version`, `devenv shell -- zig env` | `exit 0` each; `BOX3D_SDK_VERSION: 0.1.0`; banner `sdk: box3d 0.1.0 (upstream v0.1.0)`, `sdk root: /vol/fob-vol7/mi19/gertullj/foundation-libs/box3d`, `cache: /home/tmp2/gertullj/cache/zig-local (global /home/tmp2/gertullj/cache/zig)`; `zig version` printed `0.16.0`; `zig env` named the store compiler `…-zig-0.16.0/bin/zig` and both cache variables outside this tree | that index |
| Consumer package, through `sdk:consumer` | `devenv tasks run --mode single … sdk:consumer`, body `cd consumer && zig build run --summary all` | `exit 0`, `Build Summary: 6/6 steps succeeded`, `run exe box3d-consumer success 64ms`; Debug, native, default static archive; the program's own known answers all matched | that index |
| Provenance integrity, through `sdk:provenance` | `devenv tasks run --mode single … sdk:provenance` | `exit 0` in 215 ms; `tools/check-provenance.sh` passed | that index |
| Nested `consumer` step, four routes | `zig build consumer` nine times: static and dynamic, linked and runtime-loaded, defaults omitted and stated | Debug / native | all nine `exit 0` except the no-provider refusal, which `exit 1` with its own message; each passing case `Build Summary: 6/6 steps succeeded`; nested `--prefix` byte-identical to the outer one | that run's `index.json` |
| Native matrix, both linkages and four optimize modes | `zig build test smoke install`, static and dynamic, `Debug`, ReleaseSafe, ReleaseFast, ReleaseSmall | Debug and Release, native | eight of eight `exit 0`, each `Build Summary: 18/18 steps succeeded; 19/19 tests passed`; 15 installed files static, 17 shared | `native-final-evidence/contract-final-after-20261004/run.json` |
| Foreign boundary classes, eleven targets | the physics-boundary probe's C control, raw-direct and typed stages on eleven targets | n/a | every C control `exit 0`; every raw-direct and typed stage fails, at four distinct first boundaries; `riscv32` exits 70 on an argument mismatch instead of crashing | `physics-boundary-probes/receipts/` |
| Review-contract probe: linked-build `load` | `zig build` of a linked consumer calling `load` unconditionally | `exit 1`, the documented panic text; the guard compiles as written | `review-contract-probes/evidence/before-20261004T200332Z/box3d-linked-load.json` |
| Review-contract probe: linked `loadedSource` | same, calling `loadedSource` | `exit 0`, answered `null` | `.../before-20261004T200332Z/box3d-linked-loaded-source.json` |
| Review-contract probe: `MotionLocks` defaults | `zig build motion-locks -Doptimize=Debug -j8 --summary all` | `exit 0`, `6/6 steps`; empty and partial literals both compiled; locked x drifted `0.000000 m` over a `5.020831 m` fall, unlocked advanced `1.999998 m`; `setMotionLocks` agreed | `.../before-20261004T200332Z/box3d-motion-locks.json` |
| Review-contract probe: runtime consumer with a fresh provider | `zig build` of the consumer under `-Druntime=true` against a shared object built from this tree | `exit 0` | `.../before-20261004T200332Z/box3d-consumer-runtime-provider.json` |
| Six-target compile matrix | `zig build check` | `exit 0`, `Build Summary: 37/37 steps succeeded`, no failing step, all six declared targets seen; compiles and links, runs nothing | baseline run `20261005T014547Z-797a73f2`, label `baseline-box3d-check` |
| Published 53-target matrix | `cross-test --jobs 8 --build-jobs 8` | `exit 1`: **9 pass, 33 build-only, 0 build failures, 11 run failures** of 53; 20 cells executed, 19 tests each | run `20261004T221720228710Z-45046`, receipt `box3d-53-target-8.json`, source stamp `88106c0349…` unchanged across the run |

Three of the four probe rows answer the two review findings, both refuted with
no source change.
In a linked build `c` is the translated header itself — the
`translate.createModule()` import in `build.zig`'s linked branch — which
publishes neither `load` nor `loadedSource` — only the generated dispatch
does, from the template at `runtime/generate.zig:951-960` reached through
`graph.createModule` (the runtime-loaded branch of the same `build.zig`) — and
the probe showed that Zig 0.16.0 does not analyse the statements after the
`comptime`-taken branch, so
`zig/root.zig:263-282` is correct as written and needs no rewrite. On
`MotionLocks`, the translate-c output gives all six fields `= false`
(`box3d-standalone-linked-static/o/8a9a8830e2a72bc62d9a596f86498d0b/translate.zig:3190-3198`)
and the dispatch re-exports that declaration rather than restating it, and the
probe then measured the promise rather than only compiling it. The provider row
loaded one shared object named on the command line and tried no fallback.

The shared row built and installed; it did not execute the shared object. The
runtime row loaded one provider that was named on the command line and worked,
and tried no fallback, no system basename and no second provider.

Each double-precision row named an explicit `--cache-dir`,
`--global-cache-dir` and `--prefix`, and each ran at `-j8 --summary all`. Those
rows add no other optimize mode, no other target and no NetBSD cell, and none of
them runs the `consumer` step, so they say nothing about the helper recorded
above, and no run here has driven the nested build through that step.

The devenv rows are one acceptance run and they say exactly what it says. All
eight of its gates passed, `gates_failed` and `gates_unsupported` are empty, and
`gates_not_run` names `nix:build` alone, so both Nix outputs remain outstanding.
The three build gates ran with `--from path:/vol/fob-vol7/mi19/gertullj/foundation-libs/box3d`
and a working directory outside this tree, so the `sdk root:` the banner printed
is this SDK's own and the task bodies resolved it themselves. The consumer row is
the manual `cd consumer && zig build run` form: it is the first build of
`consumer/` in this SDK, and it is not the `consumer` step. The earlier run
`20261004T212645Z` is kept above as the cause of the `devenv.nix:222` fix; this
run neither supersedes nor upgrades it.

The foreign row separates four first boundaries, which this file's earlier
entries did not: a wrong world ID **returned** by `b3CreateWorld` on
`aarch64_be-linux`, `mips64-linux` and `powerpc64-linux`, where the payload
arrived intact and the C control returned a valid id; a world ID that looks
correct and a wrong argument to the later `b3World_IsValid` on `x86-linux`; a
`b3WorldDef` pointer fault on `powerpc-linux` and `s390x-linux`, where no world ID
is ever returned; a `b3BodyDef` pointer fault on `hexagon-linux`,
`loongarch64-linux`, `mips64el-linux` and `powerpc64le-linux`, where the world ID
was accepted first; and the two trailing shape arguments on `riscv32-linux`,
where the body is correct and the adapter receives `def=0x1 hull=0x10000`. These
are four distinct observed boundaries. Whether one compiler-level defect
produces all of them is unresolved, and this file claims the boundaries and the
values, not a shared mechanism.

The 53-target row is the same eleven cells the physics-boundary probe above
names, over one more run and with the corrected audit's own classification: 9
pass, 33 build-only, no build failure at all, 11 run failures. Its three
signatures are `error.WorldLimitExceeded` raised at `zig/world.zig:197` when
`b3World_IsValid(id)` answers false (`aarch64_be-linux`, `mips64-linux`,
`powerpc64-linux`, `x86-linux`), a misaligned or null `const b3BodyDef` at
`B3_CHECK_DEF( def )` in `src/body.c:159` and `src/physics_world.c:208` and a
misaligned `const b3HullData` at `src/hull.c:1658` (`hexagon-linux`,
`loongarch64-linux`, `mips64el-linux`, `powerpc64le-linux`, `riscv32-linux`), and
`Segmentation fault` (`powerpc-linux`, `s390x-linux`). None of them is the
scene-shape defect *Fixed* above answers: that fix is about the geometry a
caller builds, and every one of these eleven cells fails before the library has
anything to simulate.

Both new rows hold one source stamp each. Every build-graph, header, helper and
normalisation edit made after a run describes a tree that run never saw, and
this file claims no cause for the eleven boundary failures.


### Not claimed

* No gate has been run for the rest of this entry. Still outstanding: the tests
  in the three Release modes against an explicit cross target; `zig build
  upstream-test`; `zig build check -Dlinkage=dynamic`, the six-target `check`
  itself having one observed run over the default linkage; any foreign target
  through the `consumer` step; an installed C consumer and a fetched consumer;
  the runtime-loaded build against an in-tree provider; both Nix derivations;
  every `sdk:*` task body except `sdk:consumer` and `sdk:provenance`.
* No claim is made for `castShapeCollect`'s total-count behaviour: no caller
  exists in `tests.zig` or `smoke.zig`, so that path rests on reading
  `zig/query.zig` and not on a run.
* The linked-build path of `load` and `loadedSource` (`zig/root.zig:263-282`)
  is now observed and closed: both probe rows above are this SDK's own. The
  linked build compiles a call to `load` and reaches the documented panic, and
  `loadedSource()` compiles and answers `null`, so the guard is correct as
  written and needs no rewrite. What is *not* claimed: no gate calls `load`
  unconditionally in a runtime-loaded build either, so the guard's success path
  is covered only by `smoke`, `tests` and the consumer under `-Druntime=true`,
  each through its own `if (comptime runtime_loaded)`. See `FORK-NOTES.md`.
* The `buildFlags` tail and the fail-closed `cdSdkRoot` cache preamble in
  `devenv.nix` are now observed on one route. Run `20261004T214803Z` ran
  `sdk:consumer` under `--mode single`, so that body ran without the shell hooks:
  `cdSdkRoot` did not `exit 1`, and the `Build Summary: 6/6 steps succeeded` line
  is the `--summary all` the body passed. The shell route printed the two banner
  lines this entry used to demand before anything could move — `sdk root:
  /vol/fob-vol7/mi19/gertullj/foundation-libs/box3d` and `cache:
  /home/tmp2/gertullj/cache/zig-local (global /home/tmp2/gertullj/cache/zig)` —
  and `zig env` reported both cache variables outside this tree, so the shell
  chose its own directories and named them. What is still not claimed: the other
  ten task bodies have not run, no other body has passed the flag tail to a
  compiler, and `devenv build outputs.static` and `outputs.shared` have not run,
  so §23's prefix rule is exercised by no receipt in this file.
* `zig build check` is a compile check. A target that compiles and links has
  not executed, and no cross-built binary is reported as having run.
* Windows is not exposed as a flake package. That is a packaging decision about
  what has been defined here, recorded in `README.md` and `flake.nix`, and not a
  claim that Box3D's source cannot build for it.
* The 53-platform run `20261004-164517-9067-28500` is red in 27 of 53 cells:
  16 build failures and 11 run failures. The three entries under *Fixed* each
  answer one of those three groups, and none of them has been run: no cell of
  that run, no `zig build check` cell and no consumer gate observes them. They
  are `PENDING-VERIFICATION`, and nothing above should be read as their
  result.

## 1. Import of Box3D v0.1.0 — 2026-10-04

* Imported the official `erincatto/box3d` tree at tag `v0.1.0`, commit
  `8441b4a06d6d09dcfb0b0f704df4d847d1437b92`: 349 files, 11,095,421 bytes.
  The working tree carries no history — `.git/` has `HEAD`, a `config` with no
  remote, and empty `objects/`, `refs/heads/`, `refs/tags/` — so the commit id
  is a recorded pin and the per-file digests are the observation. See
  `UPSTREAM.md`.
* No native file was edited, patched or reformatted. That is checked by
  `tools/check-provenance.sh`, not asserted by prose.
* The upstream README was preserved byte for byte as `README.upstream.md`
  before `README.md` was taken over by this fork.