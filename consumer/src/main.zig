// SPDX-License-Identifier: MIT
//
//! Consumes the `box3d` package the way an outside project would.
//!
//! Everything here goes through the published surface only: `dep.module` in
//! `build.zig`, and `@import("box3d")` here. No path reaches into the library's
//! own tree, so if this builds and produces the answers below, the module
//! contract is real.
//!
//! The scene is different from `smoke.zig`'s on purpose. Where the smoke drops a
//! cube and watches it land, this one asks three questions a consumer actually
//! has:
//!
//!   1. Does a body that is already resting where its geometry says it should
//!      stay there, rather than being pushed out or sinking?
//!   2. Does a distance joint confine a dynamic body to its rest length from a
//!      static anchor - on every step of a swing, not only at the end - and
//!      leave it hanging directly below once gravity and drag have settled it?
//!   3. Does a ray cast against that same world report the surfaces the geometry
//!      puts in its path?
//!
//! The answers are derived from the scene, so a mismatch is a real fault rather
//! than a restatement of what the library just did, and any mismatch exits
//! non-zero.
//!
//! The same source builds against a linked package and against a runtime-loaded
//! one. `box3d.runtime_loaded` is a comptime constant, so the difference is one
//! branch and no duplicated program: in the runtime-loaded build the provider is
//! named on the command line (`--provider <path>`) or in `BOX3D_TEST_PROVIDER`,
//! loaded once, and the same answers follow.

const std = @import("std");
const box3d = @import("box3d");

/// A shared object exporting the `b3*` entry points of `box3d/box3d.h` and
/// the ten `box3dAbi_*` entry points of `build_support/box3d_abi_bridge.h`,
/// named by the environment in a runtime-loading build. The ten are this
/// package's own bridge source unit, so a provider built before it existed is
/// short exactly those ten, and `load` refuses it by name rather than by
/// count.
const provider_variable = "BOX3D_TEST_PROVIDER";

/// The ground: half-extents (50, 10, 50) centred at y = -10, so its top face is
/// at y = 0.
const ground_half: box3d.Vec3 = .{ .x = 50, .y = 10, .z = 50 };
const ground_centre: box3d.Pos = .{ .x = 0, .y = -10, .z = 0 };
/// The unit cube's half-extent, so its AABB is its centre plus and minus 1.
const cube_half: f32 = 1;
/// A unit cube at density 1 has volume 8, so mass 8.
const cube_mass: f32 = 8;
/// Where the joint anchors on the ground, and how long the joint is.
const anchor: box3d.Pos = .{ .x = 2, .y = 5, .z = 0 };
const anchor_distance: f32 = 1.5;
/// The sphere's own radius. The joint does not use it: the far end of the
/// segment is the sphere's centre, not its surface.
const probe_radius: f32 = 0.25;
/// Where the sphere starts: level with the anchor, a whole segment to its +x
/// side. That puts it at exactly the rest length, so the joint starts
/// satisfied, and it puts gravity across the segment rather than along it.
const release: box3d.Pos = .{
    .x = anchor.x + anchor_distance,
    .y = anchor.y,
    .z = anchor.z,
};
/// Drag on the sphere, in 1/s. Box3D scales a body's velocity by
/// `1 / (1 + h * linearDamping)` in every substep (`src/solver.c:91-93`), and
/// nothing else in this scene takes energy out of the sphere, so a rigid
/// pendulum without it would still be at full amplitude when the run ended.
const probe_damping: f32 = 2;
/// Ten seconds of swing, counted in `time_step`s. The sphere is kept awake, so
/// these steps follow the drag all the way down instead of freezing it wherever
/// Box3D's sleep threshold happened to catch it.
const swing_steps: usize = 600;
/// The same anchor measured in the ground body's own frame. A joint's local
/// frames are measured from the attached body's origin rather than in world
/// space (`include/box3d/types.h:599-602`), and the solver transforms each one
/// by its body's world transform before it measures the joint
/// (`src/joint.c:1213-1215`). Passing `anchor` unchanged therefore anchors the
/// joint a whole `ground_centre` lower than where it was meant to sit.
const anchor_on_ground: box3d.Vec3 = .{
    .x = anchor.x - ground_centre.x,
    .y = anchor.y - ground_centre.y,
    .z = anchor.z - ground_centre.z,
};
const time_step: f32 = 1.0 / 60.0;
const sub_steps: c_int = 4;
/// Two seconds of settling for the cube: long enough for it to stop moving.
const settle_steps: usize = 120;
/// The resting contact tolerance, the one upstream's own test of this scene uses
/// (`test/test_world.c:96-98`).
const rest_tolerance: f32 = 0.01;
/// The band the joint's own geometry stays inside. Box3D solves a rigid
/// distance joint as a soft constraint - 60 hertz and damping ratio 2 by
/// default (`src/joint.c:30-31`), turned into bias and stiffness by
/// `b3MakeSoft` (`src/solver.h:264-304`) - so the segment is held to a
/// fraction of a millimetre rather than exactly. A twentieth of the joint
/// length is well above that error and well below what a joint that is present
/// and doing nothing allows: at the world's own 10 m/s^2 gravity
/// (`src/types.c:13-14`) an unconfined sphere falls half this band in three
/// steps.
const joint_tolerance: f32 = 0.02;

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};
/// What went wrong when a checked answer was not the expected one.
const ConsumerError = error{ConsumerCheckFailed};

