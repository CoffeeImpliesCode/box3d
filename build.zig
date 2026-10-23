//! Zig 0.16 build for Box3D, erincatto's 3D physics engine.
const std = @import("std");

const manifest = @import("build.zig.zon");

const graph = @import("runtime/graph.zig");

const upstream_version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 0 };

const lib_name = "box3d";

const c_import_name = "c";
const rt_import_name = "rt";

const translate_header = "zig/translate.h";
const facade_root = "zig/root.zig";
const test_root = "tests.zig";
const smoke_root = "smoke.zig";

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

const shared_sources = [_][]const u8{
    "benchmarks.c",
    "determinism.c",
    "human.c",
    "overflow_color.c",
    "stability.c",
    "utils.c",
};

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

const PublicHeader = struct {
    source: []const u8,
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

/// The bridge adapts x86-64 by-value `b3Pos` calls for Zig's C ABI.
/// A late include path resolves upstream's capitalized `Windows.h` for Windows targets.
const bridge_dir = "build_support";

const bridge_sources = [_][]const u8{
    "box3d_abi_bridge.c",
};

const licence_records = [_][]const u8{
    "LICENSE",
    "README.upstream.md",
    "NOTICE.md",
    "UPSTREAM.md",
    "FORK-LICENSE.md",
};

/// Match upstream's GNU C17 dialect and deterministic-math flags.
const language_flags = [_][]const u8{
    "-std=gnu17",
    "-ffp-contract=off",
};

/// Upstream's Apple warning flags (`src/CMakeLists.txt:197-198`).
const apple_warning_flags = [_][]const u8{
    "-Wall",
    "-Wextra",
    "-pedantic",
    "-Wmissing-prototypes",
};

/// Upstream's Unix warning flags (`src/CMakeLists.txt:202-204`).
const unix_warning_flags = [_][]const u8{
    "-Wall",
    "-Wextra",
    "-pedantic",
    "-Wmissing-prototypes",
    "-Wno-unused-value",
};

const no_warning_flags = [_][]const u8{};

/// Upstream's hidden-visibility flags (`src/CMakeLists.txt:103-106`).
const visibility_flags = [_][]const u8{
    "-fvisibility=hidden",
    "-fvisibility-inlines-hidden",
};

/// Visibility flags apply only to core sources.
const CUnit = enum {
    core,
    support,
    tests,
};

const Options = struct {
    linkage: std.builtin.LinkMode,
    /// Whether the facade dispatches through a loaded table.
    runtime_loaded: bool,
    /// Upstream's public precision definition; it changes the ABI.
    double_precision: bool,
    /// `null` resolves the SIMD default for each target in a matrix build.
    disable_simd: ?bool,
    validate: bool,
};

const Graph = struct {
    c_lib: *std.Build.Step.Compile,
    module: *std.Build.Module,
};

const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// Matrix artifacts need per-target names to avoid output collisions.
fn artifactName(b: *std.Build, target: std.Build.ResolvedTarget, public: bool) []const u8 {
    if (public) return lib_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("box3d: unspellable target");
    return b.fmt("{s}-{s}", .{ lib_name, triple });
}

/// Only Linux needs pthread; Apple's calls resolve through libSystem.
fn usesPthread(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .linux;
}

/// Box3D uses libm on Unix; macOS and WASI provide math through libc.
/// The Windows GNU target uses its CRT.
fn usesLibm(target: std.Build.ResolvedTarget) bool {
    return switch (target.result.os.tag) {
        .linux, .freebsd, .netbsd, .openbsd, .dragonfly, .illumos => true,
        else => false,
    };
}

fn warningFlags(target: std.Build.ResolvedTarget) []const []const u8 {
    return switch (target.result.os.tag) {
        // Upstream's Windows branch adds no GCC-style warning flags.
        .windows => &no_warning_flags,
        .macos => &apple_warning_flags,
        else => &unix_warning_flags,
    };
}

/// 32-bit ARM selects NEON, but Box3D's float divide and square-root
/// intrinsics are available only to 64-bit ARM targets.
fn targetLacksArmNeonFloatMath(target: std.Build.ResolvedTarget) bool {
    return switch (target.result.cpu.arch) {
        .arm, .armeb, .thumb, .thumbeb => true,
        else => false,
    };
}

/// Explicit settings win; otherwise disable SIMD only where the target lacks its NEON intrinsics.
fn resolveDisableSimd(opts: Options, target: std.Build.ResolvedTarget) bool {
    return opts.disable_simd orelse targetLacksArmNeonFloatMath(target);
}

/// Use the same language and determinism flags for every C source group.
fn cFlags(b: *std.Build, target: std.Build.ResolvedTarget, unit: CUnit) []const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    const alloc = b.allocator;
    list.append(alloc, language_flags[0]) catch @panic("OOM");
    list.append(alloc, language_flags[1]) catch @panic("OOM");
    if (usesPthread(target)) {
        // Mark Linux C units as threaded for Box3D's pthread paths.
        list.append(alloc, "-pthread") catch @panic("OOM");
    }
    if (unit == .core) {
        list.append(alloc, visibility_flags[0]) catch @panic("OOM");
        list.append(alloc, visibility_flags[1]) catch @panic("OOM");
    }
    for (warningFlags(target)) |flag| list.append(alloc, flag) catch @panic("OOM");
    return list.items;
}

