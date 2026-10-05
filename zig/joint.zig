// SPDX-License-Identifier: MIT
//
//! Joints: connecting two bodies with one of nine constraint types.
//!
//! ## What this module covers, and what it does not
//!
//! It covers joint creation - all nine types - destruction, validity, the
//! attached bodies, and the settings every joint has: its local frames, whether
//! the connected bodies collide, its user data, its event thresholds, its
//! constraint tuning, and the constraint force, torque and separations the
//! solver currently holds.
//!
//! It does not restate the per-type tuning accessors, of which there are well
//! over a hundred: `b3DistanceJoint_SetSpringHertz` and its eight siblings,
//! `b3WheelJoint_*`, and so on. Those are one call each with no argument worth
//! checking and no failure to map, so they stay on `c`, reachable through
//! `box3d.c.b3DistanceJoint_SetSpringHertz` and so on. They are not missing and
//! not renamed; they were left where the header has them rather than duplicated
//! into a second list that could drift.
//!
//! ## Ownership
//!
//! A joint belongs to the world, is attached to two bodies, and is destroyed
//! either explicitly or when either attached body is destroyed. `world.destroy`
//! takes it too. There is no wrapper and no heap: a `JointId` is
//! `b3JointId` (`include/box3d/id.h:60-65`), passed by value.
//!
//! ## Local frames
//!
//! Both frames are measured from the body's origin rather than its centre of
//! mass, and upstream explains why (`include/box3d/types.h:599-603`): the
//! centre of mass is not always known in advance, and it moves when shapes are
//! added or removed, which would break the joint.

const c = @import("c");
const math = @import("math.zig");
const body_mod = @import("body.zig");
const world_mod = @import("world.zig");

/// A joint handle, `b3JointId` (`include/box3d/id.h:60-65`).
pub const JointId = c.b3JointId;

/// Which kind of constraint this is, `b3JointType`
/// (`include/box3d/types.h:586-597`).
pub const JointType = c.b3JointType;

/// The settings every joint type shares, `b3JointDef`
/// (`include/box3d/types.h:604-641`).
///
/// The two attached bodies are not optional in any useful sense: a joint with
/// no second body has nothing to constrain. `bodyIdA` and `bodyIdB` are plain
/// ids rather than options here, because every creator needs both and making
/// them optional would move the failure from the compiler to a runtime check for
/// no gain.
pub const JointDef = struct {
    /// The first attached body.
    bodyIdA: body_mod.BodyId,
    /// The second attached body.
    bodyIdB: body_mod.BodyId,
    /// The joint frame in body A's local coordinates.
    localFrameA: ?math.Transform = null,
    /// The joint frame in body B's local coordinates.
    localFrameB: ?math.Transform = null,
    /// Force above which a joint event is reported, in newtons.
    forceThreshold: ?f32 = null,
    /// Torque above which a joint event is reported, in newton-metres.
    torqueThreshold: ?f32 = null,
    /// Constraint stiffness in hertz. Upstream marks this an advanced feature.
    constraintHertz: ?f32 = null,
    /// Constraint damping ratio. Advanced, as above.
    constraintDampingRatio: ?f32 = null,
    /// Debug-draw scale for this joint.
    drawScale: ?f32 = null,
    /// Should the two attached bodies collide with each other?
    collideConnected: ?bool = null,
    /// Application data, readable with `userData`.
    userData: ?*anyopaque = null,

    /// The base definition Box3D wants: upstream's `b3Default*JointDef` base
    /// with the set fields written over it.
    pub fn native(self: JointDef) c.b3JointDef {
        var out = defaultBase();
        out.bodyIdA = self.bodyIdA;
        out.bodyIdB = self.bodyIdB;
        if (self.localFrameA) |value| out.localFrameA = value;
        if (self.localFrameB) |value| out.localFrameB = value;
        if (self.forceThreshold) |value| out.forceThreshold = value;
        if (self.torqueThreshold) |value| out.torqueThreshold = value;
        if (self.constraintHertz) |value| out.constraintHertz = value;
        if (self.constraintDampingRatio) |value| out.constraintDampingRatio = value;
        if (self.drawScale) |value| out.drawScale = value;
        if (self.collideConnected) |value| out.collideConnected = value;
        if (self.userData) |value| out.userData = value;
        return out;
    }
};

