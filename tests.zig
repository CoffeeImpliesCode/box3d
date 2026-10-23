// SPDX-License-Identifier: MIT
//
//! Geometry-derived tests for the Box3D facade.

const std = @import("std");
const box3d = @import("box3d");
const testing = std.testing;

const provider_variable = "BOX3D_TEST_PROVIDER";

fn nativeReady() void {
    if (comptime !box3d.runtime_loaded) return;
    if (box3d.loadedSource() != null) return;

    var buffer: [4096]u8 = undefined;
    const value = testing.environ.getAlloc(testing.allocator, provider_variable) catch
        missingProvider();
    defer testing.allocator.free(value);
    if (value.len == 0 or value.len > buffer.len) missingProvider();
    @memcpy(buffer[0..value.len], value);
    box3d.load(.{ .path = buffer[0..value.len] }) catch |err| {
        std.debug.print(
            "tests.zig: loading " ++ provider_variable ++ " = \"{s}\" failed: {t}\n",
            .{ buffer[0..value.len], err },
        );
        @panic("tests.zig: the provider named by " ++ provider_variable ++
            " did not load; nothing below this line ran");
    };
}

fn missingProvider() noreturn {
    @panic(
        "tests.zig: this is a runtime-loading build and " ++ provider_variable ++
            " is not set. Point it at a shared object exporting the entry points of " ++
            "include/box3d/box3d.h, for example the one `zig build " ++
            "-Dlinkage=dynamic --prefix <dir>` installs, and export it for the whole " ++
            "`zig build` invocation: the build cannot inject a path into a run " ++
            "step's environment.",
    );
}

const ground_half: box3d.Vec3 = .{ .x = 50, .y = 10, .z = 50 };
const ground_centre: box3d.Pos = .{ .x = 0, .y = -10, .z = 0 };
const cube_half: f32 = 1;
const cube_drop: box3d.Pos = .{ .x = 0, .y = 4, .z = 0 };
const time_step: f32 = 1.0 / 60.0;
const sub_steps: c_int = 4;
const cube_side: f32 = 2 * cube_half;
const cube_volume: f32 = cube_side * cube_side * cube_side;
const cube_mass: f32 = cube_volume;
const cube_inertia: f32 = cube_mass * (2 * cube_side * cube_side) / 12;

const Scene = struct {
    world: box3d.WorldId,
    ground: box3d.BodyId,
    ground_shape: box3d.ShapeId,
    cube: box3d.BodyId,
    cube_shape: box3d.ShapeId,

    fn deinit(self: Scene) void {
        box3d.world.destroy(self.world);
    }

    fn step(self: Scene, steps: usize) void {
        for (0..steps) |_| box3d.world.step(self.world, time_step, sub_steps);
    }
};

fn buildScene(cube_density: ?f32) !Scene {
    const world = try box3d.world.create(.{});
    errdefer box3d.world.destroy(world);

    const ground = try box3d.body.create(world, .{ .position = ground_centre });
    const ground_hull = box3d.shape.boxHull(ground_half.x, ground_half.y, ground_half.z);
    const ground_shape = try box3d.shape.createHull(ground, .{}, &ground_hull.base);

    const cube = try box3d.body.create(world, .{
        .bodyType = box3d.dynamicBody,
        .position = cube_drop,
    });
    var cube_shape: box3d.ShapeId = .{ .index1 = 0, .world0 = 0, .generation = 0 };
    if (cube_density) |density| {
        const cube_hull = box3d.shape.cubeHull(cube_half);
        cube_shape = try box3d.shape.createHull(cube, .{ .density = density }, &cube_hull.base);
    }
    return .{
        .world = world,
        .ground = ground,
        .ground_shape = ground_shape,
        .cube = cube,
        .cube_shape = cube_shape,
    };
}

test "a cube dropped straight down rests exactly one half-extent above the ground" {
    nativeReady();
    const scene = try buildScene(1.0);
    defer scene.deinit();

    scene.step(90);

    const resting = box3d.body.position(scene.cube);

    const expected_height = ground_centre.y + ground_half.y + cube_half;
    try testing.expectApproxEqAbs(expected_height, resting.y, 0.01);
    const rotation = box3d.body.rotation(scene.cube);
    try testing.expectApproxEqAbs(0.0, rotation.v.x, 0.01);
    try testing.expectApproxEqAbs(0.0, rotation.v.z, 0.01);
}