/// Apply Box3D definitions and resolve target-dependent SIMD defaults.
fn addConfigMacros(
    mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    opts: Options,
) void {
    if (opts.double_precision) mod.addCMacro("BOX3D_DOUBLE_PRECISION", "1");
    if (resolveDisableSimd(opts, target)) mod.addCMacro("BOX3D_DISABLE_SIMD", "1");
    if (opts.validate) mod.addCMacro("BOX3D_VALIDATE", "1");
}

fn addTranslateMacros(translate: *std.Build.Step.TranslateC, opts: Options) void {
    if (opts.double_precision) translate.defineCMacro("BOX3D_DOUBLE_PRECISION", "1");
    // The translation sees public ABI definitions, not private code-path flags.
    // `BOX3D_DLL` is for shared consumers; `box3d_EXPORTS` stays on library compilation.
    if (opts.linkage == .dynamic) translate.defineCMacro("BOX3D_DLL", "1");
}

const TranslateRoute = enum {
    aro,
    preprocessed,
};

/// NetBSD headers expand `__END_DECLS` through `_Pragma`, which Aro cannot parse.
/// Preprocess NetBSD headers with the target C compiler.
fn translateRoute(target: std.Build.ResolvedTarget) TranslateRoute {
    return if (target.result.os.tag == .netbsd) .preprocessed else .aro;
}

/// Preprocess NetBSD headers with the target compiler, retaining macros and dependency inputs.
fn preprocessedTranslateHeader(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    opts: Options,
) std.Build.LazyPath {
    // Use the compiler running this build.
    const run = b.addSystemCommand(&[_][]const u8{ b.graph.zig_exe, "cc", "-E", "-dD" });
    run.setName("preprocess box3d translate.h");
    if (!target.query.isNative()) {
        const triple = target.result.zigTriple(b.allocator) catch @panic("box3d: unspellable target");
        run.addArg("-target");
        run.addArg(triple);
    }
    run.addPrefixedDirectoryArg("-I", b.path("include"));
    if (opts.double_precision) run.addArg("-DBOX3D_DOUBLE_PRECISION=1");
    if (opts.linkage == .dynamic) run.addArg("-DBOX3D_DLL=1");
    run.addArg("-o");
    const preprocessed = run.addOutputFileArg("box3d-translate.c");
    run.addArg("-MD");
    _ = run.addPrefixedDepFileOutputArg("-MF", "box3d-translate.d");
    run.addFileArg(b.path(translate_header));
    return preprocessed;
}

