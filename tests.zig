// SPDX-License-Identifier: MIT
//
//! Behavioural tests for the Box3D facade.
//!
//! ## Where the expected answers come from
//!
//! Every number here is derived from the geometry of the scene the test builds,
//! not copied from what Box3D produced when someone ran it. The scene is the one
//! in upstream's own `HelloWorld` (`test/test_world.c:21-101`) - a ground box
//! and a unit cube - because it is small enough to reason about exactly:
//!
//!   * the ground is a box with half-extents (50, 10, 50) whose centre is at
//!     y = -10, so its top face is at y = 0 and its bottom at y = -20;
//!   * the cube is a box with half-extent 1, so while it is falling its AABB is
//!     exactly x, y, z in [-1, 1] around its centre;
//!   * therefore a ray cast straight down from (0, 10, 0) by 20 units must meet
//!     the cube's top face at y = 5, five of those 20 units along, so the
//!     fraction is 0.25; and a ray from (5, 10, 5) by the same 20 units, which
//!     misses the cube entirely, must meet the ground's top face at y = 0, ten
//!     units along, so 0.5;
//!   * therefore a cube that comes to rest must come to rest with its centre at
//!     y = 1, one half-extent above the ground's top face, and with no tilt
//!     about x or z, which is exactly what upstream's own fixture checks for
//!     this scene (`test/test_world.c:96-98`). How far the solver lets the cube
//!     drift sideways, or yaw it by, while settling is not something the
//!     geometry determines, so nothing here asks it to;
//!   * a cube of half-extent 1 and density 1 kg/m^3 has volume 8 m^3, so it has
//!     mass 8 kg and a diagonal inertia of m * s^2 / 6 = 8 * 4 / 6;
//!   * so a query box in the band above the ground's top face and outside the
//!     cube's footprint overlaps neither shape and must find nothing, while one
//!     just below the top face lies in the ground's extent alone and must find
//!     exactly the ground.
//!
//! Nothing here pins a version string, a default constant, an export's presence
//! or a forwarding accessor. The tests that do run twice and compare, and the
//! tests that destroy something and check the ids went stale, are about
//! behaviour Box3D promises.
//!
//! ## Precision
//! The scene and the assertions are written against `Pos` and the lengths
//! upstream's defaults use, so they hold in either precision mode. The numeric
//! tolerances are the ones upstream's own test of this scene uses
//! (`test/test_world.c:96-98`), which is also the whole of what that test says
//! about the cube's resting state.

const std = @import("std");
const box3d = @import("box3d");
const testing = std.testing;

/// A shared object exporting the `b3*` entry points of `box3d/box3d.h`, named
/// by the environment in a runtime-loading build.
const provider_variable = "BOX3D_TEST_PROVIDER";

/// Make the native library usable, once, before a test calls the facade.
///
/// In a linked build the facade is usable already and this is a no-op at
/// comptime. In a runtime-loading build every call into the module goes through a
/// table that `load` fills, so this is where the one explicit load happens. It is
/// safe to call from every test: the contract makes the same request idempotent,
/// and the loader keeps the handle to the end of the process.
///
/// A build that was not told which file to load stops here with the variable's
/// name, rather than reporting a test failure that says nothing about the reason.
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

// -- the shared scene --------------------------------------------------------

/// The half-extents of the ground box. Its centre is at y = -10, so the top face
/// is at y = 0 and the bottom at y = -20.
const ground_half: box3d.Vec3 = .{ .x = 50, .y = 10, .z = 50 };
/// Where the ground box sits, so that its top face lands on y = 0.
const ground_centre: box3d.Pos = .{ .x = 0, .y = -10, .z = 0 };
/// Half-extent of the dropped cube. A unit cube's AABB is its centre plus and
/// minus 1 on each axis.
const cube_half: f32 = 1;
/// Where the cube starts.
const cube_drop: box3d.Pos = .{ .x = 0, .y = 4, .z = 0 };
/// The step upstream's scene uses.
const time_step: f32 = 1.0 / 60.0;
/// The sub-step count upstream's scene uses.
const sub_steps: c_int = 4;

/// A cube's side length: twice its half-extent.
const cube_side: f32 = 2 * cube_half;
/// The cube's volume in cubic units.
const cube_volume: f32 = cube_side * cube_side * cube_side;
/// The cube's mass at density 1.
const cube_mass: f32 = cube_volume;
/// A solid cube's inertia about each axis through its centre:
/// `m * (width^2 + height^2) / 12`, and the two non-diagonal axes are equal, so
/// for a cube of side `s` that is `m * 2 * s^2 / 12`.
const cube_inertia: f32 = cube_mass * (2 * cube_side * cube_side) / 12;

