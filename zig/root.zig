// SPDX-License-Identifier: MIT
//
//! A typed Zig surface over Box3D, upstream erincatto/box3d v0.1.0.
//!
//! No part of the simulation is reimplemented here. Every answer this module
//! returns is produced by the C under `include/box3d` and `src/`, reached
//! through `pub const c`, the module `b.addTranslateC` produces from
//! `zig/translate.h`. What the facade adds is the part a C header cannot
//! express: a definition type where `.{}` means "upstream's defaults" and every
//! other field is an override, a query that fills a slice instead of demanding a
//! callback, an id validity check where upstream says ids can go stale, and one
//! place that says which callback has to stay alive for how long.
//!
//! ## The shortest useful program
//!
//! ```zig
//! const std = @import("std");
//! const box3d = @import("box3d");
//!
//! pub fn main() !void {
//!     const world = try box3d.world.create(.{});
//!     defer box3d.world.destroy(world);
//!
//!     // Ground: a static body with a box hull on it.
//!     const ground = try box3d.body.create(world, .{
//!         .position = .{ .x = 0, .y = -10, .z = 0 },
//!     });
//!     const ground_hull = box3d.shape.boxHull(50, 10, 50);
//!     _ = try box3d.shape.createHull(ground, .{}, &ground_hull.base);
//!
//!     // A unit cube dropped from four metres up.
//!     const cube = try box3d.body.create(world, .{
//!         .bodyType = .dynamic,
//!         .position = .{ .x = 0, .y = 4, .z = 0 },
//!     });
//!     const cube_hull = box3d.shape.cubeHull(1);
//!     _ = try box3d.shape.createHull(cube, .{ .density = 1.0 }, &cube_hull.base);
//!
//!     for (0..90) |_| box3d.world.step(world, 1.0 / 60.0, 4);
//!
//!     const resting = box3d.body.position(cube);
//!     std.debug.print("resting at y = {d:.3}\n", .{resting.y});
//! }
//! ```
//!
//! That is upstream's own `HelloWorld` (`test/test_world.c:21-101`) with the
//! names this module gives it. After 90 steps of 1/60 s with 4 sub-steps the
//! cube rests with its centre one metre up, because the ground's top face is at
//! y = 0 and the cube's half-width is 1 - which is `tests.zig`'s fixture, and the
//! number there is derived rather than copied.
//!
//! ## How the surface is organised
//!
//! Types are flat on this module, because they appear in every signature:
//! `WorldId`, `BodyId`, `ShapeId`, `JointId`, `Vec3`, `Pos`, `Transform`,
//! `WorldDef`, `BodyDef`, `ShapeDef` and the rest.
//!
//! Operations are grouped into namespaces, because a physics engine has a great
//! many of them and one flat list would be unusable:
//!
//!   * `base` - version, precision, the allocator and the assert and log hooks,
//!     the clock, the length scale, Box3D's own hash.
//!   * `math` - vector, quaternion, transform, position, matrix and bounding-box
//!     helpers. Each is a named alias of an upstream inline, not a
//!     reimplementation.
//!   * `world` - create, step, tune, read the last step's events, destroy.
//!   * `body` - create, transform, velocities, forces, mass, sleep, destroy.
//!   * `shape` - the three convex creators plus mesh, height field and compound;
//!     density, friction, restitution, filter, events, contacts.
//!   * `joint` - the nine joint types, destruction and the settings they share.
//!   * `query` - overlap, ray cast, shape cast and the character mover, each
//!     with a callback form and a slice-filling `collect` form.
//!
//! ## Ids, and nothing that owns one
//!
//! There is no `World`, no `Body`, no `Shape`: those would be wrappers holding an
//! id, an allocator and a `deinit`, and Box3D's ids are already generation-
//! checked value types that upstream tells you to pass around by value
//! (`include/box3d/id.h:30-31`). So `create` returns an id, every operation takes
//! one, and `destroy` takes it back. A struct in this package would add a second
//! lifetime the library does not have and could not keep in step with upstream's
//! own pool, where an id is stale the moment its object is freed
//! (`src/physics_world.c:1777-1793` is the check, and it compares a generation).
//!
//! ## Errors
//!
//! Creation calls that can fail are reported as errors rather than as a null
//! id: `world.create`, `body.create`, the seven shape creators and the nine
//! joint creators. Each names the null-id cases upstream can return, with the
//! source line for each on the error.
//!
//! A creator whose parent id has gone stale is reported here instead of being
//! passed on, because upstream resolves that parent by asserting on it before
//! it can return null. So `body.create` and the joint creators check the world
//! and the shape creators check the body, each with the same public validity
//! predicate upstream exposes (`b3World_IsValid`, `b3Body_IsValid`) and before
//! the call, and each creator keeps the null-id check for what is left.
//! `world.create` has no parent to check and is the exception: its limit is
//! upstream's own assertion, so `Error.WorldLimitExceeded` is only reported
//! where that assertion does not fire.
//!
//! Everything else in Box3D returns `void` or a value that cannot be absent,
//! and is declared that way rather than wrapped in an error union that could
//! never fire.
//!
//! ## Allocation
//!
//! This module allocates nothing on the caller's behalf. The only two functions
//! that take an allocator - `body.shapeSlice` and `body.jointSlice` - fill a
//! slice the caller owns, and everything else returns values or borrows memory
//! Box3D owns. Box3D's own allocations go through the process-global allocator
//! pair; see `base.setAllocator` for what that means and why a `std.mem.Allocator`
//! cannot simply be handed over.
//!
//! ## Threading
//!
//! Worlds are independent and may be simulated in parallel
//! (`include/box3d/box3d.h:32-34`). A single world is not internally locked for
//! the application: call `step` on one thread per world. Every callback the world
//! stores may be called from a worker thread during `step`, which is why
//! `world.setCustomFilterCallback` and its neighbours say so.
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! This module is built in one of two shapes, and `runtime_loaded` says which at
//! comptime.
//!
//! *Linked* is the default. The C library is linked, `c` is the translated
//! header, and every call below is a direct call with no table and no check.
//!
//! *Runtime-loaded* is opt-in with `-Druntime=true`. The library is not linked;
//! `c` is a dispatch generated from the same translation step's output, and every
//! `b3*` entry point those headers declare is resolved through the platform
//! loader when the caller calls
//!
//! ```zig
//! try box3d.load(.{ .path = "/usr/lib/libbox3d.so" });
//! ```
//!
//! before using anything else. A call into a module that has not loaded stops the
//! program with a message naming the function, in every optimization mode: that
//! is a programming error rather than a recoverable condition, because the table
//! does not exist yet and there is no partial state to fall back on.
//!
//! The provider is reached, never guessed. `.path` names a file and `.system`
//! names a library for the platform loader; neither falls back to the other, the
//! module has no unload and no reset, and it keeps the handle and its own copy of
//! the request to the end of the process. Calling `load` again with the same
//! request succeeds and changes nothing; a different request after a success is
//! `ProviderMismatch`, and the library already in use stays in use.
//!
//! What a provider must be, and what is and is not checked about it, is stated
//! in `runtime/library.zig`. It is worth reading before trusting one: Box3D's ABI
//! depends on more than a version number.
//!
//! This package is developed and gated against Zig 0.16.0.

