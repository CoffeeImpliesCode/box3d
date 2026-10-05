// SPDX-License-Identifier: MIT
//
//! Worlds: creating one, stepping it, tuning it, reading what the last step
//! reported, and destroying it.
//!
//! ## Ids, not handles
//!
//! A `WorldId` is `b3WorldId`, upstream's own two-`uint16` handle
//! (`include/box3d/id.h:36-41`), passed by value. There is no wrapper struct, no
//! allocator, and nothing to free: `createWorld` hands back the id and
//! `destroyWorld` takes it. That is deliberate. Box3D pools its worlds in a
//! fixed-size process-global array (`src/physics_world.c:214-221`) and encodes a
//! generation in the id so a stale one is detectable rather than silently
//! wrong, and a wrapper that owned the id by address would add a second
//! lifetime the library does not have.
//!
//! ## What a world owns
//!
//! A world owns every body, shape and joint created in it. `destroyWorld`
//! frees all of them at once and leaves every id you still hold pointing at a
//! generation that no longer exists - upstream says so directly in the
//! comment above its own `HelloWorld`
//! (`test/test_world.c:92-94`). That is why `body.isValid` and
//! `shape.isValid` exist and why this module exports them: an id is only
//! meaningful while the object behind it is alive, and a world destroyed in the
//! middle of a frame is the ordinary way to find that out.
//!
//! ## Stepping
//!
//! `step` is the whole simulation: broad phase, narrow phase, solve, integrate.
//! Keep `time_step` and `sub_step_count` fixed across the run
//! (`include/box3d/box3d.h:49-52`); a variable time step is the usual reason a
//! simulation stops being deterministic.
//!
//! ## Callback lifetime
//!
//! `setCustomFilterCallback`, `setPreSolveCallback`, `setFrictionCallback` and
//! `setRestitutionCallback` store the function pointer in the world and call it
//! later - during `step`, from worker threads when the world has more than one
//! (`include/box3d/types.h:50-60,62-88`). The functions must therefore stay
//! valid for as long as the world, and they must be thread-safe, because they
//! are. The friction and restitution callbacks are additionally documented not
//! to touch Box3D state at all (`include/box3d/types.h:52-53,58-59`). A
//! callback that needs its own state uses the world-level `userData` or a
//! pointer it closes over; Zig closures are not C function pointers, so a
//! callback that needs state has to reach it through one of those.

const c = @import("c");
const math = @import("math.zig");

/// A world handle, `b3WorldId` (`include/box3d/id.h:36-41`).
pub const WorldId = c.b3WorldId;

/// Upstream's `b3Capacity`, the optional starting sizes a world allocates
/// (`include/box3d/types.h:118-136`).
///
/// Giving these the sizes a scene actually needs removes the growth reallocs
/// from the first steps. `createWorld` copies them; changing the value later
/// does nothing.
pub const Capacity = c.b3Capacity;

