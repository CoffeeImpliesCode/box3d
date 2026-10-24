// SPDX-License-Identifier: MIT
//
//! Exercises the public `box3d` module from a dependent package.
//! Checks resting contact, a distance-joint swing and a ray cast.
//! Supports linked and runtime-loaded configurations.

const std = @import("std");
const box3d = @import("box3d");

/// Environment variable used when no `--provider` path is supplied.
const provider_variable = "BOX3D_TEST_PROVIDER";

/// Ground half-extents; its top face lies at y = 0.
const ground_half: box3d.Vec3 = .{ .x = 50, .y = 10, .z = 50 };
const ground_centre: box3d.Pos = .{ .x = 0, .y = -10, .z = 0 };
const cube_half: f32 = 1;
const cube_mass: f32 = 8;
const anchor: box3d.Pos = .{ .x = 2, .y = 5, .z = 0 };
const anchor_distance: f32 = 1.5;
/// Sphere radius; the distance joint attaches at its centre.
const probe_radius: f32 = 0.25;
/// Starts level with the anchor and one joint length to the side.
const release: box3d.Pos = .{
    .x = anchor.x + anchor_distance,
    .y = anchor.y,
    .z = anchor.z,
};
/// Drag lets the pendulum settle during the finite run.
const probe_damping: f32 = 2;
/// Ten seconds of swing; sleep is disabled so drag, not the sleep threshold, settles it.
const swing_steps: usize = 600;
/// Joint frames are body-local, so this subtracts the ground body's origin.
/// See `include/box3d/types.h` and `src/joint.c`.
const anchor_on_ground: box3d.Vec3 = .{
    .x = anchor.x - ground_centre.x,
    .y = anchor.y - ground_centre.y,
    .z = anchor.z - ground_centre.z,
};
const time_step: f32 = 1.0 / 60.0;
const sub_steps: c_int = 4;
/// Two seconds of cube settling.
const settle_steps: usize = 120;
/// Tolerance for the resting-height check.
const rest_tolerance: f32 = 0.01;
/// Tolerance for the soft distance constraint's solver error.
/// A missing joint lets gravity move the sphere beyond this band.
const joint_tolerance: f32 = 0.02;

/// Error returned when a runtime-loading build has no provider.
const ConfigurationError = error{NoProviderConfigured};
const ConsumerError = error{ConsumerCheckFailed};

