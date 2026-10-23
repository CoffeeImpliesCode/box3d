// SPDX-License-Identifier: MIT
//
//! Typed Zig facade for Box3D.
//! Upstream: erincatto/box3d v0.1.0.
//! This package is developed and gated against Zig 0.17.0.

const std = @import("std");

/// Translated Box3D declarations or the equivalent runtime-loaded dispatch.
/// On double-precision x86_64, Zig 0.16 mis-lowers 24-byte `b3Pos` arguments; use `box3dAbi_*` bridges (`build_support/box3d_abi_bridge.h`) (observed with Zig 0.16; not rechecked on 0.17).
pub const c = @import("c");

const rt = @import("rt");

/// Whether this build resolves native symbols at runtime.
/// Compile-time constant; runtime-loaded builds require `load` first.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// `.path` names a file; `.system` names a platform library. Neither falls back to the other.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Errors returned by `load`.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the selected provider; failures publish no state and can be retried by calling again.
/// Same-source calls are idempotent; different sources after success return `ProviderMismatch`.
///
/// Thread-safe; concurrent calls for the same source share the result. Reentrant calls return
/// `ReentrantLoad`. The handle lasts for the process; linked builds panic if called.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime !runtime_loaded) {
        std.debug.panic(
            "box3d: load was called on a linked build; this module is not " ++
                "runtime-loaded, so there is no library to load. Build with " ++
                "runtime loading configured, or do not call load.",
            .{},
        );
    }
    return c.load(source);
}

/// Return the retained successful request, or null before loading or in a linked build.
/// The value remains valid for the process lifetime.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}
pub const base = @import("base.zig");
pub const math = @import("math.zig");
pub const world = @import("world.zig");
pub const body = @import("body.zig");
pub const shape = @import("shape.zig");
pub const joint = @import("joint.zig");
pub const query = @import("query.zig");

pub const WorldId = c.b3WorldId;
pub const BodyId = c.b3BodyId;
pub const ShapeId = c.b3ShapeId;
pub const JointId = c.b3JointId;

/// Contact event id; upstream warns it may be orphaned (`include/box3d/id.h:68-75`).
pub const ContactId = c.b3ContactId;

pub const Vec2 = math.Vec2;
pub const Vec3 = math.Vec3;
pub const Quat = math.Quat;
pub const Pos = math.Pos;
pub const Transform = math.Transform;
pub const WorldTransform = math.WorldTransform;
pub const Mat3 = math.Mat3;
pub const Aabb = math.Aabb;
pub const Plane = math.Plane;
pub const pi: f32 = math.pi;
pub const zeroVec3: Vec3 = math.zero;
pub const identityQuat: Quat = math.identity_quat;
pub const identityTransform: Transform = math.identity_transform;
pub const BodyType = body.BodyType;
pub const staticBody: BodyType = body.staticBody;
pub const kinematicBody: BodyType = body.kinematicBody;
pub const dynamicBody: BodyType = body.dynamicBody;

pub const ShapeType = shape.ShapeType;
pub const JointType = joint.JointType;

pub const WorldDef = world.WorldDef;
pub const BodyDef = body.BodyDef;
pub const ShapeDef = shape.ShapeDef;
pub const JointDef = joint.JointDef;
pub const QueryFilterDef = query.QueryFilterDef;

pub const DistanceJointDef = joint.DistanceJointDef;
pub const MotorJointDef = joint.MotorJointDef;
pub const FilterJointDef = joint.FilterJointDef;
pub const ParallelJointDef = joint.ParallelJointDef;
pub const PrismaticJointDef = joint.PrismaticJointDef;
pub const RevoluteJointDef = joint.RevoluteJointDef;
pub const SphericalJointDef = joint.SphericalJointDef;
pub const WeldJointDef = joint.WeldJointDef;
pub const WheelJointDef = joint.WheelJointDef;

pub const MotionLocks = body.MotionLocks;
pub const MassData = body.MassData;
pub const Filter = shape.Filter;
pub const SurfaceMaterial = shape.SurfaceMaterial;
pub const Sphere = shape.Sphere;
pub const Capsule = shape.Capsule;
pub const BoxHull = shape.BoxHull;
pub const HullData = shape.HullData;
pub const QueryFilter = query.QueryFilter;
pub const TreeStats = query.TreeStats;
pub const RayResult = query.RayResult;
pub const ShapeProxy = query.ShapeProxy;

pub const Version = base.Version;
