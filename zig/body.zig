// SPDX-License-Identifier: MIT
//
//! Body creation, state, forces, mass and lifecycle.

const std = @import("std");
const c = @import("c");
const math = @import("math.zig");
const world_mod = @import("world.zig");

pub const BodyId = c.b3BodyId;

pub const BodyType = c.b3BodyType;
pub const staticBody: BodyType = c.b3_staticBody;
pub const kinematicBody: BodyType = c.b3_kinematicBody;
pub const dynamicBody: BodyType = c.b3_dynamicBody;

/// Axis locks; all fields default to false, so an empty value locks nothing.
pub const MotionLocks = c.b3MotionLocks;

pub const MassData = c.b3MassData;

/// `manifolds` borrows world memory; invalid after the next step or destruction.
pub const ContactData = c.b3ContactData;

/// Optional overrides of upstream's body defaults; unset fields retain them.
/// `.{}` uses an awake, enabled static body at the origin; Box3D sets its validity marker.
pub const BodyDef = struct {
    bodyType: ?BodyType = null,
    position: ?math.Pos = null,
    rotation: ?math.Quat = null,
    linearVelocity: ?math.Vec3 = null,
    angularVelocity: ?math.Vec3 = null,
    /// Linear damping above 1 is allowed and depends on the time step.
    linearDamping: ?f32 = null,
    angularDamping: ?f32 = null,
    gravityScale: ?f32 = null,
    /// Speed threshold for sleep; upstream scales its default by length units.
    sleepThreshold: ?f32 = null,
    /// Box3D copies at most `base.bodyNameLength` bytes including the terminator.
    name: ?[:0]const u8 = null,
    userData: ?*anyopaque = null,
    motionLocks: ?MotionLocks = null,
    enableSleep: ?bool = null,
    isAwake: ?bool = null,
    /// Continuous collision hint; bullets may still miss dynamic-versus-dynamic impacts
    /// (`include/box3d/types.h:320-333`).
    isBullet: ?bool = null,
    isEnabled: ?bool = null,
    allowFastRotation: ?bool = null,
    /// Contact recycling can leave ghost collisions; characters may disable it
    /// (`include/box3d/types.h:342-345`).
    enableContactRecycling: ?bool = null,

    pub fn native(self: BodyDef) c.b3BodyDef {
        var out = c.b3DefaultBodyDef();
        if (self.bodyType) |value| out.type = value;
        if (self.position) |value| out.position = value;
        if (self.rotation) |value| out.rotation = value;
        if (self.linearVelocity) |value| out.linearVelocity = value;
        if (self.angularVelocity) |value| out.angularVelocity = value;
        if (self.linearDamping) |value| out.linearDamping = value;
        if (self.angularDamping) |value| out.angularDamping = value;
        if (self.gravityScale) |value| out.gravityScale = value;
        if (self.sleepThreshold) |value| out.sleepThreshold = value;
        if (self.name) |value| out.name = value.ptr;
        if (self.userData) |value| out.userData = value;
        if (self.motionLocks) |value| out.motionLocks = value;
        if (self.enableSleep) |value| out.enableSleep = value;
        if (self.isAwake) |value| out.isAwake = value;
        if (self.isBullet) |value| out.isBullet = value;
        if (self.isEnabled) |value| out.isEnabled = value;
        if (self.allowFastRotation) |value| out.allowFastRotation = value;
        if (self.enableContactRecycling) |value| out.enableContactRecycling = value;
        return out;
    }
};

pub const Error = error{
    /// Returned when the world id is stale. A locked world may assert before
    /// this error is reported (`include/box3d/base.h:123-131`).
    InvalidWorld,
};

/// Create an empty body; attach geometry with `shape.create*`.
pub fn create(world_id: world_mod.WorldId, def: BodyDef) Error!BodyId {
    if (!world_mod.isValid(world_id)) return error.InvalidWorld;
    var native_def = def.native();
    const id = c.b3CreateBody(world_id, &native_def);
    if (!c.b3Body_IsValid(id)) return error.InvalidWorld;
    return id;
}

