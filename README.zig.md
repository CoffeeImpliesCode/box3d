# box3d — the Zig interface

Everything a Zig consumer needs that `README.md` does not cover: how to depend
on the module, the two routes it offers, the external ABI boundaries the native
library actually has, and the runtime-loading contract.

This file names the surface and does not reproduce its signatures. The
authoritative declarations are the ones in `zig/root.zig` and in the translated
`c` module, and a full second copy here would be a second dialect of the same
interface — the same argument `zig/translate.h` makes about the C header. What
is stated here is what a consumer cannot read off the headers, or must not
misread in them.

## Depending on it

```zig
// build.zig.zon
.dependencies = .{
    .box3d = .{
        .path = "../box3d", // or a fetched, hashed copy
    },
},
```

```zig
// build.zig
const box3d = b.dependency("box3d", .{
    .target = target,
    .optimize = optimize,
}).module("box3d");

exe.root_module.addImport("box3d", box3d);
```

The dependency name and the module name are both `box3d`
(`build.zig.zon`, `.name = .box3d`). `dep.module("box3d")` carries the compiled
native library with it; there is nothing to install and nothing to find on the
system. For a C-only consumer, `dep.artifact("box3d")` is the library and
`box3d/` is already on the include path.

The minimum Zig version is 0.16.0 (`build.zig.zon`).

## The two routes

### The raw route — `box3d.c`

`pub const c = @import("c");` in `zig/root.zig` is the complete translated
native surface. It is not a facade over a facade and it is not narrowed to what
the typed surface happens to call: it is every `B3_API` declaration the pinned
headers contain.

| | |
|---|---|
| Public functions | **578** distinct names, in 580 `B3_API` declarations. `b3DynamicTree_Validate` (`collision.h:85` and `:106`) and `b3IsValidFloat` (`math_functions.h:159` and `:1077`) are each declared twice in upstream's own header with an identical signature, so they are one symbol each. |
| Structs | 123 named `b3*` structs, plus three opaque handles — `b3DebugShape`, `b3RecPlayer`, `b3Recording` — that are only ever used through a pointer. |
| Enums | 9: `b3BodyType`, `b3ShapeType`, `b3JointType`, `b3TOIState`, `b3TreeNodeFlags`, `b3MeshEdgeFlags`, `b3HexColor`, `b3DebugMaterial`, `b3RecQueryType`. |
| Callback typedefs | 16 `b3*Fcn` prototypes plus `b3FrictionCallback`, `b3RestitutionCallback`, `b3TaskCallback`, `b3EnqueueTaskCallback`, `b3FinishTaskCallback`, `b3CreateDebugShapeCallback` and `b3DestroyDebugShapeCallback`. |
| Exported data | **None.** No `extern` variable is declared by any public header, so there is no exported data symbol whose value could be stale, and no data symbol that has to be read by address rather than copied. |
| Variadic functions | **None.** No public declaration is variadic, so the dispatch has no variadic entry point and needs no tuple call. |
| Inline bodies | 109 `B3_INLINE`/`B3_FORCE_INLINE` functions (`math_functions.h` 93, `collision.h` 15, `types.h` 1) are header-only and never routed through a table. They are compiled into the consumer, exactly as in C. |
| Fork ABI bridge | 10 `box3dAbi_*` functions, declared in `build_support/box3d_abi_bridge.h` and compiled into this same module. These are **not** upstream declarations: each takes pointers to the same nominal types and forwards to the unchanged by-value entry point. See the caveat below. |

Types are nominally the module's own: `c.b3Vec3` here and `c.b3Vec3` in a
runtime-loaded build are the same type from the same translation step, and this
package does not compile a second, separately-named copy of a native struct and
cast between them.

**Ten of those declarations cannot be *called* by value on x86-64.** Zig
0.16.0's x86-64 argument lowering consumes one vector-register pair for a
by-value float aggregate of at most 24 bytes that the System V ABI then passes
in memory. Under `-Ddouble-precision=true` a `b3Pos` is 24 bytes
(`math_functions.h:74-77`), so a signature that takes a `b3Pos` by value ahead of
a floating-point argument or a floating-point return hands that later argument
one register pair too high. The ten are `b3World_CastRay`,
`b3World_CastRayClosest`, `b3World_CastShape`, `b3World_CastMover`,
`b3Body_CastRay`, `b3Body_CastShape`, `b3Body_SetTransform`,
`b3Body_GetLocalPoint`, `b3Body_GetWorldPointVelocity` and `b3Shape_RayCast`.