const std = @import("std");

/// The translated Box3D headers, that is upstream's ABI exactly as published.
///
/// This is the escape hatch. Anything the facade does not name is here:
/// the geometry builders that allocate (`b3CreateCylinder`, `b3CreateMesh`,
/// `b3LoadHeightField`), the narrow-phase functions (`b3RayCastHull`,
/// `b3CollideSpheres`, `b3ShapeDistance`, `b3TimeOfImpact`), the low-level
/// dynamic tree (`b3DynamicTree_Create` and its tree queries), the recording and
/// replay API (`b3CreateRecording`, `b3RecPlayer_*`), debug draw, and the
/// struct fields themselves. It is the same module the facade calls, on the same
/// library, so importing the facade is all a dependent needs to reach it; it is
/// not published under a name of its own.
///
/// The declarations are for whichever header this build selected. A caller that
/// reaches past the facade gets upstream behaviour and inherits every obligation
/// upstream declares.
///
/// Ten of those declarations cannot be *called* by value on this target. Zig
/// 0.16.0's x86_64 argument lowering consumes one vector-register pair for a
/// by-value float aggregate of at most 24 bytes that it then passes in memory,
/// so a signature that takes a `b3Pos` by value ahead of a floating-point
/// argument or return places that later argument one register pair too high.
/// Under `-Ddouble-precision=true` a `b3Pos` is 24 bytes
/// (`include/box3d/math_functions.h:74-77`), so the ten are
/// `b3World_CastRay`, `b3World_CastRayClosest`, `b3World_CastShape`,
/// `b3World_CastMover`, `b3Body_CastRay`, `b3Body_CastShape`,
/// `b3Body_SetTransform`, `b3Body_GetLocalPoint`,
/// `b3Body_GetWorldPointVelocity` and `b3Shape_RayCast`. The declarations are
/// still upstream's, because the header still says that; what is wrong is the
/// call Zig emits for them, so reading them is fine and calling them is not.
///
/// The same module carries the `box3dAbi_*` functions for those ten, which
/// take pointers to the very same types and forward to the very same
/// by-value entry points. `query.castRayClosest` and its neighbours reach
/// Box3D that way, so a caller who goes past the facade should do the same.
/// `build_support/box3d_abi_bridge.h` has the measurement and the full list;
/// `b3Transform` at 28 bytes and `b3Mat3` at 36 bytes were checked on the same
/// build and agree with the native callee, which is why nothing else is here.
///
/// In a runtime-loading build this module is a generated dispatch instead of the
/// translation step's own output. It publishes the same namespace: every type and
/// constant is re-exported from the translated header rather than restated, so
/// `WorldId` is the same nominal type either way and nothing here needs a cast.
/// What differs is how a name reaches the library - directly, or through a table
/// `load` fills. `runtime_loaded` says which configuration this build is.
pub const c = @import("c");

