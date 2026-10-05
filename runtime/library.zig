// SPDX-License-Identifier: MIT
//
//! Box3D's side of the runtime loader: the names its synchronization binding
//! has, and what it requires of a provider beyond resolving its symbols.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them
//! Box3D's, and it is the file another SDK replaces.
//!
//! ## What a provider must be
//!
//! Every `extern` the selected headers declare, and nothing else. The public
//! surface is `box3d/box3d.h`, which includes `base.h`, `collision.h`,
//! `id.h`, `math_functions.h` and `types.h`, and those declare the whole of it:
//! the world, body, shape, joint and contact entry points of
//! `box3d/box3d.h`, the geometry builders of `box3d/collision.h`, the base
//! services of `box3d/base.h` and `box3d/constants.h`, and the trigonometry of
//! `box3d/math_functions.h`. The C library's `<math.h>`, which the headers reach
//! through `box3d/math_functions.h:10-11`, is not part of that set and is not
//! resolved from the provider; `runtime/graph.zig` says which names those are.
//!
//! ## The ABI boundary, stated honestly
//!
//! The check below is a version and a precision mode, and it is worth being
//! exact about what it does and does not establish, because Box3D's ABI is not
//! carried by a version string alone.
//!
//! What a provider must match, and why each one matters:
//!
//!   * **Precision mode.** `include/box3d/math_functions.h:70-95` makes `b3Pos`
//!     and `b3Vec3` the same type, and `b3WorldTransform` and `b3Transform` the
//!     same type, unless `BOX3D_DOUBLE_PRECISION` is defined, in which case
//!     both become distinct double-translation structs. Every position in the
//!     API is a `b3Pos`, so the two modes disagree about the width and the
//!     alignment of a large share of the argument lists. Upstream forces the
//!     mismatch to be visible at link time by renaming `b3CreateWorld` to
//!     `b3CreateWorldDoublePrecision` in that mode
//!     (`include/box3d/box3d.h:25-30`), which is a trap for the one call every
//!     program makes. Upstream marks the option `PUBLIC`
//!     (`src/CMakeLists.txt:164-168`) precisely because a consumer must see the
//!     same mode in the headers or it cannot match the ABI, and this build
//!     follows that: `-Ddouble-precision=true` defines it on the translation
//!     line as well as on the core. The mode is therefore *not* fixed at
//!     compile time in this file. `validate` reads it out of the translated
//!     types instead, because those are the headers this build actually
//!     selected.
//!   * **Structure return convention.** `b3MakeBoxHull`, `b3MakeCubeHull`,
//!     `b3MakeOffsetBoxHull`, `b3MakeTransformedBoxHull` and `b3MakeScaledBoxHull`
//!     return a `b3BoxHull` by value (`include/box3d/types.h:2022-2032`), and
//!     that struct carries its vertex, point, half-edge, face and plane arrays
//!     inline. Passing and returning it is the platform's structure-return
//!     convention, not an ordinary register return, so the provider must be
//!     compiled by a toolchain for the same ABI as this dispatch. The same holds
//!     for the small by-value returns - `b3Vec3`, `b3Quat`, `b3AABB`, `b3Version`
//!     and the result structs of the queries - which are returned in registers
//!     or in memory according to the same ABI.
//!   * **Scalar widths.** `int32_t`, `uint16_t`, `uint64_t` and `float` are the
//!     same widths on every ABI this package targets, but they are only the same
//!     widths because the header says so; nothing here widens or narrows them.
//!   * **Allocator.** Box3D allocates every world, body, shape and joint from
//!     one process-global allocator pair, replaceable with `b3SetAllocator`
//!     (`include/box3d/base.h:88-102`, `src/core.c:130-139`). The two callbacks
//!     take no context, so a provider handed its own allocator pair and a
//!     dispatch built for the default pair are still interchangeable: there is
//!     nothing in the table that captures an allocator.
//!   * **Callback lifetime.** The world stores the pointers it is given -
//!     task enqueue/finish, friction and restitution mixing, custom filtering,
//!     pre-solve, debug shape creation and destruction - and calls them later,
//!     some of them from worker threads during `b3World_Step`. Those pointers
//!     are provider state, not table state: they must stay valid for as long as
//!     the world that holds them, and the dispatch cannot check it. The facade
//!     documents the rule where a caller meets it.
//!   * **This package's own exports.** The required symbol set is the translated
//!     header plus the ten `box3dAbi_*` entry points in
//!     `build_support/box3d_abi_bridge.h`, because `zig/translate.h` includes
//!     that header and `runtime/generate.zig` routes every `extern` the
//!     translation produced. They are required, not optional: the facade calls
//!     them for the ten signatures Zig's x86_64 argument lowering places in the
//!     wrong vector registers (see `build_support/box3d_abi_bridge.h` for the
//!     measurement), so a provider without them is not this package's library
//!     and `load` refuses it rather than falling back. A provider built from
//!     another toolchain still supplies them, because they are ordinary
//!     `B3_API` definitions compiled beside the core.
//!
//! The ten are the tail of the required list, and a provider that predates
//! `build_support/box3d_abi_bridge.c` exports none of them: it is this
//! package's own library with one source unit missing, not a different ABI.
//! `load` names the first one it cannot resolve
//! (`runtime/loader.zig:480-494`), so that case arrives as a sentence rather
//! than as a count (SOURCE-CONFIRMED, 2026-10-04, Debug, `x86_64-linux-gnu`:
//! the Debug translation demands 588 names, and a Debug provider built before
//! that unit exports 578 of them — every `b3*` one, and none of the
//! `box3dAbi_*` ten).
//!
//! What this file does not do is claim that a provider answering these two
//! questions is interchangeable with this build. Resolving the symbols,
//! answering the version and answering the precision mode are the boundary;
//! agreement on a version word and on one compile-time option is evidence, not
//! proof, and this file does not pretend otherwise. A provider that passes both
//! checks and still differs will fail later, loudly, in Box3D's own code.
//!
//! ## Configuration boundaries of this package
//!
//! Two settings have to agree between the translation step and the compiled
//! object, because each one changes the declared surface:
//!
//!   * `NDEBUG`. `b3InternalAssert` is declared under
//!     `!defined( NDEBUG ) || defined( B3_ENABLE_ASSERT )`
//!     (`include/box3d/base.h:123-131`) and defined under the same guard
//!     (`src/core.c:81-90`). One `-Doptimize` driving both steps keeps them in
//!     step; a mismatch makes the table demand a symbol the provider does not
//!     export, and `load` returns `error.MissingSymbol`
//!     (`runtime/loader.zig:480-494`) after printing the name it could not find.
//!   * `BOX3D_DOUBLE_PRECISION`, which `-Ddouble-precision=true` defines on the
//!     translation line as well as on the core. A build that defines it and a
//!     provider that does not are two different ABIs, not a broken provider,
//!     and `validate` refuses the candidate.
//!
//! Neither setting reaches the C library. The `<math.h>` names the translation
//! declares are classified by `runtime/graph.zig` for every configuration of
//! this package, and they are not a build-flag question: `bits/mathcalls.h` is
//! gated on `__GLIBC_USE (IEC_60559_TYPES_EXT)`, but the classification-helper
//! family is declared by `bits/mathcalls-helper-functions.h`, which the
//! `_FloatN` and `_FloatNx` passes of `generic-glibc/math.h:561-678` include
//! outside that gate. `_GNU_SOURCE` turns `__USE_GNU` on
//! (`generic-glibc/bits/libc-header-start.h:105-110`) and so widens the
//! surface, and no line of this package's translation step defines it - but a
//! build that did would still need no change to this file or to
//! `runtime/graph.zig`.
//!
//!   * The delivered linkage. `-Dlinkage=dynamic` delivers a shared object only
//!     where the target has a dynamic linker; on a target whose
//!     `std.Target.DynamicLinker.kind` is `.none`, such as `wasm32-wasi`, the
//!     build delivers a static archive instead. A runtime-loaded build on such
//!     a target has no provider to open, so `load` can only be given a file the
//!     platform itself can load. That is a boundary of the delivered
//!     configuration, not something this dispatch can paper over.