The declarations are still upstream's, because the header still says so. What is
wrong is the call Zig emits for them, so **reading them is fine and calling them
is not** — types, fields, sizes, the `b3CreateWorldDoublePrecision` rename, all of
that still describes this library. The same module carries the `box3dAbi_*` forms
for exactly those ten, and the typed route reaches Box3D through them:
`query.castRay`, `query.castRayClosest`, `query.castShape`, `query.castMover`,
`query.castRayAgainstBody`, `query.castShapeAgainstBody`, `body.setTransform`,
`body.localPoint`, `body.worldPointVelocity` and `shape.rayCast`
(`query.castRayClosestShape` is `castRayClosest` reduced, so it goes the same
way). A caller who goes past the facade should call the pointer form too. The
measured boundary is 24 bytes and not a guess: `b3Transform` at 28 bytes and
`b3Mat3` at 36 bytes were checked on the same binary and agree with the native
callee, which is why they are not in the set. The measurement and the full
argument are in `build_support/box3d_abi_bridge.h`.

### The typed route — flat types, grouped operations

`@import("box3d")` publishes a documented typed surface over the same native
calls. Types are flat on the root; operations are grouped in namespaces. Nothing
is reimplemented: every `box3d.math` entry is an alias of the upstream inline in
`include/box3d/math_functions.h`, and every namespace entry forwards to `c`.

Flat types on the root: `Vec2`, `Vec3`, `Quat`, `Pos`, `Transform`,
`WorldTransform`, `Mat3`, `Aabb`, `Plane`, `WorldId`, `BodyId`, `ShapeId`,
`JointId`, `ContactId`, `BodyType`, `ShapeType`, `JointType`, `Sphere`,
`Capsule`, `HullData`, `BoxHull`, `ShapeProxy`, `MassData`, `Filter`,
`SurfaceMaterial`, `MotionLocks`, `QueryFilter`, `RayResult`, `TreeStats`, the
`WorldDef`/`BodyDef`/`ShapeDef` trio, and nine typed joint definitions:
`DistanceJointDef`, `MotorJointDef`, `FilterJointDef`, `ParallelJointDef`,
`PrismaticJointDef`, `RevoluteJointDef`, `SphericalJointDef`, `WeldJointDef`,
`WheelJointDef`.

| Namespace | What it covers |
|---|---|
| `box3d.math` | vector, quaternion, transform, position, AABB, matrix and scalar helpers |
| `box3d.base` | version, precision, the allocator/assert/log hooks, ticks, hash, length units, stall threshold |
| `box3d.world` | `create`/`destroy`/`isValid`/`count`/`maxCount`/`step`/`bounds`/`awakeBodyCount`/`maxCapacity`/`profile`/`counters`, gravity, sleeping, continuous, warm starting, speculative, contact tuning and thresholds, worker count, user data, the four event getters and their `*Begin`/`*End` refinements, `explode`, the dumps and `rebuildStaticTree` |
| `box3d.body` | `create`/`destroy`/`isValid`/`world`/`getType`, name, user data, transform and target transform, velocities and point velocities, force/impulse/torque application, mass and mass data, damping, gravity scale, `isAwake`/`setAwake`, sleep enable and threshold, enable/disable, motion locks, bullet, contact recycling, hit events, and shape/joint/contact enumeration |
| `box3d.shape` | `createSphere`, `createCapsule`, `createHull`, `createTransformedHull`, `createMesh`, `createHeightField` and `createCompound`; the geometry builders `sphere`, `capsule`, `cubeHull`, `boxHull`, `offsetBoxHull`, `transformedBoxHull` and `scaledBoxHull`; `destroy`/`isValid`, type/body/world, sensor, density, friction, restitution, surface material, filter, the four event switches, contact and sensor data, `applyWind`, and the in-place geometry setters |
| `box3d.joint` | `createDistance` … `createWheel`, `defaultBase`, `destroy`/`isValid`/`getType`/`bodyA`/`bodyB`/`world`, the local frame accessors, `collideConnected`, user data, `wakeBodies`, `setConstraintTuning` and the force and torque thresholds. Per-type tuning accessors stay on `c` |
| `box3d.query` | `overlapAabb`, `overlapShape`, `castRay`, `castRayClosest`, `castRayClosestShape`, `castShape`, `castMover`, `collideMover` and `solvePlanes`, and the four per-body forms `castRayAgainstBody`, `castShapeAgainstBody`, `overlapShapeAgainstBody` and `collideMoverAgainstBody`. Two of them also have a slice-filling form: `overlapAabbCollect` and `castShapeCollect` |

