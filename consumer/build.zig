//! A package that consumes `box3d` from outside.
//!
//! This exists to prove one thing: that a dependent needs only
//! `dep.module("box3d")` and gets a working, correctly linked library. If the
//! facade module stopped carrying the compiled library, or the translated
//! header stopped matching the compiled `src/*.c`, or the platform libraries
//! `sqrtf` and `pthread_create` need stopped being named on the module rather
//! than only inside the archive's own link line, this would stop building or
//! stop producing the results below, and nothing inside the library itself
//! would notice.
//!
//! Run it with `zig build run`. It exits non-zero if any result disagrees with
//! the independent expectation it states, so it is a check and not a demo.
//!
//! It deliberately asks for nothing but the module. There is no
//! `dep.artifact("box3d")` here, no `-I` for `<box3d/...>`, no `-lbox3d`, no
//! `-lm` and no `-pthread`: a dependent that had to supply any of those would
//! prove nothing about the module being self-contained, and adding them here
//! would hide a library that forgot to declare them.
//!
//! The library's own native configuration is different in kind, and is
//! forwarded rather than supplied. `BOX3D_DOUBLE_PRECISION` is upstream's only
//! `PUBLIC` compile definition (`src/CMakeLists.txt:164-168`) and it changes the
//! width of `b3Pos`, so a dependent that wants it configures the dependency
//! rather than passing the macro to its own program. That is what the options
//! below are for; none of them is a definition this package hands to the
//! compiler.
//!
//! `-Dlinkage` is forwarded on the same terms, and it is not an ABI choice at
//! all: it names which artifact the library builds and installs --
//! `libbox3d.a`, its default, or the shared object with upstream's own soname
//! -- and never which one the module dispatches through. `-Druntime` is the
//! dispatch question, and the two are independent: `zig build run
//! -Dlinkage=dynamic -Druntime=true` builds and installs the shared object and
//! links none of it into this program, which still names its provider with an
//! explicit `load`. Naming none of them leaves the library's own defaults
//! alone: this package states no default for any option it forwards.
//!
//! Two things this program states rather than inherits, because neither can be
//! inherited:
//!
//!   * `.use_llvm = true` on the executable root. The backend is a property of
//!     the root, which is this file's, so a published module cannot set it; see
//!     the note above `b.addExecutable` below.
//!   * No default for any forwarded option. `-Ddisable-simd` is the one whose
//!     default this build derives rather than hard-codes -- the library decides
//!     it per resolved target -- so naming it here would answer a question that
//!     belongs to the library, and not naming it is what lets the two builds
//!     agree.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Each field below is the dependency's own option name, verbatim. Zig
    // registers a dependency argument under its *struct field name*
    // (`std/Build.zig:421-426`, `:440`), so a field spelled `double_precision`
    // would hand the library an option called `double_precision`, which it never
    // asks for (`box3d/build.zig:1444-1446`) and which is then reported as an
    // unused flag (`std/Build.zig:1644-1651`). A quoted field carries the hyphen
    // through, so `-Ddouble-precision`, `-Ddisable-simd` and the nested
    // consumer step (`box3d/build.zig:1194-1195`) all name one option.

    // Forwarded, and unnamed stays unnamed, for the same reason the field
    // spellings above matter: this package must not answer a question that
    // belongs to the library. `std.Build` records a dependency argument only
    // when it carries a value -- the enum arm is guarded by `if (maybe_value)
    // |v|` (`std/Build.zig:510-516`), the bool arm the same way (`:503-509`),
    // and an optional is unwrapped into that value before either
    // (`:569-580`) -- so a `null` here is not forwarded at all and the library
    // resolves its own policy for all five. Nothing is recorded for an option
    // nobody named, so there is nothing for `validateUserInputDidItFail`
    // (`:1644-1651`) to report as unused either. That is also where the
    // refusal lives: `requireSupportedLinkage` in `box3d/build.zig` rejects a
    // shared object on a target whose OS has no dynamic linker, and naming a
    // default here would let this package answer that instead, with an
    // archive the caller did not ask for.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Forwarded to the box3d dependency: which artifact its build delivers " ++
            "and installs, the default static archive or a real shared object " ++
            "with upstream's soname. It selects the delivery and never the " ++
            "dispatch, so it is independent of `-Druntime`, which decides " ++
            "whether the module links that artifact at all. Left unset, the " ++
            "library's own default applies.",
    );

    const dep = b.dependency("box3d", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = b.option(bool, "runtime", "Load the native library at run time instead of linking it"),
        .@"double-precision" = b.option(bool, "double-precision", "Store world positions in double, as upstream's only PUBLIC definition requires"),
        .@"disable-simd" = b.option(bool, "disable-simd", "Build without the SIMD kernels upstream's option selects"),
        .validate = b.option(bool, "validate", "Compile upstream's validation checks in"),
    });

    // No `link_libc` here on purpose. The C requirement belongs to the library
    // module, which carries it: Box3D's core allocates through `malloc` and
    // frees through `free`, includes `<math.h>` and, on Linux, `<pthread.h>`
    // and `<semaphore.h>`, so a dependent needs a libc, and the module is what
    // must say so. This program needs nothing beyond what the library already
    // brings.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("box3d", dep.module("box3d"));

    // `.use_llvm = true`, and this is not a preference. Zig 0.16's default
    // self-hosted backend lowers a C ABI argument list differently from the
    // compiler that built the core; `build_support/box3d_abi_bridge.h:1-36`
    // records the measurement on this pin, and `FORK-NOTES.md` records the
    // 53-platform receipt. The backend is a property of the executable or test
    // root, so the library cannot set it for a dependent -- every Zig root that
    // imports `dep.module("box3d")` has to say so itself, which is why it is
    // stated here rather than only in the library's own build.

    const exe = b.addExecutable(.{
        .use_llvm = true,
        .name = "box3d-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.has_side_effects = true;
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}