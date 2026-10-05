// SPDX-License-Identifier: MIT
//
//! Shapes: the geometry and the material that bound to a body.
//!
//! ## Who owns the geometry
//!
//! This is the one part of the API where ownership is not uniform, and getting
//! it wrong is a use-after-free rather than an error, so it is spelled out per
//! creator:
//!
//!   * `createSphere`, `createCapsule` and `createHull` **clone** their geometry
//!     into the world (`include/box3d/box3d.h:782,787,792`). The value you
//!     passed may go out of scope immediately.
//!   * `createMesh` and `createHeightField` do **not** clone
//!     (`include/box3d/box3d.h:804-816`). The mesh or height field must stay
//!     alive and unchanged for as long as the shape, and upstream says so on
//!     both declarations.
//!   * `createCompound` does **not** clone either
//!     (`include/box3d/box3d.h:818-819`), so a compound stays yours for the
//!     life of the shape on the same terms as a mesh. The builder that
//!     allocates one and the `b3DestroyCompound` that frees it are both on
//!     the `box3d.c` escape hatch.
//!
//! ## Contacts are not created at creation time
//!
//! Every creator's comment says contacts appear on the next step
//! (`include/box3d/box3d.h:783,788,793,799`). So a shape created and queried in
//! the same step will not yet be in contact with anything, and a static shape
//! can be created before the geometry around it is.
//!
//! ## Mass
//!
//! Density is what makes a dynamic body dynamic, and it lives on the shape
//! (`include/box3d/types.h:470-472`). A shape with zero density contributes no
//! mass. Changing density or destroying a shape can recompute the body's mass,
//! and the two `update_body_mass` arguments below are how a caller defers that
//! when it is cheaper to do it once at the end.

const c = @import("c");
const math = @import("math.zig");
const body_mod = @import("body.zig");
const world_mod = @import("world.zig");

/// A shape handle, `b3ShapeId` (`include/box3d/id.h:51-56`).
pub const ShapeId = c.b3ShapeId;

/// What kind of geometry a shape is, `b3ShapeType`
/// (`include/box3d/types.h:428-452`).
pub const ShapeType = c.b3ShapeType;


/// A solid sphere, `b3Sphere` (`include/box3d/types.h:1885-1892`).
///
/// `center` is a local offset, so a sphere need not be centred on its body.
pub const Sphere = c.b3Sphere;
/// A solid capsule: a cylinder between two hemisphere centres
/// (`include/box3d/types.h:1904-1914`).
pub const Capsule = c.b3Capsule;
/// A convex hull, `b3HullData` (`include/box3d/types.h:1963-2019`).
///
/// Upstream's own warning on that declaration is that it has data hanging off
/// the end and cannot be copied directly; it is always reached through the
/// `vertexOffset`, `pointOffset`, `edgeOffset`, `faceOffset` and `planeOffset`
/// fields.
pub const HullData = c.b3HullData;
/// An efficient box hull, `b3BoxHull` (`include/box3d/types.h:2022-2032`).
///
/// The hull itself is the `base` field; the arrays after it are what the
/// offsets index into.
pub const BoxHull = c.b3BoxHull;
/// A reusable collision mesh, `b3MeshData` (`include/box3d/types.h:2146-2195`).
///
/// Allocated by Box3D's mesh builders on `box3d.c` (`b3CreateGridMesh`,
/// `include/box3d/collision.h:312`); free it with `box3d.c.b3DestroyMesh`
/// (`include/box3d/collision.h:334`).
pub const MeshData = c.b3MeshData;
/// A triangle-soup shape's runtime form, `b3Mesh`
/// (`include/box3d/types.h:2198-2206`).
pub const Mesh = c.b3Mesh;
/// A height field, `b3HeightFieldData` (`include/box3d/types.h:2259-2309`).
///
/// Allocated by Box3D's height-field builders on `box3d.c` (`b3CreateGrid`,
/// `include/box3d/collision.h:383`); free it with
/// `box3d.c.b3DestroyHeightField` (`include/box3d/collision.h:390`).
pub const HeightFieldData = c.b3HeightFieldData;
/// A compound of child shapes, `b3CompoundData`
/// (`include/box3d/types.h:2413-2462`).
///
/// Allocated by `box3d.c.b3CreateCompound`
/// (`include/box3d/collision.h:427`); free it with
/// `box3d.c.b3DestroyCompound` (`include/box3d/collision.h:430`). A compound
/// rebuilt from bytes with `b3ConvertBytesToCompound`
/// (`include/box3d/collision.h:437-440`) is that buffer rather than a fresh
/// allocation, so it is the caller's to free.
pub const CompoundData = c.b3CompoundData;
/// Per-shape collision filtering, `b3Filter`
/// (`include/box3d/types.h:358-390`).
pub const Filter = c.b3Filter;
/// Friction, restitution, rolling resistance and a user material id,
/// `b3SurfaceMaterial` (`include/box3d/types.h:398-422`).
pub const SurfaceMaterial = c.b3SurfaceMaterial;

