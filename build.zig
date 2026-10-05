//! Zig 0.16 build for Box3D, erincatto's 3D physics engine.
//!
//! The library is upstream's own C, byte for byte: the forty-nine translation
//! units of `BOX3D_SOURCE_FILES` (`src/CMakeLists.txt:3-90`) and the eight
//! public headers of `BOX3D_INCLUDE_FILES` (`:92-101`). Nothing is downloaded,
//! no CMake/Make/configure script is executed, and there is no system-library
//! mode: a build here always compiles this repository.
//!
//! The one C translation unit this package compiles beside those forty-nine
//! and that upstream does not ship is `build_support/box3d_abi_bridge.c`, which
//! adds no algorithm: it gives the ten public signatures that take a `b3Pos`
//! by value ahead of a floating-point argument a pointer-taking form Zig can
//! lower correctly on x86-64, and each body is one call into the unchanged
//! by-value entry point. `build_support/box3d_abi_bridge.h` is the long form,
//! with the measurement that showed which ten.
//!
//! Upstream reference: tag `v0.1.0`, commit
//! `8441b4a06d6d09dcfb0b0f704df4d847d1437b92`, `project(box3d VERSION 0.1.0
//! DESCRIPTION "A 3D physics engine for games" HOMEPAGE_URL "https://box2d.org")`
//! (`CMakeLists.txt:4-9`). The pin itself belongs in `UPSTREAM.md`, which the
//! fork's provenance owner writes; this script holds the version because the
//! manifest, the shared object's file name and the pkg-config metadata all have
//! to agree on it, and refuses to configure when they stop agreeing.
//!
//! Entry points
//! -----------
//!   zig build           install the library, the eight public headers, the
//!                       pkg-config file, the licence and provenance records,
//!                       and compile the smoke program (not run)
//!   zig build test      run the behavioural tests for the selected target
//!                       (`-Dtarget`; the host when it is absent)
//!   zig build smoke     run the smoke program
//!   zig build upstream-test
//!                       build and run upstream's own C unit-test program,
//!                       unmodified: the twenty-one files of `BOX3D_TEST_FILES`
//!                       (`test/CMakeLists.txt:3-26`) plus the `shared/`
//!                       support library they link (`shared/CMakeLists.txt:3-16`)
//!   zig build consumer  build the `consumer/` package against
//!                       `dep.module("box3d")`, and run it when this host can
//!                       execute the selected target
//!   zig build check     compile the core, the translation, the facade, the
//!                       tests, the smoke program and upstream's own C unit
//!                       tests for the six-target matrix, running nothing
//!
//!   cross-test          the same `test` step, for the published 53-platform
//!                       Zig 0.16.0 Tier 1/2 table rather than the host alone.
//!                       `cross-test` discovers `cross-test.profile.sh` from
//!                       the package root, runs `zig build test -Dtarget=TARGET`
//!                       for each of them, and executes the binary where a
//!                       runner exists and records explicit `build_only`
//!                       coverage where one does not. `test` is what the
//!                       harness reaches for, and it builds the same graph and
//!                       the same test binary for whatever `-Dtarget` says:
//!                       nothing in `build()` narrows it to the host, and the
//!                       `check` matrix below is compile-only and is not a
//!                       substitute for it.
//!
//! Options
//! -------
//!   -Dlinkage=static   a static archive, `libbox3d.a`. This is the default.
//!   -Dlinkage=dynamic    A real shared object with upstream's own file name
//!                        and soname. Refused on a target whose OS has no
//!                        dynamic linker; see "Where the shared variant is not
//!                        available" below.
//!   -Druntime=true     resolve the native entry points at run time instead of
//!                      linking them. Default off, and orthogonal to
//!                      `-Dlinkage`: the option says which artifact this build
//!                      delivers and installs, this one says whether the facade
//!                      calls it through a link line or through a table an
//!                      explicit `load` fills. The dispatch itself is
//!                      `runtime/graph.zig`, which the API role owns.
//!
//!                      A provider named to `load` has to come from this
//!                      configuration: the same `-Doptimize` and the same
//!                      `-Ddouble-precision`. See "What a provider has to be"
//!                      in `README.zig.md`.
//!   -Ddouble-precision=true
//!                      define `BOX3D_DOUBLE_PRECISION`, which stores world
//!                      positions in `double`. Upstream's own default is off
//!                      (`CMakeLists.txt:91`) and it is the only compile
//!                      definition upstream marks `PUBLIC`
//!                      (`src/CMakeLists.txt:164-168`), because it changes the
//!                      width of fields a consumer also sees.
//!   -Ddisable-simd=false
//!                      force the SIMD kernels on. Left unset, the default is
//!                      decided per resolved target by
//!                      `resolveDisableSimd`: upstream's own default is off
//!                      (`CMakeLists.txt:89`), and it stays off everywhere
//!                      except on a 32-bit ARM target, where `B3_SIMD_NEON`
//!                      cannot compile at all. See "SIMD, and what a target can
//!                      actually run" below.
//!   -Ddisable-simd=true
//!                      define `BOX3D_DISABLE_SIMD` and compile the scalar
//!                      fallback instead of SSE2/NEON.
//!   -Dvalidate=false   compile without `BOX3D_VALIDATE`. Upstream's own
//!                      default is on (`CMakeLists.txt:118`), so this build's
//!                      default is on and passing the option is how it is
//!                      turned off.
//!   -Dtarget=<triple>  build for one target; `zig build check` then checks
//!                      that target only instead of the whole matrix.
//!
//! What is deliberately not an option
//! ---------------------------------
//! `-Dprofile` has no equivalent here. Upstream's `BOX3D_PROFILE` fetches
//! wolfpld/tracy over the network (`src/CMakeLists.txt:137-152`) and this
//! package downloads nothing, so a profiler is not a build configuration this
//! graph can offer rather than one it has hidden.
//!
//! There is no system-library mode. `b.systemIntegrationOption` is the switch
//! this workspace uses for one, and a fork with no system mode records the rule
//! as vacuous rather than satisfied: no Box3D is installed by anything this
//! package controls, and a mode that bound one would describe an ABI that
//! release might not have.
//!
//! Language level and flags
//! ------------------------
//! C17 with extensions, because upstream asks for exactly that
//! (`C_STANDARD 17`, `C_STANDARD_REQUIRED YES`, `C_EXTENSIONS YES`,
//! `src/CMakeLists.txt:124-131`) and the sources use `_Static_assert` and
//! anonymous unions. `-ffp-contract=off` is upstream's own global flag on
//! MinGW, Apple and Unix (`CMakeLists.txt:85-87`), added for the determinism
//! documented at <https://box2d.org/posts/2024/08/determinism/>; it is on every
//! C line here, including the test app's, because upstream adds it before any
//! target is defined.
//!
//! The warning set follows upstream's own per-platform branches
//! (`src/CMakeLists.txt:170-211`) rather than a fixed list: `-Wall -Wextra
//! -pedantic -Wmissing-prototypes` on Apple, the same plus `-Wno-unused-value`
//! on Unix, and nothing on the Windows targets, whose branch upstream leaves
//! empty for MinGW. Upstream's `-Werror` is off by default
//! (`CMakeLists.txt:90`) and is not turned on here. Upstream's Emscripten arm
//! (`-msimd128 -msse2`) is unreachable: this package has no Emscripten target,
//! and `wasm32-wasi` takes the Unix arm, which is the arm upstream's own build
//! would use for it.
//!
//! SIMD, and what a target can actually run
//! ----------------------------------------
//! `BOX3D_DISABLE_SIMD` is not a performance knob here; on one family of
//! targets it is the difference between a library and no library.
//!
//! `src/core.h:50-53` reads it first and selects `B3_SIMD_NONE`. Otherwise
//! `:55-72` picks the widest kernel the *CPU family* names: SSE2 for
//! `B3_CPU_X86_X64` (`:55`), NEON for `B3_CPU_ARM` (`:59`). That family test is
//! `__aarch64__ || __arm__ || _M_ARM64 || _M_ARM` (`src/core.h:41-42`), so
//! 32-bit ARM takes the NEON arm as surely as AArch64 does, and it cannot use
//! it: the NEON block calls `vdivq_f32` (`src/contact_solver.c:872`) and
//! `vsqrtq_f32` (`:877`), and on the pinned toolchain both are declared inside
//! `#if defined(__aarch64__) || defined(__arm64ec__)` at
//! `lib/include/arm_neon.h:44308` -- the float divide and the float square
//! root are AArch64 NEON instructions, not 32-bit ones. A 32-bit NEON vector
//! has no single-instruction float divide or square root at all.
//!
//! So the corrected default is per resolved target and narrow: every target
//! but 32-bit ARM keeps upstream's own default, and 32-bit ARM
//! (`std.Target.Cpu.Arch.arm`, `.armeb`, `.thumb` and `.thumbeb` -- `thumb-*`
//! targets resolve to `.thumb`/`.thumbeb`, which are architectures of their
//! own) defaults to the scalar fallback, because there is no configuration in
//! which its NEON arm compiles. Nothing else
//! about the build changes: `B3_SIMD_NONE` keeps `B3_SIMD_WIDTH 4`
//! (`src/core.h:51-52`), the same width the NEON arm uses, so the C ABI, the
//! struct layouts and every published declaration are identical either way and
//! the only difference is arithmetic width. `-Ddisable-simd=false` still
//! forces the NEON arm on, and still fails to compile -- that is the caller's
//! choice made explicitly, not a default this file quietly overrides.
//!
//! The decision is read from the resolved target inside each graph rather
//! than once in `build`, because `check` walks six targets of its own and a
//! single value computed for the host would silently apply the host's SIMD
//! answer to all six of them.
//!
//! Compilation backend
//! -------------------
//! Every Zig root this build owns sets `.use_llvm = true`: the `test` root,
//! both `smoke` roots and the `consumer` root, plus
//! `consumer/build.zig`'s own executable. See "Zig's x86_64 backend lowers
//! differently from the compiler that built the core" in
//! `build_support/box3d_abi_bridge.h:1-36`, which measured it on this pin, and
//! `FORK-NOTES.md` for the 53-platform receipt. The requirement is on the
//! root, so an external dependent has to state it too; a published module
//! cannot force a dependent's backend.
//!
//! The C archive is not one of those roots. It has no Zig code of its own,
//! and the upstream C unit-test program is a pure C program for the same
//! reason, so neither carries the flag.
//!
//! The translation's front end
//! ---------------------------
//! `zig translate-c` parses C with Aro, and Aro preprocesses as well as
//! parses, so `zig/translate.h` can be read either way round: Aro can do both
//! jobs, or the target's own C preprocessor can do the first and Aro the
//! second. `translateRoute` decides per target and
//! `preprocessedTranslateHeader` is the extra front end. Both routes read this
//! repository's headers on the same include path with the same macros; only
//! the preprocessor that has to understand the target's C library changes.
//!
//! NetBSD is the one family that needs the second route, for the reason
//! `generic-netbsd/sys/cdefs.h:411-416` spells out: it defines
//! `__END_DECLS` as `extern "C"` framing around
//! `_Pragma("GCC visibility push(default)")` and
//! `_Pragma("GCC visibility pop")`, `<math.h>` closes every declaration block
//! with `__END_DECLS` (`generic-netbsd/math.h:607`), and Aro destringizes
//! each of those into a `#pragma` line it then hands to the parser as C. The
//! condition is the OS tag rather than a list of nine triples, because the
//! whole family shares that one header and that one cause.
//!
//! Static and shared delivery
//! --------------------------
//! `-Dlinkage` selects which artifact this package produces, and the default is
//! `static`. Nothing about the compiled C changes between the two: the same
//! forty-nine sources, the same language level, the same macros and the same
//! include paths. The option selects the *delivery*, never the dispatch.
//!
//! `dynamic` is a real shared object, which takes four things this build would
//! otherwise not do:
//!
//!   * **Position independence.** A shared library's objects have to be PIC;
//!     every compilation unit here belongs to the one module that produces it,
//!     so there is no independently compiled constituent that could be missed.
//!   * **An export surface.** Upstream compiles the library with hidden default
//!     visibility (`C_VISIBILITY_PRESET hidden`, `CMAKE_VISIBILITY_INLINES_HIDDEN
//!     1`, `src/CMakeLists.txt:103-106`) and lets `BOX3D_EXPORT` be the only
//!     thing that widens it. This build adds `-fvisibility=hidden` and
//!     `-fvisibility-inlines-hidden` for the same reason, which needs no version
//!     script and no hand-written export list: `include/box3d/base.h:28-30`
//!     resolves `BOX3D_EXPORT` to `__attribute__((visibility("default")))`
//!     whenever `box3d_EXPORTS` is defined, so every `B3_API` declaration stays
//!     exported and every internal cross-translation-unit symbol stays private.
//!   * **The export macro itself.** `include/box3d/base.h:21-35` reads
//!     `box3d_EXPORTS` for "this compilation is producing the shared library"
//!     and `BOX3D_DLL` for "this compilation is consuming one". The first is
//!     CMake's own doing: a shared `add_library` target is compiled with
//!     `<target>_EXPORTS` defined, and `base.h:22` is written to read exactly
//!     that name. The second is upstream's explicit `INTERFACE` definition for a
//!     Windows shared build (`src/CMakeLists.txt:170-175`). This build puts
//!     `box3d_EXPORTS` on the library's own compile line and `BOX3D_DLL` on the
//!     translation and in the installed `box3d.pc`, which is upstream's own
//!     split between the definition side and the declaration side. A static
//!     build defines neither, which is why `base.h:33` leaves `BOX3D_EXPORT`
//!     empty there.
//!   * **A version.** `b.addLibrary`'s `version` is what
//!     `std/Build/Step/Compile.zig:487-508` turns into upstream's file name:
//!     `VERSION ${PROJECT_VERSION}` and `SOVERSION ${PROJECT_VERSION_MAJOR}`
//!     (`src/CMakeLists.txt:128-131`) make `libbox3d.so.0.1.0` with
//!     `libbox3d.so.0` and `libbox3d.so` beside it on ELF
//!     (`Compile.zig:501-504`, and `wantSharedLibSymLinks` at
//!     `lib/std/Build.zig:2717-2719` says there are none on Windows, where
//!     `box3d.dll` and its import library `box3d.lib` land instead), and
//!     `libbox3d.0.dylib` with `libbox3d.dylib` beside it on Darwin
//!     (`Compile.zig:492-495`). The *soname* -- the number a dependent's
//!     `DT_NEEDED` records, and the name a `.system` load has to give -- is
//!     `libbox3d.so.0`.
//!
//! Where the shared variant is not available, and what this build does
//! -------------------------------------------------------------------
//! WASI has no dynamic linker -- `std.Target.DynamicLinker.kind` is `.none` for
//! that OS -- so it cannot carry a shared object at all, and `zig build check`
//! walks a WASI target. A `-Dlinkage=dynamic` graph therefore *refuses* that
//! combination: it stops at configure time, names the platform fact it resolved
//! from `std.Target.DynamicLinker.kind`, and names the spelling that works
//! there. It does not build a static archive and hand it back as though that
//! were what was asked for, because the artifact's name, its file name, the
//! `-DBOX3D_DLL` in `box3d.pc` and the loader a caller would then point at would
//! all disagree with what came back.
//!
//! `-Dlinkage=static` is the default and is a full configuration for every
//! target in the matrix, WASI included. What is unsupported is the shared
//! variant of one target, not the target. `zig build check -Dlinkage=dynamic`
//! therefore names its five targets one at a time, the way
//! `.github/workflows/verify.yml` does, and the sixth is covered by a step that
//! asserts the documented refusal.
//!
//! Installed closure
//! -----------------
//! `zig build` installs, under `--prefix`:
//!
//!   * the native library in the selected linkage, through `installArtifact`;
//!   * the eight public headers at `include/box3d/`, through `installHeader`,
//!     which also puts them on the include search path of anything that links
//!     this artifact, so a C consumer needs nothing from this tree;
//!   * `lib/pkgconfig/box3d.pc`, generated here. Upstream ships no
//!     pkg-config template, so this file is fork-authored: `prefix` is
//!     `${pcfiledir}/../..` rather than a configured absolute prefix, so the
//!     installed file is correct wherever `--prefix` put it;
//!   * `share/licenses/box3d/` with upstream's `LICENSE`, the preserved
//!     upstream `README.upstream.md`, and this fork's `NOTICE.md`,
//!     `UPSTREAM.md` and `FORK-LICENSE.md`. A private repository removes no
//!     licence obligation, and a package that ships a binary without them is
//!     the failure this prevents.
//!
//! No native tool executable and no data file is installed. Upstream builds
//! none outside `samples/` and `benchmark/`, which this package does not
//! compile: `samples/` needs sokol, earcut, jsmn and tiny_obj_loader and a
//! windowing backend, and `benchmark/` needs a mesh loader that is part of the
//! samples. `src/box3d.natvis` is a Visual Studio debugger-visualisation file
//! that only MSVC loads (`src/CMakeLists.txt:177-179`) and is retained rather
//! than installed. `data/` is sample and benchmark material; nothing this
//! package compiles reads it.
//!
//! Upstream's own unit tests
//! -------------------------
//! `test/main.c` reaches Box3D's internals directly -- `test/CMakeLists.txt:36-37`
//! puts `src/` on its include path, and the twenty-one files include `aabb.h`,
//! `bitset.h`, `block_allocator.h`, `compound.h`, `container.h`, `core.h`,
//! `ctz.h`, `math_internal.h`, `physics_world.h`, `platform.h`, `recording.h`,
//! `shape.h`, `simd.h`, `table.h` and `utils.h`. None of those is exported from
//! the shared object, because none of them is public and upstream compiles with
//! hidden visibility. Upstream therefore builds the tests only when the library
//! is static (`CMakeLists.txt:139-146`: "Tests need static linkage because they
//! test internal Box3D functions"). This build keeps that property rather than
//! restricting `-Dlinkage`: the native test app always links a *static*
//! compilation of the same forty-nine sources with the same flags, so
//! `upstream-test` works under `-Dlinkage=dynamic` too. Under the default
//! `-Dlinkage=static` the delivered archive is that archive and is reused.
//!
//! Published routes
//! ----------------
//!   * `dep.module("box3d")`: the Zig facade, `zig/root.zig`. This is the one
//!     registered module. It carries `link_libc`, the translated header as `c`,
//!     the platform libraries the core actually uses, and the library behind it,
//!     so a dependent that adds this module needs nothing further.
//!   * `box3d.c` on that same module: the translated header itself, for a
//!     caller that needs a declaration the facade does not name. It is
//!     deliberately *not* registered as a module of its own: `addModule("c")`
//!     would make `dep.module("c")` resolve, and that route hands over the same
//!     declarations without the library that satisfies them, which is a
//!     reachability a dependent cannot tell from support.
//!   * `dep.artifact("box3d")`: the compiled native library, in whichever
//!     `-Dlinkage` selected. This is the C-ABI route for a dependent that links
//!     the library into its own C or Zig build.