/// Destroy a body and its shapes and joints; their ids become stale.
pub fn destroy(id: BodyId) void {
    c.b3DestroyBody(id);
}

pub fn isValid(id: BodyId) bool {
    return c.b3Body_IsValid(id);
}

pub fn world(id: BodyId) world_mod.WorldId {
    return c.b3Body_GetWorld(id);
}

pub fn getType(id: BodyId) BodyType {
    return c.b3Body_GetType(id);
}

/// Change body type; existing contacts end and may be rebuilt on the next step.
pub fn setType(id: BodyId, body_type: BodyType) void {
    c.b3Body_SetType(id, body_type);
}

/// Set a debug name; Box3D copies at most `base.bodyNameLength` bytes including the terminator.
pub fn setName(id: BodyId, name: [:0]const u8) void {
    c.b3Body_SetName(id, name.ptr);
}

/// Borrow the body's name; the pointer expires on rename or destruction.
pub fn getName(id: BodyId) ?[:0]const u8 {
    const raw = c.b3Body_GetName(id);
    if (raw == null) return null;
    return std.mem.span(raw);
}

/// Box3D borrows this pointer and never frees it; body move events return it.
pub fn setUserData(id: BodyId, user_data: ?*anyopaque) void {
    c.b3Body_SetUserData(id, user_data);
}

pub fn userData(id: BodyId) ?*anyopaque {
    return c.b3Body_GetUserData(id);
}

pub fn position(id: BodyId) math.Pos {
    return c.b3Body_GetPosition(id);
}

pub fn rotation(id: BodyId) math.Quat {
    return c.b3Body_GetRotation(id);
}

pub fn transform(id: BodyId) math.WorldTransform {
    return c.b3Body_GetTransform(id);
}

/// Teleport the body; existing contacts are rebuilt on the next step.
pub fn setTransform(id: BodyId, new_position: math.Pos, new_rotation: math.Quat) void {
    c.box3dAbi_BodySetTransform(id, &new_position, &new_rotation);
}

pub fn localPoint(id: BodyId, world_point: math.Pos) math.Vec3 {
    return c.box3dAbi_BodyGetLocalPoint(id, &world_point);
}

pub fn worldPoint(id: BodyId, local_point: math.Vec3) math.Pos {
    return c.b3Body_GetWorldPoint(id, local_point);
}

pub fn localVector(id: BodyId, world_vector: math.Vec3) math.Vec3 {
    return c.b3Body_GetLocalVector(id, world_vector);
}

pub fn worldVector(id: BodyId, local_vector: math.Vec3) math.Vec3 {
    return c.b3Body_GetWorldVector(id, local_vector);
}

/// Move a kinematic body toward a target transform; `wake` controls bodies crossed.
pub fn setTargetTransform(id: BodyId, target: math.WorldTransform, time_step: f32, wake: bool) void {
    c.b3Body_SetTargetTransform(id, target, time_step, wake);
}

/// Linear velocity of the body origin, in m/s.
pub fn linearVelocity(id: BodyId) math.Vec3 {
    return c.b3Body_GetLinearVelocity(id);
}

pub fn angularVelocity(id: BodyId) math.Vec3 {
    return c.b3Body_GetAngularVelocity(id);
}

pub fn setLinearVelocity(id: BodyId, velocity: math.Vec3) void {
    c.b3Body_SetLinearVelocity(id, velocity);
}

pub fn setAngularVelocity(id: BodyId, velocity: math.Vec3) void {
    c.b3Body_SetAngularVelocity(id, velocity);
}

pub fn localPointVelocity(id: BodyId, local_point: math.Vec3) math.Vec3 {
    return c.b3Body_GetLocalPointVelocity(id, local_point);
}

