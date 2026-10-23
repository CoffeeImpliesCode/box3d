// SPDX-License-Identifier: MIT
//
//! World creation, simulation, events, callbacks and lifecycle.

const c = @import("c");
const math = @import("math.zig");

pub const WorldId = c.b3WorldId;

pub const Capacity = c.b3Capacity;

/// Optional overrides of upstream's world defaults; unset fields retain them.
/// The native validity marker is initialized by Box3D, not supplied by callers.
pub const WorldDef = struct {
    /// Gravity; the default `(0, -10, 0)` is not scaled by length units.
    gravity: ?math.Vec3 = null,
    /// Impact speed in m/s above which restitution applies.
    restitutionThreshold: ?f32 = null,
    /// Impact speed in m/s above which a hit event may be reported.
    hitEventThreshold: ?f32 = null,
    /// Contact stiffness in hertz; higher values recover overlap faster and may jitter.
    contactHertz: ?f32 = null,
    /// Contact bounciness. Non-dimensional.
    contactDampingRatio: ?f32 = null,
    /// Cap on overlap recovery speed, in m/s.
    contactSpeed: ?f32 = null,
    /// Maximum linear speed in m/s.
    maximumLinearSpeed: ?f32 = null,
    /// Stored by the world; keep the callback valid and thread-safe for its lifetime.
    frictionCallback: ?*const c.b3FrictionCallback = null,
    /// Stored by the world; keep the callback valid and thread-safe for its lifetime.
    restitutionCallback: ?*const c.b3RestitutionCallback = null,
    enableSleep: ?bool = null,
    enableContinuous: ?bool = null,
    /// Worker count, clamped to `[1, B3_MAX_WORKERS]`; values above one enable threading.
    workerCount: ?u32 = null,
    /// Pair with `finishTask`; both callbacks are required, and the scheduler must preserve stacks
    /// while `step` waits for forked tasks (`include/box3d/types.h:33-38`).
    enqueueTask: ?*const c.b3EnqueueTaskCallback = null,
    /// Pair with `enqueueTask`.
    finishTask: ?*const c.b3FinishTaskCallback = null,
    /// Passed back to `enqueueTask` and `finishTask` untouched.
    userTaskContext: ?*anyopaque = null,
    userData: ?*anyopaque = null,
    /// Called on first draw to create a renderer-side object (`include/box3d/types.h:200-208`).
    createDebugShape: ?*const c.b3CreateDebugShapeCallback = null,
    /// Paired with `createDebugShape`; called on change or destruction.
    destroyDebugShape: ?*const c.b3DestroyDebugShapeCallback = null,
    /// Passed back to the two debug shape callbacks.
    userDebugShapeContext: ?*anyopaque = null,
    capacity: ?Capacity = null,

    pub fn native(self: WorldDef) c.b3WorldDef {
        var out = c.b3DefaultWorldDef();
        if (self.gravity) |value| out.gravity = value;
        if (self.restitutionThreshold) |value| out.restitutionThreshold = value;
        if (self.hitEventThreshold) |value| out.hitEventThreshold = value;
        if (self.contactHertz) |value| out.contactHertz = value;
        if (self.contactDampingRatio) |value| out.contactDampingRatio = value;
        if (self.contactSpeed) |value| out.contactSpeed = value;
        if (self.maximumLinearSpeed) |value| out.maximumLinearSpeed = value;
        if (self.frictionCallback) |value| out.frictionCallback = value;
        if (self.restitutionCallback) |value| out.restitutionCallback = value;
        if (self.enableSleep) |value| out.enableSleep = value;
        if (self.enableContinuous) |value| out.enableContinuous = value;
        if (self.workerCount) |value| out.workerCount = value;
        if (self.enqueueTask) |value| out.enqueueTask = value;
        if (self.finishTask) |value| out.finishTask = value;
        if (self.userTaskContext) |value| out.userTaskContext = value;
        if (self.userData) |value| out.userData = value;
        if (self.createDebugShape) |value| out.createDebugShape = value;
        if (self.destroyDebugShape) |value| out.destroyDebugShape = value;
        if (self.userDebugShapeContext) |value| out.userDebugShapeContext = value;
        if (self.capacity) |value| out.capacity = value;
        return out;
    }
};