const std = @import("std");

const manifest = @import("build.zig.zon");

/// The runtime-loading seam, which the API role owns.
///
/// `-Druntime=true` substitutes `graph.createModule` for
/// `translate.createModule()`. It takes the `TranslateC` step this build has
/// already made, so the generated dispatch keeps the exact translated type and
/// constant namespace rather than compiling a second copy of the native extern
/// structs and casting between two nominally distinct Zig modules.
const graph = @import("runtime/graph.zig");

/// The upstream release this fork is pinned to, in the one form this file
/// needs it: a version to hold `build.zig.zon`, the shared object's file name
/// and the pkg-config metadata to.
///
/// Read out of `project(box3d VERSION 0.1.0 ...)` (`CMakeLists.txt:4-8`).
const upstream_version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 0 };

/// The installed library's base name, the module name, and the artifact name.
/// All three are upstream's own (`add_library(box3d ...)`, `add_library(box3d
/// ...)` alias `box3d::box3d`, `src/CMakeLists.txt:108`, `:216`).
const lib_name = "box3d";

/// The import name `zig/root.zig` reaches the translated header by, and the one
/// it reaches the loader core's public types by in a linked build.
const c_import_name = "c";
const rt_import_name = "rt";

/// The fork's translate-c root header, the facade, the behavioural tests and
/// the smoke program.
///
/// ## Two public declarations upstream declares twice
///
/// Two names in the pinned public headers are each declared twice, unguarded,
/// with byte-identical signatures, so every configuration that reaches them
/// sees both copies:
///
///   * `b3IsValidFloat` at `include/box3d/math_functions.h:159` and
///     `include/box3d/math_functions.h:1077`;
///   * `b3DynamicTree_Validate` at `include/box3d/collision.h:85` and
///     `include/box3d/collision.h:106`.
///
/// 580 `B3_API` declarations therefore describe 578 distinct symbols. The
/// aggregate header cannot avoid this: both copies of each pair are inside one
/// header, so no include order and no `-D` reaches them differently, and there
/// is no configuration in which one is hidden.
///
/// Nothing here changes that. `zig/translate.h` includes upstream's
/// `box3d/box3d.h` whole, upstream's public headers stay byte-for-byte, and a
/// generated shadow copy of a public header would be a second dialect of the
/// same interface rather than a fix -- it would quietly drift from the header
/// the core is compiled against, which is the failure `WISDOM.md` W14 is about.
///
/// Whether it matters is a question about `zig translate-c`, and this file
/// cannot answer it: the translator's duplicate handling lives in the compiler,
/// not in `lib/std`, and no gate has run here. If the translator rejects an
/// identical redeclaration, the first `zig build` prints
/// `redefinition of 'b3IsValidFloat'` (or of `b3DynamicTree_Validate`) against
/// `zig/translate.h` and the resolution is a recorded native-source deviation:
/// remove the *second* declaration in each pair, per file and per line, with the
/// integrity record and `NOTICE.md` updated. That is a change to bytes upstream
/// ships, so it waits for the observed diagnostic and the driver's authorisation
/// rather than landing pre-emptively.
const translate_header = "zig/translate.h";
const facade_root = "zig/root.zig";
const test_root = "tests.zig";
const smoke_root = "smoke.zig";

/// The whole library: forty-nine translation units.
///
/// This list is `BOX3D_SOURCE_FILES` (`src/CMakeLists.txt:3-90`) with the
/// headers, the `.natvis` file and the `recording_ops.inl` include dropped,
/// because those are inputs rather than translation units. `hull_map.h` is not
/// in upstream's list at all and is not here either; it is a private header
/// reached by quoted include from `mesh.c`, which needs it on the include path
/// and not on a source list.
const core_sources = [_][]const u8{
    "aabb.c",
    "arena_allocator.c",
    "bitset.c",
    "block_allocator.c",
    "body.c",
    "broad_phase.c",
    "capsule.c",
    "compound.c",
    "constraint_graph.c",
    "contact.c",
    "contact_solver.c",
    "convex_manifold.c",
    "core.c",
    "distance.c",
    "distance_joint.c",
    "dynamic_tree.c",
    "height_field.c",
    "hull.c",
    "id_pool.c",
    "island.c",
    "joint.c",
    "manifold.c",
    "math_functions.c",
    "mesh.c",
    "mesh_contact.c",
    "motor_joint.c",
    "mover.c",
    "parallel_for.c",
    "parallel_joint.c",
    "physics_world.c",
    "prismatic_joint.c",
    "recording.c",
    "recording_replay.c",
    "revolute_joint.c",
    "scheduler.c",
    "sensor.c",
    "shape.c",
    "simd.c",
    "solver.c",
    "solver_set.c",
    "sphere.c",
    "spherical_joint.c",
    "table.c",
    "timer.c",
    "triangle_manifold.c",
    "types.c",
    "weld_joint.c",
    "wheel_joint.c",
    "world_snapshot.c",
};