/// One scene: a world, a ground body with a box shape on it, and a cube body
/// with a box shape on it.
const Scene = struct {
    world: box3d.WorldId,
    ground: box3d.BodyId,
    ground_shape: box3d.ShapeId,
    cube: box3d.BodyId,
    cube_shape: box3d.ShapeId,

    fn deinit(self: Scene) void {
        box3d.world.destroy(self.world);
    }

    /// Step the scene `steps` times.
    fn step(self: Scene, steps: usize) void {
        for (0..steps) |_| box3d.world.step(self.world, time_step, sub_steps);
    }
};

/// Build the shared scene.
///
/// `cube_density` of null leaves the cube with no shape at all, which is how a
/// test asks what a dynamic body with no geometry does.
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

// -- the physical fixture ----------------------------------------------------

test "a cube dropped straight down rests exactly one half-extent above the ground" {
    nativeReady();
    const scene = try buildScene(1.0);
    defer scene.deinit();

    // Upstream's scene runs 90 steps; that is 1.5 seconds, long enough for a
    // 3 m fall to land and settle.
    scene.step(90);

    const resting = box3d.body.position(scene.cube);

    // The ground's top face is at y = 0 and the cube's half-extent is 1, so the
    // answer is 1. It is written as the geometry rather than as the number,
    // because that is what makes this a known answer and not a restatement.
    const expected_height = ground_centre.y + ground_half.y + cube_half;
    try testing.expectApproxEqAbs(expected_height, resting.y, 0.01);

    // The cube's lateral position and its yaw are not checked, and that is
    // deliberate: a cube dropped onto a flat face lands flat, but how far the
    // solver carries it sideways while settling is its own business, and
    // upstream's fixture for this scene checks neither, in
    // `test/test_world.c:96-98`. Pinning them would pin the solver rather than
    // the geometry.

    const rotation = box3d.body.rotation(scene.cube);
    // A quaternion's vector part is its rotation axis times the sine of half the
    // angle, so a cube that landed flat has nothing in the components for tilt
    // about x or about z.
    try testing.expectApproxEqAbs(0.0, rotation.v.x, 0.01);
    try testing.expectApproxEqAbs(0.0, rotation.v.z, 0.01);
}

test "a cube at rest stops moving and then falls asleep" {
    nativeReady();
    const scene = try buildScene(1.0);
    defer scene.deinit();

    // While it is falling the cube is awake and moving.
    scene.step(1);
    try testing.expect(box3d.body.isAwake(scene.cube));
    const falling = box3d.body.position(scene.cube);
    try testing.expect(falling.y < cube_drop.y);
    try testing.expect(box3d.math.length(box3d.body.linearVelocity(scene.cube)) > 0.0);

    // Long enough for the fall, the settling and then `B3_TIME_TO_SLEEP`
    // (0.5 s, include/box3d/constants.h:97-98) of stillness. Upstream's own
    // drop test allows 400 steps before calling a resting scene asleep
    // (test/test_world.c:676-698).
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
    // The ground never wakes, so the whole world is asleep.
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

    // Box3D's own djb2 over the simulation state, which is what upstream uses to
    // compare runs for determinism (include/box3d/base.h:185-187). Two runs of
    // the same scene in the same build must agree bit for bit; a solver whose
    // state depended on anything else would not.
    const first_hash = stateHash(first.cube);
    const second_hash = stateHash(second.cube);
    try testing.expectEqual(first_hash, second_hash);

    // And the geometry is checked separately, so a hash collision that happened
    // to agree would still have to agree on the position.
    try testing.expectEqual(
        box3d.body.position(first.cube).y,
        box3d.body.position(second.cube).y,
    );
    try testing.expectEqual(
        box3d.body.rotation(first.cube).s,
        box3d.body.rotation(second.cube).s,
    );
}