/// Every category bit set, `B3_DEFAULT_CATEGORY_BITS`
/// (`include/box3d/types.h:13`).
pub const defaultCategoryBits: u64 = c.B3_DEFAULT_CATEGORY_BITS;
/// Every mask bit set, `B3_DEFAULT_MASK_BITS` (`include/box3d/types.h:14`).
pub const defaultMaskBits: u64 = c.B3_DEFAULT_MASK_BITS;

/// A shape definition, as optional overrides of upstream's defaults.
///
/// `.{}` is a complete, valid definition that asks for upstream's defaults
/// (`src/types.c`, `b3DefaultShapeDef`): no events, not a sensor, default
/// material and filter. `.{ .{} }` and a partial literal are both valid,
/// because every field is optional.
///
/// `internalValue` is absent on purpose: it is upstream's validity marker
/// (`include/box3d/types.h:510-512`) and must come from
/// `b3DefaultShapeDef`.
pub const ShapeDef = struct {
    /// Application data, readable with `userData`.
    userData: ?*anyopaque = null,
    /// Per-triangle materials for meshes. Box3D copies them into shape-owned
    /// storage when the shape is created (`src/shape.c:203-209,213`), so the
    /// array need not outlive the call. Upstream declares the field as a
    /// mutable `b3SurfaceMaterial*` (`include/box3d/types.h:462`) and only
    /// reads through it, but this field has to be that same pointer type to be
    /// written into the translated `b3ShapeDef`.
    materials: ?[*]SurfaceMaterial = null,
    /// How many entries `materials` has.
    materialCount: ?c_int = null,
    /// The material convex shapes use. Ignored for compound shapes
    /// (`include/box3d/types.h:467-468`).
    baseMaterial: ?SurfaceMaterial = null,
    /// Density in kg/m^3. Zero means the shape contributes no mass, which is
    /// how a static shape is made on a dynamic body.
    density: ?f32 = null,
    /// Explosion scale for `world.explode`. Non-dimensional.
    explosionScale: ?f32 = null,
    /// Collision filtering.
    filter: ?Filter = null,
    /// Opt into the world's custom filter callback. Only one of the two shapes
    /// in a pair needs it (`include/box3d/types.h:479-480`).
    enableCustomFiltering: ?bool = null,
    /// A sensor reports overlaps but never produces a collision response, and
    /// has no continuous collision (`include/box3d/types.h:482-484`).
    isSensor: ?bool = null,
    /// Report sensor events for this shape. Off by default even for sensors
    /// (`include/box3d/types.h:489-491`).
    enableSensorEvents: ?bool = null,
    /// Report begin/end-touch contact events. Off by default, and ignored for
    /// sensors (`include/box3d/types.h:492-494`).
    enableContactEvents: ?bool = null,
    /// Report hit events. Off by default, and ignored for sensors.
    enableHitEvents: ?bool = null,
    /// Report pre-solve contact events. Dynamic bodies only, expensive, and
    /// must be handled carefully under multithreading
    /// (`include/box3d/types.h:495-500`).
    enablePreSolveEvents: ?bool = null,
    /// Scan the environment for contacts on the next step. Static shapes only;
    /// upstream notes this can make bulk static creation significantly slower
    /// and that dynamic and kinematic shapes always create contacts anyway
    /// (`include/box3d/types.h:502-505`).
    invokeContactCreation: ?bool = null,
    /// Recompute the body's mass after creating this shape. Upstream's default
    /// is true (`include/box3d/types.h:507-508`).
    updateBodyMass: ?bool = null,

    /// The definition Box3D wants: upstream's defaults with the set fields
    /// written over them.
    pub fn native(self: ShapeDef) c.b3ShapeDef {
        var out = c.b3DefaultShapeDef();
        if (self.userData) |value| out.userData = value;
        if (self.materials) |value| out.materials = value;
        if (self.materialCount) |value| out.materialCount = value;
        if (self.baseMaterial) |value| out.baseMaterial = value;
        if (self.density) |value| out.density = value;
        if (self.explosionScale) |value| out.explosionScale = value;
        if (self.filter) |value| out.filter = value;
        if (self.enableCustomFiltering) |value| out.enableCustomFiltering = value;
        if (self.isSensor) |value| out.isSensor = value;
        if (self.enableSensorEvents) |value| out.enableSensorEvents = value;
        if (self.enableContactEvents) |value| out.enableContactEvents = value;
        if (self.enableHitEvents) |value| out.enableHitEvents = value;
        if (self.enablePreSolveEvents) |value| out.enablePreSolveEvents = value;
        if (self.invokeContactCreation) |value| out.invokeContactCreation = value;
        if (self.updateBodyMass) |value| out.updateBodyMass = value;
        return out;
    }
};