/// Upstream's sample/benchmark support library, in full.
///
/// `shared/CMakeLists.txt:3-16` builds all ten as one static library for the
/// samples, the benchmarks and the unit tests; `test_world.c` uses
/// `benchmarks.h`, `overflow_color.h` and `stability.h`, `test_determinism.c`
/// uses `determinism.h` and `test_math.c` uses `utils.h`, and `benchmarks.c`
/// itself includes `human.h` (`shared/benchmarks.c:6`). The whole library is
/// therefore part of the test closure, and none of it is part of the installed
/// Box3D: upstream never links it into the library either
/// (`shared/CMakeLists.txt:25`).
const shared_sources = [_][]const u8{
    "benchmarks.c",
    "determinism.c",
    "human.c",
    "overflow_color.c",
    "stability.c",
    "utils.c",
};

/// Upstream's own C test program: every file of `BOX3D_TEST_FILES`
/// (`test/CMakeLists.txt:3-26`), the header included, compiled unmodified.
const upstream_test_sources = [_][]const u8{
    "main.c",
    "test_allocator.c",
    "test_bitset.c",
    "test_body.c",
    "test_body_query.c",
    "test_collision.c",
    "test_compound.c",
    "test_container.c",
    "test_determinism.c",
    "test_distance.c",
    "test_height_field.c",
    "test_hull.c",
    "test_id.c",
    "test_joint.c",
    "test_large_world.c",
    "test_math.c",
    "test_mover.c",
    "test_recording.c",
    "test_shape.c",
    "test_table.c",
    "test_world.c",
};

/// The public headers, each with the path it is installed at.
///
/// `BOX3D_INCLUDE_FILES` (`src/CMakeLists.txt:92-101`, `:231-240`). Upstream
/// installs them flattened into `${CMAKE_INSTALL_INCLUDEDIR}/box3d`, and the
/// sources include them as `<box3d/...>`, so the installed tree has to keep the
/// `box3d/` directory for a consumer's `#include <box3d/box3d.h>` to resolve.
const PublicHeader = struct {
    /// The file in this repository.
    source: []const u8,
    /// Where it lands under the prefix, which is `include/` plus this.
    dest: []const u8,
};

const public_headers = [_]PublicHeader{
    .{ .source = "include/box3d/base.h", .dest = "box3d/base.h" },
    .{ .source = "include/box3d/box3d.h", .dest = "box3d/box3d.h" },
    .{ .source = "include/box3d/collision.h", .dest = "box3d/collision.h" },
    .{ .source = "include/box3d/config.h", .dest = "box3d/config.h" },
    .{ .source = "include/box3d/constants.h", .dest = "box3d/constants.h" },
    .{ .source = "include/box3d/id.h", .dest = "box3d/id.h" },
    .{ .source = "include/box3d/math_functions.h", .dest = "box3d/math_functions.h" },
    .{ .source = "include/box3d/types.h", .dest = "box3d/types.h" },
};

/// The fork's own C sources and its one include-path shim, in `build_support`.
///
/// `box3d_abi_bridge.c` exists because Zig 0.16's x86_64 argument lowering
/// consumes a vector-register pair for a by-value float aggregate of at most
/// 24 bytes that it then passes in memory, so the ten `B3_API` signatures in
/// `include/box3d/box3d.h` that take a `b3Pos` by value ahead of a
/// floating-point argument or return place their later vector arguments one
/// register pair too high. Measured on this package's own artifacts: the
/// native `b3World_CastRayClosest` reads `translation` from `XMM0`/`XMM1` and
/// the Zig caller writes it to `XMM2`/`XMM3`, while the `b3Transform` and
/// `b3Mat3` neighbours agree on `XMM0`/`XMM1` and are not in the set.
/// `build_support/box3d_abi_bridge.h` carries the long form and the complete
/// list.
///
/// The bridge is compiled into `c_mod` rather than a module of its own, so the
/// call each body makes is laid out by the same clang invocation, with the
/// same `BOX3D_*` settings, as the `src/` unit it reaches. `zig/translate.h`
/// reaches its header by a quoted relative path, so no other translation unit
/// can pick that one up by name.
///
/// `Windows.h` is the other file here, and the only one that has to be on a
/// search path: `src/timer.c:26` and `shared/utils.c:7` both include
/// `<Windows.h>`, which resolves only on a case-insensitive filesystem, so a
/// Windows cross build from Linux drops the unit that defines `b3GetTicks`.
/// `addCoreLibrary` and `addUpstreamTestApp` add this directory through
/// `addAfterIncludePath`, which is `-idirafter`, and only for a Windows
/// target. That spelling matters, and the reason is at the call site: an
/// ordinary `-I` would let this directory match its own capitalised name on a
/// case-insensitive host and swallow MinGW's real header.
const bridge_dir = "build_support";

const bridge_sources = [_][]const u8{
    "box3d_abi_bridge.c",
};

/// The licence and provenance material installed beside the binary.
///
/// `LICENSE` is upstream's own MIT text, verbatim. `README.upstream.md` is
/// upstream's `README.md`, preserved byte for byte. The other three are this
/// fork's records, and `share/licenses/box3d/` is the location `package.nix`
/// uses too, so the packaging layer's own install is an idempotent overwrite of
/// these bytes rather than a second copy.
const licence_records = [_][]const u8{
    "LICENSE",
    "README.upstream.md",
    "NOTICE.md",
    "UPSTREAM.md",
    "FORK-LICENSE.md",
};

/// The language level, for every C compilation in this package.
///
/// `-std=gnu17` is upstream's `C_STANDARD 17` with `C_EXTENSIONS YES`
/// (`src/CMakeLists.txt:123-131`); the sources need `_Static_assert` and
/// anonymous unions, so a strict `c17` spelling would be a second opinion
/// upstream never asked for. `-ffp-contract=off` is upstream's own global
/// determinism flag (`CMakeLists.txt:85-87`); it is here on every C line,
/// including the test app's, because upstream adds it before any target is
/// defined.
const language_flags = [_][]const u8{
    "-std=gnu17",
    "-ffp-contract=off",
};

/// Upstream's Apple warning branch (`src/CMakeLists.txt:197-198`).
const apple_warning_flags = [_][]const u8{
    "-Wall",
    "-Wextra",
    "-pedantic",
    "-Wmissing-prototypes",
};

/// Upstream's Unix warning branch (`src/CMakeLists.txt:202-204`).
///
/// `-Wno-unused-value` is upstream's own suppression of the conditional
/// expression warnings the SIMD and contact code raise, and it is not a
/// portability exception: it is in upstream's file.
const unix_warning_flags = [_][]const u8{
    "-Wall",
    "-Wextra",
    "-pedantic",
    "-Wmissing-prototypes",
    "-Wno-unused-value",
};

/// Upstream's Windows branch adds no GCC-style warning options at all: the
/// MinGW arm (`src/CMakeLists.txt:194-195`) is a message and nothing else, and
/// the MSVC arm above it uses `/W4` and four `/wd` suppressions, which are
/// MSVC's own spelling and do not apply to a clang target. Named rather than
/// written `&.{}` so the switch's arms are three slices of the same type.
const no_warning_flags = [_][]const u8{};

/// The hidden-visibility pair upstream sets on the library target
/// (`src/CMakeLists.txt:103-106`).
const visibility_flags = [_][]const u8{
    "-fvisibility=hidden",
    "-fvisibility-inlines-hidden",
};

/// Which C compilation a flag list is being built for.
///
/// The visibility flags belong to the library alone: upstream's
/// `C_VISIBILITY_PRESET` and `VISIBILITY_INLINES_HIDDEN` are set in
/// `src/CMakeLists.txt` before `add_library(box3d ...)`, so they are directory
/// properties of `src/` and never reach `shared/` or `test/`.
const CUnit = enum {
    /// The forty-nine sources of `src/`.
    core,
    /// `shared/`, upstream's sample and benchmark support.
    support,
    /// `test/`, upstream's own unit-test program.
    tests,
};

/// Everything the option line decides, resolved once.
///
/// One value, so the core, the translation, the facade, the native test app and
/// the pkg-config file cannot describe two different builds.
const Options = struct {
    /// Which artifact this build delivers and installs.
    linkage: std.builtin.LinkMode,
    /// Whether the facade dispatches through a loaded table or a link line.
    runtime_loaded: bool,
    /// `BOX3D_DOUBLE_PRECISION`, upstream's only `PUBLIC` compile definition.
    double_precision: bool,
    /// `BOX3D_DISABLE_SIMD`. `null` is not a third value the build has to keep
    /// straight: it is the caller having named no answer, and
    /// `resolveDisableSimd` supplies the one this target gets. It is `?bool`
    /// rather than `bool` for exactly that reason -- a `bool` here would have
    /// to be resolved once, against the host, and `check` builds six graphs
    /// that are not the host.
    disable_simd: ?bool,
    /// `BOX3D_VALIDATE`.
    validate: bool,
};

/// Everything one target needs: the compiled library and the facade module.
///
/// The translated header is reached through the facade's `c` import, so nothing
/// else in this file needs it by name and it is not a field here.
const Graph = struct {
    /// The C ABI artifact a C or Zig consumer links, and the one the facade
    /// module carries so a dependent gets it by asking for the module alone.
    c_lib: *std.Build.Step.Compile,
    /// The Zig facade, with `c` bound to the translation and the library linked
    /// in -- or, under `-Druntime=true`, with `c` bound to the generated
    /// dispatch and nothing linked at all.
    module: *std.Build.Module,
};

/// The six compile-only baseline targets.
///
/// These are the six this workspace keeps as the fast matrix, in the order the
/// documentation names them. `check` compiles every one of them and runs
/// nothing.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// The artifact name for one target.
///
/// Cross-target checks need a distinct name per target: six libraries called
/// `box3d` in one build graph write to one cache path and make `--summary all`
/// unable to tell them apart.
fn artifactName(b: *std.Build, target: std.Build.ResolvedTarget, public: bool) []const u8 {
    if (public) return lib_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("box3d: unspellable target");
    return b.fmt("{s}-{s}", .{ lib_name, triple });
}

/// Whether this target's OS reaches Box3D's pthread paths.
///
/// `src/timer.c` has four arms: `_WIN32` (`:20`), `__linux__ || __EMSCRIPTEN__`
/// (`:227`, `<pthread.h>` at `:266`, `<semaphore.h>` at `:296`), `__APPLE__`
/// (`:384`, `<pthread.h>` at `:442`, `<dispatch/dispatch.h>` at `:473`) and a
/// fallback (`:562`) whose `b3CreateThread` runs the worker inline
/// (`:651-655`) and needs no threading library at all. This package has no
/// Emscripten target, so the two that need a threading library are these two.
///
/// Only Linux is given `-pthread` and `-lpthread`. Upstream's Apple branch adds
/// neither -- CMake does not, and macOS resolves `pthread_create` from
/// libSystem -- so adding them there would be a change to upstream's own
/// configuration rather than a reproduction of it.
fn usesPthread(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .linux;
}