pub const Error = error{
    /// Returned when `B3_MAX_WORLDS` is exhausted if upstream's assertion does not abort first
    /// (`src/physics_world.c:223-228`; `include/box3d/constants.h:62-65`).
    WorldLimitExceeded,
};

/// Create a world; stored callback pointers and application data must remain valid.
pub fn create(def: WorldDef) Error!WorldId {
    var native_def = def.native();
    const id = c.b3CreateWorld(&native_def);
    if (!c.b3World_IsValid(id)) return error.WorldLimitExceeded;
    return id;
}

/// Destroy a world and its objects; their ids become stale. Invalid ids assert.
pub fn destroy(id: WorldId) void {
    c.b3DestroyWorld(id);
}

pub fn isValid(id: WorldId) bool {
    return c.b3World_IsValid(id);
}

pub fn count() c_int {
    return c.b3GetWorldCount();
}

pub fn maxCount() c_int {
    return c.b3GetMaxWorldCount();
}

/// Advance by one step. Keep both time-step arguments fixed for deterministic runs.
/// Event buffers remain valid until the next step or a destruction.
pub fn step(id: WorldId, time_step: f32, sub_step_count: c_int) void {
    c.b3World_Step(id, time_step, sub_step_count);
}

/// Simulation AABB; may include padding (`include/box3d/box3d.h:58-60`).
pub fn bounds(id: WorldId) math.Aabb {
    return c.b3World_GetBounds(id);
}

pub fn awakeBodyCount(id: WorldId) c_int {
    return c.b3World_GetAwakeBodyCount(id);
}

/// Per-phase timings for the last step, in milliseconds.
pub const Profile = c.b3Profile;
pub fn profile(id: WorldId) Profile {
    return c.b3World_GetProfile(id);
}

pub const Counters = c.b3Counters;
pub fn counters(id: WorldId) Counters {
    return c.b3World_GetCounters(id);
}

pub fn maxCapacity(id: WorldId) Capacity {
    return c.b3World_GetMaxCapacity(id);
}

/// Move events are emitted only for bodies the simulation moved.
/// They carry the body id, transform, user data and sleep transition.
pub const BodyMoveEvent = c.b3BodyMoveEvent;
pub const BodyEvents = c.b3BodyEvents;
pub const SensorBeginTouchEvent = c.b3SensorBeginTouchEvent;
/// End-touch events may name destroyed shapes; validate ids with `shape.isValid`.
pub const SensorEndTouchEvent = c.b3SensorEndTouchEvent;
pub const SensorEvents = c.b3SensorEvents;
pub const ContactBeginTouchEvent = c.b3ContactBeginTouchEvent;
/// End-touch events may name destroyed shapes or contacts.
pub const ContactEndTouchEvent = c.b3ContactEndTouchEvent;
/// Hit data; `approachSpeed` is the positive speed at which shapes were closing.
pub const ContactHitEvent = c.b3ContactHitEvent;
pub const ContactEvents = c.b3ContactEvents;
pub const JointEvent = c.b3JointEvent;
pub const JointEvents = c.b3JointEvents;

/// Raw event buffers borrow world memory; the next step or destruction invalidates them.
/// Read the data before either operation and do not retain its pointers.
pub fn bodyEvents(id: WorldId) BodyEvents {
    return c.b3World_GetBodyEvents(id);
}

pub fn bodyMoveEvents(id: WorldId) []const BodyMoveEvent {
    const events = bodyEvents(id);
    if (events.moveCount <= 0) return &.{};
    const items: [*]const BodyMoveEvent = events.moveEvents;
    return items[0..@intCast(events.moveCount)];
}