test "a cube at rest stops moving and then falls asleep" {
    nativeReady();
    const scene = try buildScene(1.0);
    defer scene.deinit();

    scene.step(1);
    try testing.expect(box3d.body.isAwake(scene.cube));
    const falling = box3d.body.position(scene.cube);
    try testing.expect(falling.y < cube_drop.y);
    try testing.expect(box3d.math.length(box3d.body.linearVelocity(scene.cube)) > 0.0);

    scene.step(400);
    const settled = box3d.body.position(scene.cube);
    try testing.expectApproxEqAbs(ground_centre.y + ground_half.y + cube_half, settled.y, 0.01);
    try testing.expectApproxEqAbs(
        0.0,
        box3d.math.length(box3d.body.linearVelocity(scene.cube)),
        0.05,
    );
    try testing.expectApproxEqAbs(
        0.0,
        box3d.math.length(box3d.body.angularVelocity(scene.cube)),
        0.05,
    );
    try testing.expect(!box3d.body.isAwake(scene.cube));
    try testing.expectEqual(0, box3d.world.awakeBodyCount(scene.world));
}

test "the same scene stepped the same way lands in the same state" {
    nativeReady();

    const first = try buildScene(1.0);
    defer first.deinit();
    first.step(60);

    const second = try buildScene(1.0);
    defer second.deinit();
    second.step(60);

    const first_hash = stateHash(first.cube);
    const second_hash = stateHash(second.cube);
    try testing.expectEqual(first_hash, second_hash);

    try testing.expectEqual(
        box3d.body.position(first.cube).y,
        box3d.body.position(second.cube).y,
    );
    try testing.expectEqual(
        box3d.body.rotation(first.cube).s,
        box3d.body.rotation(second.cube).s,
    );
}

fn stateHash(id: box3d.BodyId) u32 {
    const position = box3d.body.position(id);
    const rotation = box3d.body.rotation(id);
    const velocity = box3d.body.linearVelocity(id);

    var hash = box3d.base.hashInit;
    hash = box3d.base.hash(hash, std.mem.asBytes(&position));
    hash = box3d.base.hash(hash, std.mem.asBytes(&rotation));
    hash = box3d.base.hash(hash, std.mem.asBytes(&velocity));
    return hash;
}

test "a cube's mass is its own volume times its density, and its inertia follows from that" {
    nativeReady();
    const scene = try buildScene(1.0);
    defer scene.deinit();

    try testing.expectApproxEqAbs(cube_mass, box3d.body.mass(scene.cube), 0.001);

    const inertia = box3d.body.localRotationalInertia(scene.cube);
    try testing.expectApproxEqAbs(cube_inertia, inertia.cx.x, 0.001);
    try testing.expectApproxEqAbs(cube_inertia, inertia.cy.y, 0.001);
    try testing.expectApproxEqAbs(cube_inertia, inertia.cz.z, 0.001);
    try testing.expectApproxEqAbs(0.0, inertia.cx.y, 0.001);
    try testing.expectApproxEqAbs(0.0, inertia.cx.z, 0.001);
    try testing.expectApproxEqAbs(0.0, inertia.cy.x, 0.001);
    try testing.expectApproxEqAbs(0.0, inertia.cy.z, 0.001);
    try testing.expectApproxEqAbs(0.0, inertia.cz.x, 0.001);
    try testing.expectApproxEqAbs(0.0, inertia.cz.y, 0.001);

    const centre = box3d.body.localCenterOfMass(scene.cube);
    try testing.expectApproxEqAbs(0.0, centre.x, 0.001);
    try testing.expectApproxEqAbs(0.0, centre.y, 0.001);
    try testing.expectApproxEqAbs(0.0, centre.z, 0.001);

    try testing.expectEqual(box3d.staticBody, box3d.body.getType(scene.ground));
    try testing.expectApproxEqAbs(0.0, box3d.body.mass(scene.ground), 0.0);
    try testing.expectApproxEqAbs(0.0, box3d.body.inverseMass(scene.ground), 0.0);
}

test "a dynamic body with no shape has no mass and does not fall" {
    nativeReady();
    const scene = try buildScene(null);
    defer scene.deinit();

    try testing.expectApproxEqAbs(0.0, box3d.body.mass(scene.cube), 0.0);
    scene.step(60);
    const held = box3d.body.position(scene.cube);
    try testing.expectApproxEqAbs(cube_drop.y, held.y, 0.01);
    try testing.expectApproxEqAbs(cube_drop.x, held.x, 0.01);
    try testing.expectApproxEqAbs(cube_drop.z, held.z, 0.01);
}