/// Whether this target's maths functions live in a separate `libm`.
///
/// Upstream attaches `m` for `UNIX AND NOT APPLE AND NOT EMSCRIPTEN`
/// (`src/CMakeLists.txt:218-221`) and calls the reason out in the comment above
/// it: "libm is required on many Unix toolchains for sqrtf, etc." The core does
/// call `sqrtf` (`src/capsule.c:126`, `src/contact_solver.c:1102`,
/// `src/manifold.c:27` and more than a dozen other places).
///
/// macOS is excluded because libSystem carries the maths functions, and WASI
/// because wasi-libc carries them in libc. Windows is excluded for a different
/// reason: CMake's `UNIX` is also true for MinGW, so upstream would name `m`
/// there, but this package's only Windows target is `x86_64-windows-gnu`, whose
/// maths functions come from the CRT the toolchain already links, and naming a
/// library that target may not carry would trade a working link for a name
/// upstream's flag only happened to imply. That is a build-configuration fact
/// the driver confirms with `zig build check -Dtarget=x86_64-windows-gnu`, not
/// an observed result.
fn usesLibm(target: std.Build.ResolvedTarget) bool {
    return switch (target.result.os.tag) {
        .linux, .freebsd, .netbsd, .openbsd, .dragonfly, .illumos => true,
        else => false,
    };
}

/// Upstream's warning set for one target.
fn warningFlags(target: std.Build.ResolvedTarget) []const []const u8 {
    return switch (target.result.os.tag) {
        // Upstream's MinGW branch (`src/CMakeLists.txt:194-195`) is a message
        // and no options. Its MSVC branch uses `/W4` and four `/wd`
        // suppressions, which are MSVC's own option spelling; this package has
        // no MSVC target, so neither set applies and nothing is added.
        .windows => &no_warning_flags,
        .macos => &apple_warning_flags,
        else => &unix_warning_flags,
    };
}

/// Whether this target cannot run the float NEON intrinsics Box3D's NEON
/// kernel calls.
///
/// `src/core.h:41-42` makes `B3_CPU_ARM` cover `__arm__` as well as
/// `__aarch64__`, so `src/core.h:59-61` hands a 32-bit ARM build the same
/// `B3_SIMD_NEON` arm an AArch64 build gets, and `src/contact_solver.c:777`
/// includes `<arm_neon.h>` for it. That header declares `vdivq_f32`
/// (`lib/include/arm_neon.h:50216`) and `vsqrtq_f32` (`:64883`) inside the
/// block opened at `:44308`, `#if defined(__aarch64__) ||
/// defined(__arm64ec__)`: on a 32-bit ARM target neither exists, because the
/// single-instruction float divide and square root are AArch64 NEON
/// instructions. 32-bit NEON has integer `vdivq` and no float divide or square
/// root at all.
///
/// `.arm`, `.armeb`, `.thumb` and `.thumbeb` are the four 32-bit ARM
/// architectures in `std.Target.Cpu.Arch` (`std/Target.zig:1333-1334`,
/// `:1374-1375`), and all four need this answer. `thumb` and `thumbeb` are
/// architectures of their own, not features on `.arm`/`.armeb`: they are enum
/// values, `std/zig/system.zig:407-409` *adds* `arm.thumb_mode` to them as a
/// feature, `std/Target.zig:1067` gives all four the same `.ARM` ABI family,
/// and `std/zig/system.zig:138-139` lists them beside the other architectures
/// that need a runner name. A build that matched only `.arm`/`.armeb` resolved
/// `disable-simd=false` for every `thumb-*` target and then failed to compile
/// the same two intrinsics on all of them.
///
/// Nothing else in this build's target space is affected -- AArch64 in either
/// endianness has the instructions, `wasm32-wasi` never reaches NEON at all
/// because `B3_CPU_WASM` needs `__EMSCRIPTEN__` (`src/core.h:43-44`,
/// `:63-67`), and x86 keeps SSE2 on both widths.
fn targetLacksArmNeonFloatMath(target: std.Build.ResolvedTarget) bool {
    return switch (target.result.cpu.arch) {
        .arm, .armeb, .thumb, .thumbeb => true,
        else => false,
    };
}

/// `BOX3D_DISABLE_SIMD` for one resolved target.
///
/// An explicit `-Ddisable-simd=` always wins, in both directions: a caller who
/// says `false` on a 32-bit ARM target is choosing a compile that fails, and
/// this file does not turn that into a success by answering a question they
/// asked. Unset, the answer is upstream's own default -- SIMD on -- everywhere
/// except where the target cannot execute the instructions the C
/// implementation calls, where the scalar fallback is the only thing that
/// compiles. See the header note "SIMD, and what a target can actually run".
fn resolveDisableSimd(opts: Options, target: std.Build.ResolvedTarget) bool {
    return opts.disable_simd orelse targetLacksArmNeonFloatMath(target);
}

/// The C flags for one compilation.
///
/// One list, so the core, `shared/` and `test/` cannot disagree about the
/// language level or about the determinism flag: upstream adds
/// `-ffp-contract=off` globally, before any target is defined
/// (`CMakeLists.txt:85-87`), so it belongs to all three.
fn cFlags(b: *std.Build, target: std.Build.ResolvedTarget, unit: CUnit) []const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    const alloc = b.allocator;
    list.append(alloc, language_flags[0]) catch @panic("OOM");
    list.append(alloc, language_flags[1]) catch @panic("OOM");
    if (usesPthread(target)) {
        // The compile half of the Linux threading configuration. `timer.c`
        // itself defines `_GNU_SOURCE` at its line 6 before any system header,
        // so this flag is not what exposes `pthread_setname_np`; it is what
        // tells the compiler and the linker that this translation unit is part
        // of a threaded program.
        list.append(alloc, "-pthread") catch @panic("OOM");
    }
    if (unit == .core) {
        list.append(alloc, visibility_flags[0]) catch @panic("OOM");
        list.append(alloc, visibility_flags[1]) catch @panic("OOM");
    }
    for (warningFlags(target)) |flag| list.append(alloc, flag) catch @panic("OOM");
    return list.items;
}

/// The Box3D compile-time options, as upstream defines them.
///
/// `double_precision` is upstream's only `PUBLIC` definition
/// (`src/CMakeLists.txt:164-168`): a consumer that does not see it would
/// describe a different width for the world-position fields, so it is passed to
/// the translation and the facade as well as to the core.
///
/// `disable_simd` and `validate` are `PRIVATE`
/// (`src/CMakeLists.txt:154-162`), so they reach the core and upstream's own
/// test program -- which upstream also compiles with them
/// (`test/CMakeLists.txt:39-41`) -- and deliberately do *not* reach the
/// translation: `pub const c` must not expose constants that the compiled
/// archive was not built with.
///
/// `target` is here for `disable_simd` alone, and it is what makes the
/// per-target default correct rather than merely intended: the core and
/// upstream's test program are two separate compilations of the same headers,
/// and resolving the option against a target other than the one being built is
/// how those two would end up disagreeing about the kernel.
fn addConfigMacros(
    mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    opts: Options,
) void {
    if (opts.double_precision) mod.addCMacro("BOX3D_DOUBLE_PRECISION", "1");
    if (resolveDisableSimd(opts, target)) mod.addCMacro("BOX3D_DISABLE_SIMD", "1");
    if (opts.validate) mod.addCMacro("BOX3D_VALIDATE", "1");
}

/// The translation's half of the same decision.
///
/// `opts.linkage` is the linkage that was asked for, validated for this target
/// by `requireSupportedLinkage` before anything was created, so there is no
/// third value to keep straight: the translation, the library and the metadata
/// are all driven by that one option.
fn addTranslateMacros(translate: *std.Build.Step.TranslateC, opts: Options) void {
    // `BOX3D_DOUBLE_PRECISION` and nothing else. It is upstream's only `PUBLIC`
    // compile definition (`src/CMakeLists.txt:164-168`), and the comment there
    // says why: "consumers must see the same precision mode in the headers or
    // they cannot match the ABI". It changes the width of `b3Pos` and of
    // `b3WorldTransform` (`include/box3d/math_functions.h:87-95`) and it renames
    // `b3CreateWorld` (`include/box3d/box3d.h:25-30`), so a translation without
    // it would not describe the compiled core. It is off by default, which is
    // upstream's own default, and in that default configuration `b3Pos` is
    // `b3Vec3`.
    //
    // `BOX3D_DISABLE_SIMD` and `BOX3D_VALIDATE` are deliberately absent. Both
    // are `PRIVATE` upstream (`src/CMakeLists.txt:154-162`), both select code
    // paths inside the library, and neither changes a declaration; defining
    // them here would expose constants that the compiled archive was never
    // built with. `B3_ENABLE_VALIDATION` (`include/box3d/base.h:70-74`) is a
    // header constant computed from a macro this line does not define, so it
    // reads 0 in the translation whatever `-Dvalidate` says -- which is right,
    // because `pub const c` describes the interface, not one compilation of it.
    if (opts.double_precision) translate.defineCMacro("BOX3D_DOUBLE_PRECISION", "1");
    // Upstream's `INTERFACE BOX3D_DLL` for a Windows shared build
    // (`src/CMakeLists.txt:170-175`). `include/box3d/base.h:25-27` reads it to
    // choose `__declspec(dllimport)`; on ELF and macOS it is unread and
    // `BOX3D_EXPORT` resolves to nothing at all, so defining it there is
    // upstream's own behaviour rather than a portability exception.
    //
    // `box3d_EXPORTS` is deliberately *not* here: it is the half that says
    // "this compilation is producing the shared library", and it belongs only on
    // the library's own compile line. Defining it on the translation would make
    // every declaration visible-default in a module that defines none of them.
    if (opts.linkage == .dynamic) translate.defineCMacro("BOX3D_DLL", "1");
}

/// Which front end reads `zig/translate.h` for this target.
const TranslateRoute = enum {
    /// Aro preprocesses `zig/translate.h` for itself and parses what comes out
    /// of it.
    aro,
    /// The target's own C preprocessor expands `zig/translate.h` first, and Aro
    /// parses what that produced.
    preprocessed,
};

/// Chooses the front end that reads `zig/translate.h` for this target.
///
/// ## Aro, on every target but NetBSD
///
/// `<box3d/box3d.h>` reaches `include/box3d/base.h` (`:14`) and through it
/// `config.h`, and `include/box3d/math_functions.h:11` reaches `<math.h>`. So
/// one system header is dragged in, and every C library in this matrix but one
/// spells `__END_DECLS` as plain tokens Aro reads without help.
///
/// ## The target's own preprocessor on NetBSD
///
/// NetBSD is the one bundled family whose `__END_DECLS` is not made of plain
/// tokens, so it is the one family whose translation cannot be left to Aro.
/// `generic-netbsd/sys/cdefs.h:411-416` defines
/// `__BEGIN/END_PUBLIC_DECLS` as `extern "C"` framing around
/// `_Pragma("GCC visibility push(default)")` and
/// `_Pragma("GCC visibility pop")`, `:432` routes `__END_DECLS` through it,
/// and `generic-netbsd/math.h:607` closes its declaration block with it, so
/// every NetBSD translation drags two `_Pragma` operator invocations into the
/// translation. Aro destringizes each into a `#pragma` line it then hands to
/// the parser as C, and the observed 53-platform run reported five errors at
/// `math.h:607` for that reason on all nine NetBSD targets and on no other
/// target, with the C archive itself compiled (`FORK-NOTES.md`, cross-8 box3d
/// run `20261004-164517-9067-28500`, `build-aarch64-netbsd.log:10-57`).
///
/// The condition is the OS tag rather than a list of nine triples because the
/// whole family shares that one header and that one cause: every NetBSD target
/// that reaches it fails for the same reason, and a list would silently stop
/// covering the next architecture.
fn translateRoute(target: std.Build.ResolvedTarget) TranslateRoute {
    return if (target.result.os.tag == .netbsd) .preprocessed else .aro;
}

