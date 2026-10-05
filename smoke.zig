// SPDX-License-Identifier: MIT
//
//! A runnable, deterministic demonstration of the Box3D facade.
//!
//! `zig build smoke` runs this. There is no input to supply and no output that
//! depends on the host, the clock or a random seed, so the same lines come out
//! every time.
//!
//! In a runtime-loading build the provider is named on the command line
//! (`--provider <path>`) or in `BOX3D_TEST_PROVIDER`, and the program says which
//! configuration it is in the first two lines. In a linked build neither is
//! needed and neither is read.
//!
//! Every answer below is checked against a number derived from the geometry of
//! the scene, not against a value this program once printed. The scene is the one
//! in upstream's own `HelloWorld` (`test/test_world.c:21-101`): a ground box
//! with half-extents (50, 10, 50) centred at y = -10, so its top face is at
//! y = 0, and a unit cube dropped from y = 4. That makes the resting height
//! exactly 1, the mass of a unit cube at density 1 exactly 8, and a downward ray
//! from y = 10 long enough to reach the ground meet that ground at exactly
//! fraction 0.5. A query box out in the gap between the two bodies, above the
//! ground and clear of the cube, is inside neither of them and finds nothing.
//! A mismatch prints both sides and exits non-zero, so this is a check and not
//! a demo.
//!
//! The only value printed without being checked is Box3D's own version, which is
//! what this build reached and which the provider validation already required to
//! be 0.1.0.

const std = @import("std");
const box3d = @import("box3d");

/// A shared object exporting the `b3*` entry points of `box3d/box3d.h`, named
/// by the environment in a runtime-loading build.
const provider_variable = "BOX3D_TEST_PROVIDER";

/// The ground box: half-extents, and the centre that puts its top face on y = 0.
const ground_half: box3d.Vec3 = .{ .x = 50, .y = 10, .z = 50 };
const ground_centre: box3d.Pos = .{ .x = 0, .y = -10, .z = 0 };
/// The unit cube: half-extent, drop height, and its volume at density 1.
const cube_half: f32 = 1;
const cube_drop: box3d.Pos = .{ .x = 0, .y = 4, .z = 0 };
const cube_volume: f32 = 8;
/// The step, the sub-steps and the step count upstream's scene uses.
const time_step: f32 = 1.0 / 60.0;
const sub_steps: c_int = 4;
const drop_steps: usize = 90;
/// How far a resting contact may be from the exact geometric height. This is the
/// tolerance upstream's own test of this scene uses
/// (`test/test_world.c:96-98`).
const rest_tolerance: f32 = 0.01;

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// What went wrong when a checked answer was not the expected one.
const SmokeError = error{SmokeCheckFailed};