/// Box3D's own hash over a body's position, rotation and linear velocity.
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

    // Half-extent 1 on each axis, so a side of 2, so 8 cubic units. Density 1, so
    // 8 kg. The ground body is static and contributes nothing.
    try testing.expectApproxEqAbs(cube_mass, box3d.body.mass(scene.cube), 0.001);

    const inertia = box3d.body.localRotationalInertia(scene.cube);
    try testing.expectApproxEqAbs(cube_inertia, inertia.cx.x, 0.001);
    try testing.expectApproxEqAbs(cube_inertia, inertia.cy.y, 0.001);
    try testing.expectApproxEqAbs(cube_inertia, inertia.cz.z, 0.001);
    // A cube centred on its own origin has no off-diagonal inertia term.
    try testing.expectApproxEqAbs(0.0, inertia.cx.y, 0.001);
    try testing.expectApproxEqAbs(0.0, inertia.cx.z, 0.001);
    try testing.expectApproxEqAbs(0.0, inertia.cy.x, 0.001);
    try testing.expectApproxEqAbs(0.0, inertia.cy.z, 0.001);
    try testing.expectApproxEqAbs(0.0, inertia.cz.x, 0.001);
    try testing.expectApproxEqAbs(0.0, inertia.cz.y, 0.001);

    // A body's centre of mass is its centre only while the geometry is symmetric
    // about it, which a single centred cube is.
    const centre = box3d.body.localCenterOfMass(scene.cube);
    try testing.expectApproxEqAbs(0.0, centre.x, 0.001);
    try testing.expectApproxEqAbs(0.0, centre.y, 0.001);
    try testing.expectApproxEqAbs(0.0, centre.z, 0.001);

    // The static ground, whose shape has default density, is still static: mass
    // is only meaningful for a body the solver has to move.
    try testing.expectEqual(box3d.staticBody, box3d.body.getType(scene.ground));
    // A static body's mass is zero, and its inverse mass is zero too, because
    // the mass update returns before the dynamic case for a static body
    // (src/body.c:820-821).
    try testing.expectApproxEqAbs(0.0, box3d.body.mass(scene.ground), 0.0);
    try testing.expectApproxEqAbs(0.0, box3d.body.inverseMass(scene.ground), 0.0);
}

test "a dynamic body with no shape has no mass and does not fall" {
    nativeReady();
    const scene = try buildScene(null);
    defer scene.deinit();

    // A dynamic body whose only mass source is its shapes, and which has none,
    // is a zero-mass dynamic body. Upstream says a dynamic body has positive mass
    // (include/box3d/types.h:232), so this is the boundary of that promise: it
    // is accepted, and it does not move.
    try testing.expectApproxEqAbs(0.0, box3d.body.mass(scene.cube), 0.0);
    scene.step(60);
    const held = box3d.body.position(scene.cube);
    try testing.expectApproxEqAbs(cube_drop.y, held.y, 0.01);
    try testing.expectApproxEqAbs(cube_drop.x, held.x, 0.01);
    try testing.expectApproxEqAbs(cube_drop.z, held.z, 0.01);
}

// -- queries with exact geometric answers ------------------------------------

test "a downward ray meets the surfaces the scene geometry puts in its path" {
    nativeReady();
    const scene = try buildScene(1.0);
    defer scene.deinit();
    const filter = (box3d.QueryFilterDef{}).native();

    // From y = 10 downwards by 20 units. The cube's top face is at
    // 4 + 1 = 5, which is 5 of the 20 units travelled, so the fraction is 0.25.
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

    // From x = z = 5, which is outside the cube's half-extent of 1, the ray
    // misses the cube and meets the ground's top face at y = 0. That is 10 of
    // the 20 units travelled, so the fraction is 0.5.
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
    // Straight down from below the ground's bottom face at y = -20, so the
    // whole ray, from y = -30 to y = -50, is outside the ground.
    const missed = box3d.query.castRayClosestShape(
        scene.world,
        .{ .x = 0, .y = -30, .z = 0 },
        .{ .x = 0, .y = -20, .z = 0 },
        filter,
        &hit,
    );
    try testing.expect(!missed);
    // Upstream's rule is that every other field is invalid when `hit` is false
    // (include/box3d/types.h:1352-1353), so `hit` itself is the only thing to
    // read.

    // Sideways, at a height that is above the ground's top face at y = 0 and
    // below the cube's bottom face at y = 3, out at z = 5 which is well outside
    // the cube's own extent: from x = 5 to x = -15 the ray crosses the whole
    // width of the scene without touching either shape. A ray that started
    // below the ground's top face would be inside the ground instead of
    // outside it, and would report nothing for the other reason:
    // `b3World_CastRayClosest` ignores initial overlap
    // (include/box3d/box3d.h:96). That is not the same answer as this one.
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

    // A box in the band above the ground's top face at y = 0 and below the
    // cube's bottom face at y = 3, at x = z in [1.5, 2.5], which is outside the
    // cube's extent too: it is inside neither shape, so it finds neither.
    const gap = box3d.math.makeAabb(
        &[_]box3d.Vec3{
            .{ .x = 1.5, .y = 1.0, .z = 1.5 },
            .{ .x = 2.5, .y = 2.0, .z = 2.5 },
        },
        2,
        0,
    );
    try testing.expectEqual(0, box3d.query.overlapAabbCollect(scene.world, gap, filter, &found));

    // That same box lowered until it is inside the ground, which spans y in
    // [-20, 0], and still out at x = z in [1.5, 2.5] where the cube is not, is
    // in the ground's extent alone, so it finds exactly the ground.
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

    // A box spanning both bodies finds both shapes.
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

    // A box far above everything finds nothing. A zero-length output slice is
    // how the collect forms answer "how many are there" without allocating.
    const above = box3d.math.makeAabb(
        &[_]box3d.Vec3{
            .{ .x = -1.0, .y = 100.0, .z = -1.0 },
            .{ .x = 1.0, .y = 101.0, .z = 1.0 },
        },
        2,
        0,
    );
    try testing.expectEqual(0, box3d.query.overlapAabbCollect(scene.world, above, filter, &.{}));

    // Too small a slice still reports the true count rather than truncating it,
    // which is what makes the count above a total and not a written count.
    const overflow = box3d.query.overlapAabbCollect(scene.world, both, filter, found[0..1]);
    try testing.expectEqual(2, overflow);
}