fn addPlatformLibraries(mod: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    if (usesLibm(target)) mod.linkSystemLibrary("m", .{ .use_pkg_config = .no });
    if (usesPthread(target)) mod.linkSystemLibrary("pthread", .{ .use_pkg_config = .no });
}

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
        // Match upstream's VERSION and SOVERSION for shared libraries.
        .version = if (linkage == .dynamic) upstream_version else null,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = if (linkage == .dynamic) true else null,
        }),
    });
    const c_mod = c_lib.root_module;

    // The core needs public `include/` and private `src/` headers.
    c_mod.addIncludePath(b.path("include"));
    c_mod.addIncludePath(b.path("src"));
    // Resolve upstream's capitalized `<Windows.h>` on case-sensitive hosts.
    // Use `-idirafter` so MinGW's header wins on case-insensitive hosts.
    if (target.result.os.tag == .windows) c_mod.addAfterIncludePath(b.path(bridge_dir));
    addPlatformLibraries(c_mod, target);
    addConfigMacros(c_mod, target, opts);
    if (linkage == .dynamic) {
        // Define the library-side export macro for shared builds.
        c_mod.addCMacro("box3d_EXPORTS", "1");
    }
    c_mod.addCSourceFiles(.{
        .root = b.path("src"),
        .files = &core_sources,
        .flags = cFlags(b, target, .core),
    });

    // Compile the ABI bridge with the core's flags and macros.
    c_mod.addCSourceFiles(.{
        .root = b.path(bridge_dir),
        .files = &bridge_sources,
        .flags = cFlags(b, target, .core),
    });

    // Installed headers are also exposed to dependent C code.
    for (public_headers) |header| {
        c_lib.installHeader(b.path(header.source), header.dest);
    }

    return c_lib;
}

/// Register the public module only for the selected target; matrix graphs stay private.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: Options,
    public: bool,
) Graph {
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
        .root_source_file = switch (translateRoute(target)) {
            .aro => b.path(translate_header),
            .preprocessed => preprocessedTranslateHeader(b, target, opts),
        },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // Translate against this tree's headers, not a system-installed copy.
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

    // Runtime dispatch and artifact delivery are independent.
    // The linked facade imports the core module's `LoadSource` and `LoadError` types.
    if (opts.runtime_loaded) {
        // Runtime mode links no libraries; `load()` supplies the provider.
        module.addImport(c_import_name, graph.createModule(b, translate, target, optimize));
    } else {
        // Import translation through the facade; do not publish a bare C module.
        module.addImport(c_import_name, translate.createModule());
        module.addImport(rt_import_name, graph.createCoreModule(b, target, optimize));
        // Propagate static-link dependencies through the facade module.
        addPlatformLibraries(module, target);
        module.linkLibrary(c_lib);
    }
    // Keep dependent C includes bound to this package's headers.
    module.addIncludePath(b.path("include"));

    return .{ .c_lib = c_lib, .module = module };
}

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

/// Upstream tests call hidden internals, so they need a static archive.
/// Reuse the delivered archive when the package already builds static.
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
        .link_libc = true,
    });
    test_mod.addIncludePath(b.path("include"));
    test_mod.addIncludePath(b.path("src"));
    test_mod.addIncludePath(b.path("shared"));
    if (target.result.os.tag == .windows) test_mod.addAfterIncludePath(b.path(bridge_dir));
    addPlatformLibraries(test_mod, target);
    // Match the core's configuration; upstream tests always link static.
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

    // This C-only executable needs no Zig LLVM backend.
    return b.addExecutable(.{ .name = name, .root_module = test_mod });
}

/// Compile the facade and upstream tests for one target without running them.
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

