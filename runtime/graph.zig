// SPDX-License-Identifier: MIT
//
//! Runtime-loaded module graph for the translated C API.
//! Keeps the dispatch and its patched translation on the same target.

const std = @import("std");

/// Prefix used by this SDK's synchronization symbols.
/// Keep it aligned with `runtime/library.zig` and `runtime/sync.c`.
const sync_prefix = "box3d_rt";

/// C library symbols from `<math.h>` stay direct and never enter the loader table.
/// Expand the base and suffix lists to cover libc exports on each target.
/// Keep this set disjoint from Box3D's `b3*` and `box3dAbi_*` exports.
const libc_math_bases =
    \\acos,acosh,asin,asinh,atan,atan2,atanh,
    \\cbrt,copysign,cos,cosh,sin,sinh,tan,tanh,
    \\exp,exp2,expm1,log,log10,log1p,log2,logb,
    \\fabs,fdim,fmax,fmin,fmod,fma,frexp,ldexp,modf,pow,sqrt,remainder,remquo,
    \\hypot,erf,erfc,lgamma,tgamma,
    \\ceil,floor,trunc,rint,round,nearbyint,roundeven,
    \\drem,significand,nan,j0,j1,jn,y0,y1,yn,gamma,lgamma_r,
    \\nextafter,nexttoward,scalbn,ilogb,scalbln,lrint,llrint,lround,llround,scalb,
    \\getpayload,getsign,putpayload,
    \\fegetround,fesetround,fegetenv,fesetenv,feholdexcept,fetestexcept,
    \\feraiseexcept,feupdateenv,fegetmode,fesetmode,
    \\_copysign,_finite,_hypot,_j0,_j1,_jn,_y0,_y1,_yn,
    \\finite,isnan,isinf,isfinite,isnormal,issignaling,signbit,fpclassify,iseqsig,
    \\chgsign,fpclass,signgam,sincos,cospi,sinpi,tanpi,exp10,inf,infinity,
    \\abs,atof,labs,gamma_r,rinttol,roundtol,
    \\__inline_isfinite,__inline_isinf,__inline_isnormal,
    \\_chgsign,_isnan,_logb,_nextafter,_fpclass,_cabs,_scalb,_matherr
;

/// Platform-specific `<math.h>` names that the base and suffix expansion cannot produce.
const libc_extra_names =
    \\__fpclassifyd,__imp__HUGE,__inline_isfinited,__inline_isinfd,__math_errhandling,
    \\__mingw_get_crt_info,__mingw_raise_matherr,__mingw_setusermatherr,__prefetch,
    \\__setusermatherr,__sincos_stret,__sincosf_stret,__sincospi_stret,__sincospif_stret,_atof_l
;

/// Comptime storage for the expanded direct-libc symbol list.
/// The fixed buffer makes overflow a compile-time failure.
const Noise = struct {
    buf: [64 * 1024]u8,
    len: usize,
};

/// Appends a comma-separated name to comptime storage.
/// Capacity overflow fails during comptime evaluation.
fn reserve(storage: *Noise, len: usize) []u8 {
    if (storage.len != 0) {
        storage.buf[storage.len] = ',';
        storage.len += 1;
    }
    const at = storage.len;
    storage.len += len;
    return storage.buf[at..][0..len];
}