/// Everything that can go wrong in this module.
pub const Error = error{
    /// The body id was not a live body, or `b3CreateShape` returned a null id
    /// (`src/shape.c:256-308`). Upstream has four ways to reach that null id
    /// and this module does not tell them apart, because it cannot:
    ///
    ///   * the world named by the body id was free (`src/shape.c:264-268`);
    ///   * the world was at `B3_MAX_SHAPES` (`src/shape.c:270-274`), which
    ///     upstream asserts on, so a Debug build stops rather than returning;
    ///   * a compound or height field was put on a non-static body
    ///     (`src/shape.c:277-281`), which upstream requires;
    ///   * the internal allocation failed (`src/shape.c:290-294`).
    ///
    /// A stale body is not among them, because upstream does not get as far as
    /// answering: `b3CreateShape` resolves the body first, through
    /// `b3GetBodyFullId` (`src/shape.c:276`), and that asserts
    /// `b3Body_IsValid` before it returns one (`src/body.c:28-34`). So every
    /// creator here checks `body.isValid` - upstream's own public predicate
    /// (`src/physics_world.c:1795-1832`) - before it calls, and reports this
    /// error for a body that is gone.
    ///
    /// `B3_MAX_SHAPES` is `1 << B3_SHAPE_POWER`, so this is a large number, but
    /// it is a fixed limit rather than a memory question.
    ShapeCreationFailed,
};

// -- creation ----------------------------------------------------------------

/// Attach a sphere to a body (`include/box3d/box3d.h:785`).
///
/// The sphere is cloned; the value you pass may go out of scope immediately.
pub fn createSphere(body_id: body_mod.BodyId, def: ShapeDef, sphere_geometry: Sphere) Error!ShapeId {
    if (!body_mod.isValid(body_id)) return error.ShapeCreationFailed;
    var native_def = def.native();
    const id = c.b3CreateSphereShape(body_id, &native_def, &sphere_geometry);
    if (!c.b3Shape_IsValid(id)) return error.ShapeCreationFailed;
    return id;
}

/// Attach a capsule to a body (`include/box3d/box3d.h:790`).
///
/// The capsule is cloned.
pub fn createCapsule(body_id: body_mod.BodyId, def: ShapeDef, capsule_geometry: Capsule) Error!ShapeId {
    if (!body_mod.isValid(body_id)) return error.ShapeCreationFailed;
    var native_def = def.native();
    const id = c.b3CreateCapsuleShape(body_id, &native_def, &capsule_geometry);
    if (!c.b3Shape_IsValid(id)) return error.ShapeCreationFailed;
    return id;
}

/// Attach a convex hull to a body (`include/box3d/box3d.h:795`).
///
/// The hull is cloned, and the clone goes into the world's hull database where
/// it is shared with any other shape that hashes to the same geometry
/// (`include/box3d/box3d.h:797-799` describes that sharing for the transformed
/// form).
pub fn createHull(body_id: body_mod.BodyId, def: ShapeDef, hull: *const HullData) Error!ShapeId {
    if (!body_mod.isValid(body_id)) return error.ShapeCreationFailed;
    var native_def = def.native();
    const id = c.b3CreateHullShape(body_id, &native_def, hull);
    if (!c.b3Shape_IsValid(id)) return error.ShapeCreationFailed;
    return id;
}

