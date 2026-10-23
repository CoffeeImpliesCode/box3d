# Zig facade API

`@import("box3d")` exposes typed operations and `c`, the translated upstream C headers. See `README.md` for package setup and build options.

## Routes

- `box3d.c` exposes the complete translated public C surface, including functions the facade does not wrap.
- `box3d.math` aliases upstream's inline math functions. Other typed namespaces forward to C.
- Root types are aliases of the selected translation. `.{}` uses upstream defaults for definition types.

With double precision on x86-64, avoid direct Zig calls to these by-value declarations. Use the pointer-taking `c.box3dAbi_*` form instead:

| C declaration | Pointer form |
|---|---|
| `b3World_CastRay` | `box3dAbi_CastRay` |
| `b3World_CastRayClosest` | `box3dAbi_CastRayClosest` |
| `b3World_CastShape` | `box3dAbi_CastShape` |
| `b3World_CastMover` | `box3dAbi_CastMover` |
| `b3Body_CastRay` | `box3dAbi_BodyCastRay` |
| `b3Body_CastShape` | `box3dAbi_BodyCastShape` |
| `b3Body_SetTransform` | `box3dAbi_BodySetTransform` |
| `b3Body_GetLocalPoint` | `box3dAbi_BodyGetLocalPoint` |
| `b3Body_GetWorldPointVelocity` | `box3dAbi_BodyGetWorldPointVelocity` |
| `b3Shape_RayCast` | `box3dAbi_ShapeRayCast` |

The typed facade uses those pointer forms for `query.castRay`, `castRayClosest`, `castShape`, `castMover`, `castRayAgainstBody`, `castShapeAgainstBody`, `body.setTransform`, `body.localPoint`, `body.worldPointVelocity` and `shape.rayCast`. `query.castRayClosestShape` uses `castRayClosest`.

## Root types

- Handles: `WorldId`, `BodyId`, `ShapeId`, `JointId`, `ContactId`.
- Math: `Vec2`, `Vec3`, `Quat`, `Pos`, `Transform`, `WorldTransform`, `Mat3`, `Aabb`, `Plane`.
- Enums: `BodyType`, `ShapeType`, `JointType`; body values `staticBody`, `kinematicBody`, `dynamicBody`.
- Definitions: `WorldDef`, `BodyDef`, `ShapeDef`, `JointDef`, `QueryFilterDef`, and `DistanceJointDef`, `MotorJointDef`, `FilterJointDef`, `ParallelJointDef`, `PrismaticJointDef`, `RevoluteJointDef`, `SphericalJointDef`, `WeldJointDef`, `WheelJointDef`.
- Shape and query data: `Sphere`, `Capsule`, `HullData`, `BoxHull`, `ShapeProxy`, `MassData`, `Filter`, `SurfaceMaterial`, `MotionLocks`, `QueryFilter`, `RayResult`, `TreeStats`.
- Constants and metadata: `pi`, `zeroVec3`, `identityQuat`, `identityTransform`, `Version`.

## Namespaces

| Namespace | Operations |
|---|---|
| `base` | Version and precision, allocator, assert and log hooks, ticks, length scale, hash. |
| `math` | Vector, quaternion, position, transform, matrix and AABB helpers. |
| `world` | Create, step, configure, inspect, read events, destroy. |
| `body` | Create, transform, velocity, forces, mass, sleep, enumerate, destroy. |
| `shape` | Build and mutate geometry; set materials and filters; read contacts and events. |
| `joint` | Create nine joint types; shared settings, accessors and destruction. Per-type tuning remains in `c`. |
| `query` | Overlaps, ray and shape casts, mover operations; callback and slice forms. |

## Ownership and results

World, body, shape and joint IDs are generation-checked values, not owning wrappers. Check validity before reusing an ID after destruction; destroying a body also destroys its shapes and joints.

Creation functions return errors for native null IDs. The facade checks parent IDs before calling C: a stale world returns `error.InvalidWorld`, and a stale body returns `error.ShapeCreationFailed`. Pool exhaustion and body IDs inside joint definitions remain upstream preconditions.

`base.setAllocator` installs a process-wide allocation/free pair before creating worlds. Free Box3D allocations through the same pair. `body.shapeSlice` and `body.jointSlice` take a caller allocator; no other facade call allocates on the caller's behalf.

`query.overlapAabbCollect` and `query.castShapeCollect` return the total hit count. Only `out[0..min(count, out.len)]` is written, and hit order is unspecified. Other buffer-taking operations return the number of entries written. `world.jointEventSlice` borrows Box3D's event array and performs no allocation; event data is valid until the next step.

A world is not locked for application calls. Step each world from one application thread; independent worlds can run in parallel. Callbacks may run on worker threads. A supplied `finishTask` callback must wait until its task completes.

## Runtime loader

`runtime_loaded` is a compile-time boolean. In a runtime-loaded build, call `load` before any C or facade operation:

```zig
try box3d.load(.{ .path = "/path/to/libbox3d.so" });
// Or: try box3d.load(.{ .system = "libbox3d.so.0" });
```

`LoadSource` is `.path` (an absolute file path) or `.system` (a library basename); the loader does not fall back between them. `load(source: LoadSource) LoadError!void` accepts the same request again, but rejects a different request after success with `ProviderMismatch`. Failed attempts publish no table and can be retried by calling `load` again. Calling the API before a successful load panics.

`loadedSource() ?LoadSource` returns the successful request, or `null` in a linked build. `LoadError` includes `EmptySource`, `SourceTooLong`, `UnsupportedTarget`, `OpenFailed`, `MissingSymbol`, `ValidationFailed`, `ProviderMismatch` and `ReentrantLoad`. A runtime provider must use the same optimization and precision settings and include this fork's ABI bridge; loading checks the ABI, not solver behavior.
