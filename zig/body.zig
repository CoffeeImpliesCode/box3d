// SPDX-License-Identifier: MIT
//
//! Bodies: creating one, giving it shapes, reading and writing its state,
//! pushing it around, and destroying it.
//!
//! ## Ids, not handles
//!
//! A `BodyId` is `b3BodyId` (`include/box3d/id.h:43-48`), an index, a world
//! index and a generation, passed by value. There is no wrapper and no heap:
//! `create` hands back an id and `destroy` takes it.
//!
//! ## What a body owns, and what destroying it does to your ids
//!
//! A body owns the shapes created on it and the joints attached to it.
//! Destroying the body destroys both, and every shape and joint id the caller
//! still holds becomes stale (`include/box3d/box3d.h:488-489`). The contact
//! and sensor events it read in a previous step may name shapes that have
//! since gone - upstream warns about exactly this on `b3SensorEndTouchEvent`
//! (`include/box3d/types.h:1062-1073`) and on `b3ContactData`.
//!
//! ## Mass comes from shapes
//!
//! A dynamic body's mass is computed from the density of its shapes
//! (`include/box3d/box3d.h:619-642`). A dynamic body with no shapes, or with
//! shapes of zero density, has zero mass, and a zero-mass dynamic body does not
//! move under gravity. `mass` reads back what was computed;
//! `applyMassFromShapes` recomputes it after shapes are added or destroyed.

const std = @import("std");
const c = @import("c");
const math = @import("math.zig");
const world_mod = @import("world.zig");

/// A body handle, `b3BodyId` (`include/box3d/id.h:43-48`).
pub const BodyId = c.b3BodyId;

/// How a body behaves, `b3BodyType` (`include/box3d/types.h:221-237`).
///
/// * `static`: zero mass, zero velocity, moved only by the application.
/// * `kinematic`: zero mass, velocity set by the application, moved by the
///   solver against dynamics.
/// * `dynamic`: positive mass, velocity determined by forces.
pub const BodyType = c.b3BodyType;
/// No mass and no velocity; the application moves it.
pub const staticBody: BodyType = c.b3_staticBody;
/// No mass, velocity set by the application, pushed by the solver.
pub const kinematicBody: BodyType = c.b3_kinematicBody;
/// Positive mass, velocity determined by forces.
pub const dynamicBody: BodyType = c.b3_dynamicBody;

/// Axis locks, `b3MotionLocks` (`include/box3d/types.h:241-260`).
///
/// All six fields default to false, so `.{ .{} }` locks nothing and a partial
/// literal is valid.
pub const MotionLocks = c.b3MotionLocks;

/// Mass, centre of mass and inertia, `b3MassData`
/// (`include/box3d/types.h:1865-1876`).
pub const MassData = c.b3MassData;

/// Contact data for two touching shapes, `b3ContactData`
/// (`include/box3d/types.h:1250-1268`).
///
/// `manifolds` points into world memory that the next step or any destruction
/// replaces, and upstream says not to store the pointer
/// (`include/box3d/types.h:1262-1263`).
pub const ContactData = c.b3ContactData;

