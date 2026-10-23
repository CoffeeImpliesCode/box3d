//! External-package consumer that depends only on `dep.module("box3d")`.
//! Forwards dependency options and runs a linked or runtime-loaded example.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Null options preserve the dependency's defaults, including target-dependent SIMD.
    const linkage = b.option(
        std.lang.LinkMode,
        "linkage",
        "Forward the native library linkage to the box3d dependency",
    );
    const dep = b.dependency("box3d", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = b.option(bool, "runtime", "Load the native library at run time instead of linking it"),
        .@"double-precision" = b.option(bool, "double-precision", "Store world positions in double"),
        .@"disable-simd" = b.option(bool, "disable-simd", "Build without the SIMD kernels"),
        .validate = b.option(bool, "validate", "Compile upstream's validation checks in"),
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("box3d", dep.module("box3d"));

    // C ABI lowering requires LLVM; a dependency cannot select its consumer's backend.
    const exe = b.addExecutable(.{
        .use_llvm = true,
        .name = "box3d-consumer",
        .root_module = exe_mod,
    });
    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);

    const run_exe = b.addRunArtifact(exe);
    run_exe.has_side_effects = true;
    run_exe.addPassthruArgs();
    b.step("run", "Build and run the consumer program").dependOn(&run_exe.step);

    const try_run_exe = b.addRunArtifact(exe);
    try_run_exe.has_side_effects = true;
    try_run_exe.failing_to_execute_foreign_is_an_error = false;
    try_run_exe.addPassthruArgs();
    const consumer_step = b.step("consumer", "Run the consumer when possible and install it");
    consumer_step.dependOn(&try_run_exe.step);
    consumer_step.dependOn(&install_exe.step);
}
