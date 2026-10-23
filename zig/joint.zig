// SPDX-License-Identifier: MIT
//
//! Joint definitions, creation, shared settings and lifecycle.

const c = @import("c");
const math = @import("math.zig");
const body_mod = @import("body.zig");
const world_mod = @import("world.zig");

pub const JointId = c.b3JointId;

pub const JointType = c.b3JointType;

/// Local frames are relative to body origins, not centres of mass (`include/box3d/types.h:599-603`).
pub const JointDef = struct {
    bodyIdA: body_mod.BodyId,
    bodyIdB: body_mod.BodyId,
    localFrameA: ?math.Transform = null,
    localFrameB: ?math.Transform = null,
    /// Force above which a joint event is reported, in newtons.
    forceThreshold: ?f32 = null,
    /// Torque above which a joint event is reported, in newton-metres.
    torqueThreshold: ?f32 = null,
    constraintHertz: ?f32 = null,
    constraintDampingRatio: ?f32 = null,
    drawScale: ?f32 = null,
    collideConnected: ?bool = null,
    userData: ?*anyopaque = null,

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

/// Upstream defaults both body ids to null; its constructor preserves the validity cookie.
pub fn defaultBase() c.b3JointDef {
    return c.b3DefaultDistanceJointDef().base;
}

pub const Error = error{
    /// Stale worlds return this error; locked worlds and stale body ids may assert first
    /// (`src/joint.c:163-164`; `src/physics_world.c:93-104`).
    InvalidWorld,
};

/// Distance joint for ropes and springs, connecting points on bodies A and B
/// (`include/box3d/types.h:643-688`).
pub const DistanceJointDef = struct {
    base: JointDef,
    /// Rest length, clamped internally to a stable minimum.
    length: ?f32 = null,
    /// False makes the joint rigid and overrides limits and motors (`include/box3d/types.h:655-656`).
    enableSpring: ?bool = null,
    lowerSpringForce: ?f32 = null,
    upperSpringForce: ?f32 = null,
    /// Spring stiffness in hertz.
    hertz: ?f32 = null,
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

/// Drives relative linear and angular velocity (`include/box3d/types.h:694-730`).
pub const MotorJointDef = struct {
    base: JointDef,
    linearVelocity: ?math.Vec3 = null,
    /// Maximum motor force in newtons.
    maxVelocityForce: ?f32 = null,
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

pub const FilterJointDef = struct {
    base: JointDef,

    pub fn native(self: FilterJointDef) c.b3FilterJointDef {
        var out = c.b3DefaultFilterJointDef();
        out.base = self.base.native();
        return out;
    }
};

/// Keeps the bodies' z axes parallel through a spring (`include/box3d/types.h:748-765`).
pub const ParallelJointDef = struct {
    base: JointDef,
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

/// Body B slides along frame A's x-axis and cannot rotate (`include/box3d/types.h:771-810`).
pub const PrismaticJointDef = struct {
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

/// A point on B is fixed to a point on A; rotation is allowed about frame A's z-axis
/// (`include/box3d/types.h:816-854`).
pub const RevoluteJointDef = struct {
    base: JointDef,
    /// Reference angle: body B's angle minus body A's (`include/box3d/types.h:824-825`).
    targetAngle: ?f32 = null,
    enableSpring: ?bool = null,
    hertz: ?f32 = null,
    dampingRatio: ?f32 = null,
    enableLimit: ?bool = null,
    /// Limits are radians; upstream clamps them to `[-0.99 * pi, 0.99 * pi]`.
    lowerAngle: ?f32 = null,
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

/// A point on B is fixed to a point on A, with rotation allowed about it (`include/box3d/types.h:860-904`).
pub const SphericalJointDef = struct {
    base: JointDef,
    /// Spring that tries to align the two joint frames.
    enableSpring: ?bool = null,
    /// Spring stiffness may be clamped against the time step for stability
    /// (`include/box3d/types.h:869-871`).
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
    /// Twist limits are radians; upstream clamps them to `[-0.99 * pi, 0.99 * pi]`.
    lowerTwistAngle: ?f32 = null,
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

/// Weld joint with optional softening springs; the approximate solver cannot hold many bodies rigidly
/// (`include/box3d/types.h:912-931`).
pub const WeldJointDef = struct {
    base: JointDef,
    /// Zero hertz means maximum stiffness for both springs.
    linearHertz: ?f32 = null,
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

/// Wheel joint: A is the chassis, B the wheel; B rotates on its z-axis and slides on A's x-axis.
/// It also steers (`include/box3d/types.h:937-998`).
pub const WheelJointDef = struct {
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

pub fn createDistance(id: world_mod.WorldId, def: DistanceJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateDistanceJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

pub fn createMotor(id: world_mod.WorldId, def: MotorJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateMotorJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

pub fn createFilter(id: world_mod.WorldId, def: FilterJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateFilterJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

pub fn createParallel(id: world_mod.WorldId, def: ParallelJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateParallelJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

pub fn createPrismatic(id: world_mod.WorldId, def: PrismaticJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreatePrismaticJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

pub fn createRevolute(id: world_mod.WorldId, def: RevoluteJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateRevoluteJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

pub fn createSpherical(id: world_mod.WorldId, def: SphericalJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateSphericalJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

pub fn createWeld(id: world_mod.WorldId, def: WeldJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateWeldJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

pub fn createWheel(id: world_mod.WorldId, def: WheelJointDef) Error!JointId {
    if (!world_mod.isValid(id)) return error.InvalidWorld;
    var native_def = def.native();
    const joint = c.b3CreateWheelJoint(id, &native_def);
    if (!c.b3Joint_IsValid(joint)) return error.InvalidWorld;
    return joint;
}

/// Destroy a joint; `wake_attached` controls whether its bodies wake.
pub fn destroy(id: JointId, wake_attached: bool) void {
    c.b3DestroyJoint(id, wake_attached);
}

pub fn isValid(id: JointId) bool {
    return c.b3Joint_IsValid(id);
}

pub fn getType(id: JointId) JointType {
    return c.b3Joint_GetType(id);
}

pub fn bodyA(id: JointId) body_mod.BodyId {
    return c.b3Joint_GetBodyA(id);
}

pub fn bodyB(id: JointId) body_mod.BodyId {
    return c.b3Joint_GetBodyB(id);
}

pub fn world(id: JointId) world_mod.WorldId {
    return c.b3Joint_GetWorld(id);
}

pub fn setLocalFrameA(id: JointId, frame: math.Transform) void {
    c.b3Joint_SetLocalFrameA(id, frame);
}

pub fn localFrameA(id: JointId) math.Transform {
    return c.b3Joint_GetLocalFrameA(id);
}

pub fn setLocalFrameB(id: JointId, frame: math.Transform) void {
    c.b3Joint_SetLocalFrameB(id, frame);
}

pub fn localFrameB(id: JointId) math.Transform {
    return c.b3Joint_GetLocalFrameB(id);
}

pub fn setCollideConnected(id: JointId, should_collide: bool) void {
    c.b3Joint_SetCollideConnected(id, should_collide);
}

pub fn collideConnected(id: JointId) bool {
    return c.b3Joint_GetCollideConnected(id);
}

/// Borrowed application data; Box3D does not free it, and joint events return it.
pub fn setUserData(id: JointId, user_data: ?*anyopaque) void {
    c.b3Joint_SetUserData(id, user_data);
}

pub fn userData(id: JointId) ?*anyopaque {
    return c.b3Joint_GetUserData(id);
}

pub fn wakeBodies(id: JointId) void {
    c.b3Joint_WakeBodies(id);
}

/// Constraint force applied by the solver, in newtons.
pub const constraintForce = c.b3Joint_GetConstraintForce;

/// Constraint torque applied by the solver, in newton-metres.
pub const constraintTorque = c.b3Joint_GetConstraintTorque;

/// Linear separation from the joint's rest state.
pub const linearSeparation = c.b3Joint_GetLinearSeparation;

/// Angular separation from the joint's rest angle.
pub const angularSeparation = c.b3Joint_GetAngularSeparation;

/// Set constraint stiffness in hertz and damping ratio.
pub fn setConstraintTuning(id: JointId, hertz: f32, damping_ratio: f32) void {
    c.b3Joint_SetConstraintTuning(id, hertz, damping_ratio);
}

pub const ConstraintTuning = struct {
    hertz: f32,
    damping_ratio: f32,
};

pub fn constraintTuning(id: JointId) ConstraintTuning {
    var hertz: f32 = 0;
    var damping_ratio: f32 = 0;
    c.b3Joint_GetConstraintTuning(id, &hertz, &damping_ratio);
    return .{ .hertz = hertz, .damping_ratio = damping_ratio };
}

/// Force threshold for reporting joint events, in newtons.
pub fn setForceThreshold(id: JointId, threshold: f32) void {
    c.b3Joint_SetForceThreshold(id, threshold);
}

pub fn forceThreshold(id: JointId) f32 {
    return c.b3Joint_GetForceThreshold(id);
}

/// Torque threshold for reporting joint events, in newton-metres.
pub fn setTorqueThreshold(id: JointId, threshold: f32) void {
    c.b3Joint_SetTorqueThreshold(id, threshold);
}

pub fn torqueThreshold(id: JointId) f32 {
    return c.b3Joint_GetTorqueThreshold(id);
}