/// `zig/translate.h`, preprocessed for the target being built.
///
/// The extra front end `translateRoute` selects for NetBSD. What this writes
/// is the translate header with every `#include` resolved, every conditional
/// settled and every macro definition kept, for the target the C core is being
/// compiled for. Nothing is stubbed, narrowed, renamed or substituted: the
/// same bytes upstream ships reach Aro either way, and only the pass that has
/// to understand NetBSD's `cdefs.h` is different.
///
/// It is `b.graph.zig_exe` running the preprocessor, so the front end is the
/// same pinned compiler that compiles the C core for this target -- not
/// whatever `zig cc` happens to be on PATH, and not a host preprocessor
/// describing a cross target's headers.
///
/// ## Why `-dD`
///
/// Without it the expansion carries no macro definitions and `pub const c`
/// loses them. `<box3d/box3d.h>` reaches `include/box3d/base.h` and
/// `include/box3d/config.h`, and Box3D's public surface carries its limits and
/// sentinels as macros -- `B3_BODY_NAME_LENGTH`, `B3_HULL_VERSION` and the rest
/// of `include/box3d/constants.h` -- so a dump of used macros only would drop
/// exactly the constants the facade re-exports. `-dD` keeps the `#define` lines
/// beside the expanded text, which is what makes this route describe the same
/// `c` module the Aro route describes.
///
/// ## Why `-MD`
///
/// The eight public headers are reached only through `#include`, and a `-I`
/// directory argument contributes nothing but its own resolved path to a run
/// step's manifest, which hashes the argument rather than the directory's
/// contents. Without a depfile this step's declared inputs would be
/// `zig/translate.h` and one path string: a later revision of
/// `include/box3d/base.h` would be served from the run cache and the
/// translation would go on describing the previous one. `-MD` with `-MF`,
/// through `addPrefixedDepFileOutputArg`, hands the discovered headers to the
/// build system as this step's own inputs.
///
/// ## What is deliberately not on this line
///
/// No `-std=` and no `BOX3D_DISABLE_SIMD`/`BOX3D_VALIDATE`. The first is
/// because the C core is compiled with `-std=gnu17` and pinning the dialect
/// here instead would decide a header's branch in a file whose job is not to
/// decide it; the second two because they are `PRIVATE` upstream and
/// `addTranslateMacros` already records why the translation must not see them.
fn preprocessedTranslateHeader(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    opts: Options,
) std.Build.LazyPath {
    // `b.graph.zig_exe` is the compiler running this build script, so the
    // preprocessor is the same pinned one the C core is compiled by.
    const run = b.addSystemCommand(&[_][]const u8{ b.graph.zig_exe, "cc", "-E", "-dD" });
    run.setName("preprocess box3d translate.h");
    if (!target.query.isNative()) {
        const triple = target.result.zigTriple(b.allocator) catch @panic("box3d: unspellable target");
        run.addArg("-target");
        run.addArg(triple);
    }
    // The same include root `addGraph` gives the translation, so
    // `<box3d/box3d.h>` resolves to this repository's file and not to whatever
    // Box3D is installed on the build machine.
    run.addPrefixedDirectoryArg("-I", b.path("include"));
    // The same two definitions `addTranslateMacros` puts on the translation
    // line, and for the same reason. They stay on the translation line too:
    // where both lines define one, they define the identical object-like
    // macro, which C allows to be repeated without a diagnostic.
    if (opts.double_precision) run.addArg("-DBOX3D_DOUBLE_PRECISION=1");
    if (opts.linkage == .dynamic) run.addArg("-DBOX3D_DLL=1");
    run.addArg("-o");
    const preprocessed = run.addOutputFileArg("box3d-translate.c");
    run.addArg("-MD");
    _ = run.addPrefixedDepFileOutputArg("-MF", "box3d-translate.d");
    run.addFileArg(b.path(translate_header));
    return preprocessed;
}

/// The platform libraries the core's own object code needs.
///
/// `libm` is upstream's `PUBLIC` dependency (`src/CMakeLists.txt:218-221`) and
/// pthreads is what `src/timer.c` reaches for on Linux. `use_pkg_config` is
/// switched off: neither is a pkg-config package, and a stray `m.pc` or
/// `pthread.pc` on the build machine must not decide this graph's include path.
fn addPlatformLibraries(mod: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    if (usesLibm(target)) mod.linkSystemLibrary("m", .{ .use_pkg_config = .no });
    if (usesPthread(target)) mod.linkSystemLibrary("pthread", .{ .use_pkg_config = .no });
}

/// Compiles the whole library.
///
/// `name` is the artifact name this graph installs or reports; see
/// `artifactName`. `linkage` has already been checked against what the target
/// can carry by `requireSupportedLinkage`.
fn addCoreLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: Options,
    linkage: std.builtin.LinkMode,
    name: []const u8,
) *std.Build.Step.Compile {
    const c_lib = b.addLibrary(.{
        .name = name,
        .linkage = linkage,
        // Upstream's `VERSION ${PROJECT_VERSION}` (`src/CMakeLists.txt:128`)
        // with `SOVERSION ${PROJECT_VERSION_MAJOR}` (`:130`): 0.1.0 and 0.
        // `version` is null for a static archive, which has no soname and no
        // versioned file name.
        .version = if (linkage == .dynamic) upstream_version else null,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            // libc, because `src/timer.c:266-297` includes `<pthread.h>` and
            // `<semaphore.h>` on Linux, `src/core.c` and every allocator route
            // through `malloc`/`free`, and `include/box3d/math_functions.h:11`
            // includes `<math.h>` on every platform.
            .link_libc = true,
            // A shared library is position-independent whether or not this
            // says so; naming it states the requirement on the one module that
            // compiles all forty-nine units.
            .pic = if (linkage == .dynamic) true else null,
        }),
    });
    const c_mod = c_lib.root_module;

    // `include/` first, because that is what `<box3d/...>` resolves through and
    // what upstream marks `PUBLIC` (`src/CMakeLists.txt:112-119`). `src/` is
    // upstream's `PRIVATE` entry in the same list, and every unit of the core
    // reaches its neighbours by bare quoted name: `body.c` includes `core.h`,
    // `mesh.c` includes `hull_map.h`, `contact_solver.c` includes
    // `math_internal.h`.
    c_mod.addIncludePath(b.path("include"));
    c_mod.addIncludePath(b.path("src"));
    // `src/timer.c:26` spells its Windows include `<Windows.h>`, and upstream's
    // CMake never noticed because MSVC and every filesystem it ran on resolve
    // that to the `windows.h` beside it. A cross build from a case-sensitive
    // host does not: the only `windows.h` on the line is MinGW-w64's, which
    // Zig ships for a `windows-gnu` target, and the capitalised spelling
    // matches nothing, so the unit that defines `b3GetTicks` and
    // `b3GetMilliseconds` is dropped from a Windows build instead of merely
    // mis-spelled. `build_support/Windows.h` is that header under the spelling
    // the unit uses, and it is one `#include <windows.h>` and nothing else.
    //
    // Late, not ordinary, and that is the part that is load-bearing. Clang
    // searches every `-idirafter` directory after all `-I` and system
    // directories, so on a case-insensitive host the include resolves to
    // MinGW's own header first and this file is never opened. An ordinary
    // `-I` here would be searched first, would match itself by a
    // case-insensitive comparison, and the `#include <windows.h>` inside it
    // would match itself again - the same failure with MinGW's header never
    // read at all. Only a case-sensitive host reaches this file, which is the
    // only place it is needed.
    if (target.result.os.tag == .windows) c_mod.addAfterIncludePath(b.path(bridge_dir));
    addPlatformLibraries(c_mod, target);
    addConfigMacros(c_mod, target, opts);
    if (linkage == .dynamic) {
        // `include/box3d/base.h:22`, `:28-30`: this is the "building the shared
        // library" half. It is what turns `BOX3D_EXPORT` into
        // `__attribute__((visibility("default")))` on ELF and macOS and into
        // `__declspec(dllexport)` on Windows. A static build defines it
        // nowhere, which is why `base.h:33` leaves `BOX3D_EXPORT` empty there.
        c_mod.addCMacro("box3d_EXPORTS", "1");
    }
    c_mod.addCSourceFiles(.{
        .root = b.path("src"),
        .files = &core_sources,
        .flags = cFlags(b, target, .core),
    });

    // The same module, the same clang invocation, the same `BOX3D_*` macros,
    // and the same `cFlags` as the forty-nine units above: the whole point of
    // the bridge is that its calls to `b3World_CastRayClosest` and its
    // neighbours are laid out by the compiler that built them. A second module
    // would be a second answer to the same ABI question, which is the risk
    // this file exists to remove.
    c_mod.addCSourceFiles(.{
        .root = b.path(bridge_dir),
        .files = &bridge_sources,
        .flags = cFlags(b, target, .core),
    });

    // Installing a header also puts it on the include search path of anything
    // that links this artifact, so a C consumer needs nothing from this tree.
    for (public_headers) |header| {
        c_lib.installHeader(b.path(header.source), header.dest);
    }

    return c_lib;
}