pub fn worldPointVelocity(id: BodyId, world_point: math.Pos) math.Vec3 {
    return c.box3dAbi_BodyGetWorldPointVelocity(id, &world_point);
}

pub fn applyForce(id: BodyId, force: math.Vec3, point: math.Pos, wake: bool) void {
    c.b3Body_ApplyForce(id, force, point, wake);
}

pub fn applyForceToCenter(id: BodyId, force: math.Vec3, wake: bool) void {
    c.b3Body_ApplyForceToCenter(id, force, wake);
}

pub fn applyTorque(id: BodyId, torque: math.Vec3, wake: bool) void {
    c.b3Body_ApplyTorque(id, torque, wake);
}

pub fn applyLinearImpulse(id: BodyId, impulse: math.Vec3, point: math.Pos, wake: bool) void {
    c.b3Body_ApplyLinearImpulse(id, impulse, point, wake);
}

pub fn applyLinearImpulseToCenter(id: BodyId, impulse: math.Vec3, wake: bool) void {
    c.b3Body_ApplyLinearImpulseToCenter(id, impulse, wake);
}

pub fn applyAngularImpulse(id: BodyId, impulse: math.Vec3, wake: bool) void {
    c.b3Body_ApplyAngularImpulse(id, impulse, wake);
}

/// Mass in kg, computed from attached shapes' densities.
pub fn mass(id: BodyId) f32 {
    return c.b3Body_GetMass(id);
}

pub fn inverseMass(id: BodyId) f32 {
    return c.b3Body_GetInverseMass(id);
}

/// Inertia tensor about the centre of mass, in body-local axes.
pub fn localRotationalInertia(id: BodyId) math.Mat3 {
    return c.b3Body_GetLocalRotationalInertia(id);
}

pub const worldInverseRotationalInertia = c.b3Body_GetWorldInverseRotationalInertia;

pub fn localCenterOfMass(id: BodyId) math.Vec3 {
    return c.b3Body_GetLocalCenterOfMass(id);
}

pub fn worldCenterOfMass(id: BodyId) math.Pos {
    return c.b3Body_GetWorldCenterOfMass(id);
}

/// Override shape-computed mass properties; `applyMassFromShapes` restores them.
pub fn setMassData(id: BodyId, mass_data: MassData) void {
    c.b3Body_SetMassData(id, mass_data);
}

pub fn massData(id: BodyId) MassData {
    return c.b3Body_GetMassData(id);
}

pub fn applyMassFromShapes(id: BodyId) void {
    c.b3Body_ApplyMassFromShapes(id);
}

pub fn setLinearDamping(id: BodyId, linear_damping: f32) void {
    c.b3Body_SetLinearDamping(id, linear_damping);
}

pub fn linearDamping(id: BodyId) f32 {
    return c.b3Body_GetLinearDamping(id);
}

pub fn setAngularDamping(id: BodyId, angular_damping: f32) void {
    c.b3Body_SetAngularDamping(id, angular_damping);
}

pub fn angularDamping(id: BodyId) f32 {
    return c.b3Body_GetAngularDamping(id);
}

pub fn setGravityScale(id: BodyId, gravity_scale: f32) void {
    c.b3Body_SetGravityScale(id, gravity_scale);
}

pub fn gravityScale(id: BodyId) f32 {
    return c.b3Body_GetGravityScale(id);
}

pub fn isAwake(id: BodyId) bool {
    return c.b3Body_IsAwake(id);
}

pub fn setAwake(id: BodyId, awake: bool) void {
    c.b3Body_SetAwake(id, awake);
}

pub fn enableSleep(id: BodyId, enable_sleep: bool) void {
    c.b3Body_EnableSleep(id, enable_sleep);
}

pub fn isSleepEnabled(id: BodyId) bool {
    return c.b3Body_IsSleepEnabled(id);
}

/// Speed below which the body may sleep.
pub fn setSleepThreshold(id: BodyId, sleep_threshold: f32) void {
    c.b3Body_SetSleepThreshold(id, sleep_threshold);
}