/// Attach a convex hull with a baked transform and a scale
/// (`include/box3d/box3d.h:801-802`).
///
/// The scale is applied first and the transform second. Use this for non-uniform
/// or mirrored scale, and for a local transform that should not move the shape
/// relative to its body.
pub fn createTransformedHull(
    body_id: body_mod.BodyId,
    def: ShapeDef,
    hull: *const HullData,
    transform: math.Transform,
    scale: math.Vec3,
) Error!ShapeId {
    if (!body_mod.isValid(body_id)) return error.ShapeCreationFailed;
    var native_def = def.native();
    const id = c.b3CreateTransformedHullShape(body_id, &native_def, hull, transform, scale);
    if (!c.b3Shape_IsValid(id)) return error.ShapeCreationFailed;
    return id;
}

/// Attach a triangle mesh to a body (`include/box3d/box3d.h:809`).
///
/// The mesh is **not** cloned: `mesh` must stay valid and unchanged for as long
/// as the shape. Mesh collision only creates contacts on static bodies.
pub fn createMesh(
    body_id: body_mod.BodyId,
    def: ShapeDef,
    mesh: *const MeshData,
    scale: math.Vec3,
) Error!ShapeId {
    if (!body_mod.isValid(body_id)) return error.ShapeCreationFailed;
    var native_def = def.native();
    const id = c.b3CreateMeshShape(body_id, &native_def, mesh, scale);
    if (!c.b3Shape_IsValid(id)) return error.ShapeCreationFailed;
    return id;
}

/// Attach a height field to a body (`include/box3d/box3d.h:816`).
///
/// The height field is **not** cloned, and it is only allowed on static bodies.
pub fn createHeightField(
    body_id: body_mod.BodyId,
    def: ShapeDef,
    height_field: *const HeightFieldData,
) Error!ShapeId {
    if (!body_mod.isValid(body_id)) return error.ShapeCreationFailed;
    var native_def = def.native();
    const id = c.b3CreateHeightFieldShape(body_id, &native_def, height_field);
    if (!c.b3Shape_IsValid(id)) return error.ShapeCreationFailed;
    return id;
}

/// Attach a compound to a body (`include/box3d/box3d.h:819`).
///
/// Compounds are only allowed on static bodies (`include/box3d/box3d.h:818`).
/// This is upstream's one shape creator that takes a non-const definition
/// pointer, so a mutable copy is passed here rather than hiding the difference.
pub fn createCompound(
    body_id: body_mod.BodyId,
    def: ShapeDef,
    compound: *const CompoundData,
) Error!ShapeId {
    if (!body_mod.isValid(body_id)) return error.ShapeCreationFailed;
    var native_def = def.native();
    const id = c.b3CreateCompoundShape(body_id, &native_def, compound);
    if (!c.b3Shape_IsValid(id)) return error.ShapeCreationFailed;
    return id;
}

// -- geometry builders -------------------------------------------------------

/// A cube hull of the given half-width (`include/box3d/collision.h:213`).
///
/// Returned by value as a `BoxHull`; the hull itself is the `base` field. This
/// cannot fail, so there is no error here.
pub fn cubeHull(half_width: f32) BoxHull {
    return c.b3MakeCubeHull(half_width);
}

/// A box hull with independent half-extents (`include/box3d/collision.h:216`).
pub fn boxHull(hx: f32, hy: f32, hz: f32) BoxHull {
    return c.b3MakeBoxHull(hx, hy, hz);
}

/// A box hull offset from its body origin (`include/box3d/collision.h:219`).
pub fn offsetBoxHull(hx: f32, hy: f32, hz: f32, offset: math.Vec3) BoxHull {
    return c.b3MakeOffsetBoxHull(hx, hy, hz, offset);
}

/// A box hull with a baked local transform (`include/box3d/collision.h:224`).
pub fn transformedBoxHull(hx: f32, hy: f32, hz: f32, transform: math.Transform) BoxHull {
    return c.b3MakeTransformedBoxHull(hx, hy, hz, transform);
}

/// A box hull with a transform and a post-scale
/// (`include/box3d/collision.h:233`).
pub fn scaledBoxHull(
    half_widths: math.Vec3,
    transform: math.Transform,
    post_scale: math.Vec3,
) BoxHull {
    return c.b3MakeScaledBoxHull(half_widths, transform, post_scale);
}

/// A unit sphere centred on its body.
pub fn sphere(radius: f32) Sphere {
    return .{ .center = math.zero, .radius = radius };
}

