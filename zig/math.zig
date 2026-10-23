// SPDX-License-Identifier: MIT
//
//! Box3D vector, quaternion, transform, matrix and bounding-box operations.

const c = @import("c");

pub const Vec2 = c.b3Vec2;

/// A 3D vector; also `Pos` in single precision.
pub const Vec3 = c.b3Vec3;

/// Quaternion with vector part `v` and scalar part `s`.
pub const Quat = c.b3Quat;

/// Rigid transform containing translation and rotation.
pub const Transform = c.b3Transform;

/// World position; a distinct double-translation type in double precision.
pub const Pos = c.b3Pos;

/// Transform whose translation uses the world-position type.
pub const WorldTransform = c.b3WorldTransform;

/// A 3x3 matrix stored as column vectors.
pub const Mat3 = c.b3Matrix3;

/// Plane in `dot(normal, point) = offset` form.
pub const Aabb = c.b3AABB;
pub const Plane = c.b3Plane;

pub const pi: f32 = c.B3_PI;

pub const deg_to_rad: f32 = c.B3_DEG_TO_RAD;

pub const rad_to_deg: f32 = c.B3_RAD_TO_DEG;

pub const min_scale: f32 = c.B3_MIN_SCALE;

pub const zero: Vec3 = c.b3Vec3_zero;
pub const one: Vec3 = c.b3Vec3_one;
pub const axis_x: Vec3 = c.b3Vec3_axisX;
pub const axis_y: Vec3 = c.b3Vec3_axisY;
pub const axis_z: Vec3 = c.b3Vec3_axisZ;
pub const identity_quat: Quat = c.b3Quat_identity;
pub const identity_transform: Transform = c.b3Transform_identity;
pub const zero_mat3: Mat3 = c.b3Mat3_zero;
pub const identity_mat3: Mat3 = c.b3Mat3_identity;
pub const zero_pos: Pos = c.b3Pos_zero;
pub const identity_world_transform: WorldTransform = c.b3WorldTransform_identity;

pub const minInt = c.b3MinInt;
pub const maxInt = c.b3MaxInt;
pub const clampInt = c.b3ClampInt;
pub const absFloat = c.b3AbsFloat;
pub const minFloat = c.b3MinFloat;
pub const maxFloat = c.b3MaxFloat;
pub const clampFloat = c.b3ClampFloat;
pub const lerpFloat = c.b3LerpFloat;

/// Deprecated upstream; use `cosSin` for deterministic trigonometry
/// (`math_functions.h:201-206`).
pub const sin = c.b3Sin;
pub const cos = c.b3Cos;
/// Wrap an angle into `[-pi, pi]` (`math_functions.h:213-218`).
pub const unwindAngle = c.b3UnwindAngle;

/// True when the float is finite and not NaN (`math_functions.h:159,1077`).
pub const isValidFloat = c.b3IsValidFloat;
/// True when every vector component is finite.
pub const isValidVec3 = c.b3IsValidVec3;
/// True when the quaternion is finite and normalized.
pub const isValidQuat = c.b3IsValidQuat;
/// True when the transform is finite and its rotation is normalized.
pub const isValidTransform = c.b3IsValidTransform;
/// True when every matrix entry is finite.
pub const isValidMat3 = c.b3IsValidMatrix3;
/// True when the box is finite and its upper bound is not below its lower bound.
pub const isValidAabb = c.b3IsValidAABB;
/// True when the box is valid and near the origin, against `B3_HUGE`.
pub const isBoundedAabb = c.b3IsBoundedAABB;
/// True when the box is valid and reasonable.
pub const isSaneAabb = c.b3IsSaneAABB;
/// True when the plane normal is unit length and its offset is finite.
pub const isValidPlane = c.b3IsValidPlane;
/// True when a world position is finite.
pub const isValidPos = c.b3IsValidPosition;
/// True when the world transform is finite and its rotation is normalized.
pub const isValidWorldTransform = c.b3IsValidWorldTransform;

/// Deterministic arctangent in `[-pi, pi]`, accurate to about 0.0023 degrees.
pub const atan2 = c.b3Atan2;
/// Cosine and sine of an angle, as one pair (`math_functions.h:199`).
pub const cosSin = c.b3ComputeCosSin;

/// Inertia tensor of a mass about an axis-aligned box centred on `origin`.
pub const steiner = c.b3Steiner;

pub const pointToSegmentDistance = c.b3PointToSegmentDistance;
pub const lineDistance = c.b3LineDistance;
pub const segmentDistance = c.b3SegmentDistance;

pub const SegmentDistanceResult = c.b3SegmentDistanceResult;

