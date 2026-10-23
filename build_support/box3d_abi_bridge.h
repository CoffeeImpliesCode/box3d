/* SPDX-License-Identifier: MIT
 *
 * The pointer-taking entry points for the ten public signatures that Zig 0.16's
 * x86_64 backend lowers differently from the compiler that built the core
 * (observed with Zig 0.16; not rechecked on 0.17).
 *
 * Why it exists
 * -------------
 * Ten functions in `include/box3d/box3d.h` take a `b3Pos` by value ahead of a
 * floating-point argument or a floating-point return. Under
 * `BOX3D_DOUBLE_PRECISION` a `b3Pos` is `struct { double x, y, z; }`
 * (`include/box3d/math_functions.h:74-77`), so it is 24 bytes and the x86-64
 * System V ABI passes it in memory; without the define it is a typedef of
 * `b3Vec3` and is passed in two vector registers like any other 12-byte
 * float struct.
 *
 * Zig's argument lowering for this target nevertheless consumes one
 * vector-register pair for that memory-passed 24-byte aggregate, so every
 * floating-point argument after it is allocated one pair too high. Measured on
 * the pinned toolchain against this package's own artifacts:
 *
 *     native  b3World_CastRayClosest  vmovlpd %xmm0 ; vmovss %xmm1
 *     Zig     query.castRayClosest     vmovq   %xmm2 ; vmovss %xmm3
 *
 * The System V classification of the other three arguments is identical on
 * both sides -- the hidden return pointer in `RDI`, `worldId` in `ESI`,
 * `origin` and `filter` on the stack -- so only the vector register index
 * differs, and the symptom is a valid `origin` reaching the callee beside an
 * unreadable `translation`. That is what trips `B3_ASSERT( b3IsValidVec3(
 * translation ) )` at `src/physics_world.c:2995`.
 *
 * It is a size-and-type boundary, not a precision one. Two neighbouring
 * shapes were measured on the same binary and neither reserves: `b3Transform`
 * at 28 bytes (`b3ComputeMeshAABB`, `b3CloneAndTransformHull`) and `b3Mat3` at
 * 36 bytes (`b3MulMV`), both of which agree with the native callee on
 * `XMM0`/`XMM1`. So the affected set is exactly the functions whose first
 * memory-passed float aggregate is at most 24 bytes.
 *
 * What it does, and what it deliberately does not do
 * -------------------------------------------------
 * Each function below forwards to upstream's own by-value entry point with the
 * argument dereferenced, and does nothing else: no algorithm, no validation,
 * no default. The call it makes is compiled by the same clang that compiled
 * `src/physics_world.c`, with the same `-std=gnu17`, `-ffp-contract=off` and
 * the same `BOX3D_DOUBLE_PRECISION`, `BOX3D_DISABLE_SIMD` and `BOX3D_VALIDATE`
 * settings, because `build.zig` adds this file to the core module itself
 * rather than to a module of its own. A wrapper that reimplemented anything
 * would be a second copy free to drift from upstream, which is the failure
 * this file exists to remove.
 *
 * The parameter is a pointer because that is what removes the aggregate from
 * the call: no `b3Pos`, `b3Vec3`, `b3Quat` or `b3WorldTransform` is ever
 * passed by value across the Zig boundary, so no argument can be misallocated
 * into the wrong register pair. The types stay the ones the translation
 * produced, so a caller writes the same `.x`, `.y`, `.z` it would have
 * written for the by-value form.
 *
 * The names are this package's own. Unlike `build_support/` in the Box2D
 * package, which fills a symbol the header declares but the archive never
 * emits, nothing here can reuse upstream's name: the symbol
 * `b3World_CastRayClosest` is present and correct, and what is wrong is the
 * call the Zig backend emits for it. Overloading one name with two different
 * prototypes would hide exactly that, so the bridge is named separately and
 * `c.b3World_CastRayClosest` remains visible in the translated surface for
 * anyone reading the header.
 *
 * The list is complete at this pin
 * --------------------------------
 * Every one of the eight public headers' `B3_API` signatures was classified
 * against the rule above. A signature is affected when it takes a `b3Pos` by
 * value and something vector-classified follows it, as an argument or as the
 * return. That is these ten. The `b3Pos` signatures that are *not* here have
 * nothing vector-classified after them -- `b3World_OverlapShape`,
 * `b3World_CollideMover`, `b3Body_OverlapShape`, `b3Body_CollideMover`,
 * `b3IsValidPosition` return an integer or a pointer and take no float after
 * it -- and `b3Body_ApplyForce` and `b3Body_ApplyLinearImpulse` put their
 * `b3Vec3` first, before the `b3Pos`, so nothing shifts.
 *
 * `zig/translate.h` includes this header, so these declarations are part of
 * the one `c` module the facade and every dependent import, and the generated
 * runtime dispatch resolves them from the same provider as everything else.
 */