/// Upstream's default base joint definition, with both bodies null.
///
/// `b3JointDef` has no public `b3DefaultJointDef` of its own: upstream's is
/// `static` (`src/joint.c:23-35`) and the nine public constructors each embed a
/// copy of it (`src/joint.c:37-70`). This returns that same base, read out of a
/// public constructor rather than restated, so the validity cookie
/// `B3_CHECK_JOINT_DEF` reads comes from upstream and not from a transcription
/// here. Its values are identity joint frames, `FLT_MAX` event thresholds,
/// 60 hertz constraint stiffness, 2.0 damping, and a draw scale of one length
/// unit (`src/joint.c:25-34`).
pub fn defaultBase() c.b3JointDef {
    return c.b3DefaultDistanceJointDef().base;
}


/// Everything that can go wrong in this module.
pub const Error = error{
    /// The world id was not a live world. Create the joint in a world
    /// `world.isValid` still reports.
    ///
    /// Each creator does answer a stale world id with a null joint id
    /// (`src/joint.c:439-443` for `createDistance`, and the same lookup in the
    /// other eight), but only after `b3GetUnlockedWorldFromId`, which asserts
    /// on an out-of-range index or a generation that does not match
    /// (`src/physics_world.c:93-96`) and on a locked world
    /// (`src/physics_world.c:101-104`) before it can return null. So every
    /// creator here asks `world.isValid` - upstream's own public predicate,
    /// same generation comparison (`src/physics_world.c:1777-1793`) - first,
    /// and the null id is never reached for a stale world. The check after the
    /// call stays because it is what reports the locked-world case in a build
    /// where the assertion does not fire: `B3_ASSERT` compiles to nothing
    /// under `NDEBUG` without `B3_ENABLE_ASSERT`
    /// (`include/box3d/base.h:123-131`), and a handler installed through
    /// `base.setAssertFcn` may return 0 to skip the break
    /// (`src/core.c:81-90`).
    ///
    /// The two body ids in the definition are a different matter and stay a
    /// precondition on it: upstream resolves them through `b3GetBodyFullId`
    /// (`src/joint.c:163-164`), which asserts on a stale one, and this module
    /// does not inspect definition values.
    InvalidWorld,
};

// -- the nine typed definitions ----------------------------------------------
//
// Each is upstream's definition as optional overrides, plus a `native` that
// starts from that type's own `b3Default*JointDef`. `internalValue` is absent
// throughout, and `base` carries the shared settings.

/// A distance joint: a segment between a point on A and a point on B, for
/// ropes and springs (`include/box3d/types.h:643-688`).
pub const DistanceJointDef = struct {
    /// The shared settings. `bodyIdA` and `bodyIdB` are required.
    base: JointDef,
    /// Rest length, clamped internally to a stable minimum.
    length: ?f32 = null,
    /// Behave as a spring. When false the joint is rigid and overrides both the
    /// limit and the motor (`include/box3d/types.h:655-656`).
    enableSpring: ?bool = null,
    /// Tension the spring can sustain.
    lowerSpringForce: ?f32 = null,
    /// Compression the spring can sustain.
    upperSpringForce: ?f32 = null,
    /// Spring stiffness in hertz.
    hertz: ?f32 = null,
    /// Spring damping ratio, non-dimensional.
    dampingRatio: ?f32 = null,
    enableLimit: ?bool = null,
    /// Minimum length, clamped internally to a stable minimum.
    minLength: ?f32 = null,
    /// Maximum length; must be at least `minLength`.
    maxLength: ?f32 = null,
    enableMotor: ?bool = null,
    /// Maximum motor force, usually in newtons.
    maxMotorForce: ?f32 = null,
    /// Desired motor speed, usually m/s.
    motorSpeed: ?f32 = null,

    pub fn native(self: DistanceJointDef) c.b3DistanceJointDef {
        var out = c.b3DefaultDistanceJointDef();
        out.base = self.base.native();
        if (self.length) |v| out.length = v;
        if (self.enableSpring) |v| out.enableSpring = v;
        if (self.lowerSpringForce) |v| out.lowerSpringForce = v;
        if (self.upperSpringForce) |v| out.upperSpringForce = v;
        if (self.hertz) |v| out.hertz = v;
        if (self.dampingRatio) |v| out.dampingRatio = v;
        if (self.enableLimit) |v| out.enableLimit = v;
        if (self.minLength) |v| out.minLength = v;
        if (self.maxLength) |v| out.maxLength = v;
        if (self.enableMotor) |v| out.enableMotor = v;
        if (self.maxMotorForce) |v| out.maxMotorForce = v;
        if (self.motorSpeed) |v| out.motorSpeed = v;
        return out;
    }
};