/// Builds the C library, the translation and the facade for one target.
///
/// `public` selects between the package module set, which is what a dependent
/// reaches through `dep.module("box3d")`, and a private module set. A
/// cross-target check needs the private form: modules are registered by name
/// against the whole build, so registering `box3d` once per matrix target would
/// leave only the last one reachable and silently stop checking the rest. The
/// translated header is imported rather than registered in both forms; the
/// published routes are named above.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: Options,
    public: bool,
) Graph {
    // Validated before anything is created, so an unsupported combination is a
    // configure-time refusal rather than an artifact quietly built as something
    // else.
    requireSupportedLinkage(target, opts.linkage);
    const c_lib = addCoreLibrary(
        b,
        target,
        optimize,
        opts,
        opts.linkage,
        artifactName(b, target, public),
    );

    const translate = b.addTranslateC(.{
        // Which front end reads the translate header is `translateRoute`'s
        // call. The two routes differ in exactly one respect: the `.aro` one
        // hands `translate-c` this repository's `zig/translate.h` to preprocess
        // for itself, and the `.preprocessed` one hands it what `zig cc -E -dD`
        // already wrote for the same target, on the same include path and with
        // the same two macro definitions.
        .root_source_file = switch (translateRoute(target)) {
            .aro => b.path(translate_header),
            .preprocessed => preprocessedTranslateHeader(b, target, opts),
        },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // `zig/translate.h` includes `<box3d/box3d.h>`, and this is the only header
    // search path the translation has. Without it the translation would bind to
    // whatever Box3D happens to be installed on the build machine, describing
    // that library's declarations rather than the ones this build compiles.
    translate.addIncludePath(b.path("include"));
    addTranslateMacros(translate, opts);

    const module = if (public)
        b.addModule(lib_name, .{
            .root_source_file = b.path(facade_root),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path(facade_root),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

    // Where the runtime-loading seam is
    // ---------------------------------
    // `runtime/graph.zig`, which the API role owns, exposes
    //
    //     pub fn createModule(
    //         b: *std.Build,
    //         translate: *std.Build.Step.TranslateC,
    //         target: std.Build.ResolvedTarget,
    //         optimize: std.builtin.OptimizeMode,
    //     ) *std.Build.Module
    //
    // and `-Druntime` substitutes that one call for `translate.createModule()`.
    // It takes the `TranslateC` step this function has already built, so the
    // generated dispatch keeps the exact translated type and constant namespace
    // rather than compiling a second copy of the native extern structs and
    // casting between two nominally distinct Zig modules: every type and
    // constant in the dispatch is re-exported from the translation it was
    // generated from, so `c.b3WorldId` in the facade and the declaration behind
    // the table are one type.
    //
    // `-Dlinkage` is orthogonal and keeps meaning what it means: it selects
    // which artifact this build *delivers* and installs, never which one the
    // module dispatches through.
    //
    // The `rt` import is for the linked branch only, and the reason is the
    // nominal type rather than the code. `graph.createCoreModule` creates the
    // one core-module instance the generated dispatch uses and re-exports
    // `LoadSource`/`LoadError` from it; a second instance created here for the
    // facade would be a *different* `LoadSource`, and `box3d.load(source)` would
    // be handing the facade's type to a function expecting the dispatch's. One
    // instance per build, no more. In a linked build there is no dispatch, so
    // the facade's own `rt` import is where those two public types come from;
    // `zig/root.zig` picks between the two with a comptime branch on
    // `runtime_loaded`, so the module a configuration does not need is never
    // resolved and never compiled.
    if (opts.runtime_loaded) {
        // A loaded provider must arrive through the platform loader, so the
        // link line names nothing at all: not this tree's archive, and not the
        // platform libraries either. Linking either would resolve symbols
        // before `load` ever runs and the runtime route would quietly be a
        // linked one. The library is still built and installed above, because
        // delivery and dispatch are separate questions -- the whole point of
        // the mode is that a caller may name a provider this tree did not build.
        module.addImport(c_import_name, graph.createModule(b, translate, target, optimize));
    } else {
        // The translated header is imported, never registered. `addModule("c")`
        // would make `dep.module("c")` resolve and hand a dependent the same
        // declarations without the library that satisfies them; `box3d.c` on
        // the facade is the supported way in and carries the facade's own
        // linkage.
        module.addImport(c_import_name, translate.createModule());
        module.addImport(rt_import_name, graph.createCoreModule(b, target, optimize));
        // The platform libraries go on the *module*, not only on the archive: a
        // `linkSystemLibrary` on a static archive stays inside that archive's
        // own link line, so a dependent linking `libbox3d.a` would otherwise
        // have to discover the undefined `sqrtf` on its own.
        addPlatformLibraries(module, target);
        module.linkLibrary(c_lib);
    }
    // The package's own `include/` on the facade's include path, so a dependent
    // that compiles its own C against this module reaches the headers the core
    // was compiled with rather than whichever ones are installed.
    module.addIncludePath(b.path("include"));

    return .{ .c_lib = c_lib, .module = module };
}

/// A Zig program or test root that imports the published facade module.
///
/// `link_libc` is stated on every one of them even though the facade carries
/// it: a dependent states its own, and this build should fail here if the
/// facade ever stopped bringing libc along.
fn facadeModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    graph_modules: Graph,
    source: []const u8,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path(source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport(lib_name, graph_modules.module);
    return mod;
}

/// The static archive upstream's own unit tests link against.
///
/// Upstream builds the tests only when the library is static
/// (`CMakeLists.txt:139-146`), because they call Box3D internals that hidden
/// visibility keeps out of the shared object. Rather than restrict `-Dlinkage`
/// to keep that true, this build always has a static compilation of the same
/// forty-nine sources with the same flags available, and reuses the delivered
/// archive when it already is one. Under the default `-Dlinkage=static` nothing
/// is compiled twice; under `-Dlinkage=dynamic` the test app links a private
/// archive that no step installs.
fn staticCoreForTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: Options,
    delivered: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    if (delivered.linkage == .static) return delivered;
    const triple = target.result.zigTriple(b.allocator) catch @panic("box3d: unspellable target");
    return addCoreLibrary(
        b,
        target,
        optimize,
        opts,
        .static,
        b.fmt("{s}-tests-{s}", .{ lib_name, triple }),
    );
}

/// Upstream's own C unit-test program, built unmodified.
///
/// The twenty-one files of `BOX3D_TEST_FILES` and the six translation units of
/// `BOX3D_SHARED_FILES` go into one executable, which is what upstream's own
/// link line is: `add_executable(test ${BOX3D_TEST_FILES})` linking
/// `box3d shared` (`test/CMakeLists.txt:28`, `:43`). Compile `shared/` into
/// the program rather than into a second archive is the same link the upstream
/// build makes, spelled one step.
fn addUpstreamTestApp(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: Options,
    static_core: *std.Build.Step.Compile,
    name: []const u8,
) *std.Build.Step.Compile {
    const test_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        // libc, because `test/main.c:7` includes `<string.h>` for `strcmp` in
        // its filter, and the core it links allocates.
        .link_libc = true,
    });
    // `test/CMakeLists.txt:36-37`: "Special access to Box3D internals for
    // testing". `shared/CMakeLists.txt:24` puts its own directory on the path
    // for the same reason. `include/` is there so `test/test_body.c:6-8`'s
    // `<box3d/...>` resolves to this repository's headers.
    test_mod.addIncludePath(b.path("include"));
    test_mod.addIncludePath(b.path("src"));
    test_mod.addIncludePath(b.path("shared"));
    // The same late include path, for the same reason and the same spelling:
    // `shared/utils.c:7` is upstream's too and asks for `<Windows.h>` under
    // `_WIN64`. See the core module for why this is `-idirafter` and not `-I`.
    if (target.result.os.tag == .windows) test_mod.addAfterIncludePath(b.path(bridge_dir));
    addPlatformLibraries(test_mod, target);
    // `test/CMakeLists.txt:39-41` compiles the test program with the same
    // `BOX3D_VALIDATE` the library got, so the two agree about what validation
    // means. It is never `BOX3D_DLL`: this program links the static archive by
    // construction, exactly as upstream's does.
    addConfigMacros(test_mod, target, opts);
    test_mod.addCSourceFiles(.{
        .root = b.path("test"),
        .files = &upstream_test_sources,
        .flags = cFlags(b, target, .tests),
    });
    test_mod.addCSourceFiles(.{
        .root = b.path("shared"),
        .files = &shared_sources,
        .flags = cFlags(b, target, .support),
    });
    test_mod.linkLibrary(static_core);

    // No `.use_llvm` here, and deliberately: this program is upstream's own C
    // unit-test program, built and run unmodified, with no Zig root and no Zig
    // code of its own. The backend choice buys a correct C-ABI call made
    // *from* Zig, and nothing here makes one. See the header note
    // "Compilation backend".
    return b.addExecutable(.{ .name = name, .root_module = test_mod });
}

/// Compiles the whole graph, the tests and upstream's own C tests for one matrix
/// target and attaches all of them to `step`.
///
/// Building the Zig test binary is what makes this a check of the facade rather
/// than of an unreferenced archive: Zig analyses a function body only when
/// something calls it, `tests.zig` calls the facade it exercises, and so
/// compiling it for a target analyses those bodies for that target. Upstream's
/// own program is built here rather than left to `upstream-test` because it is
/// the only thing in the package that reaches the internal headers, so it is
/// the only place a cross-target compile can discover that they do not port.
/// Nothing is run, so every result this step produces is compile evidence and
/// not a claim that a cross-built binary executed.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    opts: Options,
) void {
    const cross_target = b.resolveTargetQuery(query);
    const triple = cross_target.result.zigTriple(b.allocator) catch @panic("box3d: unspellable target");
    if (opts.linkage == .dynamic and !targetHasDynamicLinker(cross_target)) {
        step.dependOn(&b.addFail(b.fmt(
            "box3d: shared delivery is unsupported for {s}; no static substitution. Use -Dlinkage=static.",
            .{triple},
        )).step);
        return;
    }

    const cross = addGraph(b, cross_target, optimize, opts, false);

    step.dependOn(&b.addTest(.{
        .use_llvm = true,
        .name = b.fmt("{s}-tests-{s}", .{ lib_name, triple }),
        .root_module = facadeModule(b, cross_target, optimize, cross, test_root),
    }).step);

    step.dependOn(&b.addExecutable(.{
        .use_llvm = true,
        .name = b.fmt("{s}-smoke-{s}", .{ lib_name, triple }),
        .root_module = facadeModule(b, cross_target, optimize, cross, smoke_root),
    }).step);

    step.dependOn(&addUpstreamTestApp(
        b,
        cross_target,
        optimize,
        opts,
        staticCoreForTests(b, cross_target, optimize, opts, cross.c_lib),
        b.fmt("{s}-upstream-test-{s}", .{ lib_name, triple }),
    ).step);
}