// -- events ------------------------------------------------------------------

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
            // The event carries the body's transform, and it has to agree with
            // the body, because that agreement is the whole reason the event
            // exists (include/box3d/types.h:1190-1196).
            const direct = box3d.body.position(scene.cube);
            try testing.expectApproxEqAbs(direct.y, move.transform.p.y, 0.001);
        }
    }
    try testing.expect(named_cube);

    // The static ground did not move, so it is not in the buffer.
    for (moves) |move| {
        try testing.expect(move.bodyId.index1 != scene.ground.index1);
    }
}

test "a bouncing sphere reports one begin-touch and one end-touch event" {
    nativeReady();

    const world = try box3d.world.create(.{});
    defer box3d.world.destroy(world);

    // A static ground slab whose top face is at y = 0, so a sphere of radius
    // 0.5 that comes to rest on it has its centre at y = 0.5.
    const ground = try box3d.body.create(world, .{ .position = .{ .x = 0, .y = -0.5, .z = 0 } });
    const ground_hull = box3d.shape.boxHull(10, 0.5, 10);
    const ground_shape = try box3d.shape.createHull(ground, .{}, &ground_hull.base);

    // A bouncy sphere dropped from 5 m up. The restitution is what produces the
    // end event as well as the begin: a sphere that lands and stays in contact
    // never stops touching.
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
            // The event pairs the two shapes it is about, in whichever order the
            // solver found them, and the contact id it carries must still be
            // live right now (include/box3d/types.h:1102-1103).
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

/// Compare two shape ids the way upstream's `B3_ID_EQUALS` does
/// (`include/box3d/id.h:105`): index, world and generation all together.
fn sameShape(a: box3d.ShapeId, b: box3d.ShapeId) bool {
    return a.index1 == b.index1 and a.world0 == b.world0 and a.generation == b.generation;
}

test "a sensor sphere crossing a static box reports one entry and one exit" {
    nativeReady();

    const world = try box3d.world.create(.{});
    defer box3d.world.destroy(world);

    // A static wall: centre x = 0 with half-width 1, so it spans x in [-1, 1];
    // y from 0 to 20 and z from -1 to 1.
    const wall = try box3d.body.create(world, .{ .position = .{ .x = 0, .y = 10, .z = 0 } });
    const wall_hull = box3d.shape.boxHull(1, 10, 1);
    const wall_shape = try box3d.shape.createHull(wall, .{
        .enableSensorEvents = true,
    }, &wall_hull.base);

    // A sensor sphere fired through it at 10 m/s with gravity turned off, so it
    // crosses the wall exactly once and its only path change is the overlap.
    // `enableSensorEvents` is set on both shapes because upstream documents it
    // as applying to sensors and non-sensors alike
    // (include/box3d/types.h:489-491), and its own fixture sets it on both
    // (test/test_world.c:343,356).
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
    // Ten units of travel at 10 m/s is a second, so 300 steps is twice what the
    // crossing needs and the loop is not the thing under test.
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
    // Having left the wall, the sensor has nothing left to overlap.
    try testing.expectEqual(0, box3d.shape.sensorCapacity(probe_shape));
}

// -- ownership and stale ids -------------------------------------------------

test "destroying a world invalidates every id inside it" {
    nativeReady();
    const scene = try buildScene(1.0);

    try testing.expect(box3d.world.isValid(scene.world));
    try testing.expect(box3d.body.isValid(scene.ground));
    try testing.expect(box3d.body.isValid(scene.cube));
    try testing.expect(box3d.shape.isValid(scene.ground_shape));
    try testing.expect(box3d.shape.isValid(scene.cube_shape));

    scene.deinit();

    // Upstream's own comment above its HelloWorld says a world destructor frees
    // every body and joint and can leave orphaned ids
    // (test/test_world.c:92-94), which is what these five checks are.
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

    // The other body in the same world is untouched.
    try testing.expect(box3d.body.isValid(ground));
    try testing.expect(box3d.shape.isValid(ground_shape));
    try testing.expectEqual(1, box3d.body.shapeCount(ground));

    // And the world still simulates, which is what "untouched" has to mean. A
    // body's position is its own centre, which is the y = -10 the fixture put
    // the ground at; its top face at y = 0 is the ground's surface, not
    // anything `body.position` reports.
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

    // The remaining shape is still the one that was not destroyed.
    const written = box3d.body.shapes(body_id, &shapes);
    try testing.expectEqual(1, written);
    try testing.expect(box3d.shape.isValid(shapes[0]));
    try testing.expect(shapes[0].index1 != second.index1);
}

// -- error transitions -------------------------------------------------------

test "creating a body in a world that is gone is an error, not a null id" {
    nativeReady();
    const scene = try buildScene(1.0);

    // The world is gone, so nothing inside it is a live world any more. The
    // facade answers `error.InvalidWorld` for that, and asking upstream for the
    // body anyway is not an option: `b3CreateBody` resolves the world id with
    // `b3GetUnlockedWorldFromId` (src/body.c:169), which asserts on the id
    // before it can return the null id it would otherwise answer with
    // (src/body.c:171-174, src/physics_world.c:93-96).
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

    // A shape cannot be put on a body that is gone. Upstream reaches the body
    // through `b3GetBodyFullId`, which asserts that the id is a live body
    // (src/shape.c:276, src/body.c:28-34), so this is the facade's check that
    // turns the dead id into an error instead.
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

// -- filter behaviour --------------------------------------------------------

test "a matching negative group stops two shapes that would otherwise collide" {
    nativeReady();

    // The same scene twice, differing only in one filter field, so the only thing
    // that can explain a difference in the outcome is that field. A negative
    // group index means "these two never collide", and a matching group always
    // wins against the category and mask bits
    // (include/box3d/types.h:383-385).
    const blocked = try buildFilteredScene(-1);
    defer blocked.scene.deinit();
    const allowed = try buildFilteredScene(0);
    defer allowed.scene.deinit();

    blocked.scene.step(120);
    allowed.scene.step(120);

    const resting_height = ground_centre.y + ground_half.y + cube_half;

    // With the filter left alone the cube comes to rest on the ground, which is
    // the same claim the first fixture makes.
    try testing.expectApproxEqAbs(
        resting_height,
        box3d.body.position(allowed.scene.cube).y,
        0.01,
    );

    // With the group refusing the pair there is nothing to stop the cube, so it
    // is a long way below where the ground's surface is. The gap is metres, not
    // the millimetre-scale slop a resting contact allows, so the two outcomes
    // cannot be confused.
    const fallen_y = box3d.body.position(blocked.scene.cube).y;
    try testing.expect(fallen_y < resting_height - 1.0);
}

/// The shared scene with a filter group index on both shapes.
///
/// `group_index` of 0 is the default and has no effect
/// (`include/box3d/types.h:383-386`); any other value makes the two shapes share
/// that group, and a shared negative group is a refusal.
fn buildFilteredScene(group_index: c_int) !struct { scene: Scene } {
    const world = try box3d.world.create(.{});
    errdefer box3d.world.destroy(world);

    // Upstream's default filter, with only the group index changed: a filter
    // whose category and mask bits are all zero would match nothing at all,
    // which is a different thing from matching everything.
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
