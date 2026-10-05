// SPDX-License-Identifier: MIT
//
//! Vector, quaternion, transform, position, matrix and bounding-box maths.
//!
//! Nothing here computes anything Box3D already computes. Every function in
//! this file is either an `inline fn` that `include/box3d/math_functions.h`
//! declares in its own body - `B3_INLINE` at line 54 is `static inline` in C,
//! so the translation step turns each of them into a Zig `inline fn` in `c` -
//! or one of the `B3_API` functions that header exports. The names are
//! shortened and grouped; the arithmetic is upstream's, and it is upstream's
//! arithmetic because upstream wrote it to be deterministic across platforms:
//! `b3Atan2` and `b3ComputeCosSin` exist precisely because the standard
//! library's are not cross-platform deterministic
//! (`include/box3d/math_functions.h:191-199`).
//!
//! ## Precision
//!
//! `Pos` and `WorldTransform` are the two types whose meaning depends on how
//! the library was built. In single precision they are the same types as
//! `Vec3` and `Transform` (`include/box3d/math_functions.h:87-95`); under
//! `BOX3D_DOUBLE_PRECISION` they are distinct structs whose translation is
//! `double`. Code written against `Pos` is correct in both modes, and that is
//! why these functions take `Pos` rather than `Vec3` wherever the header does.
//!
//! ## No allocation
//!
//! Every value here is a plain struct or a scalar. There is no heap traffic, no
//! hidden state, and nothing to release.

const c = @import("c");

// -- types -------------------------------------------------------------------

/// A 2D vector, `b3Vec2` (`math_functions.h:33-37`).
pub const Vec2 = c.b3Vec2;

/// A 3D vector, `b3Vec3` (`math_functions.h:39-45`). This is also `Pos` in
/// single precision.
pub const Vec3 = c.b3Vec3;

/// A quaternion, `b3Quat` (`math_functions.h:56-61`): the vector part is the
/// imaginary part and `s` is the scalar part.
pub const Quat = c.b3Quat;

/// A rigid transform in one reference frame, `b3Transform`
/// (`math_functions.h:63-68`): a translation and a rotation.
pub const Transform = c.b3Transform;

/// A world position, `b3Pos` (`math_functions.h:70-95`). `Vec3` in single
/// precision, a separate `double` struct under `BOX3D_DOUBLE_PRECISION`.
pub const Pos = c.b3Pos;

/// A transform whose translation is a world position, `b3WorldTransform`
/// (`math_functions.h:78-95`). `Transform` in single precision.
pub const WorldTransform = c.b3WorldTransform;

/// A 3x3 matrix stored as three column vectors, `b3Matrix3`
/// (`math_functions.h:97-101`).
pub const Mat3 = c.b3Matrix3;

/// An axis-aligned bounding box, `b3AABB` (`math_functions.h:103-108`).
pub const Aabb = c.b3AABB;

/// A plane in `dot(normal, point) = offset` form, `b3Plane`
/// (`math_functions.h:110-116`).
pub const Plane = c.b3Plane;

// -- constants ---------------------------------------------------------------

/// Pi as `math_functions.h:21` writes it.
pub const pi: f32 = c.B3_PI;

/// Degrees to radians, `math_functions.h:24`.
pub const deg_to_rad: f32 = c.B3_DEG_TO_RAD;

/// Radians to degrees, `math_functions.h:27`.
pub const rad_to_deg: f32 = c.B3_RAD_TO_DEG;

/// The minimum scale Box3D applies to a collision mesh, `math_functions.h:30`.
pub const min_scale: f32 = c.B3_MIN_SCALE;