/// A motor joint: drives the relative linear and angular velocity of two bodies
/// (`include/box3d/types.h:694-730`).
pub const MotorJointDef = struct {
    /// The shared settings.
    base: JointDef,
    /// Desired relative linear velocity.
    linearVelocity: ?math.Vec3 = null,
    /// Maximum motor force in newtons.
    maxVelocityForce: ?f32 = null,
    /// Desired relative angular velocity.
    angularVelocity: ?math.Vec3 = null,
    /// Maximum motor torque in newton-metres.
    maxVelocityTorque: ?f32 = null,
    /// Linear spring hertz for position control.
    linearHertz: ?f32 = null,
    linearDampingRatio: ?f32 = null,
    /// Maximum spring force in newtons.
    maxSpringForce: ?f32 = null,
    /// Angular spring hertz for position control.
    angularHertz: ?f32 = null,
    angularDampingRatio: ?f32 = null,
    /// Maximum spring torque in newton-metres.
    maxSpringTorque: ?f32 = null,

    pub fn native(self: MotorJointDef) c.b3MotorJointDef {
        var out = c.b3DefaultMotorJointDef();
        out.base = self.base.native();
        if (self.linearVelocity) |v| out.linearVelocity = v;
        if (self.maxVelocityForce) |v| out.maxVelocityForce = v;
        if (self.angularVelocity) |v| out.angularVelocity = v;
        if (self.maxVelocityTorque) |v| out.maxVelocityTorque = v;
        if (self.linearHertz) |v| out.linearHertz = v;
        if (self.linearDampingRatio) |v| out.linearDampingRatio = v;
        if (self.maxSpringForce) |v| out.maxSpringForce = v;
        if (self.angularHertz) |v| out.angularHertz = v;
        if (self.angularDampingRatio) |v| out.angularDampingRatio = v;
        if (self.maxSpringTorque) |v| out.maxSpringTorque = v;
        return out;
    }
};

/// A filter joint: disables collision between two specific bodies
/// (`include/box3d/types.h:736-742`). Nothing but the base.
pub const FilterJointDef = struct {
    /// The shared settings.
    base: JointDef,

    pub fn native(self: FilterJointDef) c.b3FilterJointDef {
        var out = c.b3DefaultFilterJointDef();
        out.base = self.base.native();
        return out;
    }
};

/// A parallel joint: keeps the z axes of two bodies parallel through a spring,
/// which is what holds a character upright (`include/box3d/types.h:748-765`).
pub const ParallelJointDef = struct {
    /// The shared settings.
    base: JointDef,
    /// Spring stiffness in hertz.
    hertz: ?f32 = null,
    dampingRatio: ?f32 = null,
    /// Maximum spring torque, typically in newton-metres.
    maxTorque: ?f32 = null,

    pub fn native(self: ParallelJointDef) c.b3ParallelJointDef {
        var out = c.b3DefaultParallelJointDef();
        out.base = self.base.native();
        if (self.hertz) |v| out.hertz = v;
        if (self.dampingRatio) |v| out.dampingRatio = v;
        if (self.maxTorque) |v| out.maxTorque = v;
        return out;
    }
};

