// SPDX-License-Identifier: MIT
//
//! Queries: what does a world contain, and what would a ray or a shape hit if
//! it were cast into it?
//!
//! Queries do not move anything and they do not need the world to be unlocked
//! by a step. Every one of them returns traversal counters alongside the
//! answer, and those counters are the honest measure of what a query cost:
//! `b3TreeStats` counts the internal nodes and the leaves the broad phase
//! visited (`include/box3d/types.h:1758-1766`).
//!
//! ## Two ways to call each query
//!
//! Every query comes in a pair:
//!
//!   * a raw form taking Box3D's own callback and context, so a caller with its
//!     own state can be called directly and can decide, mid-query, to clip or
//!     terminate. The callback is a C function pointer, so it is
//!     `callconv(.c)` and receives `?*anyopaque`;
//!   * a `collect` form that fills a caller-supplied slice of shape ids and
//!     returns the total number of hits, including those beyond its capacity.
//!
//! The `collect` forms keep going past the end of the slice rather than
//! truncating the query, so the count they return is the true number of hits
//! even when the slice was too small. That is what makes `slice.len == 0` a
//! legitimate "how many are there" query.
//!
//! ## Precision
//!
//! A query's origin is a `Pos` and the proxy points are relative to it
//! (`include/box3d/box3d.h:78-79`), and hit points come back as world positions.
//! That split is what keeps a query precise far from the world origin, and it is
//! why `ShapeProxy.points` must be local to `origin` rather than absolute.

const c = @import("c");
const math = @import("math.zig");
const shape_mod = @import("shape.zig");
const body_mod = @import("body.zig");
const world_mod = @import("world.zig");

/// A query filter, `b3QueryFilter` (`include/box3d/types.h:1283-1301`).
///
/// `categoryBits` is what this query is, `maskBits` is what it will accept.
/// `id` and `name` identify the query inside a recording and are ignored
/// otherwise (`include/box3d/types.h:1292-1300`).
pub const QueryFilter = c.b3QueryFilter;
/// Broad-phase traversal counters, `b3TreeStats`
/// (`include/box3d/types.h:1759-1766`).
pub const TreeStats = c.b3TreeStats;
/// A ray cast result, `b3RayResult` (`include/box3d/types.h:1321-1354`).
///
/// Every field except `hit` is meaningless when `hit` is false; upstream says so
/// on the declaration.
pub const RayResult = c.b3RayResult;
/// A ray or shape cast result, `b3CastOutput` or, under
/// `BOX3D_DOUBLE_PRECISION`, the `b3WorldCastOutput` variant with a
/// double-precision point (`include/box3d/types.h:1403-1466`).
pub const CastOutput = c.b3WorldCastOutput;
/// A body cast result, `b3BodyCastResult`
/// (`include/box3d/types.h:1469-1496`).
pub const BodyCastResult = c.b3BodyCastResult;
/// A generic query shape, `b3ShapeProxy`
/// (`include/box3d/types.h:1357-1367`).
///
/// A point cloud plus a radius, which is how a sphere is one point with a
/// radius, a capsule two, and a box four with zero
/// (`include/box3d/types.h:1369-1371`). `count` must not exceed
/// `B3_MAX_SHAPE_CAST_POINTS`.
pub const ShapeProxy = c.b3ShapeProxy;
/// The largest `ShapeProxy.count` Box3D accepts, `B3_MAX_SHAPE_CAST_POINTS`
/// (`include/box3d/constants.h:116-117`).
pub const maxShapeCastPoints: usize = c.B3_MAX_SHAPE_CAST_POINTS;
/// One collision plane against a mover, `b3PlaneResult`
/// (`include/box3d/types.h:1799-1807`).
pub const PlaneResult = c.b3PlaneResult;
/// The planes found against one body, `b3BodyPlaneResult`
/// (`include/box3d/types.h:1838-1845`).
pub const BodyPlaneResult = c.b3BodyPlaneResult;
/// The solved plane set, `b3PlaneSolverResult`
/// (`include/box3d/types.h:1828-1835`).
pub const PlaneSolverResult = c.b3PlaneSolverResult;