/// The zero vector, `math_functions.h:118`.
pub const zero: Vec3 = c.b3Vec3_zero;
/// The one vector, `math_functions.h:119`.
pub const one: Vec3 = c.b3Vec3_one;
/// The unit x vector, `math_functions.h:120`.
pub const axis_x: Vec3 = c.b3Vec3_axisX;
/// The unit y vector, `math_functions.h:121`.
pub const axis_y: Vec3 = c.b3Vec3_axisY;
/// The unit z vector, `math_functions.h:122`.
pub const axis_z: Vec3 = c.b3Vec3_axisZ;
/// The identity rotation, `math_functions.h:123`.
pub const identity_quat: Quat = c.b3Quat_identity;
/// The identity transform, `math_functions.h:124`.
pub const identity_transform: Transform = c.b3Transform_identity;
/// The zero matrix, `math_functions.h:125-130`.
pub const zero_mat3: Mat3 = c.b3Mat3_zero;
/// The identity matrix, `math_functions.h:131-134`.
pub const identity_mat3: Mat3 = c.b3Mat3_identity;
/// The zero world position, `math_functions.h:137`.
pub const zero_pos: Pos = c.b3Pos_zero;
/// The identity world transform, `math_functions.h:138`.
pub const identity_world_transform: WorldTransform = c.b3WorldTransform_identity;

// -- scalars -----------------------------------------------------------------

pub const minInt = c.b3MinInt;
pub const maxInt = c.b3MaxInt;
pub const clampInt = c.b3ClampInt;
pub const absFloat = c.b3AbsFloat;
pub const minFloat = c.b3MinFloat;
pub const maxFloat = c.b3MaxFloat;
pub const clampFloat = c.b3ClampFloat;
pub const lerpFloat = c.b3LerpFloat;

/// Deprecated upstream (`math_functions.h:201-206`): it exists so old code
/// compiles, and `b3ComputeCosSin` is the deterministic replacement.
pub const sin = c.b3Sin;
/// Deprecated upstream (`math_functions.h:208-211`), as `sin` is.
pub const cos = c.b3Cos;
/// Wrap an angle into `[-pi, pi]` (`math_functions.h:213-218`).
pub const unwindAngle = c.b3UnwindAngle;

/// True when the float is finite and not NaN (`math_functions.h:159,1077`).
pub const isValidFloat = c.b3IsValidFloat;
/// True when no component is NaN or infinite (`math_functions.h:1080`).
pub const isValidVec3 = c.b3IsValidVec3;
/// True when the quaternion is finite and normalized (`math_functions.h:1083`).
pub const isValidQuat = c.b3IsValidQuat;
/// True when the transform is finite and its rotation is normalized
/// (`math_functions.h:1086`).
pub const isValidTransform = c.b3IsValidTransform;
/// True when no matrix entry is NaN or infinite (`math_functions.h:1089`).
pub const isValidMat3 = c.b3IsValidMatrix3;
/// True when the box is finite and its upper bound is not below its lower bound
/// (`math_functions.h:1092`).
pub const isValidAabb = c.b3IsValidAABB;
/// True when the box is valid and near the origin, against `B3_HUGE`
/// (`math_functions.h:1095`).
pub const isBoundedAabb = c.b3IsBoundedAABB;
/// True when the box is valid and reasonable (`math_functions.h:1098`).
pub const isSaneAabb = c.b3IsSaneAABB;
/// True when the plane's normal is a unit vector and the offset is finite
/// (`math_functions.h:1101`).
pub const isValidPlane = c.b3IsValidPlane;
/// True when a world position is finite (`math_functions.h:1104`).
pub const isValidPos = c.b3IsValidPosition;
/// True when a world transform is finite and its rotation is normalized
/// (`math_functions.h:1107`).
pub const isValidWorldTransform = c.b3IsValidWorldTransform;

/// Arctangent in `[-pi, pi]`, accurate to about 0.0023 degrees, hand coded for
/// determinism (`math_functions.h:195`).
pub const atan2 = c.b3Atan2;
/// Cosine and sine of an angle, as one pair (`math_functions.h:199`).
pub const cosSin = c.b3ComputeCosSin;

/// Inertia tensor of a solid of mass `mass` about an axis-aligned box centred
/// on `origin` (`math_functions.h:953`).
pub const steiner = c.b3Steiner;

/// Closest point on segment `a`-`b` to `q` (`math_functions.h:1068`).
pub const pointToSegmentDistance = c.b3PointToSegmentDistance;
/// Closest points on two infinite lines (`math_functions.h:1071`).
pub const lineDistance = c.b3LineDistance;
/// Closest points on two line segments (`math_functions.h:1074`).
pub const segmentDistance = c.b3SegmentDistance;