/// A prismatic joint: body B slides along the x-axis of frame A and cannot
/// rotate (`include/box3d/types.h:771-810`).
pub const PrismaticJointDef = struct {
    /// The shared settings.
    base: JointDef,
    enableSpring: ?bool = null,
    hertz: ?f32 = null,
    dampingRatio: ?f32 = null,
    /// Target translation in metres; the spring drives to it.
    targetTranslation: ?f32 = null,
    enableLimit: ?bool = null,
    lowerTranslation: ?f32 = null,
    upperTranslation: ?f32 = null,
    enableMotor: ?bool = null,
    /// Maximum motor force, typically in newtons.
    maxMotorForce: ?f32 = null,
    /// Desired motor speed, typically m/s.
    motorSpeed: ?f32 = null,

    pub fn native(self: PrismaticJointDef) c.b3PrismaticJointDef {
        var out = c.b3DefaultPrismaticJointDef();
        out.base = self.base.native();
        if (self.enableSpring) |v| out.enableSpring = v;
        if (self.hertz) |v| out.hertz = v;
        if (self.dampingRatio) |v| out.dampingRatio = v;
        if (self.targetTranslation) |v| out.targetTranslation = v;
        if (self.enableLimit) |v| out.enableLimit = v;
        if (self.lowerTranslation) |v| out.lowerTranslation = v;
        if (self.upperTranslation) |v| out.upperTranslation = v;
        if (self.enableMotor) |v| out.enableMotor = v;
        if (self.maxMotorForce) |v| out.maxMotorForce = v;
        if (self.motorSpeed) |v| out.motorSpeed = v;
        return out;
    }
};

/// A revolute joint: a point on B is fixed to a point on A, with rotation
/// allowed about the z-axis (`include/box3d/types.h:816-854`).
pub const RevoluteJointDef = struct {
    /// The shared settings.
    base: JointDef,
    /// Body B's angle minus body A's in the reference state. This is the zero
    /// angle for the limit (`include/box3d/types.h:824-825`).
    targetAngle: ?f32 = null,
    enableSpring: ?bool = null,
    hertz: ?f32 = null,
    dampingRatio: ?f32 = null,
    enableLimit: ?bool = null,
    /// Lower limit in radians; upstream's minimum is `-0.99 * pi`.
    lowerAngle: ?f32 = null,
    /// Upper limit in radians; upstream's maximum is `0.99 * pi`.
    upperAngle: ?f32 = null,
    enableMotor: ?bool = null,
    /// Maximum motor torque, typically newton-metres.
    maxMotorTorque: ?f32 = null,
    /// Desired motor speed in rad/s.
    motorSpeed: ?f32 = null,

    pub fn native(self: RevoluteJointDef) c.b3RevoluteJointDef {
        var out = c.b3DefaultRevoluteJointDef();
        out.base = self.base.native();
        if (self.targetAngle) |v| out.targetAngle = v;
        if (self.enableSpring) |v| out.enableSpring = v;
        if (self.hertz) |v| out.hertz = v;
        if (self.dampingRatio) |v| out.dampingRatio = v;
        if (self.enableLimit) |v| out.enableLimit = v;
        if (self.lowerAngle) |v| out.lowerAngle = v;
        if (self.upperAngle) |v| out.upperAngle = v;
        if (self.enableMotor) |v| out.enableMotor = v;
        if (self.maxMotorTorque) |v| out.maxMotorTorque = v;
        if (self.motorSpeed) |v| out.motorSpeed = v;
        return out;
    }
};