pub const add = c.b3Add;
pub const sub = c.b3Sub;
/// Component-wise multiply (`math_functions.h:235`).
pub const mulComponentwise = c.b3Mul;
pub const neg = c.b3Neg;
pub const dot = c.b3Dot;
pub const length = c.b3Length;
pub const lengthSquared = c.b3LengthSquared;
pub const distance = c.b3Distance;
pub const distanceSquared = c.b3DistanceSquared;
pub const normalize = c.b3Normalize;
pub const getLengthAndNormalize = c.b3GetLengthAndNormalize;
pub const perp = c.b3Perp;
pub const isNormalized = c.b3IsNormalized;
pub const mulAdd = c.b3MulAdd;
pub const mulSub = c.b3MulSub;
/// Scalar times vector.
pub const scale = c.b3MulSV;
pub const cross = c.b3Cross;
pub const lerp = c.b3Lerp;
pub const blend2 = c.b3Blend2;
pub const absComponents = c.b3Abs;
pub const sign = c.b3Sign;
pub const minComponents = c.b3Min;
pub const maxComponents = c.b3Max;
pub const clampComponents = c.b3Clamp;
/// Scale a vector so integer components stay exact (`math_functions.h:438`).
pub const safeScale = c.b3SafeScale;

pub const isNormalizedQuat = c.b3IsNormalizedQuat;
pub const rotateVector = c.b3RotateVector;
pub const invRotateVector = c.b3InvRotateVector;
pub const dotQuat = c.b3DotQuat;
pub const mulQuat = c.b3MulQuat;
pub const invMulQuat = c.b3InvMulQuat;
pub const conjugate = c.b3Conjugate;
pub const negateQuat = c.b3NegateQuat;
pub const normalizeQuat = c.b3NormalizeQuat;
/// Rotation of `radians` about `axis`; normalizes the axis and returns identity for zero.
pub const quatFromAxisAngle = c.b3MakeQuatFromAxisAngle;
pub const axisAngle = c.b3GetAxisAngle;
/// Rotation angle of a quaternion in `[-pi, pi]` (`math_functions.h:553`).
pub const quatAngle = c.b3GetQuatAngle;
pub const twistAngle = c.b3GetTwistAngle;
pub const swingAngle = c.b3GetSwingAngle;
pub const lerpQuat = c.b3NLerp;
pub const quatFromMat3 = c.b3MakeQuatFromMatrix;
/// Rotation carrying unit vector `v1` onto `v2` (`math_functions.h:563`).
pub const quatBetweenUnitVectors = c.b3ComputeQuatBetweenUnitVectors;

pub const mulTransforms = c.b3MulTransforms;
pub const invertTransform = c.b3InvertTransform;
pub const transformPoint = c.b3TransformPoint;
pub const invTransformPoint = c.b3InvTransformPoint;

/// Widen a local vector to a world position; this converts to `double` in
/// double-precision builds (`math_functions.h:652`).
pub const toPos = c.b3ToPos;
pub const toVec3 = c.b3ToVec3;
pub const subPos = c.b3SubPos;
pub const offsetPos = c.b3OffsetPos;
pub const lerpPos = c.b3LerpPosition;
pub const transformWorldPoint = c.b3TransformWorldPoint;
pub const invTransformWorldPoint = c.b3InvTransformWorldPoint;
pub const invMulWorldTransforms = c.b3InvMulWorldTransforms;
pub const mulWorldTransforms = c.b3MulWorldTransforms;
/// Convert a world transform relative to a nearby base position (`math_functions.h:745`).
pub const toRelativeTransform = c.b3ToRelativeTransform;
pub const toWorldTransform = c.b3MakeWorldTransform;

pub const det = c.b3Det;
/// Matrix-vector product using the column-vector convention (`math_functions.h:784`).
pub const mulMat3Vec3 = c.b3MulMV;
pub const negateMat3 = c.b3NegateMat3;
pub const addMat3 = c.b3AddMM;
pub const subMat3 = c.b3SubMM;
pub const scaleMat3 = c.b3MulSM;
pub const mulMat3 = c.b3MulMM;
pub const transpose = c.b3Transpose;
pub const invertMat3 = c.b3InvertMatrix;
pub const solveMat3 = c.b3Solve3;
/// Inverse transpose, used to convert a world inertia tensor to local axes.
pub const invTransposeMat3 = c.b3InvertT;
pub const absMat3 = c.b3AbsMatrix3;

/// Grow an AABB to enclose a local `origin` (`math_functions.h:765`).
pub const offsetAabb = c.b3OffsetAABB;
/// AABB of `count` points inflated by `radius` (`math_functions.h:956`).
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

// These macros read the process length scale at each call, rather than a constant.
// Set the scale before any Box3D call; see `base.setLengthUnitsPerMeter`.

/// Linear slop in the current length units (`constants.h:53`).
pub fn linearSlop() f32 {
    return 0.005 * c.b3GetLengthUnitsPerMeter();
}

/// Distance at which shapes count as overlapping (`constants.h:60`).
pub fn overlapSlop() f32 {
    return 0.1 * linearSlop();
}

/// Padding added to proxy AABBs (`constants.h:91`).
pub fn maxAabbMargin() f32 {
    return 0.05 * c.b3GetLengthUnitsPerMeter();
}

pub fn speculativeDistance() f32 {
    return 4.0 * linearSlop();
}

pub fn meshRestOffset() f32 {
    return 1.0 * linearSlop();
}

pub fn contactRecycleDistance() f32 {
    return 10.0 * linearSlop();
}

pub const maxRotation: f32 = 0.25 * pi;