const CheckError = ConsumerError || std.Io.Writer.Error;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // Load the provider before any call through the runtime table.
    if (comptime box3d.runtime_loaded) {
        box3d.load(.{ .path = try providerRequest(init) }) catch |err| {
            std.debug.print("consumer: loading the provider failed: {t}\n", .{err});
            return err;
        };
    }

    try w.print("box3d consumer\n", .{});
    // Query the provider so the report reflects the loaded or linked library.
    const version = box3d.base.version();
    try w.print("{s} C library reports version {d}.{d}.{d}, double precision {s}\n", .{
        if (box3d.runtime_loaded) "loaded" else "linked",
        version.major,
        version.minor,
        version.revision,
        if (box3d.base.isDoublePrecision()) "yes" else "no",
    });

    const world = try box3d.world.create(.{});
    defer box3d.world.destroy(world);

    const ground = try box3d.body.create(world, .{ .position = ground_centre });
    const ground_hull = box3d.shape.boxHull(ground_half.x, ground_half.y, ground_half.z);
    _ = try box3d.shape.createHull(ground, .{}, &ground_hull.base);

    // Start in contact instead of dropping the cube onto the ground.

    const cube = try box3d.body.create(world, .{
        .bodyType = box3d.dynamicBody,
        .position = .{ .x = 0, .y = ground_centre.y + ground_half.y + cube_half, .z = 0 },
    });
    const cube_hull = box3d.shape.cubeHull(cube_half);
    _ = try box3d.shape.createHull(cube, .{ .density = 1.0 }, &cube_hull.base);

    try checkFloat(w, "cube mass (kg)", cube_mass, box3d.body.mass(cube), 0.001);

    const resting_height = ground_centre.y + ground_half.y + cube_half;
    for (0..settle_steps) |_| box3d.world.step(world, time_step, sub_steps);

    const resting = box3d.body.position(cube);
    try checkFloat(w, "resting height (m)", resting_height, resting.y, rest_tolerance);
    try w.print("  cube is asleep: {s}\n", .{if (box3d.body.isAwake(cube)) "no" else "yes"});

    // Start beside the anchor; a vertical segment would be a static equilibrium, not a swing.
    // Gravity across the segment tests the pendulum's arc and settled equilibrium.

    const probe = try box3d.body.create(world, .{
        .bodyType = box3d.dynamicBody,
        .position = release,
        .linearDamping = probe_damping,
        // Keep the sphere awake until drag settles; sleep would freeze it at a threshold crossing.
        .enableSleep = false,
    });
    _ = try box3d.shape.createSphere(probe, .{ .density = 1.0 }, box3d.shape.sphere(probe_radius));

    _ = try box3d.joint.createDistance(world, .{
        .base = .{
            .bodyIdA = ground,
            .bodyIdB = probe,
            // Frame A is ground-relative; frame B is at the sphere body's origin.
            .localFrameA = .{ .p = anchor_on_ground, .q = box3d.identityQuat },
        },
        // Leave the spring disabled to keep the distance constraint rigid.
        .length = anchor_distance,
        .enableMotor = false,
        .enableLimit = false,
    });

    // Check the full path, not only the final point, to catch a joint failure mid-swing.
    const arc_low: f64 = anchor.y - anchor_distance;
    const release_height: f64 = release.y;

    var worst_reach_error: f64 = 0;
    var lowest: f64 = release_height;
    var highest: f64 = release_height;
    for (0..swing_steps) |_| {
        box3d.world.step(world, time_step, sub_steps);
        const at = box3d.body.position(probe);
        const reach_error = @abs(reachFromAnchor(at) - anchor_distance);
        worst_reach_error = @max(worst_reach_error, reach_error);
        lowest = @min(lowest, at.y);
        highest = @max(highest, at.y);
    }
    try checkAtMost(w, "worst reach error (m)", joint_tolerance, worst_reach_error);

    const hung = box3d.body.position(probe);
    // The swing went through that low point instead of stalling on the way.
    try checkAtMost(w, "miss at the arc's low point (m)", joint_tolerance, arc_low - lowest);
    // The sphere must not rise above its release height.
    // At rest, the segment should hang vertically below the anchor.
    try checkAtMost(w, "rise above the release (m)", joint_tolerance, highest - release_height);
    try checkFloat(w, "hung height (m)", arc_low, hung.y, joint_tolerance);
    try checkAtMost(w, "hung sideways offset (m)", joint_tolerance, sidewaysOffset(hung));

    // The ray's second vector is a translation, from (5, 10, 5) to (0, -10, 5).
    // It intersects the ground halfway along the ray, at x = 2.5.

    const filter = (box3d.QueryFilterDef{}).native();
    var hit: box3d.RayResult = undefined;
    try w.print("\nray cast\n", .{});
    if (!box3d.query.castRayClosestShape(
        world,
        .{ .x = 5, .y = 10, .z = 5 },
        .{ .x = -5, .y = -20, .z = 0 },
        filter,
        &hit,
    )) {
        std.debug.print("consumer: a ray that should have hit the ground did not\n", .{});
        return error.ConsumerCheckFailed;
    }
    // The ground is the first hit; its top face intersects the ray at fraction 0.5.
    try checkFloat(w, "ground hit fraction", 0.5, hit.fraction, 0.0001);
    try checkFloat(w, "ground hit height (m)", 0.0, hit.point.y, 0.001);
    try checkFloat(w, "ground hit offset (m)", 2.5, hit.point.x, 0.001);
    try checkFloat(w, "ground hit normal", 1.0, hit.normal.y, 0.001);

    try w.print("\nevery checked answer matched the scene's geometry\n", .{});
    try w.flush();
}

/// Gets the provider path from `--provider` or `BOX3D_TEST_PROVIDER`.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get(provider_variable) orelse
        return noProvider();
}

/// Reports how to configure a missing runtime provider.
fn noProvider() ConfigurationError {
    std.debug.print(
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export " ++ provider_variable ++ " with a shared object exporting the " ++
            "entry points of include/box3d/box3d.h and the ten box3dAbi_* " ++
            "entry points of build_support/box3d_abi_bridge.h. Nothing is loaded " ++
            "by default and no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

/// Print one floating-point answer and fail if it is not the expected one.
fn checkFloat(
    w: *std.Io.Writer,
    what: []const u8,
    expected: f64,
    actual: f64,
    tolerance: f64,
) CheckError!void {
    try w.print("  {s: <32}{d:.6} (expected {d:.6})\n", .{ what, actual, expected });
    if (!std.math.approxEqAbs(f64, expected, actual, tolerance)) {
        std.debug.print("consumer: {s}: expected {d:.6}, computed {d:.6}, tolerance {d:.6}\n", .{
            what,
            expected,
            actual,
            tolerance,
        });
        return error.ConsumerCheckFailed;
    }
}

/// How far `at` sits from the anchor, in metres.
fn reachFromAnchor(at: box3d.Pos) f64 {
    // subPos returns a Vec3 in both position precision modes.
    return box3d.math.length(box3d.math.subPos(at, anchor));
}

/// Measures horizontal distance from the anchor in `f64` for both precision modes.
fn sidewaysOffset(at: box3d.Pos) f64 {
    const dx = @as(f64, at.x) - @as(f64, anchor.x);
    const dz = @as(f64, at.z) - @as(f64, anchor.z);
    return @sqrt(dx * dx + dz * dz);
}

/// Print one measured answer and fail if it is outside a one-sided band.
fn checkAtMost(w: *std.Io.Writer, what: []const u8, limit: f64, actual: f64) CheckError!void {
    try w.print("  {s: <32}{d:.6} (at most {d:.6})\n", .{ what, actual, limit });
    if (!(actual <= limit)) {
        std.debug.print("consumer: {s}: expected at most {d:.6}, computed {d:.6}\n", .{
            what,
            limit,
            actual,
        });
        return error.ConsumerCheckFailed;
    }
}