pub fn sensorEvents(id: WorldId) SensorEvents {
    return c.b3World_GetSensorEvents(id);
}

pub fn sensorBeginEvents(id: WorldId) []const SensorBeginTouchEvent {
    const events = sensorEvents(id);
    if (events.beginCount <= 0) return &.{};
    const items: [*]const SensorBeginTouchEvent = events.beginEvents;
    return items[0..@intCast(events.beginCount)];
}

pub fn sensorEndEvents(id: WorldId) []const SensorEndTouchEvent {
    const events = sensorEvents(id);
    if (events.endCount <= 0) return &.{};
    const items: [*]const SensorEndTouchEvent = events.endEvents;
    return items[0..@intCast(events.endCount)];
}

pub fn contactEvents(id: WorldId) ContactEvents {
    return c.b3World_GetContactEvents(id);
}

pub fn contactBeginEvents(id: WorldId) []const ContactBeginTouchEvent {
    const events = contactEvents(id);
    if (events.beginCount <= 0) return &.{};
    const items: [*]const ContactBeginTouchEvent = events.beginEvents;
    return items[0..@intCast(events.beginCount)];
}

pub fn contactEndEvents(id: WorldId) []const ContactEndTouchEvent {
    const events = contactEvents(id);
    if (events.endCount <= 0) return &.{};
    const items: [*]const ContactEndTouchEvent = events.endEvents;
    return items[0..@intCast(events.endCount)];
}

pub fn contactHitEvents(id: WorldId) []const ContactHitEvent {
    const events = contactEvents(id);
    if (events.hitCount <= 0) return &.{};
    const items: [*]const ContactHitEvent = events.hitEvents;
    return items[0..@intCast(events.hitCount)];
}

pub fn jointEvents(id: WorldId) JointEvents {
    return c.b3World_GetJointEvents(id);
}

pub fn jointEventSlice(id: WorldId) []const JointEvent {
    const events = jointEvents(id);
    if (events.count <= 0) return &.{};
    const items: [*]const JointEvent = events.jointEvents;
    return items[0..@intCast(events.count)];
}

pub fn setGravity(id: WorldId, new_gravity: math.Vec3) void {
    c.b3World_SetGravity(id, new_gravity);
}

pub fn gravity(id: WorldId) math.Vec3 {
    return c.b3World_GetGravity(id);
}

/// Toggle sleeping. Disabling it emits move events for dynamic and kinematic bodies
/// on every step (`include/box3d/types.h:1196`).
pub fn enableSleeping(id: WorldId, flag: bool) void {
    c.b3World_EnableSleeping(id, flag);
}

pub fn isSleepingEnabled(id: WorldId) bool {
    return c.b3World_IsSleepingEnabled(id);
}

pub fn enableContinuous(id: WorldId, flag: bool) void {
    c.b3World_EnableContinuous(id, flag);
}

pub fn isContinuousEnabled(id: WorldId) bool {
    return c.b3World_IsContinuousEnabled(id);
}

pub fn setRestitutionThreshold(id: WorldId, value: f32) void {
    c.b3World_SetRestitutionThreshold(id, value);
}

pub fn restitutionThreshold(id: WorldId) f32 {
    return c.b3World_GetRestitutionThreshold(id);
}

/// Set the impact-speed threshold for hit events; shapes must also enable them.
pub fn setHitEventThreshold(id: WorldId, value: f32) void {
    c.b3World_SetHitEventThreshold(id, value);
}

pub fn hitEventThreshold(id: WorldId) f32 {
    return c.b3World_GetHitEventThreshold(id);
}

pub fn setContactTuning(id: WorldId, hertz: f32, damping_ratio: f32, contact_speed: f32) void {
    c.b3World_SetContactTuning(id, hertz, damping_ratio, contact_speed);
}

pub fn setContactRecycleDistance(id: WorldId, recycle_distance: f32) void {
    c.b3World_SetContactRecycleDistance(id, recycle_distance);
}

