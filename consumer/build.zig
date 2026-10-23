//! External-package consumer that depends only on `dep.module("box3d")`.
//! Forwards dependency options and runs a linked or runtime-loaded example.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Quoted fields preserve the dependency option names' hyphens.
    // `b.dependency` uses struct field names as option names (`std/Build.zig`).

    // Null values are not forwarded, leaving each option's default to the library.
    // Do not override target-dependent `disable-simd` or unsupported linkage here.
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

    // The dependency module carries the C-library link requirement.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("box3d", dep.module("box3d"));

    // Use LLVM: the self-hosted backend's C ABI lowering differs from the core compiler (`build_support/box3d_abi_bridge.h`).
    // Each consumer root must set its backend because a published module cannot.

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