test "a downward ray meets the surfaces the scene geometry puts in its path" {
    nativeReady();
    const scene = try buildScene(1.0);
    defer scene.deinit();
    const filter = (box3d.QueryFilterDef{}).native();

    var hit: box3d.RayResult = undefined;
    try testing.expect(box3d.query.castRayClosestShape(
        scene.world,
        .{ .x = 0, .y = 10, .z = 0 },
        .{ .x = 0, .y = -20, .z = 0 },
        filter,
        &hit,
    ));
    try testing.expectEqual(scene.cube_shape, hit.shapeId);
    try testing.expectApproxEqAbs(0.25, hit.fraction, 0.0001);
    try testing.expectApproxEqAbs(cube_drop.y + cube_half, hit.point.y, 0.001);
    try testing.expectApproxEqAbs(1.0, hit.normal.y, 0.001);

    try testing.expect(box3d.query.castRayClosestShape(
        scene.world,
        .{ .x = 5, .y = 10, .z = 5 },
        .{ .x = 0, .y = -20, .z = 0 },
        filter,
        &hit,
    ));
    try testing.expectEqual(scene.ground_shape, hit.shapeId);
    try testing.expectApproxEqAbs(0.5, hit.fraction, 0.0001);
    try testing.expectApproxEqAbs(ground_centre.y + ground_half.y, hit.point.y, 0.001);
    try testing.expectApproxEqAbs(1.0, hit.normal.y, 0.001);
}

test "a ray that points away from the scene hits nothing" {
    nativeReady();
    const scene = try buildScene(1.0);
    defer scene.deinit();
    const filter = (box3d.QueryFilterDef{}).native();

    var hit: box3d.RayResult = undefined;
    const missed = box3d.query.castRayClosestShape(
        scene.world,
        .{ .x = 0, .y = -30, .z = 0 },
        .{ .x = 0, .y = -20, .z = 0 },
        filter,
        &hit,
    );
    try testing.expect(!missed);

    try testing.expect(!box3d.query.castRayClosestShape(
        scene.world,
        .{ .x = 5, .y = 1, .z = 5 },
        .{ .x = -20, .y = 0, .z = 0 },
        filter,
        &hit,
    ));
}

test "a shape cast reports all hits when the output slice cannot hold them" {
    nativeReady();
    const world = try box3d.world.create(.{});
    defer box3d.world.destroy(world);

    var shapes: [4]box3d.ShapeId = undefined;
    for (&shapes, 0..) |*shape, i| {
        const x: f32 = 2.0 * @as(f32, @floatFromInt(i));
        const body = try box3d.body.create(world, .{ .position = .{ .x = x, .y = 0, .z = 0 } });
        const hull = box3d.shape.boxHull(0.5, 2, 2);
        shape.* = try box3d.shape.createHull(body, .{}, &hull.base);
    }

    const centre: box3d.Vec3 = .{ .x = 0, .y = 0, .z = 0 };
    const proxy: box3d.ShapeProxy = .{ .points = &centre, .count = 1, .radius = 0.5 };
    const filter = (box3d.QueryFilterDef{}).native();
    const start: box3d.Pos = .{ .x = -10, .y = 0, .z = 0 };
    const travel: box3d.Vec3 = .{ .x = 20, .y = 0, .z = 0 };

    try testing.expectEqual(4, box3d.query.castShapeCollect(world, start, &proxy, travel, filter, &.{}));

    var out: [3]box3d.ShapeId = @splat(shapes[3]);
    try testing.expectEqual(4, box3d.query.castShapeCollect(world, start, &proxy, travel, filter, out[0..2]));
    try testing.expect(box3d.shape.isValid(out[0]));
    try testing.expect(box3d.shape.isValid(out[1]));
    try testing.expect(!std.meta.eql(out[0], out[1]));
    try testing.expect(std.meta.eql(out[2], shapes[3]));
    for (out[0..2]) |hit| {
        var belongs_to_scene = false;
        for (shapes) |shape| belongs_to_scene = belongs_to_scene or std.meta.eql(hit, shape);
        try testing.expect(belongs_to_scene);
    }
}

