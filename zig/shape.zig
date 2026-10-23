// SPDX-License-Identifier: MIT
//
//! Shape definitions, geometry creation, materials and contacts.

const c = @import("c");
const math = @import("math.zig");
const body_mod = @import("body.zig");
const world_mod = @import("world.zig");

pub const ShapeId = c.b3ShapeId;

pub const ShapeType = c.b3ShapeType;

/// Solid sphere; `center` is a body-local offset.
pub const Sphere = c.b3Sphere;
/// Solid capsule defined by two hemisphere centres and a radius.
pub const Capsule = c.b3Capsule;
/// Convex hull data with trailing arrays addressed by offset fields.
/// Use the offsets; the struct cannot be copied as a plain value.
pub const HullData = c.b3HullData;
/// Box hull; `base` is hull data and offsets address the following arrays.
pub const BoxHull = c.b3BoxHull;
/// Box3D-allocated mesh data; free it with `box3d.c.b3DestroyMesh`.
pub const MeshData = c.b3MeshData;
pub const Mesh = c.b3Mesh;
/// Box3D-allocated height-field data; free it with `box3d.c.b3DestroyHeightField`.
pub const HeightFieldData = c.b3HeightFieldData;
/// Box3D-allocated compound; free it with `box3d.c.b3DestroyCompound`.
/// A compound rebuilt from bytes is backed by caller-owned memory.
pub const CompoundData = c.b3CompoundData;
/// Per-shape collision filtering, `b3Filter` (`include/box3d/types.h:358-390`).
pub const Filter = c.b3Filter;
pub const SurfaceMaterial = c.b3SurfaceMaterial;

pub const defaultCategoryBits: u64 = c.B3_DEFAULT_CATEGORY_BITS;
pub const defaultMaskBits: u64 = c.B3_DEFAULT_MASK_BITS;