pub fn sleepThreshold(id: BodyId) f32 {
    return c.b3Body_GetSleepThreshold(id);
}

/// Disabled bodies neither move nor collide (`include/box3d/types.h:335-336`).
pub fn isEnabled(id: BodyId) bool {
    return c.b3Body_IsEnabled(id);
}

pub fn disable(id: BodyId) void {
    c.b3Body_Disable(id);
}

pub fn enable(id: BodyId) void {
    c.b3Body_Enable(id);
}

pub fn setMotionLocks(id: BodyId, locks: MotionLocks) void {
    c.b3Body_SetMotionLocks(id, locks);
}

pub fn motionLocks(id: BodyId) MotionLocks {
    return c.b3Body_GetMotionLocks(id);
}

pub fn setBullet(id: BodyId, flag: bool) void {
    c.b3Body_SetBullet(id, flag);
}

pub fn isBullet(id: BodyId) bool {
    return c.b3Body_IsBullet(id);
}

pub fn enableContactRecycling(id: BodyId, flag: bool) void {
    c.b3Body_EnableContactRecycling(id, flag);
}

pub fn isContactRecyclingEnabled(id: BodyId) bool {
    return c.b3Body_IsContactRecyclingEnabled(id);
}

/// Hit events also require the world's impact-speed threshold.
pub fn enableHitEvents(id: BodyId, enable_hit_events: bool) void {
    c.b3Body_EnableHitEvents(id, enable_hit_events);
}

pub fn shapeCount(id: BodyId) c_int {
    return c.b3Body_GetShapeCount(id);
}

/// Write up to `out.len` shape ids and return the count; a full slice may omit more.
pub fn shapes(id: BodyId, out: []c.b3ShapeId) c_int {
    if (out.len == 0) return 0;
    return c.b3Body_GetShapes(id, out.ptr, @intCast(out.len));
}

/// Allocate a slice of all shape ids; the caller owns the returned slice.
pub fn shapeSlice(id: BodyId, allocator: std.mem.Allocator) ![]c.b3ShapeId {
    const count = shapeCount(id);
    if (count <= 0) return &.{};
    const out = try allocator.alloc(c.b3ShapeId, @intCast(count));
    errdefer allocator.free(out);
    const written = c.b3Body_GetShapes(id, out.ptr, count);
    return out[0..@intCast(written)];
}

pub fn jointCount(id: BodyId) c_int {
    return c.b3Body_GetJointCount(id);
}

/// Write up to `out.len` joint ids and return the count.
pub fn joints(id: BodyId, out: []c.b3JointId) c_int {
    if (out.len == 0) return 0;
    return c.b3Body_GetJoints(id, out.ptr, @intCast(out.len));
}

/// Allocate a slice of all joint ids; the caller owns the returned slice.
pub fn jointSlice(id: BodyId, allocator: std.mem.Allocator) ![]c.b3JointId {
    const count = jointCount(id);
    if (count <= 0) return &.{};
    const out = try allocator.alloc(c.b3JointId, @intCast(count));
    errdefer allocator.free(out);
    const written = c.b3Body_GetJoints(id, out.ptr, count);
    return out[0..@intCast(written)];
}

pub fn contactCapacity(id: BodyId) c_int {
    return c.b3Body_GetContactCapacity(id);
}

/// Write up to `out.len` contacts and return the number written.
/// `manifolds` borrows world memory and expires; see `ContactData`.
pub fn contactData(id: BodyId, out: []ContactData) c_int {
    if (out.len == 0) return 0;
    return c.b3Body_GetContactData(id, out.ptr, @intCast(out.len));
}

pub const computeAabb = c.b3Body_ComputeAABB;

pub fn closestPoint(id: BodyId, result: *math.Vec3, target: math.Vec3) f32 {
    return c.b3Body_GetClosestPoint(id, result, target);
}