/// Run the separate package that imports the published facade.
fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: Options,
) *std.Build.Step.Run {
    // Preserve the original target query; resolving it early loses target details.
    const query = target.query;
    const triple = query.zigTriple(b.allocator) catch @panic("box3d: unspellable target");
    defer b.allocator.free(triple);
    const cpu = query.serializeCpuAlloc(b.allocator) catch @panic("box3d: unspellable CPU");
    defer b.allocator.free(cpu);

    // Invoke the compiler running this build, not a separate PATH toolchain.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    // Preserve the target's CPU model and feature overrides in the nested build.
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    run.addArg(b.fmt("-Druntime={}", .{opts.runtime_loaded}));
    run.addArg(b.fmt("-Ddouble-precision={}", .{opts.double_precision}));
    run.addArg(b.fmt("-Ddisable-simd={}", .{resolveDisableSimd(opts, target)}));
    run.addArg(b.fmt("-Dvalidate={}", .{opts.validate}));
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(opts.linkage)}));
    if (b.enable_darling) run.addArg("-fdarling");
    if (b.enable_qemu) run.addArg("-fqemu");
    if (b.enable_rosetta) run.addArg("-frosetta");
    if (b.enable_wasmtime) run.addArg("-fwasmtime");
    if (b.enable_wine) run.addArg("-fwine");
    if (b.libc_runtimes_dir) |runtimes| run.addArgs(&.{ "--libc-runtimes", runtimes });
    // Keep the nested build on this SDK's fixed `-j8` job count.
    run.addArg("-j8");
    run.addArg("--summary");
    run.addArg("all");
    // Give the nested graph its own manifest cache.
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
    }
    // Forward the global cache selected by the parent build.
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArg("--global-cache-dir");
        run.addArg(global_cache);
    }
    // Forward only an explicit prefix, resolved against this build's root.
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    // Delimit caller arguments so the consumer receives them.
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

/// Write a relocatable pkg-config file with ABI macros and static-link dependencies.
/// Keep its metadata aligned with the artifact this build produces.
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
            // Emit public ABI definitions in the installed metadata.
            if (opts.double_precision) " -DBOX3D_DOUBLE_PRECISION" else "",
            if (opts.linkage == .dynamic) " -DBOX3D_DLL" else "",
        })),
        .lib,
        "pkgconfig/box3d.pc",
    );
    // Attach the generated file explicitly to the install step.
    b.getInstallStep().dependOn(&install_pc.step);
}

fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |record| {
        const install_record = b.addInstallFileWithDir(
            b.path(record),
            .prefix,
            b.fmt("share/licenses/{s}/{s}", .{ lib_name, record }),
        );
        // Attach each record explicitly to the install step.
        b.getInstallStep().dependOn(&install_record.step);
    }
}

/// Whether the OS can load a shared library. Windows uses its PE/COFF loader
/// without an interpreter path. Other targets need a dynamic linker.
/// WASI has neither and a shared request is refused.
fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// Reject shared linkage when the target OS has no dynamic linker.
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

/// Inspect raw options because the resolved target loses an explicit host selection.
fn targetWasNamed(b: *const std.Build) bool {
    return b.user_input_options.contains("target");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
        // Keep `null` so the SIMD default resolves separately for every target.
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

    requireSupportedLinkage(target, opts.linkage);

    const published = addGraph(b, target, optimize, opts, true);
    b.installArtifact(published.c_lib);
    addPkgConfig(b, opts);
    installLicenceRecords(b);

    const smoke = b.addExecutable(.{
        .use_llvm = true,
        .name = "box3d-smoke",
        .root_module = facadeModule(b, target, optimize, published, smoke_root),
    });
    b.getInstallStep().dependOn(&smoke.step);

    // Ensure the smoke program runs instead of reusing a cached result.
    const run_smoke = b.addRunArtifact(smoke);
    run_smoke.has_side_effects = true;
    if (b.args) |args| run_smoke.addArgs(args);
    b.step("smoke", "Run the smoke program").dependOn(&run_smoke.step);

    // `tests.zig` names the test blocks; a re-export-only root discovers none.
    const unit_tests = b.addTest(.{
        .use_llvm = true,
        .name = "box3d-tests",
        .root_module = facadeModule(b, target, optimize, published, test_root),
    });
    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.has_side_effects = true;
    b.step("test", "Run the behavioural tests for the selected target")
        .dependOn(&run_tests.step);

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

    b.step(
        "consumer",
        "Build the independent dep.module(\"box3d\") consumer, and run it when this host can execute it",
    ).dependOn(&runConsumer(b, target, optimize, opts).step);

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
        // Runtime dispatch is separate from the artifact this build installs.
        std.debug.print(
            "box3d: runtime-loaded dispatch (-Druntime=true); no library is " ++
                "linked into the module, and a provider is named by an explicit " ++
                "load(source)\n",
            .{},
        );
    }
}