/// The loader core, which is where a linked build's two public types come from.
///
/// Imported only by the linked configuration. In a runtime-loading build the
/// dispatch carries its own copy of the same declarations, and this module is
/// never referenced, so it is never resolved and never compiled. Either way
/// there is exactly one `LoadSource` and one `LoadError` in a build, which is
/// what keeps them one type for a consumer that names them.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the C library is linked and `c` is the
/// translated header itself. True when the build generated a dispatch that
/// resolves the same symbols through the platform loader, in which case `load`
/// is the call that makes the library usable.
///
/// It is a comptime constant, so a consumer can write two different code paths
/// and have only the one it chose analyzed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader. There is no path-to-system fallback and no implicit fallback
/// of any kind: a request that cannot be honoured is an error, not a different
/// library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside the
/// loader: the caller names the failure it is handling.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then use
/// this module as if it were linked. It is idempotent for the same request, it
/// refuses a different request after a success, and a failed attempt publishes
/// nothing and is retried only when the caller calls again - there is no
/// automatic retry and no implicit second source.
///
/// It keeps the process handle and its own copy of the request to the end of the
/// process. There is no unload and no reset, because the table is process-global
/// state that other code may already have called through.
///
/// Safe to call from any thread. A thread that arrives while an attempt for the
/// same request is in flight waits for that attempt and gets its result, whatever
/// it was. A call from the thread that is running the attempt is `ReentrantLoad`
/// rather than a deadlock.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly succeeding.
/// `runtime_loaded` is false there, so a consumer that supports both
/// configurations can tell the two apart at comptime instead of meeting this at
/// run time.
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

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

// -- components --------------------------------------------------------------

/// Process-wide services: version, allocator, hooks, clock, length scale.
pub const base = @import("base.zig");
/// Vector, quaternion, transform, position, matrix and AABB maths.
pub const math = @import("math.zig");
/// Worlds: create, step, tune, read events, destroy.
pub const world = @import("world.zig");
/// Bodies: create, transform, velocity, mass, sleep, destroy.
pub const body = @import("body.zig");
/// Shapes: geometry, material, filter, events, contacts.
pub const shape = @import("shape.zig");
/// Joints: the nine constraint types, and the settings they share.
pub const joint = @import("joint.zig");
/// Queries: overlap, ray cast, shape cast, character mover.
pub const query = @import("query.zig");

// -- ids ---------------------------------------------------------------------

/// A world handle, `b3WorldId` (`include/box3d/id.h:36-41`).
pub const WorldId = c.b3WorldId;
/// A body handle, `b3BodyId` (`include/box3d/id.h:43-48`).
pub const BodyId = c.b3BodyId;
/// A shape handle, `b3ShapeId` (`include/box3d/id.h:51-56`).
pub const ShapeId = c.b3ShapeId;
/// A joint handle, `b3JointId` (`include/box3d/id.h:60-65`).
pub const JointId = c.b3JointId;
/// A contact handle, `b3ContactId` (`include/box3d/id.h:68-75`).
///
/// Carried by the contact events and returned by `shape.contactData`. Upstream's
/// note on that declaration is that this id may be orphaned, so it is carried and
/// compared rather than trusted for long.
pub const ContactId = c.b3ContactId;