The typed route adds no algorithm and drops none. Anything it does not wrap is
still reachable through `c`; the nine per-type joint tuning families are a
deliberate boundary rather than an omission, for the same reason the recording
and replay group stays reachable only through `c`.

### The two slice-filling collectors, and what their return value is

`query.overlapAabbCollect` and `query.castShapeCollect` are the only two entry
points that write into a caller-owned slice, and both return **the total number
of hits the query found, not the number it wrote**. The valid prefix of the
slice is exactly `min(returned, out.len)`; anything past that was not written.

That is not a rounding convenience, it is the point of the two functions. The
collector keeps counting after the slice is full instead of stopping the query,
so a caller can ask "how many are there" by passing a zero-length slice, and
can size the real allocation from the answer. Two rules follow from it and both
are easy to get wrong:

* a return larger than `out.len` is **not** an error and not a truncation notice
  in itself — it is the answer, and the caller decides what to do about the
  shortfall;
* a caller that treats the return as the written count silently drops the
  overflow. Read `out[0..min(count, out.len)]`, never `out[0..count]`.

The ids are written in the order the traversal produced them, and Box3D does not
define that order (`include/box3d/box3d.h:85`), so a caller that needs both
results from one query has to scan for them rather than index. A cast clipped
by the callback still reports every shape up to the clip point, because the
collector returns the unclipped value (`1`) from its callback rather than a
fraction.

**What has actually been exercised.** The overlap form's two distinctive cases
are probed by `tests.zig`: a zero-length slice answers "how many are there"
(`tests.zig:481`), and a one-slot slice for a query with two shapes still
answers `2` (`tests.zig:485-486`). Both ran in the linked gate recorded in
`README.md`. `castShapeCollect` has no caller in `tests.zig` or `smoke.zig` at
all, so neither its total-count behaviour nor the same overflow case is covered
by any run so far. The two forms share one collector shape in `zig/query.zig`,
and that is a reading of the code, not evidence.

The buffer-taking wrappers that wrap an upstream call are a different shape and
are not the same thing. `body.shapes`, `body.joints`, `body.contactData`,
`shape.contactData`, `shape.sensorData` and `query.collideMoverAgainstBody` all
forward a capacity to a native call that takes one, and all of them return
upstream's own **written** count — the number of entries valid in the buffer, not
a total that may be larger. Upstream is explicit about that reading, and warns
twice not to ignore the value, which "specifies the valid number of elements"
(`include/box3d/box3d.h:981`, and `:967` for the shape-side contact data). Two
convenience wrappers exist because the raw calls make the two-step awkward:
`body.shapeSlice` and `body.jointSlice` allocate a slice of exactly
`shapeCount`/`jointCount` for the caller and return it already truncated to what
was written, and `world.jointEventSlice` borrows the world's own event array and
slices it to `events.count` — it copies nothing and allocates nothing, and the
data expires with the step like every other event payload.

## External ABI

Symbol lookup is not compatibility proof. These are the boundaries that
actually decide whether a build of this library can serve a given consumer.

### Precision — this one is load-bearing

`BOX3D_DOUBLE_PRECISION` is upstream's only `PUBLIC` compile definition
(`src/CMakeLists.txt:164-168`) because it changes the ABI:

* `b3Pos` becomes a three-`double` struct instead of a typedef of `b3Vec3`, and
  `b3WorldTransform` changes with it (`math_functions.h:70-93`);
* `b3World_CastOutput` gets a double-precision mirror (`types.h:1429-1433`);
* `B3_HUGE` changes from `1.0e5f` to `1.0e9f` times the length scale
  (`constants.h:25-29`);