/// Runs the `consumer/` package as its own `zig build`.
///
/// The consumer is a separate package on purpose: a manifest dependency here
/// would close a cycle, because its manifest points back at this package by
/// path. Running it as a separate build is what makes the proof real -- that a
/// package which writes only `b.dependency("box3d", ...)` and
/// `dep.module("box3d")` gets a working, correctly linked library. Its
/// `build.zig` asks for nothing else, which is the point: if the module stopped
/// carrying the library or the translation, this would stop linking.
/// It asks for the five options this graph was configured with as well, by
/// name, and states each of them rather than letting the nested build pick a
/// default. `-Ddouble-precision` in particular is the whole ABI
/// (`include/box3d/math_functions.h:70-95`): the consumer reaches `b3Pos`
/// through `dep.module("box3d")`, which carries the compile definition itself,
/// so a nested build that guessed `false` would be exercising a different
/// library from the one under test rather than a different spelling of the
/// same one. The consumer declares these options itself and forwards them to
/// `b.dependency`; it never supplies a `BOX3D_*` macro of its own, because
/// the library's configuration is the library's answer.
///
/// Runs the consumer when an enabled executor can run target; otherwise
/// installs it without execution. Foreign installation is build-only evidence.
fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: Options,
) *std.Build.Step.Run {
    // The target travels down as the caller's *query*, never as this graph's
    // resolved result. `ResolvedTarget` carries both precisely because the
    // query records which parts of the target were "native"
    // (`lib/std/Build.zig:2695-2700`), and `Target.Query.zigTriple` writes the
    // literal string `native` for a query that named nothing
    // (`lib/std/Target/Query.zig:421-422`). The resolved result instead spells a
    // concrete host: its CPU carries this machine's own feature range, and a
    // triple has no field for a dynamic linker at all. The nested build would
    // then resolve an explicitly named target against the ABI's defaults rather
    // than against this machine, and ask for a dynamic linker this host does not
    // use, and its `run` step would refuse its own artifact -- `Step.Run`
    // compares the host's dynamic linker with the target's and fails the step
    // (`lib/std/Build/Step/Run.zig:1337-1348`). The dynamic linker therefore
    // rides the native route rather than travelling as an argument, because
    // `b.dependency` forwards no `-Ddynamic-linker` for the library half either
    // (`lib/std/Build.zig:439-461`): an argument carried to the nested build
    // alone would give its consumer executable a linker the library it links
    // against never received. Same rule, same reason and same wording as
    // `utf8proc/build.zig:1386-1416`, which is where it was read out of first.
    const query = target.query;
    // `addArg` copies each argument, so these temporaries can go right after.
    const triple = query.zigTriple(b.allocator) catch @panic("box3d: unspellable target");
    defer b.allocator.free(triple);
    const cpu = query.serializeCpuAlloc(b.allocator) catch @panic("box3d: unspellable CPU");
    defer b.allocator.free(cpu);

    // `b.graph.zig_exe` is the compiler running this build script, so the
    // nested build is the same toolchain rather than whatever is on PATH.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    // The model and its feature set, because the triple cannot carry them.
    // `serializeCpu` writes `native` for a query that named no CPU and
    // `baseline` for a cross query that named none, and otherwise the model name
    // followed by its added and subtracted features
    // (`lib/std/Target/Query.zig:488-533`); `-Dcpu` is read from exactly that
    // string by the four options `standardTargetOptions` registers
    // (`lib/std/Build.zig:1473-1493`). The consumer already declares it --
    // `consumer/build.zig:54` calls `standardTargetOptions` -- and already hands
    // both halves on to the library (`lib/std/Build.zig:451-462`), so nothing in
    // `consumer/` changed. Without this a nested build given only `-Dtarget`
    // compiled the consumer against the ABI baseline while this graph compiled
    // the library against the host's features, which is the same "the consumer
    // builds the library this build built" claim the lines below are making.
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    // The native configuration, under the same names `b.option` took them.
    // `-Druntime` is the dispatch question rather than the ABI one, and it
    // decides whether the nested build links the archive or resolves it through
    // the loader, which is as much a part of what is being exercised as the
    // precision mode is.
    run.addArg(b.fmt("-Druntime={}", .{opts.runtime_loaded}));
    run.addArg(b.fmt("-Ddouble-precision={}", .{opts.double_precision}));
    // Resolved against the target this graph is building, not passed through as
    // the caller's optional: the nested build would otherwise be handed
    // "unset" and would reach its own answer from its own `-Dtarget`, and
    // "the consumer builds the library this build built" has to hold for the
    // SIMD kernel as much as for the precision mode.
    run.addArg(b.fmt("-Ddisable-simd={}", .{resolveDisableSimd(opts, target)}));
    run.addArg(b.fmt("-Dvalidate={}", .{opts.validate}));
    // `-Dlinkage` is the delivery question, and it is independent of the
    // dispatch above: it names the artifact this build delivers and installs
    // while `-Druntime` decides whether the module links that artifact at all.
    // It is written out in full because the consumer gives it no default, so a
    // nested build that was not told resolves the library's own default rather
    // than the one under test (`std/Build.zig:435`, `:569-581` record a
    // dependency argument only when it carries a value).
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(opts.linkage)}));
    // Forward the selected executor and its dynamic-linker support.
    if (b.enable_darling) run.addArg("-fdarling");
    if (b.enable_qemu) run.addArg("-fqemu");
    if (b.enable_rosetta) run.addArg("-frosetta");
    if (b.enable_wasmtime) run.addArg("-fwasmtime");
    if (b.enable_wine) run.addArg("-fwine");
    if (b.libc_runtimes_dir) |runtimes| run.addArgs(&.{ "--libc-runtimes", runtimes });
    // This workspace's job count and its step list, for one reason: nothing can
    // append a `-j` or a `--summary` to a `Run` step's command. A nested build
    // left to derive its own width takes `cpu_count - 1`
    // (`lib/std/Io/Threaded.zig:1639`), so the consumer this step proves would
    // compile at a different width from the build that asked for it, and again
    // on whichever machine runs the gate. `-j8` is what every `zig build` body in
    // this SDK's `devenv.nix` already carries (`devenv.nix:118`) and what this
    // workspace asks of every gate (`AGENTS.md:157-159`); `--summary` is two
    // tokens for the same reason the two cache flags are
    // (`lib/compiler/build_runner.zig:262-267`).
    run.addArg("-j8");
    run.addArg("--summary");
    run.addArg("all");
    // Two arguments, not one `--cache-dir=...`: the second is the form the
    // build system emits to the compiler itself, not to the build runner. Two
    // build graphs must not write the same manifest directory, so the nested one
    // gets a subdirectory rather than sharing. Unchanged in what it names and
    // unchanged in its two-token shape.
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
    }
    // The global cache is the one this build was itself given, and it is not
    // optional here. The working directory above is `consumer/`, so a global
    // cache the nested build resolved for itself would be resolved from there
    // rather than from where this build was told to put it. Every compiler
    // invocation the nested graph makes already carries the global cache its own
    // build script names -- that is the stdlib's own shape, at
    // `lib/std/Build/Step/Compile.zig:1477-1479`,
    // `lib/std/Build/Step/TranslateC.zig:178-180` and
    // `lib/std/Build/WebServer.zig:576-577` -- so forwarding it here is what
    // makes those invocations and this one agree instead of splitting one build
    // across two global caches. Two arguments again, for the same reason:
    // `--global-cache-dir [path]` is the documented two-token form
    // (`lib/compiler/build_runner.zig:1675`), and the `=`-joined spelling arrives
    // as a `-` argument the runner does not enumerate (`:160`) and is fatal
    // there (`:432-433`).
    //
    // The field is `Graph.global_cache_root` and not `Build.cache_root`
    // (`lib/std/Build.zig:112-122` against `:57-58`): the first is the package
    // cache the compiler shares, and the second is this build graph's own
    // manifest directory, which is the one already given its own `/consumer`
    // subdirectory above. The path is guarded rather than defaulted because the
    // build runner builds that `Directory` with `.path` set unconditionally
    // (`lib/compiler/build_runner.zig:73-76`), so no run takes the guard, and a
    // null must not be answered by naming a directory nobody chose.
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArg("--global-cache-dir");
        run.addArg(global_cache);
    }
    // The install prefix is the caller's own, and only when it named one. The
    // default is this build's `<build root>/zig-out`, which equals what the
    // nested build would resolve for itself under `consumer/`, so forwarding
    // it would name nothing the caller chose. A prefix that is not the
    // default is forwarded, and made absolute first: a relative `--prefix`
    // resolves against the nested working directory, which is `consumer/`
    // rather than this build's root. `DESTDIR` needs no forwarding, because
    // the nested build inherits the environment this one ran with.
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    // The caller's own arguments, last and behind `--`. Everything above is
    // ahead of it on purpose: `--` is where the build runner stops parsing
    // options and starts recording `b.args` (`lib/compiler/build_runner.zig:428-430`),
    // so a caller's own argument reaches the consumer program itself and is not
    // read as an option of the nested build graph.
    if (b.args) |args| {
        run.addArg("--");
        run.addArgs(args);
    }
    run.has_side_effects = true;
    return run;
}

/// Matches Step.Run executor selection for the libc-linked consumer. Foreign
/// glibc execution also requires libc runtimes.
fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const host = &b.graph.host.result;
    const candidate = &target.result;
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .allow_darling = b.enable_darling,
        .allow_qemu = b.enable_qemu,
        .allow_wasmtime = b.enable_wasmtime,
        .allow_wine = b.enable_wine,
        .qemu_fixes_dl = candidate.isGnuLibC() and b.libc_runtimes_dir != null,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(b.graph.io, host, candidate, options)) {
        .native, .rosetta => true,
        .qemu => !candidate.isGnuLibC() or b.libc_runtimes_dir != null,
        .wine, .wasmtime, .darling => true,
        .bad_dl, .bad_os_or_cpu => false,
    };
}

/// Writes `lib/pkgconfig/box3d.pc` and installs it.
///
/// Upstream ships no pkg-config template -- there is no `.pc` and no `.pc.in`
/// anywhere in the tree, and `src/CMakeLists.txt:223-240` installs only the
/// library, a CMake target export and the headers -- so this file is
/// fork-authored and says so in its first two lines. Two of its fields differ
/// from what a CMake-configured file would carry, both deliberately:
///
///   * `prefix` is `${pcfiledir}/../..`. This graph does not know where
///     `--prefix` will point when it writes the file. pkg-config resolves
///     `${pcfiledir}` against the `.pc` file it found, so the installed file is
///     correct wherever the prefix landed, including a Nix store path only known
///     at build time.
///   * `Version` is formatted from `upstream_version`, which `build` has
///     already checked against `build.zig.zon .version`. It is the same number
///     the shared object's file name carries, so the manifest, this file and the
///     library cannot name three different releases.
///
/// `Libs` is `-lbox3d` in both linkages, because the library *name* does not
/// change with linkage: a consumer asks for `-lbox3d` and the linker resolves it
/// to `libbox3d.a` or, through the `libbox3d.so` symlink, to the shared object.
///
/// `Libs.private` carries the two things a static consumer needs that a shared
/// one does not: `-lm`, which upstream attaches `PUBLIC`
/// (`src/CMakeLists.txt:218-221`) and whose reason is the `sqrtf` calls the core
/// really makes, and `-pthread`, which the Linux build of `src/timer.c`
/// really uses. `Libs.private` is only consulted when the consumer statically
/// links, which is exactly when both are needed.
///
/// `Cflags` carries the two definitions a consumer has to see for the
/// declarations to match the compiled library, and nothing else. They are the
/// `PUBLIC` and `INTERFACE` halves of upstream's own compile definitions:
///
///   * `-DBOX3D_DOUBLE_PRECISION` when `-Ddouble-precision` was given, because
///     upstream marks that one `PUBLIC` (`src/CMakeLists.txt:164-168`) and it
///     changes the width of `b3Pos` and renames `b3CreateWorld`
///     (`include/box3d/box3d.h:25-30`). A consumer without it is compiling
///     against a different ABI, whatever it then calls.
///   * `-DBOX3D_DLL` for a shared build, upstream's `INTERFACE` definition for a
///     Windows shared library (`src/CMakeLists.txt:172-175`), which is what
///     makes a consumer's declarations `__declspec(dllimport)` without
///     repeating the flag.
///
/// `BOX3D_DISABLE_SIMD` and `BOX3D_VALIDATE` are upstream's `PRIVATE`
/// definitions (`src/CMakeLists.txt:154-162`) and are deliberately absent: they
/// select code paths inside the library and change no declaration, so a
/// consumer that defined them would be describing an interface that is not the
/// one installed.
///
/// `opts.linkage` is the linkage that was asked for, already checked by
/// `requireSupportedLinkage`, so the file describes the artifact that is beside
/// it and nothing else.
fn addPkgConfig(b: *std.Build, opts: Options) void {
    const files = b.addWriteFiles();
    const install_pc = b.addInstallFileWithDir(
        files.add("box3d.pc", b.fmt(
            \\# Generated by this package's build.zig. Upstream ships no
            \\# pkg-config template, so this file is fork-authored; it uses the
            \\# same field names and order a CMake-configured box3d.pc would,
            \\# with prefix expressed relatively so the installed file is correct
            \\# wherever --prefix put it.
            \\prefix=${{pcfiledir}}/../..
            \\exec_prefix=${{prefix}}
            \\libdir=${{prefix}}/lib
            \\includedir=${{prefix}}/include
            \\
            \\Name: box3d
            \\Description: A 3D physics engine for games
            \\Version: {f}
            \\
            \\Requires:
            \\Libs: -L"${{libdir}}" -lbox3d
            \\Libs.private: -lm -pthread
            \\Cflags: -I"${{includedir}}"{s}{s}
            \\
        , .{
            upstream_version,
            // Both are `PUBLIC`/`INTERFACE` facts about the compiled library,
            // in that order: precision first, because it is upstream's `PUBLIC`
            // one and it decides the width of `b3Pos`, then the DLL import
            // decoration for a shared build. A static build omits the second,
            // which is how `include/box3d/base.h:33` leaves `BOX3D_EXPORT`
            // empty.
            if (opts.double_precision) " -DBOX3D_DOUBLE_PRECISION" else "",
            if (opts.linkage == .dynamic) " -DBOX3D_DLL" else "",
        })),
        .lib,
        "pkgconfig/box3d.pc",
    );
    // `addInstallFileWithDir` creates the step and attaches it to nothing.
    // Without this line the file is described by the build graph and never
    // reaches `--prefix`, and `zig build` still exits zero: a missing
    // `box3d.pc` is invisible to every other check in this repository.
    b.getInstallStep().dependOn(&install_pc.step);
}

/// Installs the carried licence texts and provenance records under
/// `share/licenses/box3d/`.
///
/// A private repository removes no licence obligation. Upstream's `LICENSE` is
/// its MIT grant and `README.upstream.md` is its `README.md`, both preserved
/// byte for byte; `NOTICE.md`, `UPSTREAM.md` and `FORK-LICENSE.md` are this
/// fork's own records, which say what changed, what the pin is and under what
/// grant the fork-authored files were contributed.
///
/// `share/licenses/<name>` is the location `package.nix` uses too, which is
/// what lets the packaging layer's own install be an idempotent overwrite of
/// these bytes rather than a second copy.
fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |record| {
        const install_record = b.addInstallFileWithDir(
            b.path(record),
            .prefix,
            b.fmt("share/licenses/{s}/{s}", .{ lib_name, record }),
        );
        // Same reason as the `.pc` file: `addInstallFileWithDir` attaches its
        // step to nothing, and a licence file that never reaches `--prefix` is
        // an obligation quietly unmet while every other step still succeeds.
        b.getInstallStep().dependOn(&install_record.step);
    }
}

