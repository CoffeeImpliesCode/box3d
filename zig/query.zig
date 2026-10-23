// SPDX-License-Identifier: MIT
//
//! World and body overlap, cast and character-mover queries.

const c = @import("c");
const math = @import("math.zig");
const shape_mod = @import("shape.zig");
const body_mod = @import("body.zig");
const world_mod = @import("world.zig");

/// Query category, mask and optional recording identity (`include/box3d/types.h:1283-1301`).
/// Recording identity fields are ignored when not recording.
pub const QueryFilter = c.b3QueryFilter;
/// Broad-phase traversal counters, `b3TreeStats` (`include/box3d/types.h:1759-1766`).
pub const TreeStats = c.b3TreeStats;
/// Ray result; fields other than `hit` are invalid when `hit` is false.
/// (`include/box3d/types.h:1321-1354`.)
pub const RayResult = c.b3RayResult;
/// Cast result with a world point whose precision follows `BOX3D_DOUBLE_PRECISION`.
pub const CastOutput = c.b3WorldCastOutput;
/// Body cast result, `b3BodyCastResult` (`include/box3d/types.h:1469-1496`).
pub const BodyCastResult = c.b3BodyCastResult;
/// Point cloud plus radius; sphere, capsule and box proxies use one, two and four points.
/// `count` must not exceed `B3_MAX_SHAPE_CAST_POINTS`.
pub const ShapeProxy = c.b3ShapeProxy;
pub const maxShapeCastPoints: usize = c.B3_MAX_SHAPE_CAST_POINTS;
pub const PlaneResult = c.b3PlaneResult;
pub const BodyPlaneResult = c.b3BodyPlaneResult;
pub const PlaneSolverResult = c.b3PlaneSolverResult;

/// Optional overrides of the query filter defaults; `.{}` accepts everything.
/// Defaults come from `b3DefaultQueryFilter` (`src/types.c:53-57`).
pub const QueryFilterDef = struct {
    categoryBits: ?u64 = null,
    maskBits: ?u64 = null,
    id: ?u64 = null,
    /// Recording label copied during the query; it need only live for the call.
    /// The stored label is truncated, but identity hashes the full string (`src/recording.c:899-907`).
    name: ?[:0]const u8 = null,

    pub fn native(self: QueryFilterDef) QueryFilter {
        var out = c.b3DefaultQueryFilter();
        if (self.categoryBits) |value| out.categoryBits = value;
        if (self.maskBits) |value| out.maskBits = value;
        if (self.id) |value| out.id = value;
        if (self.name) |value| out.name = value.ptr;
        return out;
    }
};

/// Overlap callback; return false to stop the query (`include/box3d/types.h:90-95`).
pub const OverlapFn = c.b3OverlapResultFcn;
/// Ray and shape cast callback (`include/box3d/types.h:101-116`).
/// Return -1 to filter, 0 to stop, a fraction to clip, or 1 to continue unclipped.
pub const CastFn = c.b3CastResultFcn;
pub const MoverFilterFn = c.b3MoverFilterFcn;
/// Mover-plane callback; return false to stop collecting (`include/box3d/types.h:1849`).
pub const PlaneResultFn = c.b3PlaneResultFcn;

/// Broad-phase candidates whose proxy AABBs overlap `aabb`.
/// A hit is not proof of narrow-phase overlap (`include/box3d/box3d.h:75`).
pub fn overlapAabb(
    id: world_mod.WorldId,
    aabb: math.Aabb,
    filter: QueryFilter,
    callback: ?*const OverlapFn,
    context: ?*anyopaque,
) TreeStats {
    return c.b3World_OverlapAABB(id, aabb, filter, callback, context);
}

/// Overlap query for a proxy whose points are relative to `origin`.
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

/// Write candidate shape ids into `out` and return the total count.
/// If the count exceeds `out.len`, excess ids are not written.
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

/// Cast from `origin` to `origin + translation`; callback results control clipping.
/// Shape order is undefined (`include/box3d/box3d.h:85`).
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

/// Return the closest hit. Initial overlaps are ignored; custom callback filtering is unavailable.
/// Check `result.hit` before reading other result fields (`include/box3d/box3d.h:96-98`).
pub fn castRayClosest(
    id: world_mod.WorldId,
    origin: math.Pos,
    translation: math.Vec3,
    filter: QueryFilter,
) RayResult {
    return c.box3dAbi_CastRayClosest(id, &origin, &translation, &filter);
}

/// Write the closest result to `out` and return whether the ray hit a shape.
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

/// Sweep a proxy; points are relative to `origin` and hit points are world positions.
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

/// Write hit shape ids and return the total count, including hits beyond `out.len`.
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

/// Sweep a capsule mover and return the allowed travel fraction.
/// `collideMover` reports planes; the mover slides along contacts (`include/box3d/box3d.h:107-109`).
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

/// Collect collision planes for a capsule mover; both mover and planes are relative to `origin`.
/// Use these planes with `solvePlanes` (`include/box3d/collision.h:639`).
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

/// Move a target delta along collision planes (`include/box3d/collision.h:639`).
pub const solvePlanes = c.b3SolvePlanes;

// Per-body queries take an explicit transform, so callers can test a hypothetical pose.
// Pass `body.transform` to query its current pose.

const OverlapCollector = struct {
    out: []shape_mod.ShapeId,
    count: usize,
};

fn overlapCollectorTrampoline(hit: shape_mod.ShapeId, context: ?*anyopaque) callconv(.c) bool {
    const ctx: *OverlapCollector = @ptrCast(@alignCast(context.?));
    if (ctx.count < ctx.out.len) ctx.out[ctx.count] = hit;
    ctx.count += 1;
    // Count every hit, even after the output slice fills.
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
    // 1 continues without clipping (`include/box3d/types.h:101-114`).
    return 1;
}

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