* **the exported symbol changes**: `#define b3CreateWorld
  b3CreateWorldDoublePrecision` (`box3d.h:25-30`) renames the definition in
  `src/physics_world.c:206`, so a double-precision library exports
  `b3CreateWorldDoublePrecision` and not `b3CreateWorld`.
* **ten public entry points are reachable only through `box3dAbi_*` on x86-64.**
  This is the calling-convention consequence of the bullet above: a `b3Pos` by
  value is 24 bytes under this define, Zig's lowering reserves a vector-register
  pair for it, and the floating-point argument after it lands one pair too high.
  The symbols exist and Box3D's own definitions are unchanged — it is the call
  Zig emits for them that is wrong, which is why pointer forms rather than a
  patched upstream signature is the answer. `b3Body_ApplyForce` and
  `b3Body_ApplyLinearImpulse` take their `b3Vec3` first and are not in the set,
  and neither are `b3World_OverlapShape`, `b3World_CollideMover`,
  `b3Body_OverlapShape`, `b3Body_CollideMover` or `b3IsValidPosition`, because
  nothing vector-classified follows their `b3Pos`.

Upstream renames it deliberately, to turn a silent layout mismatch into a link
error. A runtime-loading descriptor that resolved the name as it appears in the
header text would break in exactly this configuration and nowhere else, so the
expanded name is the one that has to be resolved.

The default is single precision, which is upstream's default.

### Configuration

| Option | Default | What a consumer sees |
|---|---|---|
| `BOX3D_DOUBLE_PRECISION` | off | Changes layout, one exported symbol name, and the route ten entry points can be called by, as above. Must match on both sides. |
| `BOX3D_DISABLE_SIMD` | off | Scalar fallback instead of SSE2/Neon. `PRIVATE`; no declaration changes. |
| `BOX3D_VALIDATE` | on | `PRIVATE`, and effective only when `NDEBUG` is absent (`base.h:70-74`), so Debug and ReleaseSafe validate and ReleaseFast and ReleaseSmall do not. It is also written into the recording header (`src/recording.h:62`), so a recording made under one setting is not interchangeable with one made under the other. |
| `BOX3D_EXPORT` / `BOX3D_DLL` | — | Import/export decoration only. See the Windows note below. |

### Allocator and lifetime

`b3SetAllocator(b3AllocFcn*, b3FreeFcn*)` (`base.h:85-102`) takes a pair, and
the `alignment` argument is documented as a guaranteed power of two. The pairing
is installed during application startup, before any world exists, and memory
that crosses into Box3D must be released through the same pair. A test
framework's leak oracle does not cover allocations made through a user
allocator, and this package does not pretend otherwise.

### Identity and ownership

Worlds, bodies, shapes and joints are opaque integer ids, not pointers, with
`b3World_IsValid`, `b3Body_IsValid` and `b3Shape_IsValid` for orphaned ids
(validated to 64K allocations). Up to 128 independent worlds may exist at once
(`box3d.h:32-34`). Event payloads from the four `b3World_Get*Events` calls are
transient and are only valid until the next step. Destroying a body destroys
its shapes and joints.

### Stale parents are reported here; full pools are not

Box3D resolves a parent id by asserting on it before it can return anything. A
destroyed world reaches `B3_ASSERT( id.generation == world->generation )` inside
`b3GetUnlockedWorldFromId` (`src/physics_world.c:96`) through `b3CreateBody`
(`src/body.c:169`) and through each of the nine joint creators
(`src/joint.c:439-443` for `b3CreateDistanceJoint` and the same lookup in the
other eight); a destroyed body reaches `B3_ASSERT( b3Body_IsValid( bodyId ) )`
inside `b3GetBodyFullId` (`src/body.c:30`) through `b3CreateShape`
(`src/shape.c:276`). In a Debug build those are `B3_BREAKPOINT` and the process
stops. The native null-id answers on `src/body.c:171-174` and
`src/physics_world.c:101-104` sit **behind** the assertion and are not reached.

So every typed creator asks the same public predicate upstream exposes, before
it calls: `body.create` and the nine joint creators ask `world.isValid`, the
seven shape creators ask `body.isValid`. A gone parent comes back as
`error.InvalidWorld` or `error.ShapeCreationFailed` rather than as an abort. The
check after the call is kept and is not redundant — it is what reports a locked
world in a build where `B3_ASSERT` compiles to nothing under `NDEBUG` without
`B3_ENABLE_ASSERT` (`include/box3d/base.h:123-131`), or where an assert handler
installed through `base.setAssertFcn` returns 0 to skip the break
(`src/core.c:81-90`).