/// A query filter as optional overrides of upstream's defaults.
///
/// `.{}` accepts everything, which is `b3DefaultQueryFilter`
/// (`src/types.c:53-57`).
pub const QueryFilterDef = struct {
    /// What this query is.
    categoryBits: ?u64 = null,
    /// What this query will accept.
    maskBits: ?u64 = null,
    /// Recording identity. Ignored when not recording.
    id: ?u64 = null,
    /// Recording label. Ignored when not recording.
    ///
    /// A recording reads this pointer while the query runs and interns a copy
    /// of the bytes into its own tag table
    /// (`src/recording.c:604-605,921-948`); the registry writes that copy, not
    /// the caller's pointer (`src/recording.c:964-970`). So the string must be
    /// valid for the duration of the query and need not outlive it.
    ///
    /// The label the recording keeps is clamped to `B3_BODY_NAME_LENGTH` bytes
    /// (`src/recording.c:940-946`, `base.bodyNameLength`) while the key is
    /// hashed from the whole string (`src/recording.c:899-907`), so two labels
    /// sharing that prefix stay distinct queries that record as one label.
    name: ?[:0]const u8 = null,

    /// The filter Box3D wants.
    pub fn native(self: QueryFilterDef) QueryFilter {
        var out = c.b3DefaultQueryFilter();
        if (self.categoryBits) |value| out.categoryBits = value;
        if (self.maskBits) |value| out.maskBits = value;
        if (self.id) |value| out.id = value;
        if (self.name) |value| out.name = value.ptr;
        return out;
    }
};

/// Box3D's overlap callback, `b3OverlapResultFcn`
/// (`include/box3d/types.h:90-95`). Return false to stop the query.
pub const OverlapFn = c.b3OverlapResultFcn;
/// Box3D's ray and shape cast callback, `b3CastResultFcn`
/// (`include/box3d/types.h:101-116`).
///
/// The return value controls the cast: -1 filters the shape out, 0 terminates,
/// a fraction clips the ray to the hit, and 1 continues unclipped
/// (`include/box3d/types.h:101-114`).
pub const CastFn = c.b3CastResultFcn;
/// Box3D's mover filter callback, `b3MoverFilterFcn`
/// (`include/box3d/types.h:1853`).
pub const MoverFilterFn = c.b3MoverFilterFcn;
/// Box3D's mover plane callback, `b3PlaneResultFcn`
/// (`include/box3d/types.h:1849`). Return false to stop collecting planes.
pub const PlaneResultFn = c.b3PlaneResultFcn;

// -- overlap -----------------------------------------------------------------

/// Every shape that potentially overlaps `aabb` (`include/box3d/box3d.h:75`).
///
/// "Potentially" is the broad phase's word, not this function's: the proxy
/// AABBs are what is tested, so a hit is a candidate for the narrow phase
/// rather than proof of overlap.
pub fn overlapAabb(
    id: world_mod.WorldId,
    aabb: math.Aabb,
    filter: QueryFilter,
    callback: ?*const OverlapFn,
    context: ?*anyopaque,
) TreeStats {
    return c.b3World_OverlapAABB(id, aabb, filter, callback, context);
}

/// Every shape that overlaps a proxy shape (`include/box3d/box3d.h:80`).
///
/// `origin` is the world position and `proxy.points` are relative to it.
pub fn overlapShape(
    id: world_mod.WorldId,
    origin: math.Pos,
    proxy: *const ShapeProxy,
    filter: QueryFilter,
    callback: ?*const OverlapFn,
    context: ?*anyopaque,
) TreeStats {
    return c.b3World_OverlapShape(id, origin, proxy, filter, callback, context);
}

/// The shape ids that potentially overlap `aabb`, into `out`.
///
/// Returns how many there are. If that exceeds `out.len`, the slice was too
/// small and the excess was not written; ask again with a bigger one.
pub fn overlapAabbCollect(
    id: world_mod.WorldId,
    aabb: math.Aabb,
    filter: QueryFilter,
    out: []shape_mod.ShapeId,
) usize {
    var ctx = OverlapCollector{ .out = out, .count = 0 };
    _ = overlapAabb(id, aabb, filter, overlapCollectorTrampoline, &ctx);
    return ctx.count;
}