/// Optional overrides of upstream defaults; unset fields retain them.
/// `.{}` disables events and sensors, uses default material/filter; Box3D sets the validity marker.
pub const ShapeDef = struct {
    userData: ?*anyopaque = null,
    /// Box3D copies these materials at creation; the array need only live for the call.
    /// The mutable pointer type matches the upstream `b3ShapeDef` ABI.
    materials: ?[*]SurfaceMaterial = null,
    materialCount: ?c_int = null,
    /// Base material for convex shapes; ignored for compounds.
    baseMaterial: ?SurfaceMaterial = null,
    /// Density in kg/m^3; zero contributes no body mass.
    density: ?f32 = null,
    explosionScale: ?f32 = null,
    filter: ?Filter = null,
    /// Enable the world's custom filter callback for this shape.
    enableCustomFiltering: ?bool = null,
    /// Sensors report overlaps, not collision response, and do not use continuous collision.
    isSensor: ?bool = null,
    /// Sensor events are off by default, even for sensors (`include/box3d/types.h:489-491`).
    enableSensorEvents: ?bool = null,
    /// Contact events are off by default and ignored for sensors.
    enableContactEvents: ?bool = null,
    /// Hit events are ignored for sensors.
    enableHitEvents: ?bool = null,
    /// Pre-solve events apply to dynamic bodies and are costly under multithreading
    /// (`include/box3d/types.h:495-500`).
    enablePreSolveEvents: ?bool = null,
    /// Static shapes only; bulk creation may be slower, while dynamic and kinematic
    /// shapes create contacts automatically (`include/box3d/types.h:502-505`).
    invokeContactCreation: ?bool = null,
    /// Recompute body mass after creating this shape; defaults to true.
    updateBodyMass: ?bool = null,

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

pub const Error = error{
    /// Returned for stale bodies, pool exhaustion, allocation failure or unsupported geometry/body pairs.
    /// Pool exhaustion may assert first (`src/shape.c:256-308`).
    ShapeCreationFailed,
};

pub fn createSphere(body_id: body_mod.BodyId, def: ShapeDef, sphere_geometry: Sphere) Error!ShapeId {
    if (!body_mod.isValid(body_id)) return error.ShapeCreationFailed;
    var native_def = def.native();
    const id = c.b3CreateSphereShape(body_id, &native_def, &sphere_geometry);
    if (!c.b3Shape_IsValid(id)) return error.ShapeCreationFailed;
    return id;
}

pub fn createCapsule(body_id: body_mod.BodyId, def: ShapeDef, capsule_geometry: Capsule) Error!ShapeId {
    if (!body_mod.isValid(body_id)) return error.ShapeCreationFailed;
    var native_def = def.native();
    const id = c.b3CreateCapsuleShape(body_id, &native_def, &capsule_geometry);
    if (!c.b3Shape_IsValid(id)) return error.ShapeCreationFailed;
    return id;
}

/// Attach a convex hull; Box3D clones it into the world's hull database.
/// Identical hulls may share that clone (`include/box3d/box3d.h:797-799`).
pub fn createHull(body_id: body_mod.BodyId, def: ShapeDef, hull: *const HullData) Error!ShapeId {
    if (!body_mod.isValid(body_id)) return error.ShapeCreationFailed;
    var native_def = def.native();
    const id = c.b3CreateHullShape(body_id, &native_def, hull);
    if (!c.b3Shape_IsValid(id)) return error.ShapeCreationFailed;
    return id;
}

/// Attach a transformed, scaled hull. Scale is applied before the transform.
/// Use for non-uniform or mirrored scale and body-local offsets.
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

/// Attach a mesh without cloning it; keep it valid and unchanged while attached.
/// Mesh collision creates contacts only on static bodies.
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

/// Attach a borrowed height field; it must remain valid and is static-body only.
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

/// Attach a borrowed compound to a static body; keep it valid while attached.
/// A mutable definition copy is required by the upstream C signature.
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

pub fn cubeHull(half_width: f32) BoxHull {
    return c.b3MakeCubeHull(half_width);
}

pub fn boxHull(hx: f32, hy: f32, hz: f32) BoxHull {
    return c.b3MakeBoxHull(hx, hy, hz);
}

pub fn offsetBoxHull(hx: f32, hy: f32, hz: f32, offset: math.Vec3) BoxHull {
    return c.b3MakeOffsetBoxHull(hx, hy, hz, offset);
}

pub fn transformedBoxHull(hx: f32, hy: f32, hz: f32, transform: math.Transform) BoxHull {
    return c.b3MakeTransformedBoxHull(hx, hy, hz, transform);
}

pub fn scaledBoxHull(
    half_widths: math.Vec3,
    transform: math.Transform,
    post_scale: math.Vec3,
) BoxHull {
    return c.b3MakeScaledBoxHull(half_widths, transform, post_scale);
}

pub fn sphere(radius: f32) Sphere {
    return .{ .center = math.zero, .radius = radius };
}

pub fn capsule(height: f32, radius: f32) Capsule {
    const half: f32 = height / 2;
    return .{
        .center1 = .{ .x = 0, .y = -half, .z = 0 },
        .center2 = .{ .x = 0, .y = half, .z = 0 },
        .radius = radius,
    };
}

/// Destroy a shape. Set `update_body_mass` false to batch changes, then recompute.
/// Contact and sensor events may retain this shape's stale id.
pub fn destroy(id: ShapeId, update_body_mass: bool) void {
    c.b3DestroyShape(id, update_body_mass);
}

/// True while the id names a live shape; validate ids from events before use.
pub fn isValid(id: ShapeId) bool {
    return c.b3Shape_IsValid(id);
}

pub fn getType(id: ShapeId) ShapeType {
    return c.b3Shape_GetType(id);
}

pub fn body(id: ShapeId) body_mod.BodyId {
    return c.b3Shape_GetBody(id);
}

pub fn world(id: ShapeId) world_mod.WorldId {
    return c.b3Shape_GetWorld(id);
}

pub fn isSensor(id: ShapeId) bool {
    return c.b3Shape_IsSensor(id);
}

/// Box3D borrows this pointer and never frees or dereferences it.
/// The caller owns the pointed-to data.
pub fn setUserData(id: ShapeId, user_data: ?*anyopaque) void {
    c.b3Shape_SetUserData(id, user_data);
}

pub fn userData(id: ShapeId) ?*anyopaque {
    return c.b3Shape_GetUserData(id);
}

/// Set density; `update_body_mass` can defer recomputation for batched changes.
pub fn setDensity(id: ShapeId, new_density: f32, update_body_mass: bool) void {
    c.b3Shape_SetDensity(id, new_density, update_body_mass);
}

pub fn density(id: ShapeId) f32 {
    return c.b3Shape_GetDensity(id);
}

/// Contact friction defaults to `sqrt(a * b)` or the world mixing callback.
pub fn setFriction(id: ShapeId, new_friction: f32) void {
    c.b3Shape_SetFriction(id, new_friction);
}

pub fn friction(id: ShapeId) f32 {
    return c.b3Shape_GetFriction(id);
}

/// Contacts bounce only above the world's restitution threshold.
pub fn setRestitution(id: ShapeId, new_restitution: f32) void {
    c.b3Shape_SetRestitution(id, new_restitution);
}

pub fn restitution(id: ShapeId) f32 {
    return c.b3Shape_GetRestitution(id);
}

/// Replaces the base material but does not change per-triangle mesh materials.
pub fn setSurfaceMaterial(id: ShapeId, material: SurfaceMaterial) void {
    c.b3Shape_SetSurfaceMaterial(id, material);
}

pub fn surfaceMaterial(id: ShapeId) SurfaceMaterial {
    return c.b3Shape_GetSurfaceMaterial(id);
}

pub fn meshMaterialCount(id: ShapeId) c_int {
    return c.b3Shape_GetMeshMaterialCount(id);
}

pub fn setMeshMaterial(id: ShapeId, material: SurfaceMaterial, index: c_int) void {
    c.b3Shape_SetMeshMaterial(id, material, index);
}

pub fn meshSurfaceMaterial(id: ShapeId, index: c_int) SurfaceMaterial {
    return c.b3Shape_GetMeshSurfaceMaterial(id, index);
}

pub fn filter(id: ShapeId) Filter {
    return c.b3Shape_GetFilter(id);
}

pub fn setFilter(id: ShapeId, new_filter: Filter, invoke_contacts: bool) void {
    c.b3Shape_SetFilter(id, new_filter, invoke_contacts);
}

/// Sensor events require a kinematic or dynamic body and do not apply to sensors.
pub fn enableSensorEvents(id: ShapeId, flag: bool) void {
    c.b3Shape_EnableSensorEvents(id, flag);
}

pub const areSensorEventsEnabled = c.b3Shape_AreSensorEventsEnabled;

pub fn enableContactEvents(id: ShapeId, flag: bool) void {
    c.b3Shape_EnableContactEvents(id, flag);
}

pub const areContactEventsEnabled = c.b3Shape_AreContactEventsEnabled;

/// Pre-solve events apply to dynamic bodies and may be costly with multithreading.
pub fn enablePreSolveEvents(id: ShapeId, flag: bool) void {
    c.b3Shape_EnablePreSolveEvents(id, flag);
}

pub const arePreSolveEventsEnabled = c.b3Shape_ArePreSolveEventsEnabled;

/// Hit events also require the world's impact-speed threshold to be met.
pub fn enableHitEvents(id: ShapeId, flag: bool) void {
    c.b3Shape_EnableHitEvents(id, flag);
}

pub const areHitEventsEnabled = c.b3Shape_AreHitEventsEnabled;

pub fn contactCapacity(id: ShapeId) c_int {
    return c.b3Shape_GetContactCapacity(id);
}

/// Write at most `out.len` contacts and return the number of valid entries.
/// Each `manifolds` pointer borrows world memory and expires; see `body.ContactData`.
pub fn contactData(id: ShapeId, out: []body_mod.ContactData) c_int {
    if (out.len == 0) return 0;
    return c.b3Shape_GetContactData(id, out.ptr, @intCast(out.len));
}

/// Non-sensor shapes have no sensor overlaps.
pub fn sensorCapacity(id: ShapeId) c_int {
    return c.b3Shape_GetSensorCapacity(id);
}

/// Overlaps may include destroyed shapes; validate each id with `isValid`.
pub fn sensorData(id: ShapeId, out: []ShapeId) c_int {
    if (out.len == 0) return 0;
    return c.b3Shape_GetSensorData(id, out.ptr, @intCast(out.len));
}

pub const getAabb = c.b3Shape_GetAABB;

pub const computeMassData = c.b3Shape_ComputeMassData;

pub const getClosestPoint = c.b3Shape_GetClosestPoint;

/// Ray-cast this shape; the result point uses double precision in double-precision builds.
pub fn rayCast(id: ShapeId, origin: math.Pos, translation: math.Vec3) c.b3WorldCastOutput {
    return c.box3dAbi_ShapeRayCast(id, &origin, &translation);
}

/// Apply wind from projected area and relative velocity; cap `max_speed` for stability.
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

/// Upstream asserts unless this shape is a sphere; no checked error is returned.
pub const getSphere = c.b3Shape_GetSphere;

pub const getCapsule = c.b3Shape_GetCapsule;

/// Borrow hull data from the world's hull database; do not write through it.
/// The pointer remains valid until the world is destroyed.
pub const getHull = c.b3Shape_GetHull;

pub const getMesh = c.b3Shape_GetMesh;

pub const getHeightField = c.b3Shape_GetHeightField;

/// Replace sphere geometry; recompute body mass separately if needed.
pub fn setSphere(id: ShapeId, new_sphere: *const Sphere) void {
    c.b3Shape_SetSphere(id, new_sphere);
}

pub fn setCapsule(id: ShapeId, new_capsule: *const Capsule) void {
    c.b3Shape_SetCapsule(id, new_capsule);
}

pub fn setHull(id: ShapeId, new_hull: *const HullData) void {
    c.b3Shape_SetHull(id, new_hull);
}

/// The mesh is borrowed, not cloned; keep it valid and unchanged while attached.
pub fn setMesh(id: ShapeId, new_mesh: *const MeshData, scale: math.Vec3) void {
    c.b3Shape_SetMesh(id, new_mesh, scale);
}