/// What a helper that reports an answer and then checks it can return: the
/// answer was wrong, or the writer it reports through failed. The write failure
/// is propagated rather than swallowed, so a full or closed output stops the
/// run instead of silently truncating the report.
const CheckError = ConsumerError || std.Io.Writer.Error;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // In a runtime-loaded build every call below goes through a table that this one
    // call fills. In a linked build the branch is not analyzed at all.
    if (comptime box3d.runtime_loaded) {
        box3d.load(.{ .path = try providerRequest(init) }) catch |err| {
            std.debug.print("consumer: loading the provider failed: {t}\n", .{err});
            return err;
        };
    }

    try w.print("box3d consumer\n", .{});
    // Through the raw escape hatch, so these lines name the C library this build
    // reached rather than constants compiled into this program.
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

    // -- the ground ----------------------------------------------------------

    const ground = try box3d.body.create(world, .{ .position = ground_centre });
    const ground_hull = box3d.shape.boxHull(ground_half.x, ground_half.y, ground_half.z);
    _ = try box3d.shape.createHull(ground, .{}, &ground_hull.base);

    // -- a cube already resting where its geometry says it should ------------
    //
    // Created at y = 1, which is the ground's top face plus the cube's half
    // extent, so it starts in contact rather than being dropped into contact.

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

    // -- a dynamic sphere on a distance joint --------------------------------
    //
    // A distance joint is a segment, not a hinge. It holds the two frames
    // `anchor_distance` apart and says nothing about which side of the anchor
    // the sphere is on (`include/box3d/types.h:643-688`; the solve acts along
    // the segment alone, `src/distance_joint.c:381-384` and `:498-522`). So a
    // sphere placed straight above the anchor is not "let go and caught on the
    // way down": with gravity and the segment collinear that is an equilibrium,
    // and a rigid joint holds an equilibrium as well as it holds anything else.
    // A symmetric scene like that measures nothing about a swing. This sphere
    // starts level with the anchor a whole segment to its +x side instead,
    // where gravity is perpendicular to the segment and has to swing it.
    //
    // What is left is a pendulum, and every answer below is read off that
    // geometry rather than off where the solver happened to stop: the joint
    // confines the sphere to an arc whose low point is one segment below the
    // anchor, a sphere released from rest swings through that low point, and
    // drag brings the swing down until the segment hangs vertical, which is the
    // only place on the arc where the segment alone can balance gravity.

    const probe = try box3d.body.create(world, .{
        .bodyType = box3d.dynamicBody,
        .position = release,
        .linearDamping = probe_damping,
        // Sleeping would freeze the sphere wherever its speed first stayed
        // below `sleepThreshold` (`src/types.c:37`) for half a second, which is
        // a fact about that threshold rather than about the joint.
        .enableSleep = false,
    });
    _ = try box3d.shape.createSphere(probe, .{ .density = 1.0 }, box3d.shape.sphere(probe_radius));

    _ = try box3d.joint.createDistance(world, .{
        .base = .{
            .bodyIdA = ground,
            .bodyIdB = probe,
            // Frame A is a point on the ground body, so it is `anchor_on_ground`:
            // the world anchor measured back from that body's own origin rather
            // than in world coordinates. Frame B sits on the sphere at its own
            // origin, which is what makes this a plain distance between two
            // points.
            .localFrameA = .{ .p = anchor_on_ground, .q = box3d.identityQuat },
        },
        // `enableSpring` is left at its default of false, which makes the
        // constraint rigid rather than a spring
        // (`include/box3d/types.h:655-657`), so the rest length is the length
        // the segment settles at.
        .length = anchor_distance,
        .enableMotor = false,
        .enableLimit = false,
    });

    // Every step is measured, not just the last: a joint that let go halfway
    // through the swing would pass a check that only looked at the end.
    //
    // The arc's low point is one segment below the anchor, which is also the
    // height the sphere starts at: it is released level with the anchor.
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
    // Gravity moved it, and nothing could have moved it the other way: it never
    // rose above the height it was released at.
    try checkAtMost(w, "rise above the release (m)", joint_tolerance, highest - release_height);
    // It came to rest hanging under the anchor. The sideways offset is the
    // statement that the segment ended up vertical rather than at some other
    // point of the swing.
    try checkFloat(w, "hung height (m)", arc_low, hung.y, joint_tolerance);
    try checkAtMost(w, "hung sideways offset (m)", joint_tolerance, sidewaysOffset(hung));

    // -- a ray against the same world ----------------------------------------
    //
    // The second argument is a translation, not a second endpoint: the native
    // call puts both straight into its ray input as given, with a maximum
    // fraction of one (`src/physics_world.c:2999`). So this ray runs from
    // (5, 10, 5) to (0, -10, 5). `fraction` is that parameter and not a distance
    // along the ray: the hull test divides the plane distance by
    // `dot(normal, translation)` (`src/hull.c:2481`) and rebuilds the point as
    // `origin + fraction * translation` (`src/hull.c:2508,2510`), and the tree
    // divides its slab distances by the ray's own length for the same reason
    // (`src/aabb.c:171-173`).

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
    // The ground's top face is at y = 0, which is 10 units of the 20 this ray
    // falls through, so the fraction is half however far the ray also travels
    // sideways, and 5 of its units of x have gone by then. Nothing else is in
    // the way: the cube is a unit wide around the origin, and the sphere hangs
    // at z = 0, five metres from the ray.
    try checkFloat(w, "ground hit fraction", 0.5, hit.fraction, 0.0001);
    try checkFloat(w, "ground hit height (m)", 0.0, hit.point.y, 0.001);
    try checkFloat(w, "ground hit offset (m)", 2.5, hit.point.x, 0.001);
    try checkFloat(w, "ground hit normal", 1.0, hit.normal.y, 0.001);

    try w.print("\nevery checked answer matched the scene's geometry\n", .{});
    try w.flush();
}

/// The provider this run should load, from `--provider <path>` or from
/// `BOX3D_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location, and a build that
/// was not told which file to load says so rather than loading something else.
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
    // `b3SubPos` returns a `Pos`, which is not a `Vec3` in large world mode, so
    // the difference is narrowed before its length is taken
    // (`include/box3d/math_functions.h:87-95`, `math_functions.h:689,658`).
    return box3d.math.length(box3d.math.toVec3(box3d.math.subPos(at, anchor)));
}

/// How far `at` sits from the anchor's vertical line, in metres.
///
/// Taken in `f64` rather than through `math`, because a `Pos` field is `double`
/// in large world mode and `float` otherwise
/// (`include/box3d/math_functions.h:74-90`) and this consumer wants the same
/// arithmetic in both precision modes.
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