/// The distance result `lineDistance` and `segmentDistance` return
/// (`math_functions.h:1059-1065`).
pub const SegmentDistanceResult = c.b3SegmentDistanceResult;

// -- vectors -----------------------------------------------------------------

pub const add = c.b3Add;
pub const sub = c.b3Sub;
/// Component-wise multiply, which is not a dot product and not a cross
/// product (`math_functions.h:235`).
pub const mulComponentwise = c.b3Mul;
pub const neg = c.b3Neg;
pub const dot = c.b3Dot;
pub const length = c.b3Length;
pub const lengthSquared = c.b3LengthSquared;
pub const distance = c.b3Distance;
pub const distanceSquared = c.b3DistanceSquared;
pub const normalize = c.b3Normalize;
/// Normalize and also report the original length through `length`.
pub const getLengthAndNormalize = c.b3GetLengthAndNormalize;
pub const perp = c.b3Perp;
pub const isNormalized = c.b3IsNormalized;
pub const mulAdd = c.b3MulAdd;
pub const mulSub = c.b3MulSub;
/// Scalar times vector. Upstream has no vector-times-scalar; the two are the
/// same operation and this is the spelling the header uses.
pub const scale = c.b3MulSV;
pub const cross = c.b3Cross;
pub const lerp = c.b3Lerp;
pub const blend2 = c.b3Blend2;
pub const absComponents = c.b3Abs;
pub const sign = c.b3Sign;
pub const minComponents = c.b3Min;
pub const maxComponents = c.b3Max;
pub const clampComponents = c.b3Clamp;
/// Scale a vector so its integer components stay exact
/// (`math_functions.h:438`).
pub const safeScale = c.b3SafeScale;

// -- quaternions -------------------------------------------------------------

pub const isNormalizedQuat = c.b3IsNormalizedQuat;
pub const rotateVector = c.b3RotateVector;
pub const invRotateVector = c.b3InvRotateVector;
pub const dotQuat = c.b3DotQuat;
pub const mulQuat = c.b3MulQuat;
pub const invMulQuat = c.b3InvMulQuat;
pub const conjugate = c.b3Conjugate;
pub const negateQuat = c.b3NegateQuat;
pub const normalizeQuat = c.b3NormalizeQuat;
/// A rotation of `radians` about `axis` (`math_functions.h:529`). The axis is
/// normalized by the function, and a zero axis yields the identity.
pub const quatFromAxisAngle = c.b3MakeQuatFromAxisAngle;
/// The axis-angle form of a quaternion, with the angle through `radians`.
pub const axisAngle = c.b3GetAxisAngle;
/// The rotation angle of a quaternion in `[-pi, pi]`
/// (`math_functions.h:553`).
pub const quatAngle = c.b3GetQuatAngle;
pub const twistAngle = c.b3GetTwistAngle;
pub const swingAngle = c.b3GetSwingAngle;
pub const lerpQuat = c.b3NLerp;
/// A quaternion from a rotation matrix (`math_functions.h:560`).
pub const quatFromMat3 = c.b3MakeQuatFromMatrix;
/// The rotation carrying unit vector `v1` onto unit vector `v2`
/// (`math_functions.h:563`).
pub const quatBetweenUnitVectors = c.b3ComputeQuatBetweenUnitVectors;

// -- transforms and positions ------------------------------------------------

pub const mulTransforms = c.b3MulTransforms;
pub const invertTransform = c.b3InvertTransform;
pub const transformPoint = c.b3TransformPoint;
pub const invTransformPoint = c.b3InvTransformPoint;

/// Widen a local vector into a world position (`math_functions.h:652`). In
/// single precision this is the identity; under `BOX3D_DOUBLE_PRECISION` it is
/// the conversion that makes the type change worth having.
pub const toPos = c.b3ToPos;
/// Narrow a world position into a local vector (`math_functions.h:658`).
pub const toVec3 = c.b3ToVec3;
pub const subPos = c.b3SubPos;
pub const offsetPos = c.b3OffsetPos;
pub const lerpPos = c.b3LerpPosition;
pub const transformWorldPoint = c.b3TransformWorldPoint;
pub const invTransformWorldPoint = c.b3InvTransformWorldPoint;
pub const invMulWorldTransforms = c.b3InvMulWorldTransforms;
pub const mulWorldTransforms = c.b3MulWorldTransforms;
/// A world transform relative to a nearby base position
/// (`math_functions.h:745`).
pub const toRelativeTransform = c.b3ToRelativeTransform;
/// Fold a frame-local transform into a world transform
/// (`math_functions.h:754`).
pub const toWorldTransform = c.b3MakeWorldTransform;