// -- ray casts ---------------------------------------------------------------

/// Cast a ray and report every shape in its path
/// (`include/box3d/box3d.h:93-94`).
///
/// The callback decides what to do with each shape, so this is the general
/// form: closest hit, first hit, or several. The order shapes arrive in is not
/// defined (`include/box3d/box3d.h:85`).
///
/// The ray runs from `origin` to `origin + translation`; there is no separate
/// maximum, so clipping is the callback's job.
pub fn castRay(
    id: world_mod.WorldId,
    origin: math.Pos,
    translation: math.Vec3,
    filter: QueryFilter,
    callback: ?*const CastFn,
    context: ?*anyopaque,
) TreeStats {
    return c.box3dAbi_CastRay(id, &origin, &translation, &filter, callback, context);
}

/// Cast a ray and take the closest hit (`include/box3d/box3d.h:98`).
///
/// The convenience form. It ignores initial overlap - a ray that starts inside
/// a shape does not report it - and it does not allow custom filtering beyond
/// the filter argument (`include/box3d/box3d.h:96-97`). Check `result.hit`
/// before reading anything else in it.
pub fn castRayClosest(
    id: world_mod.WorldId,
    origin: math.Pos,
    translation: math.Vec3,
    filter: QueryFilter,
) RayResult {
    return c.box3dAbi_CastRayClosest(id, &origin, &translation, &filter);
}

/// The first shape a ray hits, into `out`.
///
/// Returns null when the ray hit nothing. This is `castRayClosest` with the
/// result reduced to the two things a caller usually wants.
pub fn castRayClosestShape(
    id: world_mod.WorldId,
    origin: math.Pos,
    translation: math.Vec3,
    filter: QueryFilter,
    out: *RayResult,
) bool {
    const result = castRayClosest(id, origin, translation, filter);
    out.* = result;
    return result.hit;
}

// -- shape casts -------------------------------------------------------------

/// Sweep a proxy shape through the world (`include/box3d/box3d.h:104-105`).
///
/// The same callback protocol as `castRay`. The proxy points stay relative to
/// `origin`, and hit points come back in world space.
pub fn castShape(
    id: world_mod.WorldId,
    origin: math.Pos,
    proxy: *const ShapeProxy,
    translation: math.Vec3,
    filter: QueryFilter,
    callback: ?*const CastFn,
    context: ?*anyopaque,
) TreeStats {
    return c.box3dAbi_CastShape(id, &origin, proxy, &translation, &filter, callback, context);
}

/// The shape ids a swept proxy passes through, into `out`.
///
/// Returns how many there are; see `overlapAabbCollect` for what an overflow
/// means. A clipped cast still reports everything up to the clip point.
pub fn castShapeCollect(
    id: world_mod.WorldId,
    origin: math.Pos,
    proxy: *const ShapeProxy,
    translation: math.Vec3,
    filter: QueryFilter,
    out: []shape_mod.ShapeId,
) usize {
    var ctx = CastCollector{ .out = out, .count = 0 };
    _ = castShape(id, origin, proxy, translation, filter, castCollectorTrampoline, &ctx);
    return ctx.count;
}

// -- character mover ---------------------------------------------------------

/// Sweep a capsule mover and return the fraction it may travel
/// (`include/box3d/box3d.h:118-119`).
///
/// Upstream is explicit that this is not a good source of information about what
/// the mover touched - it slides along things - and that `collideMover` is what
/// to use for that (`include/box3d/box3d.h:107-109`).
pub fn castMover(
    id: world_mod.WorldId,
    origin: math.Pos,
    mover: *const shape_mod.Capsule,
    translation: math.Vec3,
    filter: QueryFilter,
    callback: ?*const MoverFilterFn,
    context: ?*anyopaque,
) f32 {
    return c.box3dAbi_CastMover(id, &origin, mover, &translation, &filter, callback, context);
}