/// A capsule whose hemispheres are `height` apart, centred on its body.
pub fn capsule(height: f32, radius: f32) Capsule {
    const half: f32 = height / 2;
    return .{
        .center1 = .{ .x = 0, .y = -half, .z = 0 },
        .center2 = .{ .x = 0, .y = half, .z = 0 },
        .radius = radius,
    };
}

// -- lifecycle ---------------------------------------------------------------

/// Destroy a shape (`include/box3d/box3d.h:824`).
///
/// `update_body_mass` may be false when several shapes on one body are being
/// destroyed at once, and the mass is then updated once at the end with
/// `body.applyMassFromShapes`. Upstream's own comment on that line is the reason
/// the argument exists.
///
/// Every contact and sensor event that named this shape becomes stale.
pub fn destroy(id: ShapeId, update_body_mass: bool) void {
    c.b3DestroyShape(id, update_body_mass);
}

/// True while the id names a live shape (`include/box3d/box3d.h:826-827`).
///
/// Upstream recommends exactly this check on shape ids that came out of an
/// event, because a sensor or contact end event can name a shape that has
/// already been destroyed (`include/box3d/types.h:1060-1061,1115-1117`).
pub fn isValid(id: ShapeId) bool {
    return c.b3Shape_IsValid(id);
}

/// The geometry kind of this shape (`include/box3d/box3d.h:830`).
pub fn getType(id: ShapeId) ShapeType {
    return c.b3Shape_GetType(id);
}

/// The body this shape is attached to (`include/box3d/box3d.h:833`).
pub fn body(id: ShapeId) body_mod.BodyId {
    return c.b3Shape_GetBody(id);
}

/// The world that owns this shape (`include/box3d/box3d.h:836`).
pub fn world(id: ShapeId) world_mod.WorldId {
    return c.b3Shape_GetWorld(id);
}

/// Is this shape a sensor (`include/box3d/box3d.h:839`)?
pub fn isSensor(id: ShapeId) bool {
    return c.b3Shape_IsSensor(id);
}

/// Attach application data to a shape (`include/box3d/box3d.h:842`).
///
/// Box3D never dereferences or frees it. Upstream's note on the getter is that
/// this is how a shape id from an event or a query becomes the caller's own
/// object (`include/box3d/box3d.h:844-846`).
pub fn setUserData(id: ShapeId, user_data: ?*anyopaque) void {
    c.b3Shape_SetUserData(id, user_data);
}

/// The pointer set with `setUserData` (`include/box3d/box3d.h:846`).
pub fn userData(id: ShapeId) ?*anyopaque {
    return c.b3Shape_GetUserData(id);
}

// -- material ----------------------------------------------------------------

/// Set the shape's density in kg/m^3 (`include/box3d/box3d.h:851`).
///
/// `update_body_mass` does what its name says; see `destroy` for why it is a
/// parameter rather than always on.
pub fn setDensity(id: ShapeId, new_density: f32, update_body_mass: bool) void {
    c.b3Shape_SetDensity(id, new_density, update_body_mass);
}

/// The shape's density (`include/box3d/box3d.h:854`).
pub fn density(id: ShapeId) f32 {
    return c.b3Shape_GetDensity(id);
}

/// Set the shape's friction coefficient (`include/box3d/box3d.h:857`).
///
/// The value two shapes actually collide with is produced by mixing: `sqrt(a*b)`
/// by default, or whatever `world.setFrictionCallback` returns.
pub fn setFriction(id: ShapeId, new_friction: f32) void {
    c.b3Shape_SetFriction(id, new_friction);
}

/// The shape's friction (`include/box3d/box3d.h:860`).
pub fn friction(id: ShapeId) f32 {
    return c.b3Shape_GetFriction(id);
}

/// Set the shape's restitution, its bounciness (`include/box3d/box3d.h:863`).
///
/// Only collisions above the world's restitution threshold bounce at all
/// (`include/box3d/types.h:145-147`).
pub fn setRestitution(id: ShapeId, new_restitution: f32) void {
    c.b3Shape_SetRestitution(id, new_restitution);
}

/// The shape's restitution (`include/box3d/box3d.h:866`).
pub fn restitution(id: ShapeId) f32 {
    return c.b3Shape_GetRestitution(id);
}

/// Replace the shape's base surface material (`include/box3d/box3d.h:869`).
///
/// This does not touch per-triangle materials on a mesh.
pub fn setSurfaceMaterial(id: ShapeId, material: SurfaceMaterial) void {
    c.b3Shape_SetSurfaceMaterial(id, material);
}