**What the preflight is worth.** The three stale-parent cases are
`tests.zig:739`, `tests.zig:757` and `tests.zig:775`, and all three are in the
recorded linked run. Before the check existed they died instead: the receipt
`local://foundation-contract-box3d-initial-pose-ray-and-filtered-scene-caller-repair-smoke-test.log`
shows `B3_BREAKPOINT` reached through `src/physics_world.c:96`,
`src/body.c:30` and `src/joint.c:439` — upstream's own assertions, not this
package's. That is the whole argument for asking first: without it the typed
route is a way to turn a recoverable mistake into a process kill.

**The finite capacities are deliberately not pre-empted.** `B3_MAX_WORLDS` is 128
(`include/box3d/constants.h:62-65`) and `B3_MAX_SHAPES` is `1 << 22`
(`include/box3d/constants.h:120-122`). Reaching either is an assertion in
upstream (`src/physics_world.c:223-228`, `src/shape.c:270-274`), not a value it
returns, so neither is turned into a recoverable error here. `world.create` has
no parent to check and is the clearest case: `error.WorldLimitExceeded` is
reported only on the path where upstream survives to be asked, which in a Debug
build it does not. A caller that must not abort keeps its own tally against
`base.maxWorlds`. The two body ids inside a joint definition stay a precondition
on the definition too — upstream resolves them through `b3GetBodyFullId`
(`src/joint.c:163-164`) and this module does not inspect definition values.
Nothing else in Box3D returns `void` or an absentable value, and is declared
that way rather than wrapped in an error union that could never fire.

That is a reading of the source and an observation, not a stylistic choice. A
Debug run that filled the world pool stopped inside `b3CreateWorld` at
`B3_ASSERT( worldId != B3_NULL_INDEX )` (`src/physics_world.c:226`) — the same
receipt — before the null id on `:227` existed to be checked. So
`error.WorldLimitExceeded` names the branch where upstream survives to be asked;
it is not a guarantee about `world.create` in a build whose assertions are live.
No test in `tests.zig` fills either pool, so neither assertion is exercised by
any recorded run.

### Threading and the task system

`b3WorldDef` (`types.h:140-215`) takes an optional user task system:
`enqueueTask`, `finishTask` and `userTaskContext`, with `workerCount` clamped to
`[1, B3_MAX_WORKERS]`. When the callbacks are supplied, `finishTask` **must
block** until the task completes, because the step holds its stack across every
task it spawns (`types.h:33-35`). Without them Box3D creates its own threads.

Those threads are platform-dependent: `src/timer.c` uses pthreads and unnamed
POSIX semaphores on Linux and Emscripten and falls back to a single-threaded
path elsewhere, so `workerCount > 1` is not the same promise on every target.
`b3FrictionCallback` and `b3RestitutionCallback` are called from worker threads
and take no context pointer, by design (`types.h:50-60`).

### Windows

`BOX3D_EXPORT` is `__declspec(dllexport)` when `box3d_EXPORTS` is defined,
`__declspec(dllimport)` when `BOX3D_DLL` is, and `__attribute__((visibility
("default")))` when neither applies on a non-Windows target
(`base.h:21-35`). One value cannot select both `dllexport` and `dllimport`, which
upstream states itself at `config.h:26-30`: the macro suits embedding more than
shipping Box3D as its own DLL. That is why the shared variant is packaged for
Unix systems and why `flake.nix` exposes no Windows package.

## Runtime loading

`-Druntime=true` selects it, and it is orthogonal to `-Dlinkage`: the native
library is still built and installed, only the dispatch changes. Linked builds
call the translated C directly and are unaffected.

```zig
const box3d = @import("box3d");

pub fn main() !void {
    // Exactly one of these. There is no path-to-system fallback.
    try box3d.load(.{ .path = "/usr/lib/libbox3d.so.0" });
    // try box3d.load(.{ .system = "libbox3d.so.0" });

    // Optional: the request that actually published the table.
    if (box3d.loadedSource()) |source| { _ = source; }
}
```