/// The expanded names, in comptime-owned storage.
const libc_noise_storage: Noise = blk: {
    @setEvalBranchQuota(100_000);
    // Use an explicit slice element type; tuple peer resolution infers a zero-length array on Zig 0.16.
    const prefixes = [_][]const u8{ "", "__" };
    const suffixes = [_][]const u8{
        "",     "f",      "l",      "f16",   "f32",   "f64",
        "f128", "f16x",   "f32x",   "f64x",  "f128x", "ieee128",
    };
    var storage: Noise = .{ .buf = undefined, .len = 0 };
    var bases = std.mem.splitScalar(u8, libc_math_bases, ',');
    while (bases.next()) |part| {
        // Trim line wrapping before expanding each base.
        const base = std.mem.trim(u8, part, " \t\r\n");
        if (base.len == 0) continue;
        const reentrant = std.mem.endsWith(u8, base, "_r");
        const stem: []const u8 = if (reentrant) base[0 .. base.len - 2] else base;
        // Insert precision suffixes before the reentrant `_r` marker.
        const marker: []const u8 = if (reentrant) "_r" else "";
        for (prefixes) |prefix| {
            for (suffixes) |suffix| {
                const name = reserve(&storage, prefix.len + stem.len + suffix.len + marker.len);
                @memcpy(name[0..prefix.len], prefix);
                @memcpy(name[prefix.len..][0..stem.len], stem);
                @memcpy(name[prefix.len + stem.len ..][0..suffix.len], suffix);
                @memcpy(name[prefix.len + stem.len + suffix.len ..][0..marker.len], marker);
            }
        }
    }
    var extras = std.mem.splitScalar(u8, libc_extra_names, ',');
    while (extras.next()) |part| {
        const name = std.mem.trim(u8, part, " \t\r\n");
        if (name.len == 0) continue;
        @memcpy(reserve(&storage, name.len), name);
    }
    break :blk storage;
};

/// Expanded direct-libc names, in comma-separated form.
const libc_noise: []const u8 = libc_noise_storage.buf[0..libc_noise_storage.len];

const provider_optional = "";

const provider_excluded = "";

/// Creates the loader core used by linked builds.
/// Exposes the shared `LoadSource` and `LoadError` types without creating a loader instance.
pub fn createCoreModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("runtime/loader.zig"),
        .target = target,
        .optimize = optimize,
        // The Unix backend uses libc for `dlopen`; linked builds do not compile this module.
        .link_libc = true,
    });
}

/// Creates the runtime-loaded C module for `translate`'s target and configuration.
/// The generated dispatch uses the translation output for those settings.
pub fn createModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const core = createCoreModule(b, target, optimize);

    const library = b.createModule(.{
        .root_source_file = b.path("runtime/library.zig"),
        .target = target,
        .optimize = optimize,
    });
    library.addImport("rt", core);

    return createDispatchModule(b, translate, target, optimize, core, library);
}

const GeneratedSources = struct {
    native: std.Build.LazyPath,
    dispatch: std.Build.LazyPath,
};

fn createDispatchModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: *std.Build.Module,
    library: *std.Build.Module,
) *std.Build.Module {
    const sources = generateDispatch(b, translate, target);

    const dispatch = b.createModule(.{
        .root_source_file = sources.dispatch,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dispatch.addImport("rt", core);
    dispatch.addImport("library", library);
    // The dispatch re-exports declarations from the patched translation, preserving type identity.
    // Its `__root` import points nested aliases back to routed wrappers.
    const native = b.createModule(.{
        .root_source_file = sources.native,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    native.addImport("c_routed", dispatch);
    dispatch.addImport("c_native", native);
    dispatch.addCSourceFiles(.{
        .files = &.{"runtime/sync.c"},
        .flags = &.{b.fmt("-DRT_SYNC_PREFIX={s}", .{sync_prefix})},
        .language = .c,
    });
    return dispatch;
}

/// Generates a dispatch from this target's translation output.
/// Each build configuration gets its own dispatch.
fn generateDispatch(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
) GeneratedSources {
    const generator = b.addExecutable(.{
        .name = b.fmt("box3d-runtime-generate-{s}", .{
            target.result.zigTriple(b.allocator) catch @panic("unspellable target"),
        }),
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/generate.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    const run = b.addRunArtifact(generator);
    run.addArg("--library");
    run.addArg("box3d");
    run.addArg("--translate");
    run.addFileArg(translate.getOutput());
    if (libc_noise.len != 0) {
        run.addArg("--noise");
        run.addArg(libc_noise);
    }
    if (provider_optional.len != 0) {
        run.addArg("--optional");
        run.addArg(provider_optional);
    }
    if (provider_excluded.len != 0) {
        run.addArg("--exclude");
        run.addArg(provider_excluded);
    }
    run.addArg("--native-output");
    const native_source = run.addOutputFileArg("native.zig");
    run.addArg("--output");
    const dispatch_source = run.addOutputFileArg("dispatch.zig");
    return .{ .native = native_source, .dispatch = dispatch_source };
}