// -- maths -------------------------------------------------------------------

pub const Vec2 = math.Vec2;
pub const Vec3 = math.Vec3;
pub const Quat = math.Quat;
/// A world position: `Vec3` in single precision, a separate `double` struct
/// under `BOX3D_DOUBLE_PRECISION` (`include/box3d/math_functions.h:70-95`).
pub const Pos = math.Pos;
pub const Transform = math.Transform;
pub const WorldTransform = math.WorldTransform;
pub const Mat3 = math.Mat3;
pub const Aabb = math.Aabb;
pub const Plane = math.Plane;
/// Pi as `include/box3d/math_functions.h:21` writes it.
pub const pi: f32 = math.pi;
/// The zero vector, `math_functions.h:118`.
pub const zeroVec3: Vec3 = math.zero;
/// The identity rotation, `math_functions.h:123`.
pub const identityQuat: Quat = math.identity_quat;
/// The identity transform, `math_functions.h:124`.
pub const identityTransform: Transform = math.identity_transform;

// -- enumerations and definitions ---------------------------------------------

/// How a body behaves, `b3BodyType` (`include/box3d/types.h:221-237`).
pub const BodyType = body.BodyType;
/// No mass, no velocity, moved only by the application.
pub const staticBody: BodyType = body.staticBody;
/// No mass, velocity set by the application, pushed by the solver.
pub const kinematicBody: BodyType = body.kinematicBody;
/// Positive mass, velocity determined by forces.
pub const dynamicBody: BodyType = body.dynamicBody;

/// What kind of geometry a shape is, `b3ShapeType`
/// (`include/box3d/types.h:428-452`).
pub const ShapeType = shape.ShapeType;
/// Which kind of constraint a joint is, `b3JointType`
/// (`include/box3d/types.h:586-597`).
pub const JointType = joint.JointType;

/// A world definition; `.{}` means upstream's defaults.
pub const WorldDef = world.WorldDef;
/// A body definition; `.{}` means upstream's defaults.
pub const BodyDef = body.BodyDef;
/// A shape definition; `.{}` means upstream's defaults.
pub const ShapeDef = shape.ShapeDef;
/// The settings every joint type shares.
pub const JointDef = joint.JointDef;
/// A query filter; `.{}` accepts everything.
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

/// Axis locks, `b3MotionLocks` (`include/box3d/types.h:241-260`).
pub const MotionLocks = body.MotionLocks;
/// Mass, centre of mass and inertia, `b3MassData`
/// (`include/box3d/types.h:1865-1876`).
pub const MassData = body.MassData;
/// Per-shape collision filtering, `b3Filter` (`include/box3d/types.h:358-390`).
pub const Filter = shape.Filter;
/// Friction, restitution, rolling resistance, user material id,
/// `b3SurfaceMaterial` (`include/box3d/types.h:398-422`).
pub const SurfaceMaterial = shape.SurfaceMaterial;
/// A solid sphere, `b3Sphere` (`include/box3d/types.h:1885-1892`).
pub const Sphere = shape.Sphere;
/// A solid capsule, `b3Capsule` (`include/box3d/types.h:1904-1914`).
pub const Capsule = shape.Capsule;
/// An efficient box hull, `b3BoxHull` (`include/box3d/types.h:2022-2032`).
pub const BoxHull = shape.BoxHull;
/// A convex hull, `b3HullData` (`include/box3d/types.h:1963-2019`).
pub const HullData = shape.HullData;
/// A query filter as Box3D passes it, `b3QueryFilter`
/// (`include/box3d/types.h:1283-1301`).
pub const QueryFilter = query.QueryFilter;
/// Broad-phase traversal counters, `b3TreeStats`
/// (`include/box3d/types.h:1759-1766`).
pub const TreeStats = query.TreeStats;
/// A ray cast result, `b3RayResult` (`include/box3d/types.h:1321-1354`).
pub const RayResult = query.RayResult;
/// A generic query shape, `b3ShapeProxy` (`include/box3d/types.h:1357-1367`).
pub const ShapeProxy = query.ShapeProxy;

/// Box3D's version, `b3Version` (`include/box3d/base.h:148-158`).
pub const Version = base.Version;