const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.h` compiled with
/// `RT_SYNC_PREFIX=box3d_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols, and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn box3d_rt_lock() void;
    extern fn box3d_rt_unlock() void;
    extern fn box3d_rt_wait() void;
    extern fn box3d_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
    extern fn box3d_rt_thread_self() u64;

    pub fn lock() void {
        box3d_rt_lock();
    }
    pub fn unlock() void {
        box3d_rt_unlock();
    }
    pub fn wait() void {
        box3d_rt_wait();
    }
    pub fn broadcast() void {
        box3d_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return box3d_rt_thread_self();
    }
};

/// The ABI this SDK's headers describe, and the one `validate` asks for.
///
/// `src/core.c:116-119` returns `{ 0, 1, 0 }`, so 0.1.0 is what a provider
/// built from these sources reports. It is a statement about the provider's
/// source revision, and the facade prints it rather than asserting about it; a
/// provider that reports something else is refused rather than used and
/// wondered at.
pub const abi_version: struct { major: c_int, minor: c_int, revision: c_int } = .{
    .major = 0,
    .minor = 1,
    .revision = 0,
};

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "box3d";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated header, not from this file.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// This project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// The library-specific checks, run after every symbol resolved and
        /// before anything is published.
        pub fn validate(dst: *const table) ?[]const u8 {
            const version = dst.b3GetVersion();
            if (version.major != abi_version.major or
                version.minor != abi_version.minor or
                version.revision != abi_version.revision)
            {
                return "b3GetVersion() reported a revision other than 0.1.0, so this " ++
                    "provider is not the library this header describes";
            }

            // The precision mode the headers this build translated were
            // configured for, read out of the translated types rather than out
            // of a build option: `b3Pos` is `b3Vec3` itself in single precision
            // and a separate double-translation struct in large world mode
            // (include/box3d/math_functions.h:70-95). `dispatch` re-exports
            // both, so this is the header's own answer and not a restatement of
            // a `-D` flag.
            //
            // The two types are compared as type values. `@TypeOf` of either
            // name is `type` — both are type-valued declarations — so a
            // `@TypeOf` comparison is `type == type`, true for every pair, and
            // it answered "single precision" for a double translation until a
            // `-Ddouble-precision=true` gate refused a correctly-built
            // provider with `ValidationFailed`
            // (`baselines-and-configs/20261004T200055Z-092d7677`).
            const translated_single_precision =
                dispatch.b3Pos == dispatch.b3Vec3 and
                dispatch.b3WorldTransform == dispatch.b3Transform;
            const provider_is_double = dst.b3IsDoublePrecision();
            const headers_are_double = !translated_single_precision;
            if (provider_is_double != headers_are_double) {
                return "b3IsDoublePrecision() disagrees with the precision mode these " ++
                    "headers were translated for; the two sides were built with " ++
                    "different BOX3D_DOUBLE_PRECISION settings, so every position in " ++
                    "the API has a different width";
            }
            return null;
        }
    };
}