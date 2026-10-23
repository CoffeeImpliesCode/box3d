// SPDX-License-Identifier: MIT
//
//! Deterministic smoke checks for the Box3D facade.

const std = @import("std");
const box3d = @import("box3d");

const provider_variable = "BOX3D_TEST_PROVIDER";

const ground_half: box3d.Vec3 = .{ .x = 50, .y = 10, .z = 50 };
const ground_centre: box3d.Pos = .{ .x = 0, .y = -10, .z = 0 };
const cube_half: f32 = 1;
const cube_drop: box3d.Pos = .{ .x = 0, .y = 4, .z = 0 };
const cube_volume: f32 = 8;
const time_step: f32 = 1.0 / 60.0;
const sub_steps: c_int = 4;
const drop_steps: usize = 90;
const rest_tolerance: f32 = 0.01;

const ConfigurationError = error{NoProviderConfigured};

const SmokeError = error{SmokeCheckFailed};

const CheckError = SmokeError || std.Io.Writer.Error;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

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
    try w.print("{s} C library is double precision: {s}\n", .{
        if (box3d.runtime_loaded) "loaded" else "linked",
        if (box3d.base.isDoublePrecision()) "yes" else "no",
    });

    const world = try box3d.world.create(.{});

    const ground = try box3d.body.create(world, .{ .position = ground_centre });
    const ground_hull = box3d.shape.boxHull(ground_half.x, ground_half.y, ground_half.z);
    _ = try box3d.shape.createHull(ground, .{}, &ground_hull.base);

    const cube = try box3d.body.create(world, .{
        .bodyType = box3d.dynamicBody,
        .position = cube_drop,
    });
    const cube_hull = box3d.shape.cubeHull(cube_half);
    const cube_shape = try box3d.shape.createHull(cube, .{
        .density = 1.0,
    }, &cube_hull.base);

    try checkFloat(w, "cube mass (kg)", cube_volume, box3d.body.mass(cube), 0.001);
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
    try checkFloat(w, "resting tilt about x", 0.0, rotation.v.x, rest_tolerance);
    try checkFloat(w, "resting tilt about z", 0.0, rotation.v.z, rest_tolerance);

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

    for (0..300) |_| box3d.world.step(world, time_step, sub_steps);
    try w.print("\nafter {d} more steps\n", .{@as(u32, @intCast(300))});
    try w.print("  awake bodies: {d}\n", .{box3d.world.awakeBodyCount(world)});
    try w.print("  cube awake: {s}\n", .{if (box3d.body.isAwake(cube)) "yes" else "no"});
    try w.print("  bytes Box3D has allocated: {d}\n", .{box3d.base.allocatedByteCount()});

    box3d.world.destroy(world);
    try w.print("\nevery checked answer matched the scene's geometry\n", .{});
    try w.flush();
}

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

fn expectHit(ok: bool) SmokeError!void {
    if (!ok) {
        std.debug.print("smoke: a ray cast that was expected to hit did not\n", .{});
        return error.SmokeCheckFailed;
    }
}

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