The surface is three declarations in `zig/root.zig`: `load(source: LoadSource)
LoadError!void`, `loadedSource() ?LoadSource` and `runtime_loaded: bool`.
`LoadSource` is `.path` or `.system`, and `LoadError` is the loader core's
eight: `EmptySource`, `SourceTooLong`, `UnsupportedTarget`, `OpenFailed`,
`MissingSymbol`, `ValidationFailed`, `ProviderMismatch` and `ReentrantLoad`. The
types themselves come from `runtime/loader.zig` in a linked build and from the
generated dispatch in a runtime-loaded one.

The contract this build implements:

* one immutable, process-lifetime table per configured module — there is no
  owning object, no returned API view, no unload and no reset;
* the source is **either** an explicit absolute file path **or** an explicit
  system basename; one is never tried after the other fails;
* `load` before a successful load is a programming error and panics, in every
  optimize mode including `ReleaseFast` and `ReleaseSmall`;
* the same request is idempotent; a different request after the table is ready
  is rejected. There is no automatic retry — a caller that wants another
  attempt asks for it;
* a failed attempt closes its handle and publishes nothing, and waiters on that
  attempt receive its failure rather than a later attempt's success;
* the loader trusts the native code once the symbols resolve. It validates the
  provider against this SDK's ABI description — precision, exported surface,
  scalar and layout assumptions — and the boundaries listed above are what it
  can check.

### What a provider has to be

The required table is generated from the headers this build selected, so the
provider has to be one of the same configuration. Three requirements, all of
them checkable:

* **The same `-Doptimize`.** That option is what keeps `NDEBUG` and the declared
  surface in step. Box3D declares `b3InternalAssert` only when `NDEBUG` is
  absent (`include/box3d/base.h:123-131`) and defines it under the same guard
  (`src/core.c:81-91`), so the name is in the table in `Debug` and `ReleaseSafe`
  and out of it in `ReleaseFast` and `ReleaseSmall`. A provider built in
  `ReleaseSmall` and loaded by a `Debug` build is refused with
  `error.MissingSymbol` and the name `b3InternalAssert`
  (`runtime/loader.zig:480-494`). That is the correct answer for two different
  builds, and the name is printed so the cause does not have to be guessed.
  There is nothing else behind it: this package's survey of the eight public
  headers found this one declaration to be the only entry point a build can
  drop (`runtime/graph.zig:287-300`).
* **The same `-Ddouble-precision`.** The option renames `b3CreateWorld` to
  `b3CreateWorldDoublePrecision` and widens `b3Pos` to three `double`s. A
  provider built with the other setting has the name and not the width, so
  `validate` refuses it with `error.ValidationFailed` rather than
  `error.MissingSymbol` (`runtime/library.zig:247-264`).
* **A provider that contains `build_support/box3d_abi_bridge.c`.** Any build of
  this fork has it, and a build from another toolchain still exports the ten
  `box3dAbi_*` names, because they are ordinary `B3_API` definitions compiled
  beside the core (`runtime/library.zig:79-95`). A provider built without that
  unit is refused on the first of the ten.

`-Dvalidate` and `-Ddisable-simd` are not requirements: both are `PRIVATE` and
neither moves a declaration, so one provider serves every setting of them.

In short: build the provider from this tree with the options the facade was
built with, and name that file.

```sh
zig build install -Dlinkage=dynamic -Doptimize=Debug --prefix PROVIDER_DIR
```

What the loader cannot check, and does not claim to: that the provider's solver
behaves. A provider that exports the right names with the wrong semantics
passes loading. That is the same reason `b3GetVersion` is not a compatibility
proof.

`runtime/graph.zig` implements exactly two entry points —
`createModule(b, translate, target, optimize) *std.Build.Module` and
`createCoreModule(b, target, optimize) *std.Build.Module` — and owns the
generated dispatch and the descriptor. `runtime/library.zig` exposes the `Sync`
binding, whose symbols are `box3d_rt_lock`, `box3d_rt_unlock`, `box3d_rt_wait`,
`box3d_rt_broadcast` and `box3d_rt_thread_self`, and `Config(dispatch)`, which
supplies `library_name = "box3d"`, `table`, `symbols`, `sync`, `tablePtr`,
`ready`, `assign` and `validate`. The table, the per-symbol wrappers and the
`symbols` array are generated from the translation output, so the recorded route
is whatever the pinned headers declared for that target and configuration —
including the `b3CreateWorldDoublePrecision` rename when `-Ddouble-precision` is
on. The driver owns the reusable core in `runtime/loader.zig`,
`runtime/generate.zig`, `runtime/sync.c` and `runtime/sync.h`; this repository
does not modify it.