/// The shape's base surface material (`include/box3d/box3d.h:872`).
pub fn surfaceMaterial(id: ShapeId) SurfaceMaterial {
    return c.b3Shape_GetSurfaceMaterial(id);
}

/// How many per-triangle materials this mesh shape has
/// (`include/box3d/box3d.h:875`).
pub fn meshMaterialCount(id: ShapeId) c_int {
    return c.b3Shape_GetMeshMaterialCount(id);
}

/// Set one per-triangle material of a mesh shape (`include/box3d/box3d.h:878`).
pub fn setMeshMaterial(id: ShapeId, material: SurfaceMaterial, index: c_int) void {
    c.b3Shape_SetMeshMaterial(id, material, index);
}

/// Read one per-triangle material of a mesh shape (`include/box3d/box3d.h:881`).
pub fn meshSurfaceMaterial(id: ShapeId, index: c_int) SurfaceMaterial {
    return c.b3Shape_GetMeshSurfaceMaterial(id, index);
}

/// The shape's collision filter (`include/box3d/box3d.h:884`).
pub fn filter(id: ShapeId) Filter {
    return c.b3Shape_GetFilter(id);
}

/// Replace the shape's collision filter (`include/box3d/box3d.h:891`).
///
/// Upstream's comment on that declaration is worth heeding: this is almost as
/// expensive as recreating the shape. `invoke_contacts` then recomputes every
/// contact on the next step, which is expensive again; pass false when the
/// filter change does not need immediate contacts.
pub fn setFilter(id: ShapeId, new_filter: Filter, invoke_contacts: bool) void {
    c.b3Shape_SetFilter(id, new_filter, invoke_contacts);
}

// -- event flags -------------------------------------------------------------

/// Report sensor events for this shape (`include/box3d/box3d.h:895`).
///
/// Kinematic and dynamic bodies only, and ignored for sensors.
pub fn enableSensorEvents(id: ShapeId, flag: bool) void {
    c.b3Shape_EnableSensorEvents(id, flag);
}

/// Are sensor events enabled (`include/box3d/box3d.h:898`)?
pub const areSensorEventsEnabled = c.b3Shape_AreSensorEventsEnabled;

/// Report begin/end-touch contact events (`include/box3d/box3d.h:902`).
pub fn enableContactEvents(id: ShapeId, flag: bool) void {
    c.b3Shape_EnableContactEvents(id, flag);
}

/// Are contact events enabled (`include/box3d/box3d.h:905`)?
pub const areContactEventsEnabled = c.b3Shape_AreContactEventsEnabled;

/// Report pre-solve contact events (`include/box3d/box3d.h:910`).
///
/// Dynamic bodies only. Upstream marks these expensive and warns they must be
/// handled carefully under multithreading.
pub fn enablePreSolveEvents(id: ShapeId, flag: bool) void {
    c.b3Shape_EnablePreSolveEvents(id, flag);
}

/// Are pre-solve events enabled (`include/box3d/box3d.h:913`)?
pub const arePreSolveEventsEnabled = c.b3Shape_ArePreSolveEventsEnabled;

/// Report hit events (`include/box3d/box3d.h:917`).
///
/// The world's hit event threshold also has to be met, so enabling this does not
/// guarantee a hit event for every impact.
pub fn enableHitEvents(id: ShapeId, flag: bool) void {
    c.b3Shape_EnableHitEvents(id, flag);
}

/// Are hit events enabled (`include/box3d/box3d.h:920`)?
pub const areHitEventsEnabled = c.b3Shape_AreHitEventsEnabled;

// -- contacts, sensors, geometry ---------------------------------------------

/// How many contacts this shape is in (`include/box3d/box3d.h:962`).
pub fn contactCapacity(id: ShapeId) c_int {
    return c.b3Shape_GetContactCapacity(id);
}

/// This shape's contacts, up to `out.len` of them
/// (`include/box3d/box3d.h:968`).
///
/// The provided shape appears as one of the two ids in each entry. Upstream's
/// warning on that declaration is that the return value is the number of valid
/// entries and must not be ignored. Box3D uses speculative collision, so some
/// contact points may still be separated
/// (`include/box3d/box3d.h:965`).
pub fn contactData(id: ShapeId, out: []body_mod.ContactData) c_int {
    if (out.len == 0) return 0;
    return c.b3Shape_GetContactData(id, out.ptr, @intCast(out.len));
}