pub fn contactRecycleDistance(id: WorldId) f32 {
    return c.b3World_GetContactRecycleDistance(id);
}

pub fn setMaximumLinearSpeed(id: WorldId, maximum_linear_speed: f32) void {
    c.b3World_SetMaximumLinearSpeed(id, maximum_linear_speed);
}

pub fn maximumLinearSpeed(id: WorldId) f32 {
    return c.b3World_GetMaximumLinearSpeed(id);
}

pub fn enableWarmStarting(id: WorldId, flag: bool) void {
    c.b3World_EnableWarmStarting(id, flag);
}

pub fn isWarmStartingEnabled(id: WorldId) bool {
    return c.b3World_IsWarmStartingEnabled(id);
}

pub fn enableSpeculative(id: WorldId, flag: bool) void {
    c.b3World_EnableSpeculative(id, flag);
}

/// Application data is borrowed; Box3D neither dereferences nor frees it.
/// The caller owns the pointed-to object.
pub fn setUserData(id: WorldId, user_data: ?*anyopaque) void {
    c.b3World_SetUserData(id, user_data);
}

pub fn userData(id: WorldId) ?*anyopaque {
    return c.b3World_GetUserData(id);
}

pub fn setWorkerCount(id: WorldId, worker_count: c_int) void {
    c.b3World_SetWorkerCount(id, worker_count);
}

pub fn workerCount(id: WorldId) c_int {
    return c.b3World_GetWorkerCount(id);
}

/// Stored until world destruction; the callback may run on workers and must be thread-safe.
/// Returning false rejects contact; the callback must not modify the world.
pub fn setCustomFilterCallback(id: WorldId, fcn: ?*const c.b3CustomFilterFcn, context: ?*anyopaque) void {
    c.b3World_SetCustomFilterCallback(id, fcn, context);
}

/// Stored until world destruction; callbacks may run on workers and must be thread-safe.
/// False skips this solve and may leave continuous-collision manifolds incomplete; null removes it.
pub fn setPreSolveCallback(id: WorldId, fcn: ?*const c.b3PreSolveFcn, context: ?*anyopaque) void {
    c.b3World_SetPreSolveCallback(id, fcn, context);
}

/// The callback is stored until replaced or the world is destroyed; it has no context.
/// Upstream forbids accessing Box3D or application state from this callback.
pub fn setFrictionCallback(id: WorldId, callback: ?*const c.b3FrictionCallback) void {
    c.b3World_SetFrictionCallback(id, callback);
}

/// The callback is stored until replaced or the world is destroyed; it has no context.
/// Upstream forbids accessing Box3D or application state from this callback.
pub fn setRestitutionCallback(id: WorldId, callback: ?*const c.b3RestitutionCallback) void {
    c.b3World_SetRestitutionCallback(id, callback);
}

/// Explosion parameters; only spheres, capsules and hulls are affected.
/// A negative impulse causes an implosion.
pub const ExplosionDef = c.b3ExplosionDef;
pub fn explode(id: WorldId, explosion: *const ExplosionDef) void {
    c.b3World_Explode(id, explosion);
}

pub fn dumpMemoryStats(id: WorldId) void {
    c.b3World_DumpMemoryStats(id);
}

pub fn dumpShapeBounds(id: WorldId, body_type: c.b3BodyType) void {
    c.b3World_DumpShapeBounds(id, body_type);
}

pub fn dumpAwake(id: WorldId) void {
    c.b3World_DumpAwake(id);
}

pub fn dump(id: WorldId) void {
    c.b3World_Dump(id);
}

pub fn rebuildStaticTree(id: WorldId) void {
    c.b3World_RebuildStaticTree(id);
}

/// Submit and clear debug draw data; the configured shape callbacks run here.
pub fn draw(id: WorldId, draw_state: *c.b3DebugDraw, mask_bits: u64) void {
    c.b3World_Draw(id, draw_state, mask_bits);
}