/// Collect the collision planes against a capsule mover
/// (`include/box3d/box3d.h:123-124`).
///
/// This is what a kinematic character uses: the planes feed `solvePlanes`
/// (`include/box3d/collision.h:639`) to move along surfaces. The mover and the
/// planes are both relative to `origin`.
pub fn collideMover(
    id: world_mod.WorldId,
    origin: math.Pos,
    mover: *const shape_mod.Capsule,
    filter: QueryFilter,
    callback: ?*const PlaneResultFn,
    context: ?*anyopaque,
) void {
    c.b3World_CollideMover(id, origin, mover, filter, callback, context);
}

/// Move a target delta along a set of collision planes
/// (`include/box3d/collision.h:639`).
pub const solvePlanes = c.b3SolvePlanes;

// -- per-body queries --------------------------------------------------------
//
// Each of these takes an explicit `body_transform`, which is what lets a
// hypothetical future transform be tested without moving the body. Pass the
// body's real transform - `body.transform` - to ask about where it is now.

// -- collector plumbing ------------------------------------------------------

const OverlapCollector = struct {
    out: []shape_mod.ShapeId,
    count: usize,
};

fn overlapCollectorTrampoline(hit: shape_mod.ShapeId, context: ?*anyopaque) callconv(.c) bool {
    const ctx: *OverlapCollector = @ptrCast(@alignCast(context.?));
    if (ctx.count < ctx.out.len) ctx.out[ctx.count] = hit;
    ctx.count += 1;
    // Keep going: the count is part of the answer even when the slice is full.
    return true;
}

const CastCollector = struct {
    out: []shape_mod.ShapeId,
    count: usize,
};

fn castCollectorTrampoline(
    hit: shape_mod.ShapeId,
    _: math.Pos,
    _: math.Vec3,
    _: f32,
    _: u64,
    _: c_int,
    _: c_int,
    context: ?*anyopaque,
) callconv(.c) f32 {
    const ctx: *CastCollector = @ptrCast(@alignCast(context.?));
    if (ctx.count < ctx.out.len) ctx.out[ctx.count] = hit;
    ctx.count += 1;
    // 1 is "do not clip the ray and continue"
    // (`include/box3d/types.h:101-114`).
    return 1;
}

// -- per-body query wrappers -------------------------------------------------

/// Ray cast one body at an explicit transform
/// (`include/box3d/box3d.h:757`).
pub fn castRayAgainstBody(
    body: body_mod.BodyId,
    origin: math.Pos,
    translation: math.Vec3,
    filter: QueryFilter,
    max_fraction: f32,
    body_transform: math.WorldTransform,
) BodyCastResult {
    return c.box3dAbi_BodyCastRay(body, &origin, &translation, &filter, max_fraction, &body_transform);
}

/// Sweep a proxy against one body at an explicit transform
/// (`include/box3d/box3d.h:761-762`).
pub fn castShapeAgainstBody(
    body: body_mod.BodyId,
    origin: math.Pos,
    proxy: *const ShapeProxy,
    translation: math.Vec3,
    filter: QueryFilter,
    max_fraction: f32,
    can_encroach: bool,
    body_transform: math.WorldTransform,
) BodyCastResult {
    return c.box3dAbi_BodyCastShape(body, &origin, proxy, &translation, &filter, max_fraction, can_encroach, &body_transform);
}

/// Test whether a proxy overlaps one body at an explicit transform
/// (`include/box3d/box3d.h:766`).
pub fn overlapShapeAgainstBody(
    body: body_mod.BodyId,
    origin: math.Pos,
    proxy: *const ShapeProxy,
    filter: QueryFilter,
    body_transform: math.WorldTransform,
) bool {
    return c.b3Body_OverlapShape(body, origin, proxy, filter, body_transform);
}

/// The planes a capsule mover meets on one body, at an explicit transform
/// (`include/box3d/box3d.h:770-771`).
pub fn collideMoverAgainstBody(
    body: body_mod.BodyId,
    out: []BodyPlaneResult,
    origin: math.Pos,
    mover: *const shape_mod.Capsule,
    filter: QueryFilter,
    body_transform: math.WorldTransform,
) c_int {
    if (out.len == 0) return 0;
    return c.b3Body_CollideMover(body, out.ptr, @intCast(out.len), origin, mover, filter, body_transform);
}