/// Whether the OS can load a shared library. Windows uses its PE/COFF loader
/// without an interpreter path. Other targets need a dynamic linker.
/// WASI has neither and a shared request is refused.
fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// Refuses a linkage this target cannot carry, and says which one it cannot.
///
/// There is no substitution. A caller who asks for `-Dlinkage=dynamic` on a
/// target whose OS has no dynamic linker is asking for something that platform
/// cannot provide, and handing back a static archive instead would answer a
/// different question than the one that was asked: the artifact's name, its
/// file name, the `-DBOX3D_DLL` in `box3d.pc` and the loader a caller would
/// then point at would all disagree with what came back. So the build stops,
/// names the platform fact it resolved from `std.Target.DynamicLinker.kind`,
/// and names the spelling that does work there.
///
/// The refusal is a configure-time one and it happens before any step is
/// created, so nothing is half-built and nothing is reported as a result.
/// `-Dlinkage=static` -- the default -- remains a full configuration for every
/// target in the matrix, WASI included; this is about the shared variant of a
/// target that cannot host one, not about the target being unsupported.
///
/// `addGraph` calls this for the target it is building and `build` calls it for
/// the selected target, so every target the graph walks -- including each of
/// the six in `check` -- is checked rather than the host alone.
fn requireSupportedLinkage(
    target: std.Build.ResolvedTarget,
    requested: std.builtin.LinkMode,
) void {
    if (requested == .dynamic and !targetHasDynamicLinker(target)) {
        std.debug.panic(
            "box3d: -Dlinkage=dynamic is not supported for {s}: " ++
                "std.Target.DynamicLinker.kind is {s} for that OS, so there is " ++
                "no dynamic linker to load a shared object. This package does " ++
                "not substitute a static archive for the one that was asked " ++
                "for. Build this target with -Dlinkage=static, which is the " ++
                "default and is a configuration in its own right.",
            .{
                @tagName(target.result.os.tag),
                @tagName(std.Target.DynamicLinker.kind(target.result.os.tag)),
            },
        );
    }
}

/// Whether the caller named a target on the command line.
///
/// `standardTargetOptions` cannot answer this: it folds `-Dtarget=X` and "no
/// -Dtarget at all" into the same resolved value, so comparing the query against
/// the host would report a host-native cross target as "not selected" and check
/// all six when the caller asked for one. The raw option table can, because
/// `standardTargetOptions` registers the option under exactly this name and
/// every `-Dname=value` the user passed is a key in it.
fn targetWasNamed(b: *const std.Build) bool {
    return b.user_input_options.contains("target");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // `build.zig.zon .version` and the version this build stamps into
    // `box3d.pc`, names into the shared object's file name and cites in the
    // documentation are one fact. The comparison catches a manifest edited
    // without the source it describes.
    const package_version = std.SemanticVersion.parse(manifest.version) catch {
        @panic("build.zig.zon: .version is not a semantic version");
    };
    if (package_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the pinned upstream release " ++
            "in CMakeLists.txt:4-8; see UPSTREAM.md");
    }

    const opts: Options = .{
        .linkage = b.option(
            std.builtin.LinkMode,
            "linkage",
            "Deliver the native library as a static archive (the default) or " ++
                "as a real shared object with upstream's own file name and " ++
                "soname. This selects the delivery and never the dispatch: the " ++
                "same forty-nine sources, the same language level, the same " ++
                "macros and the same include paths are compiled either way. " ++
                "dynamic is refused on a target whose OS has no dynamic linker " ++
                "-- wasm32-wasi, for one -- rather than answered with a static " ++
                "archive; static, the default, is a full configuration for every " ++
                "target.",
        ) orelse .static,
        .runtime_loaded = b.option(
            bool,
            "runtime",
            "Resolve the native entry points at run time instead of linking " ++
                "them. The facade keeps the same translated header and the same " ++
                "public types; each selected native function becomes a dispatch " ++
                "through one process-lifetime table that an explicit " ++
                "load(source) fills, and the module links no library at all. " ++
                "Independent of -Dlinkage, which still decides which artifact " ++
                "this build delivers and installs. Default off, and a linked " ++
                "build is unchanged in every respect.",
        ) orelse false,
        .double_precision = b.option(
            bool,
            "double-precision",
            "Define BOX3D_DOUBLE_PRECISION, which stores world positions in " ++
                "double. Upstream's own default is off (CMakeLists.txt:91) and " ++
                "it is the only compile definition upstream marks PUBLIC " ++
                "because it changes the width of fields a consumer also sees.",
        ) orelse false,
        // No `orelse`: `null` is what "nobody named an answer" means, and
        // `resolveDisableSimd` answers it per resolved target. `orelse false`
        // here would be upstream's default applied to every graph in the run,
        // including the six `check` graphs, none of which is the host.
        .disable_simd = b.option(
            bool,
            "disable-simd",
            "Define BOX3D_DISABLE_SIMD and compile the scalar fallback " ++
                "instead of SSE2/NEON. Upstream's own default is off " ++
                "(CMakeLists.txt:89), and this build keeps it everywhere except " ++
                "on a 32-bit ARM target, where the NEON arm of src/core.h:59-61 " ++
                "calls the AArch64-only intrinsics vdivq_f32 and vsqrtq_f32 " ++
                "(src/contact_solver.c:872, :877) and cannot compile at all. " ++
                "Name it explicitly to override that either way.",
        ),
        .validate = b.option(
            bool,
            "validate",
            "Define BOX3D_VALIDATE, which turns on Box3D's internal checks. " ++
                "Upstream's own default is on (CMakeLists.txt:118), and this " ++
                "option's default is on too, so it is passed as " ++
                "-Dvalidate=false to turn it off. Note that base.h:70-74 also " ++
                "requires NDEBUG to be absent, so the checks are live in Debug " ++
                "and ReleaseSafe and compiled out in ReleaseFast and " ++
                "ReleaseSmall whatever this option says.",
        ) orelse true,
    };

    // Checked once here, before a single step exists, so an unsupported
    // combination is a configure-time refusal rather than an artifact quietly
    // built as something else. `addGraph` checks again for the target it is
    // building, which is what covers each of the six in `check`.
    requireSupportedLinkage(target, opts.linkage);

    const published = addGraph(b, target, optimize, opts, true);
    b.installArtifact(published.c_lib);
    addPkgConfig(b, opts);
    installLicenceRecords(b);

    // `zig build` also compiles the smoke program. It is the cheapest proof that
    // the facade, the translated header and the library agree on types, symbols
    // and link-time dependencies. It is compiled, not installed: it is a proof,
    // not a deliverable.
    const smoke = b.addExecutable(.{
        .use_llvm = true,
        .name = "box3d-smoke",
        .root_module = facadeModule(b, target, optimize, published, smoke_root),
    });
    b.getInstallStep().dependOn(&smoke.step);

    // A run artifact already depends on building the executable, which depends
    // on compiling the core and linking the facade. `zig build smoke`
    // deliberately does not depend on the install step: installing is `zig
    // build`'s job, and conflating the two would make a smoke run depend on
    // the install layout.
    const run_smoke = b.addRunArtifact(smoke);
    // The smoke program reads no fixture and prints known answers, so it is
    // cheap to re-run; `has_side_effects` is what stops a second `zig build
    // smoke` being served from the run cache and reporting success without the
    // program ever running.
    run_smoke.has_side_effects = true;
    if (b.args) |args| run_smoke.addArgs(args);
    b.step("smoke", "Run the smoke program").dependOn(&run_smoke.step);

    // The test root is `tests.zig`, the file that names the test blocks; a root
    // that only re-exported them would discover no tests and still exit zero.
    // `addRunArtifact` rather than a plain compile, so this is a real runnable
    // test step for whatever `-Dtarget` names: a foreign target is left to
    // whichever executor the cross-test harness detects, and this build does
    // not decide that.
    const unit_tests = b.addTest(.{
        .use_llvm = true,
        .name = "box3d-tests",
        .root_module = facadeModule(b, target, optimize, published, test_root),
    });
    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.has_side_effects = true;
    b.step("test", "Run the behavioural tests for the selected target")
        .dependOn(&run_tests.step);

    // Upstream's own C unit-test program, built and run unmodified. Its exit
    // status is upstream's own report: `test/main.c` runs every suite through
    // `RUN_TEST` and reports the failures itself, so a non-zero exit needs no
    // wrapper here to interpret it.
    //
    // It links the static archive rather than the delivered one, because it
    // calls Box3D internals; see `staticCoreForTests`.
    const upstream_app = addUpstreamTestApp(
        b,
        target,
        optimize,
        opts,
        staticCoreForTests(b, target, optimize, opts, published.c_lib),
        "box3d-upstream-test",
    );
    const run_upstream = b.addRunArtifact(upstream_app);
    run_upstream.has_side_effects = true;
    if (b.args) |args| run_upstream.addArgs(args);
    b.step(
        "upstream-test",
        "Build and run upstream's own C unit tests against the compiled core",
    ).dependOn(&run_upstream.step);

    // Compile every called facade body and each proof root without execution.
    const check_step = b.step(
        "check",
        "Compile the C core, the translated interface, the facade, the tests, " ++
            "the smoke program and upstream's own C unit tests for the " ++
            "six-target matrix without running any of them",
    );
    if (targetWasNamed(b)) {
        addTargetCheck(b, check_step, target.query, optimize, opts);
    } else {
        for (check_targets) |query| addTargetCheck(b, check_step, query, optimize, opts);
    }

    // The consumer package is not part of the matrix: it is its own `zig
    // build`, run from inside `consumer/`. This step is that same proof driven
    // from here, so a consumer can be built or run for a target chosen on the
    // command line without changing directory.
    b.step(
        "consumer",
        "Build the independent dep.module(\"box3d\") consumer, and run it when this host can execute it",
    ).dependOn(&runConsumer(b, target, optimize, opts).step);

    // Which sources this configuration compiles and which artifact it hands
    // back are facts worth reading out of the build rather than inferring from
    // a cache directory. These are configure-time lines, not gate results:
    // nothing has been compiled when they print.
    // The SIMD line is the *resolved* answer for the selected target, not the
    // option as it was typed: `disable-simd` has no default of its own, so a
    // bare `disable-simd=false` in this line would be a different fact from
    // what the compile is about to use, and on a 32-bit ARM target it would be
    // the wrong one.
    const disable_simd = resolveDisableSimd(opts, target);
    std.debug.print(
        "box3d: {d} C units from src/, {d} public headers, C17 with extensions, " ++
            "-ffp-contract=off, double-precision={}, disable-simd={}, validate={}\n",
        .{
            core_sources.len,
            public_headers.len,
            opts.double_precision,
            disable_simd,
            opts.validate,
        },
    );
    // Say *why* when the answer was not the caller's, because the two are
    // indistinguishable in the line above and only one of them is a
    // configuration choice somebody can repeat.
    if (opts.disable_simd == null and disable_simd) {
        std.debug.print(
            "box3d: BOX3D_DISABLE_SIMD defaulted on for this target: it is " ++
                "32-bit ARM, and src/contact_solver.c:872, :877 call vdivq_f32 " ++
                "and vsqrtq_f32, which lib/include/arm_neon.h:44308 declares " ++
                "only for __aarch64__ and __arm64ec__. -Ddisable-simd=false " ++
                "overrides this and will not compile.\n",
            .{},
        );
    }
    const delivery: []const u8 = switch (opts.linkage) {
        .static => "static archive libbox3d.a (default)",
        .dynamic => b.fmt(
            "shared object, soname libbox3d.so.{d} for version {f}",
            .{ upstream_version.major, upstream_version },
        ),
    };
    std.debug.print("box3d: {s}\n", .{delivery});
    if (opts.runtime_loaded) {
        // Dispatch is a separate fact from delivery, and a runtime-loaded
        // build links nothing into the module: the caller names a provider with
        // an explicit `load(source)` and the symbols arrive through the
        // platform loader. Printing it here is what keeps "the library is still
        // built and installed" from reading as "the module links it".
        std.debug.print(
            "box3d: runtime-loaded dispatch (-Druntime=true); no library is " ++
                "linked into the module, and a provider is named by an explicit " ++
                "load(source)\n",
            .{},
        );
    }
}