#ifndef BOX3D_ABI_BRIDGE_H
#define BOX3D_ABI_BRIDGE_H

#include <box3d/box3d.h>

/// Cast a ray into the world (`include/box3d/box3d.h:93-94`). Forwards to
/// `b3World_CastRay`.
B3_API b3TreeStats box3dAbi_CastRay( b3WorldId worldId, const b3Pos* origin, const b3Vec3* translation, const b3QueryFilter* filter,
									 b3CastResultFcn* fcn, void* context );

/// Cast a ray into the world and keep the closest hit
/// (`include/box3d/box3d.h:98`). Forwards to `b3World_CastRayClosest`.
B3_API b3RayResult box3dAbi_CastRayClosest( b3WorldId worldId, const b3Pos* origin, const b3Vec3* translation, const b3QueryFilter* filter );

/// Cast a shape through the world (`include/box3d/box3d.h:104-105`).
/// Forwards to `b3World_CastShape`.
B3_API b3TreeStats box3dAbi_CastShape( b3WorldId worldId, const b3Pos* origin, const b3ShapeProxy* proxy, const b3Vec3* translation,
									   const b3QueryFilter* filter, b3CastResultFcn* fcn, void* context );

/// Cast a capsule mover through the world (`include/box3d/box3d.h:118-119`).
/// Forwards to `b3World_CastMover`.
B3_API float box3dAbi_CastMover( b3WorldId worldId, const b3Pos* origin, const b3Capsule* mover, const b3Vec3* translation,
								 const b3QueryFilter* filter, b3MoverFilterFcn* fcn, void* context );

/// Cast a ray at one body at an explicit transform (`include/box3d/box3d.h:757`).
/// Forwards to `b3Body_CastRay`.
B3_API b3BodyCastResult box3dAbi_BodyCastRay( b3BodyId bodyId, const b3Pos* origin, const b3Vec3* translation, const b3QueryFilter* filter,
											  float maxFraction, const b3WorldTransform* bodyTransform );

/// Cast a shape at one body at an explicit transform
/// (`include/box3d/box3d.h:761-763`). Forwards to `b3Body_CastShape`.
B3_API b3BodyCastResult box3dAbi_BodyCastShape( b3BodyId bodyId, const b3Pos* origin, const b3ShapeProxy* proxy, const b3Vec3* translation,
												 const b3QueryFilter* filter, float maxFraction, bool canEncroach,
												 const b3WorldTransform* bodyTransform );

/// Place a body (`include/box3d/box3d.h:527`). Forwards to
/// `b3Body_SetTransform`. The `b3Quat` rotation follows the `b3Pos`, so it is
/// the pair that shifts; nothing in this build has called that signature yet,
/// which is why the wrapper is here rather than a fix that is only half made.
B3_API void box3dAbi_BodySetTransform( b3BodyId bodyId, const b3Pos* position, const b3Quat* rotation );

/// Express a world point in a body's local frame (`include/box3d/box3d.h:530`).
/// Forwards to `b3Body_GetLocalPoint`. The return is a `b3Vec3`, which comes
/// back in `XMM0`/`XMM1`, so a reserved pair would move the result too.
B3_API b3Vec3 box3dAbi_BodyGetLocalPoint( b3BodyId bodyId, const b3Pos* worldPoint );

/// Velocity of a world point (`include/box3d/box3d.h:563`). Forwards to
/// `b3Body_GetWorldPointVelocity`.
B3_API b3Vec3 box3dAbi_BodyGetWorldPointVelocity( b3BodyId bodyId, const b3Pos* worldPoint );

/// Ray cast one shape (`include/box3d/box3d.h:924`). Forwards to
/// `b3Shape_RayCast`.
B3_API b3WorldCastOutput box3dAbi_ShapeRayCast( b3ShapeId shapeId, const b3Pos* origin, const b3Vec3* translation );

#endif /* BOX3D_ABI_BRIDGE_H */