/// A spherical joint: a point on B is fixed to a point on A, with rotation
/// allowed about it (`include/box3d/types.h:860-904`).
pub const SphericalJointDef = struct {
    /// The shared settings.
    base: JointDef,
    /// Spring that tries to align the two joint frames.
    enableSpring: ?bool = null,
    /// Spring stiffness in hertz. Upstream notes this may be clamped internally
    /// against the time step for stability (`include/box3d/types.h:869-871`).
    hertz: ?f32 = null,
    /// Spring damping ratio, non-negative.
    dampingRatio: ?f32 = null,
    /// Target spring rotation, frame B relative to frame A.
    targetRotation: ?math.Quat = null,
    /// Cone limit, centred on frame A's z-axis.
    enableConeLimit: ?bool = null,
    /// Cone half-angle in radians, in `[0, pi]`.
    coneAngle: ?f32 = null,
    /// Twist limit, centred on frame B's z-axis.
    enableTwistLimit: ?bool = null,
    /// Lower twist limit in radians; upstream's minimum is `-0.99 * pi`.
    lowerTwistAngle: ?f32 = null,
    /// Upper twist limit in radians; upstream's maximum is `0.99 * pi`.
    upperTwistAngle: ?f32 = null,
    enableMotor: ?bool = null,
    /// Maximum motor torque, typically newton-metres.
    maxMotorTorque: ?f32 = null,
    /// Desired motor angular velocity in rad/s.
    motorVelocity: ?math.Vec3 = null,

    pub fn native(self: SphericalJointDef) c.b3SphericalJointDef {
        var out = c.b3DefaultSphericalJointDef();
        out.base = self.base.native();
        if (self.enableSpring) |v| out.enableSpring = v;
        if (self.hertz) |v| out.hertz = v;
        if (self.dampingRatio) |v| out.dampingRatio = v;
        if (self.targetRotation) |v| out.targetRotation = v;
        if (self.enableConeLimit) |v| out.enableConeLimit = v;
        if (self.coneAngle) |v| out.coneAngle = v;
        if (self.enableTwistLimit) |v| out.enableTwistLimit = v;
        if (self.lowerTwistAngle) |v| out.lowerTwistAngle = v;
        if (self.upperTwistAngle) |v| out.upperTwistAngle = v;
        if (self.enableMotor) |v| out.enableMotor = v;
        if (self.maxMotorTorque) |v| out.maxMotorTorque = v;
        if (self.motorVelocity) |v| out.motorVelocity = v;
        return out;
    }
};

/// A weld joint: connects two bodies rigidly, with springs that can soften it
/// (`include/box3d/types.h:912-931`).
///
/// Upstream's note on that declaration is that Box3D's approximate solver
/// cannot hold many bodies together rigidly.
pub const WeldJointDef = struct {
    /// The shared settings.
    base: JointDef,
    /// Linear stiffness in hertz; zero means maximum stiffness.
    linearHertz: ?f32 = null,
    /// Angular stiffness in hertz; zero means maximum stiffness.
    angularHertz: ?f32 = null,
    linearDampingRatio: ?f32 = null,
    angularDampingRatio: ?f32 = null,

    pub fn native(self: WeldJointDef) c.b3WeldJointDef {
        var out = c.b3DefaultWeldJointDef();
        out.base = self.base.native();
        if (self.linearHertz) |v| out.linearHertz = v;
        if (self.angularHertz) |v| out.angularHertz = v;
        if (self.linearDampingRatio) |v| out.linearDampingRatio = v;
        if (self.angularDampingRatio) |v| out.angularDampingRatio = v;
        return out;
    }
};

/// A wheel joint: A is the chassis and B the wheel, which rotates about frame
/// B's z-axis, translates along frame A's x-axis, and can steer
/// (`include/box3d/types.h:937-998`).
pub const WheelJointDef = struct {
    /// The shared settings.
    base: JointDef,
    enableSuspensionSpring: ?bool = null,
    suspensionHertz: ?f32 = null,
    suspensionDampingRatio: ?f32 = null,
    enableSuspensionLimit: ?bool = null,
    lowerSuspensionLimit: ?f32 = null,
    upperSuspensionLimit: ?f32 = null,
    enableSpinMotor: ?bool = null,
    /// Maximum motor torque, typically newton-metres.
    maxSpinTorque: ?f32 = null,
    /// Desired speed in rad/s.
    spinSpeed: ?f32 = null,
    enableSteering: ?bool = null,
    steeringHertz: ?f32 = null,
    steeringDampingRatio: ?f32 = null,
    /// Target steering angle in radians.
    targetSteeringAngle: ?f32 = null,
    /// Maximum steering torque in newton-metres.
    maxSteeringTorque: ?f32 = null,
    enableSteeringLimit: ?bool = null,
    lowerSteeringLimit: ?f32 = null,
    upperSteeringLimit: ?f32 = null,

    pub fn native(self: WheelJointDef) c.b3WheelJointDef {
        var out = c.b3DefaultWheelJointDef();
        out.base = self.base.native();
        if (self.enableSuspensionSpring) |v| out.enableSuspensionSpring = v;
        if (self.suspensionHertz) |v| out.suspensionHertz = v;
        if (self.suspensionDampingRatio) |v| out.suspensionDampingRatio = v;
        if (self.enableSuspensionLimit) |v| out.enableSuspensionLimit = v;
        if (self.lowerSuspensionLimit) |v| out.lowerSuspensionLimit = v;
        if (self.upperSuspensionLimit) |v| out.upperSuspensionLimit = v;
        if (self.enableSpinMotor) |v| out.enableSpinMotor = v;
        if (self.maxSpinTorque) |v| out.maxSpinTorque = v;
        if (self.spinSpeed) |v| out.spinSpeed = v;
        if (self.enableSteering) |v| out.enableSteering = v;
        if (self.steeringHertz) |v| out.steeringHertz = v;
        if (self.steeringDampingRatio) |v| out.steeringDampingRatio = v;
        if (self.targetSteeringAngle) |v| out.targetSteeringAngle = v;
        if (self.maxSteeringTorque) |v| out.maxSteeringTorque = v;
        if (self.enableSteeringLimit) |v| out.enableSteeringLimit = v;
        if (self.lowerSteeringLimit) |v| out.lowerSteeringLimit = v;
        if (self.upperSteeringLimit) |v| out.upperSteeringLimit = v;
        return out;
    }
};