/// A body definition, as optional overrides of upstream's defaults.
///
/// `.{}` is a complete, valid definition that asks for upstream's defaults:
/// static, at the origin, no rotation, sleeping enabled, awake and enabled
/// (`src/types.c:32-45`). Upstream is explicit that a body should be *created*
/// at the position it wants rather than moved there afterwards: creating at the
/// origin and then moving nearly doubles the cost of creation, especially once
/// shapes have been added (`include/box3d/types.h:272-274`).
///
/// `internalValue` is absent on purpose: it is upstream's own validity marker
/// (`include/box3d/types.h:347-348`) and must come from `b3DefaultBodyDef`.
pub const BodyDef = struct {
    /// Static, kinematic or dynamic. Upstream's default is static
    /// (`src/types.c:35`).
    bodyType: ?BodyType = null,
    /// World position to create the body at.
    position: ?math.Pos = null,
    /// World rotation to create the body with.
    rotation: ?math.Quat = null,
    /// Initial linear velocity of the body origin, in m/s.
    linearVelocity: ?math.Vec3 = null,
    /// Initial angular velocity, in rad/s.
    angularVelocity: ?math.Vec3 = null,
    /// Velocity-proportional damping. Larger than 1 is allowed and makes the
    /// damping sensitive to the time step (`include/box3d/types.h:286-294`).
    linearDamping: ?f32 = null,
    /// Angular-proportional damping (`include/box3d/types.h:296-300`).
    angularDamping: ?f32 = null,
    /// Multiplier on the world's gravity for this body.
    gravityScale: ?f32 = null,
    /// Speed below which the body may sleep, in m/s. Upstream's default is
    /// `0.05 * lengthUnitsPerMeter` (`src/types.c:37`).
    sleepThreshold: ?f32 = null,
    /// Debug name. At most `base.bodyNameLength` bytes including the
    /// terminator (`include/box3d/constants.h:100-104`); Box3D copies it.
    name: ?[:0]const u8 = null,
    /// Application data, readable with `userData`.
    userData: ?*anyopaque = null,
    /// Axis locks.
    motionLocks: ?MotionLocks = null,
    /// May this body ever sleep?
    enableSleep: ?bool = null,
    /// Is it awake at creation? (`include/box3d/types.h:317-318`)
    isAwake: ?bool = null,
    /// Treat as a high-speed object and check it continuously
    /// (`include/box3d/types.h:320-333`). Upstream's own warning on that line:
    /// bullets are not a solution for general dynamic-versus-dynamic continuous
    /// collision and can miss.
    isBullet: ?bool = null,
    /// Create it enabled (`include/box3d/types.h:335-336`).
    isEnabled: ?bool = null,
    /// Bypass rotational speed limits. For circular objects like wheels
    /// (`include/box3d/types.h:338-340`).
    allowFastRotation: ?bool = null,
    /// Enable contact recycling. Upstream notes that leaving it on improves
    /// performance but can leave ghost collisions, which is why characters turn
    /// it off (`include/box3d/types.h:342-345`).
    enableContactRecycling: ?bool = null,

    /// The definition Box3D wants: upstream's defaults with the set fields
    /// written over them.
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

/// Everything that can go wrong in this module.
pub const Error = error{
    /// The world id was not a live world. Create the body in a world that
    /// `world.isValid` still reports.
    ///
    /// `b3CreateBody` does answer a stale world id with a null id
    /// (`src/body.c:171-174`), but only after it has looked the world up with
    /// `b3GetUnlockedWorldFromId` (`src/body.c:169`), and that lookup asserts
    /// on an out-of-range index or a generation that does not match
    /// (`src/physics_world.c:93-96`) and on a locked world
    /// (`src/physics_world.c:101-104`) before it can return null. So this
    /// module asks `world.isValid` - upstream's own public predicate, same
    /// generation comparison (`src/physics_world.c:1777-1793`) - first, and the
    /// null id is never reached for a stale world. The check after the call
    /// stays because it is what reports the locked-world case in a build where
    /// the assertion does not fire: `B3_ASSERT` compiles to nothing under
    /// `NDEBUG` without `B3_ENABLE_ASSERT` (`include/box3d/base.h:123-131`),
    /// and a handler installed through `base.setAssertFcn` may return 0 to
    /// skip the break (`src/core.c:81-90`).
    InvalidWorld,
};

// -- lifecycle ---------------------------------------------------------------

/// Create a body in `world_id`.
///
/// A body is created empty and gets its geometry from `shape.create*`
/// afterwards, except that upstream recommends creating it at the position it
/// will live at rather than moving it there later
/// (`include/box3d/types.h:272-274`).
pub fn create(world_id: world_mod.WorldId, def: BodyDef) Error!BodyId {
    if (!world_mod.isValid(world_id)) return error.InvalidWorld;
    var native_def = def.native();
    const id = c.b3CreateBody(world_id, &native_def);
    if (!c.b3Body_IsValid(id)) return error.InvalidWorld;
    return id;
}

/// Destroy a body, its shapes and its joints.
///
/// Every shape id and joint id for this body becomes stale immediately, as does
/// any contact id that named one of them.
pub fn destroy(id: BodyId) void {
    c.b3DestroyBody(id);
}

/// True while the id names a live body (`include/box3d/box3d.h:492-493`).
///
/// This is the check to reach for after anything that could have destroyed the
/// body underneath you: another body's destruction, a filter change, a type
/// change, or the world going away.
pub fn isValid(id: BodyId) bool {
    return c.b3Body_IsValid(id);
}

/// The world this body belongs to (`include/box3d/box3d.h:727`).
pub fn world(id: BodyId) world_mod.WorldId {
    return c.b3Body_GetWorld(id);
}

/// How a body behaves (`include/box3d/box3d.h:497`).
pub fn getType(id: BodyId) BodyType {
    return c.b3Body_GetType(id);
}

/// Change a body's type (`include/box3d/box3d.h:501`).
///
/// This is how a body becomes a mover or a platform. It ends any contacts the
/// body had, so a contact id read before the change may be orphaned.
pub fn setType(id: BodyId, body_type: BodyType) void {
    c.b3Body_SetType(id, body_type);
}

/// Give a body a debug name (`include/box3d/box3d.h:504`).
///
/// Box3D copies at most `base.bodyNameLength` bytes including the terminator, so
/// a longer name is truncated rather than rejected. A sentinel-terminated
/// string is the type, because the length that matters upstream is the length
/// the terminator implies.
pub fn setName(id: BodyId, name: [:0]const u8) void {
    c.b3Body_SetName(id, name.ptr);
}

/// The body's name, or null if it has none (`include/box3d/box3d.h:507`).
///
/// The pointer is into Box3D's storage and stays valid until the body is
/// destroyed or renamed.
pub fn getName(id: BodyId) ?[:0]const u8 {
    const raw = c.b3Body_GetName(id);
    if (raw == null) return null;
    return std.mem.span(raw);
}

/// Attach application data to a body (`include/box3d/box3d.h:510-511`).
///
/// Box3D never dereferences or frees it. The pointer is also what a body move
/// event carries back (`include/box3d/types.h:1199`), which is how a renderer
/// finds its own object from an event.
pub fn setUserData(id: BodyId, user_data: ?*anyopaque) void {
    c.b3Body_SetUserData(id, user_data);
}

/// The pointer set with `setUserData` (`include/box3d/box3d.h:513-514`).
pub fn userData(id: BodyId) ?*anyopaque {
    return c.b3Body_GetUserData(id);
}

// -- transform ---------------------------------------------------------------

/// The body's world position (`include/box3d/box3d.h:516`).
pub fn position(id: BodyId) math.Pos {
    return c.b3Body_GetPosition(id);
}

/// The body's world rotation (`include/box3d/box3d.h:519`).
pub fn rotation(id: BodyId) math.Quat {
    return c.b3Body_GetRotation(id);
}

/// The body's world transform (`include/box3d/box3d.h:522`).
///
/// One call instead of two, and in large world mode it is a
/// double-translation transform where `Transform` would not be
/// (`include/box3d/math_functions.h:78-95`).
pub fn transform(id: BodyId) math.WorldTransform {
    return c.b3Body_GetTransform(id);
}

/// Move a body (`include/box3d/box3d.h:527`).
///
/// This is a teleport, not a velocity: contacts it had are ended and rebuilt on
/// the next step. Creating a body at its final position is cheaper than creating
/// it at the origin and moving it (`include/box3d/types.h:272-274`).
pub fn setTransform(id: BodyId, new_position: math.Pos, new_rotation: math.Quat) void {
    c.box3dAbi_BodySetTransform(id, &new_position, &new_rotation);
}

/// Express a world point in the body's local frame
/// (`include/box3d/box3d.h:530`).
pub fn localPoint(id: BodyId, world_point: math.Pos) math.Vec3 {
    return c.box3dAbi_BodyGetLocalPoint(id, &world_point);
}

/// Express a local point in world space (`include/box3d/box3d.h:533`).
pub fn worldPoint(id: BodyId, local_point: math.Vec3) math.Pos {
    return c.b3Body_GetWorldPoint(id, local_point);
}

/// Express a world direction in the body's local frame
/// (`include/box3d/box3d.h:536`).
pub fn localVector(id: BodyId, world_vector: math.Vec3) math.Vec3 {
    return c.b3Body_GetLocalVector(id, world_vector);
}

/// Express a local direction in world space (`include/box3d/box3d.h:539`).
pub fn worldVector(id: BodyId, local_vector: math.Vec3) math.Vec3 {
    return c.b3Body_GetWorldVector(id, local_vector);
}

/// Move a body to a target transform over `time_step` seconds
/// (`include/box3d/box3d.h:557`).
///
/// For a kinematic mover this is the smooth way to move. `wake` says whether
/// bodies the path crosses should be woken.
pub fn setTargetTransform(id: BodyId, target: math.WorldTransform, time_step: f32, wake: bool) void {
    c.b3Body_SetTargetTransform(id, target, time_step, wake);
}

// -- velocity ----------------------------------------------------------------

/// The body's linear velocity of its origin, in m/s
/// (`include/box3d/box3d.h:542`).
pub fn linearVelocity(id: BodyId) math.Vec3 {
    return c.b3Body_GetLinearVelocity(id);
}

/// The body's angular velocity, in rad/s (`include/box3d/box3d.h:545`).
pub fn angularVelocity(id: BodyId) math.Vec3 {
    return c.b3Body_GetAngularVelocity(id);
}

/// Set the linear velocity of the body's origin (`include/box3d/box3d.h:548`).
pub fn setLinearVelocity(id: BodyId, velocity: math.Vec3) void {
    c.b3Body_SetLinearVelocity(id, velocity);
}

/// Set the angular velocity (`include/box3d/box3d.h:551`).
pub fn setAngularVelocity(id: BodyId, velocity: math.Vec3) void {
    c.b3Body_SetAngularVelocity(id, velocity);
}

/// The velocity of a point given in the body's local frame
/// (`include/box3d/box3d.h:560`).
pub fn localPointVelocity(id: BodyId, local_point: math.Vec3) math.Vec3 {
    return c.b3Body_GetLocalPointVelocity(id, local_point);
}

/// The velocity of a point given in world space (`include/box3d/box3d.h:563`).
pub fn worldPointVelocity(id: BodyId, world_point: math.Pos) math.Vec3 {
    return c.box3dAbi_BodyGetWorldPointVelocity(id, &world_point);
}

// -- forces and impulses -----------------------------------------------------

/// Apply a force at a world point, waking the body if asked
/// (`include/box3d/box3d.h:572`).
///
/// A force is integrated over the step, so it is the right unit for a thruster
/// and the wrong one for a hit.
pub fn applyForce(id: BodyId, force: math.Vec3, point: math.Pos, wake: bool) void {
    c.b3Body_ApplyForce(id, force, point, wake);
}

/// Apply a force at the body's centre of mass
/// (`include/box3d/box3d.h:579`).
pub fn applyForceToCenter(id: BodyId, force: math.Vec3, wake: bool) void {
    c.b3Body_ApplyForceToCenter(id, force, wake);
}

/// Apply a torque (`include/box3d/box3d.h:586`).
pub fn applyTorque(id: BodyId, torque: math.Vec3, wake: bool) void {
    c.b3Body_ApplyTorque(id, torque, wake);
}

/// Apply a linear impulse at a world point (`include/box3d/box3d.h:598`).
///
/// An impulse changes velocity immediately rather than being integrated, which
/// is what makes it the right unit for a collision or a jump.
pub fn applyLinearImpulse(id: BodyId, impulse: math.Vec3, point: math.Pos, wake: bool) void {
    c.b3Body_ApplyLinearImpulse(id, impulse, point, wake);
}

/// Apply a linear impulse at the body's centre of mass
/// (`include/box3d/box3d.h:607`).
pub fn applyLinearImpulseToCenter(id: BodyId, impulse: math.Vec3, wake: bool) void {
    c.b3Body_ApplyLinearImpulseToCenter(id, impulse, wake);
}

/// Apply an angular impulse (`include/box3d/box3d.h:616`).
pub fn applyAngularImpulse(id: BodyId, impulse: math.Vec3, wake: bool) void {
    c.b3Body_ApplyAngularImpulse(id, impulse, wake);
}

// -- mass --------------------------------------------------------------------

/// The body's mass in kg (`include/box3d/box3d.h:619`).
///
/// Computed from its shapes' densities; see the module comment.
pub fn mass(id: BodyId) f32 {
    return c.b3Body_GetMass(id);
}

/// One over the mass (`include/box3d/box3d.h:625`).
pub fn inverseMass(id: BodyId) f32 {
    return c.b3Body_GetInverseMass(id);
}

/// The inertia tensor about the centre of mass, in body-local axes
/// (`include/box3d/box3d.h:622`).
pub fn localRotationalInertia(id: BodyId) math.Mat3 {
    return c.b3Body_GetLocalRotationalInertia(id);
}

/// The inverse inertia tensor in world axes (`include/box3d/box3d.h:628`).
pub const worldInverseRotationalInertia = c.b3Body_GetWorldInverseRotationalInertia;

/// The centre of mass in body-local coordinates (`include/box3d/box3d.h:631`).
pub fn localCenterOfMass(id: BodyId) math.Vec3 {
    return c.b3Body_GetLocalCenterOfMass(id);
}

/// The centre of mass in world space (`include/box3d/box3d.h:634`).
pub fn worldCenterOfMass(id: BodyId) math.Pos {
    return c.b3Body_GetWorldCenterOfMass(id);
}

/// Replace the body's mass properties (`include/box3d/box3d.h:639`).
///
/// This overrides whatever the shapes computed. Call `applyMassFromShapes` to
/// go back.
pub fn setMassData(id: BodyId, mass_data: MassData) void {
    c.b3Body_SetMassData(id, mass_data);
}

/// The body's mass properties (`include/box3d/box3d.h:642`).
pub fn massData(id: BodyId) MassData {
    return c.b3Body_GetMassData(id);
}

/// Recompute mass from the shapes currently on the body
/// (`include/box3d/box3d.h:649`).
pub fn applyMassFromShapes(id: BodyId) void {
    c.b3Body_ApplyMassFromShapes(id);
}

// -- damping, gravity, sleep -------------------------------------------------

/// Linear damping (`include/box3d/box3d.h:652`). Values above 1 are allowed.
pub fn setLinearDamping(id: BodyId, linear_damping: f32) void {
    c.b3Body_SetLinearDamping(id, linear_damping);
}

/// The linear damping (`include/box3d/box3d.h:655`).
pub fn linearDamping(id: BodyId) f32 {
    return c.b3Body_GetLinearDamping(id);
}

/// Angular damping (`include/box3d/box3d.h:658`).
pub fn setAngularDamping(id: BodyId, angular_damping: f32) void {
    c.b3Body_SetAngularDamping(id, angular_damping);
}

/// The angular damping (`include/box3d/box3d.h:661`).
pub fn angularDamping(id: BodyId) f32 {
    return c.b3Body_GetAngularDamping(id);
}

/// Scale the world's gravity for this body (`include/box3d/box3d.h:665`).
pub fn setGravityScale(id: BodyId, gravity_scale: f32) void {
    c.b3Body_SetGravityScale(id, gravity_scale);
}

/// The gravity scale (`include/box3d/box3d.h:668`).
pub fn gravityScale(id: BodyId) f32 {
    return c.b3Body_GetGravityScale(id);
}

/// Is the body awake (`include/box3d/box3d.h:671`)?
pub fn isAwake(id: BodyId) bool {
    return c.b3Body_IsAwake(id);
}

/// Wake or sleep the body explicitly (`include/box3d/box3d.h:676`).
pub fn setAwake(id: BodyId, awake: bool) void {
    c.b3Body_SetAwake(id, awake);
}

/// Allow or forbid this body to sleep (`include/box3d/box3d.h:679`).
pub fn enableSleep(id: BodyId, enable_sleep: bool) void {
    c.b3Body_EnableSleep(id, enable_sleep);
}

/// May this body sleep (`include/box3d/box3d.h:682`)?
pub fn isSleepEnabled(id: BodyId) bool {
    return c.b3Body_IsSleepEnabled(id);
}

/// The speed below which the body may sleep (`include/box3d/box3d.h:685`).
pub fn setSleepThreshold(id: BodyId, sleep_threshold: f32) void {
    c.b3Body_SetSleepThreshold(id, sleep_threshold);
}

/// The sleep threshold (`include/box3d/box3d.h:688`).
pub fn sleepThreshold(id: BodyId) f32 {
    return c.b3Body_GetSleepThreshold(id);
}

/// Is the body enabled (`include/box3d/box3d.h:691`)?
///
/// A disabled body neither moves nor collides (`include/box3d/types.h:335-336`).
pub fn isEnabled(id: BodyId) bool {
    return c.b3Body_IsEnabled(id);
}

/// Disable the body (`include/box3d/box3d.h:694`).
pub fn disable(id: BodyId) void {
    c.b3Body_Disable(id);
}

/// Enable the body (`include/box3d/box3d.h:697`).
pub fn enable(id: BodyId) void {
    c.b3Body_Enable(id);
}

/// Restrict the body's motion (`include/box3d/box3d.h:700`).
pub fn setMotionLocks(id: BodyId, locks: MotionLocks) void {
    c.b3Body_SetMotionLocks(id, locks);
}

/// The body's motion locks (`include/box3d/box3d.h:703`).
pub fn motionLocks(id: BodyId) MotionLocks {
    return c.b3Body_GetMotionLocks(id);
}

/// Treat the body as a bullet (`include/box3d/box3d.h:707`).
///
/// See the warning on `BodyDef.isBullet` before using this.
pub fn setBullet(id: BodyId, flag: bool) void {
    c.b3Body_SetBullet(id, flag);
}

/// Is this body a bullet (`include/box3d/box3d.h:710`)?
pub fn isBullet(id: BodyId) bool {
    return c.b3Body_IsBullet(id);
}

/// Enable contact recycling for this body
/// (`include/box3d/box3d.h:717-719`).
///
/// Off for characters, on for everything else; see `BodyDef`.
pub fn enableContactRecycling(id: BodyId, flag: bool) void {
    c.b3Body_EnableContactRecycling(id, flag);
}

/// Is contact recycling enabled (`include/box3d/box3d.h:720`)?
pub fn isContactRecyclingEnabled(id: BodyId) bool {
    return c.b3Body_IsContactRecyclingEnabled(id);
}

/// Enable hit events for every shape on this body
/// (`include/box3d/box3d.h:724`).
///
/// The world's hit event threshold still applies
/// (`include/box3d/types.h:495-497`).
pub fn enableHitEvents(id: BodyId, enable_hit_events: bool) void {
    c.b3Body_EnableHitEvents(id, enable_hit_events);
}

// -- enumeration -------------------------------------------------------------

/// How many shapes are on this body (`include/box3d/box3d.h:730`).
pub fn shapeCount(id: BodyId) c_int {
    return c.b3Body_GetShapeCount(id);
}

/// The body's shape ids, up to `out.len` of them
/// (`include/box3d/box3d.h:734`).
///
/// Returns how many were written. If that is `out.len`, there may be more: ask
/// `shapeCount` for the exact number, or pass a slice of that size.
pub fn shapes(id: BodyId, out: []c.b3ShapeId) c_int {
    if (out.len == 0) return 0;
    return c.b3Body_GetShapes(id, out.ptr, @intCast(out.len));
}

/// The body's shape ids in a slice of exactly `shapeCount` entries
/// (`include/box3d/box3d.h:730,734`).
pub fn shapeSlice(id: BodyId, allocator: std.mem.Allocator) ![]c.b3ShapeId {
    const count = shapeCount(id);
    if (count <= 0) return &.{};
    const out = try allocator.alloc(c.b3ShapeId, @intCast(count));
    errdefer allocator.free(out);
    const written = c.b3Body_GetShapes(id, out.ptr, count);
    return out[0..@intCast(written)];
}

/// How many joints are attached to this body (`include/box3d/box3d.h:737`).
pub fn jointCount(id: BodyId) c_int {
    return c.b3Body_GetJointCount(id);
}

/// The body's joint ids, up to `out.len` of them
/// (`include/box3d/box3d.h:741`).
pub fn joints(id: BodyId, out: []c.b3JointId) c_int {
    if (out.len == 0) return 0;
    return c.b3Body_GetJoints(id, out.ptr, @intCast(out.len));
}

/// The body's joint ids in a slice of exactly `jointCount` entries.
pub fn jointSlice(id: BodyId, allocator: std.mem.Allocator) ![]c.b3JointId {
    const count = jointCount(id);
    if (count <= 0) return &.{};
    const out = try allocator.alloc(c.b3JointId, @intCast(count));
    errdefer allocator.free(out);
    const written = c.b3Body_GetJoints(id, out.ptr, count);
    return out[0..@intCast(written)];
}

/// How many contacts this body is in (`include/box3d/box3d.h:744`).
pub fn contactCapacity(id: BodyId) c_int {
    return c.b3Body_GetContactCapacity(id);
}

/// This body's contacts, up to `out.len` of them (`include/box3d/box3d.h:747`).
///
/// The `manifolds` pointer inside each entry is world memory and expires; see
/// `ContactData`. Returns how many were written.
pub fn contactData(id: BodyId, out: []ContactData) c_int {
    if (out.len == 0) return 0;
    return c.b3Body_GetContactData(id, out.ptr, @intCast(out.len));
}

// -- geometry queries --------------------------------------------------------

/// The AABB of every shape on this body (`include/box3d/box3d.h:751`).
pub const computeAabb = c.b3Body_ComputeAABB;

/// The point on this body closest to `target`, written into `result`
/// (`include/box3d/box3d.h:754`).
///
/// Returns the distance to that point. `result` must not be null.
pub fn closestPoint(id: BodyId, result: *math.Vec3, target: math.Vec3) f32 {
    return c.b3Body_GetClosestPoint(id, result, target);
}