/// A world definition, as optional overrides of upstream's defaults.
///
/// Every field is optional and defaults to null, which means "leave what
/// `b3DefaultWorldDef` put there" (`include/box3d/types.h:219`). So
/// `.{}` is a complete, valid definition that asks for exactly the upstream
/// defaults, and a partial literal overrides only what it names. Nothing in
/// this struct re-derives a default: `native` starts from upstream's own
/// `b3DefaultWorldDef` and writes over the fields that were set, so a default
/// that changes upstream changes here too.
///
/// `internalValue` is deliberately absent. It is upstream's own validity marker
/// (`include/box3d/types.h:213-214`) and must arrive from
/// `b3DefaultWorldDef`, not from a caller.
pub const WorldDef = struct {
    /// Gravity vector. Box3D has no up-vector: this is whatever you call down.
    /// Upstream's default is `(0, -10, 0)` (`src/types.c:15-16`), and unlike the
    /// other defaults in `b3DefaultWorldDef` it is not multiplied by the length
    /// scale.
    gravity: ?math.Vec3 = null,
    /// Impact speed in m/s above which restitution applies.
    restitutionThreshold: ?f32 = null,
    /// Impact speed in m/s above which a hit event may be reported.
    hitEventThreshold: ?f32 = null,
    /// Contact stiffness in hertz. Higher recovers overlap faster and jitters
    /// more (`include/box3d/types.h:153-156`).
    contactHertz: ?f32 = null,
    /// Contact bounciness. Non-dimensional.
    contactDampingRatio: ?f32 = null,
    /// Cap on overlap recovery speed, in m/s.
    contactSpeed: ?f32 = null,
    /// Maximum linear speed in m/s.
    maximumLinearSpeed: ?f32 = null,
    /// Optional friction mixing callback. See the callback-lifetime note in the
    /// module comment.
    frictionCallback: ?*const c.b3FrictionCallback = null,
    /// Optional restitution mixing callback, same lifetime rule.
    restitutionCallback: ?*const c.b3RestitutionCallback = null,
    /// May bodies fall asleep.
    enableSleep: ?bool = null,
    /// Enable continuous collision.
    enableContinuous: ?bool = null,
    /// Number of workers. Clamped to `[1, B3_MAX_WORKERS]`; above 1 turns on
    /// multithreading (`include/box3d/types.h:182-185`).
    workerCount: ?u32 = null,
    /// Task scheduler enqueue callback. Providing this pair hands Box3D's
    /// parallelism to your scheduler; leaving both null lets Box3D create its
    /// own threads.
    ///
    /// Both must be set together. `b3FinishTaskCallback` blocks until the task
    /// completes, and `b3World_Step` holds its stack across every fork and join,
    /// so a scheduler that cannot park a job's stack must not call `step` from
    /// inside a job (`include/box3d/types.h:33-38`).
    enqueueTask: ?*const c.b3EnqueueTaskCallback = null,
    /// Pairs with `enqueueTask`; see that field's note.
    finishTask: ?*const c.b3FinishTaskCallback = null,
    /// Passed back to `enqueueTask` and `finishTask` untouched.
    userTaskContext: ?*anyopaque = null,
    /// Application data for the world; readable with `userData`.
    userData: ?*anyopaque = null,
    /// Called the first time a shape is drawn, so a renderer can bind its own
    /// per-shape object (`include/box3d/types.h:200-208`).
    createDebugShape: ?*const c.b3CreateDebugShapeCallback = null,
    /// Pairs with `createDebugShape`, and is called when a shape changes or is
    /// destroyed. Both must be set together.
    destroyDebugShape: ?*const c.b3DestroyDebugShapeCallback = null,
    /// Passed back to the two debug shape callbacks.
    userDebugShapeContext: ?*anyopaque = null,
    /// Starting pool sizes.
    capacity: ?Capacity = null,

    /// The definition Box3D wants: upstream's defaults with the set fields
    /// written over them.
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

/// Everything that can go wrong in this module.
pub const Error = error{
    /// All `B3_MAX_WORLDS` worlds are in use. Destroy one and try again; this
    /// is not retryable by waiting.
    ///
    /// This is the one failure here that upstream asserts on rather than
    /// answers. `b3CreateWorld` logs and asserts inside its pool-exhausted
    /// branch (`src/physics_world.c:223-228`), and the null id on
    /// `src/physics_world.c:227` is only reached when that assertion does not
    /// fire: `B3_ASSERT` compiles to nothing under `NDEBUG` without
    /// `B3_ENABLE_ASSERT` (`include/box3d/base.h:123-131`), or an assert
    /// handler installed through `base.setAssertFcn` returns 0 to skip the
    /// break (`src/core.c:81-90`). So the check after the call reports this
    /// where upstream survives to be asked, and a build whose assertion fires
    /// stops inside `b3CreateWorld` instead.
    ///
    /// Nothing here pre-empts that: `count` and `maxCount` report after the
    /// fact, and the ceiling itself is `B3_MAX_WORLDS`
    /// (`include/box3d/constants.h:62-65`), so a caller that must not abort
    /// has to keep its own tally against that number.
    WorldLimitExceeded,
};

// -- lifecycle ---------------------------------------------------------------

/// Create a world.
///
/// `.{}` asks for exactly upstream's default world
/// (`src/types.c:10-30`): gravity `(0, -10, 0)`, sleeping on, continuous
/// collision on. A definition is consumed here; Box3D copies what it needs.
///
/// Creating more than `B3_MAX_WORLDS` worlds at once is a precondition rather
/// than a recoverable failure: see `Error.WorldLimitExceeded` for what
/// upstream does when the pool is empty.
pub fn create(def: WorldDef) Error!WorldId {
    var native_def = def.native();
    const id = c.b3CreateWorld(&native_def);
    if (!c.b3World_IsValid(id)) return error.WorldLimitExceeded;
    return id;
}

/// Destroy a world and everything in it.
///
/// Every body, shape and joint id the caller still holds becomes stale. There
/// is no way to free them individually afterwards, and `body.isValid` is how a
/// caller finds out which ones it had.
///
/// Calling this twice on the same id, or on any other invalid id, is a
/// programming error upstream asserts on; it is not reported here.
pub fn destroy(id: WorldId) void {
    c.b3DestroyWorld(id);
}

/// True while the id names a live world (`include/box3d/box3d.h:46-47`).
///
/// Valid for up to 64K allocations, because the id carries a generation
/// (`include/box3d/id.h:36-41`).
pub fn isValid(id: WorldId) bool {
    return c.b3World_IsValid(id);
}

/// How many worlds exist right now (`include/box3d/box3d.h:40-41`).
pub fn count() c_int {
    return c.b3GetWorldCount();
}

/// The high-water mark of concurrent worlds
/// (`include/box3d/box3d.h:43-44`).
pub fn maxCount() c_int {
    return c.b3GetMaxWorldCount();
}

// -- stepping ----------------------------------------------------------------

/// Advance the simulation by one step
/// (`include/box3d/box3d.h:49-53`).
///
/// `time_step` is the whole step in seconds, usually 1/60; `sub_step_count` is
/// how many internal sub-steps it is divided into, usually 4. Hold both fixed:
/// Box3D's own determinism checks compare runs that differ only in nothing.
///
/// The event arrays this step produced are readable afterwards, through
/// `bodyEvents`, `sensorEvents`, `contactEvents` and `jointEvents`, until the
/// next `step` replaces them or anything is destroyed.
pub fn step(id: WorldId, time_step: f32, sub_step_count: c_int) void {
    c.b3World_Step(id, time_step, sub_step_count);
}

/// The AABB covering the current simulation (`include/box3d/box3d.h:58-60`).
///
/// May carry a little padding.
pub fn bounds(id: WorldId) math.Aabb {
    return c.b3World_GetBounds(id);
}

/// How many bodies are awake (`include/box3d/box3d.h:206-207`).
pub fn awakeBodyCount(id: WorldId) c_int {
    return c.b3World_GetAwakeBodyCount(id);
}

/// Per-phase timings in milliseconds for the last step
/// (`include/box3d/types.h:520-547`).
///
/// Diagnostic only. The `step` field is the whole step; the rest divide it.
pub const Profile = c.b3Profile;
pub fn profile(id: WorldId) Profile {
    return c.b3World_GetProfile(id);
}

/// Allocation and object counters (`include/box3d/types.h:551-580`).
pub const Counters = c.b3Counters;
pub fn counters(id: WorldId) Counters {
    return c.b3World_GetCounters(id);
}

/// The capacities the world has grown to (`include/box3d/box3d.h:215-216`).
pub fn maxCapacity(id: WorldId) Capacity {
    return c.b3World_GetMaxCapacity(id);
}

// -- events ------------------------------------------------------------------

/// One body move event, `b3BodyMoveEvent`
/// (`include/box3d/types.h:1197-1210`).
///
/// Produced for bodies the simulation moved, which is why it exists: reading
/// transforms here is cheaper than calling `body.transform` for every body when
/// only a few moved. `userData` is the body pointer the caller attached, and
/// `fellAsleep` says whether the body stopped moving for good.
pub const BodyMoveEvent = c.b3BodyMoveEvent;
/// The body event buffer, `b3BodyEvents` (`include/box3d/types.h:1215-1222`).
pub const BodyEvents = c.b3BodyEvents;
/// A sensor begin-touch event (`include/box3d/types.h:1049-1056`).
pub const SensorBeginTouchEvent = c.b3SensorBeginTouchEvent;
/// A sensor end-touch event (`include/box3d/types.h:1062-1073`).
///
/// Either shape in it may already have been destroyed; check with
/// `shape.isValid` before using either id.
pub const SensorEndTouchEvent = c.b3SensorEndTouchEvent;
/// The sensor event buffer, `b3SensorEvents` (`include/box3d/types.h:1078-1091`).
pub const SensorEvents = c.b3SensorEvents;
/// A contact begin-touch event (`include/box3d/types.h:1094-1105`).
pub const ContactBeginTouchEvent = c.b3ContactBeginTouchEvent;
/// A contact end-touch event (`include/box3d/types.h:1108-1127`).
///
/// Any shape or contact in it may already be gone.
pub const ContactEndTouchEvent = c.b3ContactEndTouchEvent;
/// A contact hit event (`include/box3d/types.h:1131-1161`).
///
/// `approachSpeed` is positive and is the speed the shapes were closing at;
/// `userMaterialIdA` and `B` are whatever material the two shapes carry.
pub const ContactHitEvent = c.b3ContactHitEvent;
/// The contact event buffer, `b3ContactEvents`
/// (`include/box3d/types.h:1166-1185`).
pub const ContactEvents = c.b3ContactEvents;
/// A joint event (`include/box3d/types.h:1226-1233`).
pub const JointEvent = c.b3JointEvent;
/// The joint event buffer, `b3JointEvents` (`include/box3d/types.h:1238-1245`).
pub const JointEvents = c.b3JointEvents;

/// The raw body event buffer for the step just finished.
///
/// The pointers inside it point into world-owned memory that the next `step`,
/// or anything that destroys a body, replaces. Read it before either; do not
/// keep it.
pub fn bodyEvents(id: WorldId) BodyEvents {
    return c.b3World_GetBodyEvents(id);
}

/// The move events of the step just finished, as a slice
/// (`include/box3d/types.h:1219-1221`).
///
/// Transient for the same reason as `bodyEvents`.
pub fn bodyMoveEvents(id: WorldId) []const BodyMoveEvent {
    const events = bodyEvents(id);
    if (events.moveCount <= 0) return &.{};
    const items: [*]const BodyMoveEvent = events.moveEvents;
    return items[0..@intCast(events.moveCount)];
}

/// The raw sensor event buffer for the step just finished.
pub fn sensorEvents(id: WorldId) SensorEvents {
    return c.b3World_GetSensorEvents(id);
}

/// The sensor begin-touch events of the step just finished.
pub fn sensorBeginEvents(id: WorldId) []const SensorBeginTouchEvent {
    const events = sensorEvents(id);
    if (events.beginCount <= 0) return &.{};
    const items: [*]const SensorBeginTouchEvent = events.beginEvents;
    return items[0..@intCast(events.beginCount)];
}

/// The sensor end-touch events of the step just finished.
pub fn sensorEndEvents(id: WorldId) []const SensorEndTouchEvent {
    const events = sensorEvents(id);
    if (events.endCount <= 0) return &.{};
    const items: [*]const SensorEndTouchEvent = events.endEvents;
    return items[0..@intCast(events.endCount)];
}

/// The raw contact event buffer for the step just finished.
pub fn contactEvents(id: WorldId) ContactEvents {
    return c.b3World_GetContactEvents(id);
}

/// The contact begin-touch events of the step just finished.
pub fn contactBeginEvents(id: WorldId) []const ContactBeginTouchEvent {
    const events = contactEvents(id);
    if (events.beginCount <= 0) return &.{};
    const items: [*]const ContactBeginTouchEvent = events.beginEvents;
    return items[0..@intCast(events.beginCount)];
}

/// The contact end-touch events of the step just finished.
pub fn contactEndEvents(id: WorldId) []const ContactEndTouchEvent {
    const events = contactEvents(id);
    if (events.endCount <= 0) return &.{};
    const items: [*]const ContactEndTouchEvent = events.endEvents;
    return items[0..@intCast(events.endCount)];
}

/// The contact hit events of the step just finished.
pub fn contactHitEvents(id: WorldId) []const ContactHitEvent {
    const events = contactEvents(id);
    if (events.hitCount <= 0) return &.{};
    const items: [*]const ContactHitEvent = events.hitEvents;
    return items[0..@intCast(events.hitCount)];
}

/// The raw joint event buffer for the step just finished.
pub fn jointEvents(id: WorldId) JointEvents {
    return c.b3World_GetJointEvents(id);
}

/// The joint events of the step just finished.
pub fn jointEventSlice(id: WorldId) []const JointEvent {
    const events = jointEvents(id);
    if (events.count <= 0) return &.{};
    const items: [*]const JointEvent = events.jointEvents;
    return items[0..@intCast(events.count)];
}

// -- gravity and tuning ------------------------------------------------------

/// Set the world's gravity (`include/box3d/box3d.h:168`).
///
/// Box3D has no up-vector; this vector is whatever the application calls down.
pub fn setGravity(id: WorldId, new_gravity: math.Vec3) void {
    c.b3World_SetGravity(id, new_gravity);
}

/// The world's gravity (`include/box3d/box3d.h:171`).
pub fn gravity(id: WorldId) math.Vec3 {
    return c.b3World_GetGravity(id);
}

/// Allow or forbid sleeping world-wide (`include/box3d/box3d.h:129-130`).
///
/// Turning it off makes every dynamic and kinematic body produce a move event
/// every step (`include/box3d/types.h:1196`).
pub fn enableSleeping(id: WorldId, flag: bool) void {
    c.b3World_EnableSleeping(id, flag);
}

/// Is sleeping enabled (`include/box3d/box3d.h:132`)?
pub fn isSleepingEnabled(id: WorldId) bool {
    return c.b3World_IsSleepingEnabled(id);
}

/// Allow or forbid continuous collision world-wide
/// (`include/box3d/box3d.h:138-139`).
pub fn enableContinuous(id: WorldId, flag: bool) void {
    c.b3World_EnableContinuous(id, flag);
}

/// Is continuous collision enabled (`include/box3d/box3d.h:141`)?
pub fn isContinuousEnabled(id: WorldId) bool {
    return c.b3World_IsContinuousEnabled(id);
}

/// Impact speed above which restitution applies
/// (`include/box3d/box3d.h:146-147`).
pub fn setRestitutionThreshold(id: WorldId, value: f32) void {
    c.b3World_SetRestitutionThreshold(id, value);
}

/// The restitution threshold (`include/box3d/box3d.h:149`)?
pub fn restitutionThreshold(id: WorldId) f32 {
    return c.b3World_GetRestitutionThreshold(id);
}

/// Impact speed above which hit events may be reported
/// (`include/box3d/box3d.h:154-155`).
///
/// A shape also has to have hit events enabled
/// (`include/box3d/types.h:495-497`).
pub fn setHitEventThreshold(id: WorldId, value: f32) void {
    c.b3World_SetHitEventThreshold(id, value);
}

/// The hit event threshold (`include/box3d/box3d.h:157`)?
pub fn hitEventThreshold(id: WorldId) f32 {
    return c.b3World_GetHitEventThreshold(id);
}

/// Contact stiffness, damping and recovery-speed cap
/// (`include/box3d/box3d.h:184`).
///
/// `hertz` is how fast overlap is recovered, `damping_ratio` how energetic that
/// recovery is, and `contact_speed` only caps the speed; the first two are what
/// actually raise it.
pub fn setContactTuning(id: WorldId, hertz: f32, damping_ratio: f32, contact_speed: f32) void {
    c.b3World_SetContactTuning(id, hertz, damping_ratio, contact_speed);
}

/// How far a contact may drift before it is recycled
/// (`include/box3d/box3d.h:188-189`).
pub fn setContactRecycleDistance(id: WorldId, recycle_distance: f32) void {
    c.b3World_SetContactRecycleDistance(id, recycle_distance);
}

/// The contact recycle distance (`include/box3d/box3d.h:191`)?
pub fn contactRecycleDistance(id: WorldId) f32 {
    return c.b3World_GetContactRecycleDistance(id);
}

/// Cap on linear speed, in m/s (`include/box3d/box3d.h:194-195`).
pub fn setMaximumLinearSpeed(id: WorldId, maximum_linear_speed: f32) void {
    c.b3World_SetMaximumLinearSpeed(id, maximum_linear_speed);
}

/// The linear speed cap (`include/box3d/box3d.h:197`)?
pub fn maximumLinearSpeed(id: WorldId) f32 {
    return c.b3World_GetMaximumLinearSpeed(id);
}

/// Warm starting on or off (`include/box3d/box3d.h:201-202`).
pub fn enableWarmStarting(id: WorldId, flag: bool) void {
    c.b3World_EnableWarmStarting(id, flag);
}

/// Is warm starting enabled (`include/box3d/box3d.h:204`)?
pub fn isWarmStartingEnabled(id: WorldId) bool {
    return c.b3World_IsWarmStartingEnabled(id);
}

/// Speculative contacts on or off (`include/box3d/box3d.h:246-247`).
pub fn enableSpeculative(id: WorldId, flag: bool) void {
    c.b3World_EnableSpeculative(id, flag);
}

/// Application data for this world (`include/box3d/box3d.h:219-220`).
///
/// Box3D never dereferences it and never frees it, so the caller owns whatever
/// the pointer points at.
pub fn setUserData(id: WorldId, user_data: ?*anyopaque) void {
    c.b3World_SetUserData(id, user_data);
}

/// The world pointer set with `setUserData`
/// (`include/box3d/box3d.h:222-223`).
pub fn userData(id: WorldId) ?*anyopaque {
    return c.b3World_GetUserData(id);
}

/// Number of workers this world uses (`include/box3d/box3d.h:231-232`).
///
/// Changing this is the supported way to turn parallelism on or off after
/// creation.
pub fn setWorkerCount(id: WorldId, worker_count: c_int) void {
    c.b3World_SetWorkerCount(id, worker_count);
}

/// The worker count (`include/box3d/box3d.h:234`)?
pub fn workerCount(id: WorldId) c_int {
    return c.b3World_GetWorkerCount(id);
}

// -- callbacks ---------------------------------------------------------------

/// Install the contact filter (`include/box3d/box3d.h:160-161`).
///
/// Called when a contact pair is considered, and only when one of the two
/// shapes enabled custom filtering (`include/box3d/types.h:62-72`). It must be
/// thread-safe and must not modify the world; returning false disables the
/// collision. Pass null to remove the callback.
pub fn setCustomFilterCallback(id: WorldId, fcn: ?*const c.b3CustomFilterFcn, context: ?*anyopaque) void {
    c.b3World_SetCustomFilterCallback(id, fcn, context);
}

/// Install the pre-solve callback (`include/box3d/box3d.h:163-164`).
///
/// Called after a contact is updated and before it reaches the solver, so a
/// returning-false decision skips the solve for this step. It runs during
/// continuous collision, where the manifold is not complete
/// (`include/box3d/types.h:75-88`). Same lifetime and threading rules as the
/// filter callback. Pass null to remove it.
pub fn setPreSolveCallback(id: WorldId, fcn: ?*const c.b3PreSolveFcn, context: ?*anyopaque) void {
    c.b3World_SetPreSolveCallback(id, fcn, context);
}

/// Install the friction mixing callback (`include/box3d/box3d.h:225`).
///
/// Box3D's default is `sqrt(frictionA * frictionB)`
/// (`include/box3d/types.h:168`). The callback carries no context and is
/// documented not to touch Box3D or application state
/// (`include/box3d/types.h:50-53`).
pub fn setFrictionCallback(id: WorldId, callback: ?*const c.b3FrictionCallback) void {
    c.b3World_SetFrictionCallback(id, callback);
}

/// Install the restitution mixing callback (`include/box3d/box3d.h:228`).
///
/// The default is `max(restitutionA, restitutionB)`
/// (`include/box3d/types.h:168`). Same no-context, no-mutation rule as
/// `setFrictionCallback`.
pub fn setRestitutionCallback(id: WorldId, callback: ?*const c.b3RestitutionCallback) void {
    c.b3World_SetRestitutionCallback(id, callback);
}

// -- effects and diagnostics -------------------------------------------------

/// Apply an explosion (`include/box3d/box3d.h:176`).
///
/// The definition carries a mask, a centre, a radius, a falloff and an impulse
/// per unit area; only spheres, capsules and hulls are affected
/// (`include/box3d/types.h:1015-1024`). A negative impulse is an implosion.
pub const ExplosionDef = c.b3ExplosionDef;
pub fn explode(id: WorldId, explosion: *const ExplosionDef) void {
    c.b3World_Explode(id, explosion);
}

/// Print the world's memory statistics to Box3D's log
/// (`include/box3d/box3d.h:237`).
pub fn dumpMemoryStats(id: WorldId) void {
    c.b3World_DumpMemoryStats(id);
}

/// Print every shape's bounds, optionally only for one body type
/// (`include/box3d/box3d.h:240`).
pub fn dumpShapeBounds(id: WorldId, body_type: c.b3BodyType) void {
    c.b3World_DumpShapeBounds(id, body_type);
}

/// Print the awake bodies (`include/box3d/box3d.h:250`).
pub fn dumpAwake(id: WorldId) void {
    c.b3World_DumpAwake(id);
}

/// Print the whole world (`include/box3d/box3d.h:253`).
pub fn dump(id: WorldId) void {
    c.b3World_Dump(id);
}

/// Rebuild the static broad phase from scratch (`include/box3d/box3d.h:243`).
///
/// Worth doing after a build phase has added a lot of static geometry, which is
/// when the tree is least well shaped.
pub fn rebuildStaticTree(id: WorldId) void {
    c.b3World_RebuildStaticTree(id);
}

/// Submit debug draw data for every shape, then clear it
/// (`include/box3d/box3d.h:55-56`).
///
/// The callbacks installed through `WorldDef.createDebugShape` and
/// `WorldDef.destroyDebugShape` are what turn a shape into a renderer-side
/// object, and they run from here.
pub fn draw(id: WorldId, draw_state: *c.b3DebugDraw, mask_bits: u64) void {
    c.b3World_Draw(id, draw_state, mask_bits);
}