/// What a helper that reports an answer and then checks it can return: the
/// answer was wrong, or the writer it reports through failed. The write failure
/// is propagated rather than swallowed, so a full or closed output stops the
/// run instead of silently truncating the report.
const CheckError = SmokeError || std.Io.Writer.Error;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // In a runtime-loading build nothing below can run until a provider is
    // loaded, and the load is the one explicit step the contract asks for. In a
    // linked build this is a no-op at comptime and the module is already usable.
    if (comptime box3d.runtime_loaded) {
        try box3d.load(.{ .path = try providerRequest(init) });
    }

    try w.print("box3d smoke\n", .{});
    try w.print("{s} C library reports version {d}.{d}.{d}\n", .{
        if (box3d.runtime_loaded) "loaded" else "linked",
        box3d.c.b3GetVersion().major,
        box3d.c.b3GetVersion().minor,
        box3d.c.b3GetVersion().revision,
    });
    // Read through the raw route on purpose: this names the precision mode of the
    // library this build actually reached, which is an ABI fact rather than a
    // constant compiled into this program.
    try w.print("{s} C library is double precision: {s}\n", .{
        if (box3d.runtime_loaded) "loaded" else "linked",
        if (box3d.base.isDoublePrecision()) "yes" else "no",
    });

    const world = try box3d.world.create(.{});

    // The ground: a static body with a box hull on it. Its top face is at
    // ground_centre.y + ground_half.y, which is 0.
    const ground = try box3d.body.create(world, .{ .position = ground_centre });
    const ground_hull = box3d.shape.boxHull(ground_half.x, ground_half.y, ground_half.z);
    _ = try box3d.shape.createHull(ground, .{}, &ground_hull.base);

    // The cube: dynamic, with a density, so that it has mass to fall with.
    const cube = try box3d.body.create(world, .{
        .bodyType = box3d.dynamicBody,
        .position = cube_drop,
    });
    const cube_hull = box3d.shape.cubeHull(cube_half);
    const cube_shape = try box3d.shape.createHull(cube, .{
        .density = 1.0,
    }, &cube_hull.base);

    // Mass before any stepping: a unit cube at density 1 is 8 cubic units of mass.
    try checkFloat(w, "cube mass (kg)", cube_volume, box3d.body.mass(cube), 0.001);
    // A downward ray from ten metres up, twenty long. The cube's top face is at
    // y = 5, so the ray meets it a quarter of the way along; a ray that misses the
    // cube reaches the ground's top face half way along.
    const filter = (box3d.QueryFilterDef{}).native();
    var hit: box3d.RayResult = undefined;

    try w.print("\nray casts downwards from y = 10\n", .{});

    try expectHit(box3d.query.castRayClosestShape(
        world,
        .{ .x = 0, .y = 10, .z = 0 },
        .{ .x = 0, .y = -20, .z = 0 },
        filter,
        &hit,
    ));
    const cube_top = cube_drop.y + cube_half;
    const cube_fraction = (10 - cube_top) / 20;
    try checkSame(w, "first hit is the cube", cube_shape, hit.shapeId);
    try checkFloat(w, "cube hit fraction", cube_fraction, hit.fraction, 0.0001);
    try checkFloat(w, "cube hit height", cube_top, hit.point.y, 0.001);

    try expectHit(box3d.query.castRayClosestShape(
        world,
        .{ .x = 5, .y = 10, .z = 5 },
        .{ .x = 0, .y = -20, .z = 0 },
        filter,
        &hit,
    ));
    const ground_top = ground_centre.y + ground_half.y;
    const ground_fraction = (10 - ground_top) / 20;
    try checkFloat(w, "ground hit fraction", ground_fraction, hit.fraction, 0.0001);
    try checkFloat(w, "ground hit height", ground_top, hit.point.y, 0.001);
    try checkFloat(w, "ground hit normal", 1.0, hit.normal.y, 0.001);

    for (0..drop_steps) |_| box3d.world.step(world, time_step, sub_steps);

    const resting = box3d.body.position(cube);
    const expected_height = ground_centre.y + ground_half.y + cube_half;
    try checkFloat(w, "resting height (m)", expected_height, resting.y, rest_tolerance);

    const rotation = box3d.body.rotation(cube);
    // Upstream's fixture checks tilt about x and z, not yaw or horizontal drift.
    try checkFloat(w, "resting tilt about x", 0.0, rotation.v.x, rest_tolerance);
    try checkFloat(w, "resting tilt about z", 0.0, rotation.v.z, rest_tolerance);

    // An overlap query out in the gap between the two bodies finds nothing: the
    // ground's top face is at y = 0 and this box is above it, and at x = z in
    // [1.5, 2.5] it is outside the cube's own half-extent of 1 as well. It is
    // inside neither shape.
    try w.print("\noverlap query\n", .{});
    var found: [8]box3d.ShapeId = undefined;
    const gap = box3d.math.makeAabb(
        &[_]box3d.Vec3{
            .{ .x = 1.5, .y = 1.0, .z = 1.5 },
            .{ .x = 2.5, .y = 2.0, .z = 2.5 },
        },
        2,
        0,
    );
    const gap_count = box3d.query.overlapAabbCollect(world, gap, filter, &found);
    try checkCount(w, "shapes inside the gap box", 0, gap_count);

    // Long after the drop, the world is asleep, and says how many bytes it holds.
    for (0..300) |_| box3d.world.step(world, time_step, sub_steps);
    try w.print("\nafter {d} more steps\n", .{@as(u32, @intCast(300))});
    try w.print("  awake bodies: {d}\n", .{box3d.world.awakeBodyCount(world)});
    try w.print("  cube awake: {s}\n", .{if (box3d.body.isAwake(cube)) "yes" else "no"});
    try w.print("  bytes Box3D has allocated: {d}\n", .{box3d.base.allocatedByteCount()});

    box3d.world.destroy(world);
    try w.print("\nevery checked answer matched the scene's geometry\n", .{});
    try w.flush();
}

/// The provider this run should load, from `--provider <path>` or from
/// `BOX3D_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location or falls back to a
/// linked copy: a runtime-loading build that was not told which file to load
/// reports that it was not told, rather than loading something else.
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

/// Say which variable is missing. An error name on its own would send the next
/// person into the loader instead of to the command line.
fn noProvider() ConfigurationError {
    std.debug.print(
        "smoke: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export " ++ provider_variable ++ " with a shared object exporting the " ++
            "entry points of include/box3d/box3d.h. Nothing is loaded by default " ++
            "and no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

/// A cast that was expected to hit and did not is a failure of this program, not
/// a recoverable condition, so it stops here with a message rather than
/// continuing to compare fields of a result upstream says are invalid
/// (`include/box3d/types.h:1352-1353`).
fn expectHit(ok: bool) SmokeError!void {
    if (!ok) {
        std.debug.print("smoke: a ray cast that was expected to hit did not\n", .{});
        return error.SmokeCheckFailed;
    }
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
        std.debug.print("smoke: {s}: expected {d:.6}, computed {d:.6}, tolerance {d:.6}\n", .{
            what,
            expected,
            actual,
            tolerance,
        });
        return error.SmokeCheckFailed;
    }
}

/// Print one count and fail if it is not the expected one.
fn checkCount(
    w: *std.Io.Writer,
    what: []const u8,
    expected: usize,
    actual: usize,
) CheckError!void {
    try w.print("  {s: <32}{d} (expected {d})\n", .{ what, actual, expected });
    if (expected != actual) {
        std.debug.print("smoke: {s}: expected {d}, computed {d}\n", .{ what, expected, actual });
        return error.SmokeCheckFailed;
    }
}

/// Print which shape was hit and fail if it is not the expected one.
fn checkSame(
    w: *std.Io.Writer,
    what: []const u8,
    expected: box3d.ShapeId,
    actual: box3d.ShapeId,
) CheckError!void {
    const same = expected.index1 == actual.index1 and
        expected.world0 == actual.world0 and
        expected.generation == actual.generation;
    try w.print("  {s: <32}shape {d} (expected {d})\n", .{
        what,
        actual.index1,
        expected.index1,
    });
    if (!same) {
        std.debug.print(
            "smoke: {s}: expected shape {d}, computed {d}\n",
            .{ what, expected.index1, actual.index1 },
        );
        return error.SmokeCheckFailed;
    }
}