test "an overlap query finds exactly the shapes the scene puts inside its box" {
    nativeReady();
    const scene = try buildScene(1.0);
    defer scene.deinit();
    const filter = (box3d.QueryFilterDef{}).native();

    var found: [8]box3d.ShapeId = undefined;

    const gap = box3d.math.makeAabb(
        &[_]box3d.Vec3{
            .{ .x = 1.5, .y = 1.0, .z = 1.5 },
            .{ .x = 2.5, .y = 2.0, .z = 2.5 },
        },
        2,
        0,
    );
    try testing.expectEqual(0, box3d.query.overlapAabbCollect(scene.world, gap, filter, &found));

    const ground_only = box3d.math.makeAabb(
        &[_]box3d.Vec3{
            .{ .x = 1.5, .y = -2.0, .z = 1.5 },
            .{ .x = 2.5, .y = -1.0, .z = 2.5 },
        },
        2,
        0,
    );
    const ground_only_count = box3d.query.overlapAabbCollect(scene.world, ground_only, filter, &found);
    try testing.expectEqual(1, ground_only_count);
    try testing.expectEqual(scene.ground_shape, found[0]);

    const both = box3d.math.makeAabb(
        &[_]box3d.Vec3{
            .{ .x = -1.0, .y = -1.0, .z = -1.0 },
            .{ .x = 1.0, .y = 5.0, .z = 1.0 },
        },
        2,
        0,
    );
    const both_count = box3d.query.overlapAabbCollect(scene.world, both, filter, &found);
    try testing.expectEqual(2, both_count);
    var saw_cube = false;
    var saw_ground = false;
    for (found[0..both_count]) |shape| {
        if (shape.index1 == scene.cube_shape.index1) saw_cube = true;
        if (shape.index1 == scene.ground_shape.index1) saw_ground = true;
    }
    try testing.expect(saw_cube and saw_ground);

    const above = box3d.math.makeAabb(
        &[_]box3d.Vec3{
            .{ .x = -1.0, .y = 100.0, .z = -1.0 },
            .{ .x = 1.0, .y = 101.0, .z = 1.0 },
        },
        2,
        0,
    );
    try testing.expectEqual(0, box3d.query.overlapAabbCollect(scene.world, above, filter, &.{}));

    const overflow = box3d.query.overlapAabbCollect(scene.world, both, filter, found[0..1]);
    try testing.expectEqual(2, overflow);
}

test "a body that moves reports a move event naming it" {
    nativeReady();
    const scene = try buildScene(1.0);
    defer scene.deinit();

    scene.step(1);

    const moves = box3d.world.bodyMoveEvents(scene.world);
    try testing.expect(moves.len >= 1);

    var named_cube = false;
    for (moves) |move| {
        if (move.bodyId.index1 == scene.cube.index1 and
            move.bodyId.world0 == scene.cube.world0)
        {
            named_cube = true;
            const direct = box3d.body.position(scene.cube);
            try testing.expectApproxEqAbs(direct.y, move.transform.p.y, 0.001);
        }
    }
    try testing.expect(named_cube);

    for (moves) |move| {
        try testing.expect(move.bodyId.index1 != scene.ground.index1);
    }
}

test "a bouncing sphere reports one begin-touch and one end-touch event" {
    nativeReady();

    const world = try box3d.world.create(.{});
    defer box3d.world.destroy(world);

    const ground = try box3d.body.create(world, .{ .position = .{ .x = 0, .y = -0.5, .z = 0 } });
    const ground_hull = box3d.shape.boxHull(10, 0.5, 10);
    const ground_shape = try box3d.shape.createHull(ground, .{}, &ground_hull.base);

    const ball = try box3d.body.create(world, .{
        .bodyType = box3d.dynamicBody,
        .position = .{ .x = 0, .y = 5, .z = 0 },
    });
    const ball_shape = try box3d.shape.createSphere(ball, .{
        .density = 1.0,
        .enableContactEvents = true,
        .baseMaterial = .{ .restitution = 0.6 },
    }, box3d.shape.sphere(0.5));

    var begins: usize = 0;
    var ends: usize = 0;
    var ids_checked = false;
    for (0..120) |_| {
        box3d.world.step(world, time_step, sub_steps);

        const entering = box3d.world.contactBeginEvents(world);
        begins += entering.len;
        for (entering) |event| {
            if (ids_checked) continue;
            const pairs_ground_and_ball =
                (sameShape(event.shapeIdA, ground_shape) and sameShape(event.shapeIdB, ball_shape)) or
                (sameShape(event.shapeIdB, ground_shape) and sameShape(event.shapeIdA, ball_shape));
            try testing.expect(pairs_ground_and_ball);
            try testing.expect(box3d.c.b3Contact_IsValid(event.contactId));
            ids_checked = true;
        }
        ends += box3d.world.contactEndEvents(world).len;
    }

    try testing.expect(ids_checked);
    try testing.expectEqual(1, begins);
    try testing.expectEqual(1, ends);
}