## Tests and examples

| File | What it is |
|---|---|
| `tests.zig` | the fork's behavioural tests: known answers and ownership and error transitions, not presence checks |
| `smoke.zig` | the deterministic example `zig build smoke` runs, over upstream's `HelloWorld` scene (`test/test_world.c:21-101`): a ground box of half-extents `(50, 10, 50)` centred at `y = -10`, so its top face is at `y = 0`, and a unit cube of half-extent 1 dropped from `y = 4` at density 1. Eleven answers are checked against that geometry — the cube's mass (`8`), the two ray fractions and hit heights, the ground normal, the resting height within `0.01` of `1.0`, the resting tilt about x and z, and the shape count in a box inside neither body. The awake-body count, the per-body sleep state and the allocated byte count are printed, not asserted: when the island falls asleep is the solver's business. A runtime build names its provider with `--provider` or `BOX3D_TEST_PROVIDER` |
| `consumer/src/main.zig` | a separate package that consumes `dep.module("box3d")` through a relative path, proving the published module resolves from a package that did not write it. `zig build consumer` drives that package from this SDK's root: `runConsumer` in `build.zig` builds its one `Step.Run` and is called by nothing else, and that run hands the nested graph this build's target query and CPU, its mode and executor switches, its own local cache with a `/consumer` subdirectory, the external global cache, `-j8`, `--summary all`, and `--prefix` when this build was given one — then the caller's own arguments behind `--`, which the nested graph passes on to this program. Run `20261004T214803Z` built and ran this package for the first time in this SDK, through `sdk:consumer`, whose body is the manual form; the step's own relay is still unrun |
| upstream's `test/` and `shared/` | Box3D's own unit tests, compiled unmodified by `zig build upstream-test` |
| `zig/root.zig`, `zig/math.zig`, `zig/base.zig`, `zig/world.zig`, `zig/body.zig`, `zig/shape.zig`, `zig/joint.zig`, `zig/query.zig` | the typed surface: root declarations, then one component per namespace |

## What is not verified here

Eleven gate runs have receipts. Six are `Debug` on `x86_64-linux-gnu`; the rest
are one devenv acceptance run, `20261004T214803Z`, which passed all eight of its
gates, one nested-delivery run, `20261004T223101687849Z-e3904589dead`, whose nine
`consumer` cases all passed, and one native matrix run, `contract-final-after-20261004`,
whose eight cells all passed in `Debug`, ReleaseSafe, ReleaseFast and
ReleaseSmall for both linkages.
run ids are the ones in the rows above; `FORK-NOTES.md` §24 and its open-items
table carry the full receipt paths.