// -- creation ----------------------------------------------------------------

/// Create a distance joint (`include/box3d/box3d.h:1129`).
pub fn createDistance(id: world_mod.WorldId, def: DistanceJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateDistanceJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

/// Create a motor joint (`include/box3d/box3d.h:1219`).
pub fn createMotor(id: world_mod.WorldId, def: MotorJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateMotorJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

/// Create a filter joint (`include/box3d/box3d.h:1294`).
pub fn createFilter(id: world_mod.WorldId, def: FilterJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateFilterJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

/// Create a parallel joint (`include/box3d/box3d.h:1099`).
pub fn createParallel(id: world_mod.WorldId, def: ParallelJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateParallelJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

/// Create a prismatic joint (`include/box3d/box3d.h:1309`).
pub fn createPrismatic(id: world_mod.WorldId, def: PrismaticJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreatePrismaticJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

/// Create a revolute joint (`include/box3d/box3d.h:1391`).
pub fn createRevolute(id: world_mod.WorldId, def: RevoluteJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateRevoluteJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

/// Create a spherical joint (`include/box3d/box3d.h:1469`).
pub fn createSpherical(id: world_mod.WorldId, def: SphericalJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateSphericalJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

/// Create a weld joint (`include/box3d/box3d.h:1564`).
pub fn createWeld(id: world_mod.WorldId, def: WeldJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateWeldJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

/// Create a wheel joint (`include/box3d/box3d.h:1604`).
pub fn createWheel(id: world_mod.WorldId, def: WheelJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateWheelJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

// -- lifecycle and shared accessors ------------------------------------------

/// Destroy a joint (`include/box3d/box3d.h:1014`).
///
/// `wake_attached` says whether the two bodies should be woken afterwards, which
/// is what you want after changing a joint a resting scene is leaning on.
pub fn destroy(id: JointId, wake_attached: bool) void {
    c.b3DestroyJoint(id, wake_attached);
}

/// True while the id names a live joint (`include/box3d/box3d.h:1017`).
pub fn isValid(id: JointId) bool {
    return c.b3Joint_IsValid(id);
}

/// Which kind of constraint this is (`include/box3d/box3d.h:1020`).
pub fn getType(id: JointId) JointType {
    return c.b3Joint_GetType(id);
}

/// The first attached body (`include/box3d/box3d.h:1023`).
pub fn bodyA(id: JointId) body_mod.BodyId {
    return c.b3Joint_GetBodyA(id);
}

/// The second attached body (`include/box3d/box3d.h:1026`).
pub fn bodyB(id: JointId) body_mod.BodyId {
    return c.b3Joint_GetBodyB(id);
}

/// The world that owns this joint (`include/box3d/box3d.h:1029`).
pub fn world(id: JointId) world_mod.WorldId {
    return c.b3Joint_GetWorld(id);
}

/// Move the joint frame on body A (`include/box3d/box3d.h:1032`).
pub fn setLocalFrameA(id: JointId, frame: math.Transform) void {
    c.b3Joint_SetLocalFrameA(id, frame);
}

/// The joint frame on body A (`include/box3d/box3d.h:1035`).
pub fn localFrameA(id: JointId) math.Transform {
    return c.b3Joint_GetLocalFrameA(id);
}

/// Move the joint frame on body B (`include/box3d/box3d.h:1038`).
pub fn setLocalFrameB(id: JointId, frame: math.Transform) void {
    c.b3Joint_SetLocalFrameB(id, frame);
}

/// The joint frame on body B (`include/box3d/box3d.h:1041`).
pub fn localFrameB(id: JointId) math.Transform {
    return c.b3Joint_GetLocalFrameB(id);
}

/// Should the two attached bodies collide with each other?
/// (`include/box3d/box3d.h:1044`).
pub fn setCollideConnected(id: JointId, should_collide: bool) void {
    c.b3Joint_SetCollideConnected(id, should_collide);
}

/// Do the attached bodies collide (`include/box3d/box3d.h:1047`)?
pub fn collideConnected(id: JointId) bool {
    return c.b3Joint_GetCollideConnected(id);
}

/// Attach application data to a joint (`include/box3d/box3d.h:1050`).
///
/// A joint event carries this pointer back (`include/box3d/types.h:1230`), which
/// is how an application finds its own object from `world.jointEventSlice`.
pub fn setUserData(id: JointId, user_data: ?*anyopaque) void {
    c.b3Joint_SetUserData(id, user_data);
}

/// The pointer set with `setUserData` (`include/box3d/box3d.h:1053`).
pub fn userData(id: JointId) ?*anyopaque {
    return c.b3Joint_GetUserData(id);
}

/// Wake both attached bodies (`include/box3d/box3d.h:1056`).
pub fn wakeBodies(id: JointId) void {
    c.b3Joint_WakeBodies(id);
}

/// The constraint force the solver is currently applying, in newtons
/// (`include/box3d/box3d.h:1059`).
pub const constraintForce = c.b3Joint_GetConstraintForce;

/// The constraint torque the solver is currently applying
/// (`include/box3d/box3d.h:1062`).
pub const constraintTorque = c.b3Joint_GetConstraintTorque;

/// How far the joint is from its rest separation
/// (`include/box3d/box3d.h:1065`).
pub const linearSeparation = c.b3Joint_GetLinearSeparation;

/// How far the joint is from its rest angle (`include/box3d/box3d.h:1068`).
pub const angularSeparation = c.b3Joint_GetAngularSeparation;

/// Constraint stiffness and damping (`include/box3d/box3d.h:1074`).
pub fn setConstraintTuning(id: JointId, hertz: f32, damping_ratio: f32) void {
    c.b3Joint_SetConstraintTuning(id, hertz, damping_ratio);
}

/// The joint's constraint tuning (`include/box3d/box3d.h:1077`).
pub const ConstraintTuning = struct {
    hertz: f32,
    damping_ratio: f32,
};

/// Read the joint's constraint tuning. Advanced, upstream says
/// (`include/box3d/box3d.h:1075`).
pub fn constraintTuning(id: JointId) ConstraintTuning {
    var hertz: f32 = 0;
    var damping_ratio: f32 = 0;
    c.b3Joint_GetConstraintTuning(id, &hertz, &damping_ratio);
    return .{ .hertz = hertz, .damping_ratio = damping_ratio };
}

/// The force above which a joint event is reported, in newtons
/// (`include/box3d/box3d.h:1080`).
pub fn setForceThreshold(id: JointId, threshold: f32) void {
    c.b3Joint_SetForceThreshold(id, threshold);
}

/// The force threshold (`include/box3d/box3d.h:1083`)?
pub fn forceThreshold(id: JointId) f32 {
    return c.b3Joint_GetForceThreshold(id);
}

/// The torque above which a joint event is reported, in newton-metres
/// (`include/box3d/box3d.h:1086`).
pub fn setTorqueThreshold(id: JointId, threshold: f32) void {
    c.b3Joint_SetTorqueThreshold(id, threshold);
}

/// The torque threshold (`include/box3d/box3d.h:1089`)?
pub fn torqueThreshold(id: JointId) f32 {
    return c.b3Joint_GetTorqueThreshold(id);
}