fn sameShape(a: box3d.ShapeId, b: box3d.ShapeId) bool {
    return a.index1 == b.index1 and a.world0 == b.world0 and a.generation == b.generation;
}

test "a sensor sphere crossing a static box reports one entry and one exit" {
    nativeReady();

    const world = try box3d.world.create(.{});
    defer box3d.world.destroy(world);

    const wall = try box3d.body.create(world, .{ .position = .{ .x = 0, .y = 10, .z = 0 } });
    const wall_hull = box3d.shape.boxHull(1, 10, 1);
    const wall_shape = try box3d.shape.createHull(wall, .{
        .enableSensorEvents = true,
    }, &wall_hull.base);

    const probe = try box3d.body.create(world, .{
        .bodyType = box3d.dynamicBody,
        .gravityScale = 0,
        .position = .{ .x = 5, .y = 10, .z = 0 },
        .linearVelocity = .{ .x = -10, .y = 0, .z = 0 },
    });
    const probe_shape = try box3d.shape.createSphere(probe, .{
        .density = 1.0,
        .isSensor = true,
        .enableSensorEvents = true,
    }, box3d.shape.sphere(0.5));
    try testing.expect(box3d.shape.isSensor(probe_shape));

    var begins: usize = 0;
    var ends: usize = 0;
    var ids_checked = false;
    for (0..300) |_| {
        box3d.world.step(world, time_step, sub_steps);

        const entering = box3d.world.sensorBeginEvents(world);
        begins += entering.len;
        for (entering) |event| {
            if (ids_checked) continue;
            const pairs_wall_and_probe =
                (sameShape(event.sensorShapeId, probe_shape) and sameShape(event.visitorShapeId, wall_shape)) or
                (sameShape(event.sensorShapeId, wall_shape) and sameShape(event.visitorShapeId, probe_shape));
            try testing.expect(pairs_wall_and_probe);
            ids_checked = true;
        }
        ends += box3d.world.sensorEndEvents(world).len;

        if (box3d.body.position(probe).x < -5) break;
    }

    try testing.expect(ids_checked);
    try testing.expectEqual(1, begins);
    try testing.expectEqual(1, ends);
    try testing.expectEqual(0, box3d.shape.sensorCapacity(probe_shape));
}

test "destroying a world invalidates every id inside it" {
    nativeReady();
    const scene = try buildScene(1.0);

    try testing.expect(box3d.world.isValid(scene.world));
    try testing.expect(box3d.body.isValid(scene.ground));
    try testing.expect(box3d.body.isValid(scene.cube));
    try testing.expect(box3d.shape.isValid(scene.ground_shape));
    try testing.expect(box3d.shape.isValid(scene.cube_shape));

    scene.deinit();

    try testing.expect(!box3d.world.isValid(scene.world));
    try testing.expect(!box3d.body.isValid(scene.ground));
    try testing.expect(!box3d.body.isValid(scene.cube));
    try testing.expect(!box3d.shape.isValid(scene.ground_shape));
    try testing.expect(!box3d.shape.isValid(scene.cube_shape));
}

test "destroying a body invalidates its shapes and leaves other bodies alone" {
    nativeReady();
    const world = try box3d.world.create(.{});
    defer box3d.world.destroy(world);

    const ground = try box3d.body.create(world, .{ .position = ground_centre });
    const ground_hull = box3d.shape.boxHull(ground_half.x, ground_half.y, ground_half.z);
    const ground_shape = try box3d.shape.createHull(ground, .{}, &ground_hull.base);

    const crate = try box3d.body.create(world, .{
        .bodyType = box3d.dynamicBody,
        .position = cube_drop,
    });
    const crate_hull = box3d.shape.cubeHull(cube_half);
    const crate_shape = try box3d.shape.createHull(crate, .{ .density = 1.0 }, &crate_hull.base);

    try testing.expectEqual(1, box3d.body.shapeCount(ground));
    try testing.expectEqual(1, box3d.body.shapeCount(crate));

    box3d.body.destroy(crate);

    try testing.expect(!box3d.body.isValid(crate));
    try testing.expect(!box3d.shape.isValid(crate_shape));

    try testing.expect(box3d.body.isValid(ground));
    try testing.expect(box3d.shape.isValid(ground_shape));
    try testing.expectEqual(1, box3d.body.shapeCount(ground));

    box3d.world.step(world, time_step, sub_steps);
    try testing.expectApproxEqAbs(
        ground_centre.y,
        box3d.body.position(ground).y,
        0.001,
    );
}