| Gate | Result | Receipt |
|---|---|---|
| `zig build smoke test` | `18/18 tests`, `9/9 steps` | `local://foundation-contract-box3d-real-overflow-total-count-full-smoke-test-recovered-output.log` |
| `zig build install -Dlinkage=dynamic` | `13/13 steps`, soname `libbox3d.so.0` for version `0.1.0` | `local://foundation-contract-box3d-primary-shared-complete-native-closure-repaired.log` |
| `zig build smoke -Druntime=true -- --provider PATH` | `6/6 steps`, nothing linked into the module, every checked answer matched | `local://foundation-contract-box3d-current-canonical-runtime-static-real-provider-smoke.log` |
| `zig build install -Ddouble-precision=true -Dlinkage=dynamic -Doptimize=Debug` | `exit 0`, `13/13 steps` | `/home/tmp2/gertullj/scratch/foundation-libs/contract-physics-lua/baselines-and-configs/box3d-double-type-values-after/index.json`, row `secondary-box3d-double-provider` |
| `zig build test smoke -Ddouble-precision=true -Dlinkage=dynamic -Doptimize=Debug -Druntime=true` | `exit 0`, `9/9 steps`, `19/19 tests passed`, provider loaded | the same index, row `secondary-box3d-double-loaded-dynamic-test-smoke` |
| `zig build test smoke -Ddouble-precision=true -Dlinkage=static -Doptimize=Debug -Druntime=true` | `exit 0`, `9/9 steps`, `19/19 tests passed`, provider loaded | the same index, row `secondary-box3d-double-loaded-static-test-smoke` |
| `devenv info`, `devenv tasks list`, `devenv shell -- zig version`, `devenv shell -- zig env` | `exit 0` each; `BOX3D_SDK_VERSION: 0.1.0`; banner `sdk root:` and `cache:` lines naming this SDK and its caches; `zig version` `0.16.0` from the store compiler | that index |
| `devenv tasks run --mode single … sdk:consumer`, body `cd consumer && zig build run --summary all` | `exit 0`, `Build Summary: 6/6 steps succeeded`, `run exe box3d-consumer success 64ms`; the first build and run of `consumer/` in this SDK, through the manual form and not the `consumer` step | that index |
| `devenv tasks run --mode single … sdk:provenance` | `exit 0` in 215 ms; `tools/check-provenance.sh` passed | that index |
| `zig build consumer`, four routes and nine cases | nine of nine as expected: eight `exit 0` with `Build Summary: 6/6 steps succeeded`, one no-provider refusal `exit 1`; the nested `--prefix` equals the outer one; `--provider PATH` crossed both hops with no provider environment present | run `20261004T223101687849Z-e3904589dead` |
| `zig build test smoke install`, both linkages, four optimize modes | eight of eight `exit 0`, each `Build Summary: 18/18 steps succeeded; 19/19 tests passed`; 15 installed files static, 17 shared | run `contract-final-after-20261004` |
| `zig build check`, six declared compile targets | `exit 0`, `Build Summary: 37/37 steps succeeded`, no failing step; compile and link only | baseline run `20261005T014547Z-797a73f2`, label `baseline-box3d-check` |
| `cross-test`, published 53-target table | `exit 1`: **9 pass, 33 build-only, 0 build failures, 11 run failures**; 20 cells executed, 19 tests each. All 11 failures are on the Zig-to-C boundary: `error.WorldLimitExceeded` at `zig/world.zig:197`, a misaligned or null `const b3BodyDef`/`const b3HullData` at `B3_CHECK_DEF`, and `Segmentation fault` on `powerpc-linux` and `s390x-linux`. None of them is the scene-shape defect this SDK already fixed | run `20261004T221720228710Z-45046`, receipt `box3d-53-target-8.json`, source stamp `88106c0349…` |

Everything else is `PENDING-VERIFICATION`, and nothing above it is claimed:

* any foreign target through the `consumer` step: its nine cases are native, and
  the four explicit-target cases name `x86_64-linux-gnu` alone;
* `zig build upstream-test` — Box3D's own test application has never been
  compiled or run here;
* `zig build check` for either linkage beyond the one run above, so no compile
  claim is made for `wasm32-wasi` under a shared delivery, and no cross-built
  binary of that linkage has run;
* an installed C consumer and a fetched consumer; `consumer/` and the `consumer`
  step's argument relay both have receipts now, nine `consumer` cases in the
  nested run above;
* `-Ddouble-precision=true` in ReleaseSafe, ReleaseFast or ReleaseSmall, and on
  any cross target: the three double-precision rows above are `Debug` on one
  native target, and none of them runs the `consumer` step;
* both Nix derivations: `devenv shell` and `tools/check-provenance.sh` do have
  receipts in that run, and `nix:build` is the one gate its `gates_not_run` names;
* the other ten `sdk:*` task bodies, none of which has run;
* any call to `castShapeCollect` — there is none in `tests.zig` or `smoke.zig`,
  so that collector's total-count behaviour rests on reading `zig/query.zig`;
* the loader's failure, retry and idempotence paths: the one recorded run
  loaded a provider that was named and worked, and tried nothing else.

Each of the two source-bound rows above holds one source stamp for its whole
run. Every build-graph, header, helper and normalisation edit made after a run
describes a tree that run never saw, so neither row covers them. A build-only
cell compiled and had no runner; it is coverage and not a passing test.

`README.md` has the per-command table and `CHANGELOG.md` the dated entries.