/// How many shapes overlap a sensor shape (`include/box3d/box3d.h:974`).
///
/// Zero for a shape that is not a sensor.
pub fn sensorCapacity(id: ShapeId) c_int {
    return c.b3Shape_GetSensorCapacity(id);
}

/// The shapes overlapping a sensor shape, up to `out.len` of them
/// (`include/box3d/box3d.h:983`).
///
/// Upstream's warning here is explicit: an overlap may be a shape that has since
/// been destroyed, so check each one with `isValid` before using it.
pub fn sensorData(id: ShapeId, out: []ShapeId) c_int {
    if (out.len == 0) return 0;
    return c.b3Shape_GetSensorData(id, out.ptr, @intCast(out.len));
}

/// The shape's current world AABB (`include/box3d/box3d.h:986`).
pub const getAabb = c.b3Shape_GetAABB;

/// The mass this shape contributes at its current density
/// (`include/box3d/box3d.h:989`).
pub const computeMassData = c.b3Shape_ComputeMassData;

/// The closest point on this shape to a world-space target
/// (`include/box3d/box3d.h:992`).
pub const getClosestPoint = c.b3Shape_GetClosestPoint;

/// Ray cast this shape directly (`include/box3d/box3d.h:924`).
///
/// The result is a `b3WorldCastOutput`, which is a `b3CastOutput` in single
/// precision and a double-point variant under `BOX3D_DOUBLE_PRECISION`
/// (`include/box3d/types.h:1430-1466`).
pub fn rayCast(id: ShapeId, origin: math.Pos, translation: math.Vec3) c.b3WorldCastOutput {
    return c.box3dAbi_ShapeRayCast(id, &origin, &translation);
}

/// Apply wind to this shape's body (`include/box3d/box3d.h:1003`).
///
/// The force follows the shape's projected area in the wind direction and the
/// relative velocity. `max_speed` caps the relative speed, which upstream says
/// is necessary for stability and is typically 10 m/s or less.
pub fn applyWind(
    id: ShapeId,
    wind: math.Vec3,
    drag: f32,
    lift: f32,
    max_speed: f32,
    wake: bool,
) void {
    c.b3Shape_ApplyWind(id, wind, drag, lift, max_speed, wake);
}

// -- geometry accessors ------------------------------------------------------

/// The shape's sphere (`include/box3d/box3d.h:927`).
///
/// Upstream asserts the type is a sphere, so calling this on another shape is a
/// programming error, not a checked failure.
pub const getSphere = c.b3Shape_GetSphere;

/// The shape's capsule (`include/box3d/box3d.h:930`).
pub const getCapsule = c.b3Shape_GetCapsule;

/// The shape's convex hull (`include/box3d/box3d.h:933`).
///
/// A borrowed pointer into the world's hull database. It stays valid until the
/// world is destroyed, and it is not a copy: do not write through it.
pub const getHull = c.b3Shape_GetHull;

/// The shape's mesh (`include/box3d/box3d.h:936`).
pub const getMesh = c.b3Shape_GetMesh;

/// The shape's height field (`include/box3d/box3d.h:939`).
pub const getHeightField = c.b3Shape_GetHeightField;

/// Turn a shape into a sphere, or update its sphere
/// (`include/box3d/box3d.h:944`).
///
/// This does not change mass; call `body.applyMassFromShapes` after.
pub fn setSphere(id: ShapeId, new_sphere: *const Sphere) void {
    c.b3Shape_SetSphere(id, new_sphere);
}

/// Turn a shape into a capsule, or update its capsule
/// (`include/box3d/box3d.h:949`).
pub fn setCapsule(id: ShapeId, new_capsule: *const Capsule) void {
    c.b3Shape_SetCapsule(id, new_capsule);
}

/// Turn a shape into a hull, or update its hull (`include/box3d/box3d.h:954`).
pub fn setHull(id: ShapeId, new_hull: *const HullData) void {
    c.b3Shape_SetHull(id, new_hull);
}

/// Turn a shape into a mesh, or update its mesh (`include/box3d/box3d.h:959`).
///
/// The mesh is not cloned; see `createMesh`.
pub fn setMesh(id: ShapeId, new_mesh: *const MeshData, scale: math.Vec3) void {
    c.b3Shape_SetMesh(id, new_mesh, scale);
}