test "destroying a shape removes it from its body's shape list" {
    nativeReady();
    const world = try box3d.world.create(.{});
    defer box3d.world.destroy(world);

    const body_id = try box3d.body.create(world, .{ .position = ground_centre });
    const first_hull = box3d.shape.boxHull(1, 1, 1);
    const second_hull = box3d.shape.boxHull(2, 2, 2);
    _ = try box3d.shape.createHull(body_id, .{}, &first_hull.base);
    const second = try box3d.shape.createHull(body_id, .{}, &second_hull.base);
    try testing.expectEqual(2, box3d.body.shapeCount(body_id));

    var shapes: [4]box3d.ShapeId = undefined;
    try testing.expectEqual(2, box3d.body.shapes(body_id, &shapes));

    box3d.shape.destroy(second, true);

    try testing.expect(!box3d.shape.isValid(second));
    try testing.expectEqual(1, box3d.body.shapeCount(body_id));
    try testing.expect(box3d.body.isValid(body_id));

    const written = box3d.body.shapes(body_id, &shapes);
    try testing.expectEqual(1, written);
    try testing.expect(box3d.shape.isValid(shapes[0]));
    try testing.expect(shapes[0].index1 != second.index1);
}

test "creating a body in a world that is gone is an error, not a null id" {
    nativeReady();
    const scene = try buildScene(1.0);

    scene.deinit();

    try testing.expectError(
        error.InvalidWorld,
        box3d.body.create(scene.world, .{}),
    );
}

test "creating a shape on a body that is gone is an error" {
    nativeReady();
    const scene = try buildScene(1.0);

    box3d.body.destroy(scene.cube);
    try testing.expect(!box3d.body.isValid(scene.cube));
    defer scene.deinit();

    try testing.expectError(
        error.ShapeCreationFailed,
        box3d.shape.createSphere(scene.cube, .{}, box3d.shape.sphere(1)),
    );
}

test "creating a joint in a world that is gone is an error" {
    nativeReady();
    const first = try buildScene(1.0);
    defer first.deinit();

    const second = try buildScene(1.0);
    second.deinit();

    const distance = box3d.DistanceJointDef{
        .base = .{
            .bodyIdA = first.ground,
            .bodyIdB = first.cube,
        },
        .length = 2,
    };
    try testing.expectError(
        error.InvalidWorld,
        box3d.joint.createDistance(second.world, distance),
    );
}

test "a matching negative group stops two shapes that would otherwise collide" {
    nativeReady();

    const blocked = try buildFilteredScene(-1);
    defer blocked.scene.deinit();
    const allowed = try buildFilteredScene(0);
    defer allowed.scene.deinit();

    blocked.scene.step(120);
    allowed.scene.step(120);

    const resting_height = ground_centre.y + ground_half.y + cube_half;

    try testing.expectApproxEqAbs(
        resting_height,
        box3d.body.position(allowed.scene.cube).y,
        0.01,
    );

    const fallen_y = box3d.body.position(blocked.scene.cube).y;
    try testing.expect(fallen_y < resting_height - 1.0);
}

fn buildFilteredScene(group_index: c_int) !struct { scene: Scene } {
    const world = try box3d.world.create(.{});
    errdefer box3d.world.destroy(world);

    var filter = box3d.c.b3DefaultFilter();
    filter.groupIndex = group_index;

    const ground = try box3d.body.create(world, .{ .position = ground_centre });
    const ground_hull = box3d.shape.boxHull(ground_half.x, ground_half.y, ground_half.z);
    const ground_shape = try box3d.shape.createHull(ground, .{ .filter = filter }, &ground_hull.base);

    const cube = try box3d.body.create(world, .{
        .bodyType = box3d.dynamicBody,
        .position = cube_drop,
    });
    const cube_hull = box3d.shape.cubeHull(cube_half);
    const cube_shape = try box3d.shape.createHull(cube, .{
        .density = 1.0,
        .filter = filter,
    }, &cube_hull.base);

    return .{ .scene = .{
        .world = world,
        .ground = ground,
        .ground_shape = ground_shape,
        .cube = cube,
        .cube_shape = cube_shape,
    } };
}