// -- matrices ----------------------------------------------------------------

pub const det = c.b3Det;
/// Matrix times vector, using the column-vector convention the header's `cx`,
/// `cy`, `cz` fields imply (`math_functions.h:784`).
pub const mulMat3Vec3 = c.b3MulMV;
pub const negateMat3 = c.b3NegateMat3;
pub const addMat3 = c.b3AddMM;
pub const subMat3 = c.b3SubMM;
pub const scaleMat3 = c.b3MulSM;
pub const mulMat3 = c.b3MulMM;
pub const transpose = c.b3Transpose;
pub const invertMat3 = c.b3InvertMatrix;
pub const solveMat3 = c.b3Solve3;
/// Inverse transpose, the matrix that turns a world inertia tensor into a
/// local one (`math_functions.h:902`).
pub const invTransposeMat3 = c.b3InvertT;
pub const absMat3 = c.b3AbsMatrix3;

// -- bounding boxes ----------------------------------------------------------

/// An AABB grown so that `origin`, a local origin, encloses it
/// (`math_functions.h:765`).
pub const offsetAabb = c.b3OffsetAABB;
/// The AABB of `count` points inflated by `radius` (`math_functions.h:956`).
pub const makeAabb = c.b3MakeAABB;
pub const aabbContains = c.b3AABB_Contains;
pub const aabbArea = c.b3AABB_Area;
pub const aabbCenter = c.b3AABB_Center;
pub const aabbExtents = c.b3AABB_Extents;
pub const aabbUnion = c.b3AABB_Union;
pub const aabbInflate = c.b3AABB_Inflate;
pub const aabbOverlaps = c.b3AABB_Overlaps;
pub const aabbTransform = c.b3AABB_Transform;
pub const closestPointToAabb = c.b3ClosestPointToAABB;

// -- length-dependent constants ----------------------------------------------
//
// `include/box3d/constants.h` spells these as object-like macros whose bodies
// call `b3GetLengthUnitsPerMeter()`. A macro body is not a constant
// expression, so the translation step cannot turn one into a Zig constant, and
// these are functions rather than transcriptions of the numbers: each one is
// the macro's own expansion, evaluated against the length scale the process is
// currently using. `b3SetLengthUnitsPerMeter` says to set that once at startup,
// before any other Box3D call, so in practice these are constant for the life
// of a program - but they are read, not baked, because that is what upstream
// does.

/// `B3_LINEAR_SLOP`, `constants.h:53`: the collision and constraint tolerance.
pub fn linearSlop() f32 {
    return 0.005 * c.b3GetLengthUnitsPerMeter();
}

/// `B3_OVERLAP_SLOP`, `constants.h:60`: the distance at which two shapes count
/// as overlapping.
pub fn overlapSlop() f32 {
    return 0.1 * linearSlop();
}

/// `B3_MAX_AABB_MARGIN`, `constants.h:91`: how far a proxy AABB is fattened.
pub fn maxAabbMargin() f32 {
    return 0.05 * c.b3GetLengthUnitsPerMeter();
}

/// `B3_SPECULATIVE_DISTANCE`, `constants.h:73`.
pub fn speculativeDistance() f32 {
    return 4.0 * linearSlop();
}

/// `B3_MESH_REST_OFFSET`, `constants.h:79`.
pub fn meshRestOffset() f32 {
    return 1.0 * linearSlop();
}

/// `B3_CONTACT_RECYCLE_DISTANCE`, `constants.h:82`.
pub fn contactRecycleDistance() f32 {
    return 10.0 * linearSlop();
}

/// `B3_MAX_ROTATION`, `constants.h:70`: the largest rotation a body may
/// undergo in one step. Raising it to `0.5 * pi` or more breaks continuous
/// collision, which is upstream's own warning on that line.
pub const maxRotation: f32 = 0.25 * pi;