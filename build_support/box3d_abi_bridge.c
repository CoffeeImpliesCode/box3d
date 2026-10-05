/* SPDX-License-Identifier: MIT
 *
 * The definitions behind `build_support/box3d_abi_bridge.h`. Read that header
 * first: it says what the ten functions are for, what was measured, and why
 * the list is complete.
 *
 * Every body below is one call and one dereference. The call is upstream's own
 * by-value entry point, so the work done is upstream's work at upstream's
 * line, and the only thing this package contributes is the boundary shape that
 * the Zig backend can lower correctly.
 *
 * `build.zig` adds this file to `c_mod`, the module that compiles all
 * forty-nine upstream units, with the same flags and the same `BOX3D_*`
 * macros. That is load-bearing rather than tidy: the call each body makes has
 * to be laid out by the same clang invocation as the callee it reaches, in the
 * same precision mode, or this file would trade one mismatch for another.
 */

#include "box3d_abi_bridge.h"

b3TreeStats box3dAbi_CastRay( b3WorldId worldId, const b3Pos* origin, const b3Vec3* translation, const b3QueryFilter* filter,
							  b3CastResultFcn* fcn, void* context )
{
	return b3World_CastRay( worldId, *origin, *translation, *filter, fcn, context );
}

b3RayResult box3dAbi_CastRayClosest( b3WorldId worldId, const b3Pos* origin, const b3Vec3* translation, const b3QueryFilter* filter )
{
	return b3World_CastRayClosest( worldId, *origin, *translation, *filter );
}

b3TreeStats box3dAbi_CastShape( b3WorldId worldId, const b3Pos* origin, const b3ShapeProxy* proxy, const b3Vec3* translation,
								 const b3QueryFilter* filter, b3CastResultFcn* fcn, void* context )
{
	return b3World_CastShape( worldId, *origin, proxy, *translation, *filter, fcn, context );
}

float box3dAbi_CastMover( b3WorldId worldId, const b3Pos* origin, const b3Capsule* mover, const b3Vec3* translation,
						  const b3QueryFilter* filter, b3MoverFilterFcn* fcn, void* context )
{
	return b3World_CastMover( worldId, *origin, mover, *translation, *filter, fcn, context );
}

b3BodyCastResult box3dAbi_BodyCastRay( b3BodyId bodyId, const b3Pos* origin, const b3Vec3* translation, const b3QueryFilter* filter,
									   float maxFraction, const b3WorldTransform* bodyTransform )
{
	return b3Body_CastRay( bodyId, *origin, *translation, *filter, maxFraction, *bodyTransform );
}

b3BodyCastResult box3dAbi_BodyCastShape( b3BodyId bodyId, const b3Pos* origin, const b3ShapeProxy* proxy, const b3Vec3* translation,
										 const b3QueryFilter* filter, float maxFraction, bool canEncroach,
										 const b3WorldTransform* bodyTransform )
{
	return b3Body_CastShape( bodyId, *origin, proxy, *translation, *filter, maxFraction, canEncroach, *bodyTransform );
}

void box3dAbi_BodySetTransform( b3BodyId bodyId, const b3Pos* position, const b3Quat* rotation )
{
	b3Body_SetTransform( bodyId, *position, *rotation );
}

b3Vec3 box3dAbi_BodyGetLocalPoint( b3BodyId bodyId, const b3Pos* worldPoint )
{
	return b3Body_GetLocalPoint( bodyId, *worldPoint );
}

b3Vec3 box3dAbi_BodyGetWorldPointVelocity( b3BodyId bodyId, const b3Pos* worldPoint )
{
	return b3Body_GetWorldPointVelocity( bodyId, *worldPoint );
}

b3WorldCastOutput box3dAbi_ShapeRayCast( b3ShapeId shapeId, const b3Pos* origin, const b3Vec3* translation )
{
	return b3Shape_RayCast( shapeId, *origin, *translation );
}
