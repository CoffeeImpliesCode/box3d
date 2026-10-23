// SPDX-License-Identifier: MIT
//
//! Process-wide Box3D services: allocator, callbacks, timing, length scale and hash.
//! These settings affect every world; allocator and hook callbacks have no context.
//! Configure the allocator at startup and the length scale before any Box3D call.

const c = @import("c");
const math = @import("math.zig");

/// Box3D version, `b3Version` (`include/box3d/base.h:148-158`).
pub const Version = c.b3Version;

/// Read the linked or loaded library version, not the compile-time header version.
pub fn version() Version {
    return c.b3GetVersion();
}

/// True when the library uses `BOX3D_DOUBLE_PRECISION`, which changes the `math.Pos` ABI.
/// A header/library mismatch is an ABI error; the exported symbol differs (`include/box3d/box3d.h:25-30`).
pub fn isDoublePrecision() bool {
    return c.b3IsDoublePrecision();
}

/// Bytes allocated through Box3D's current allocator pair; process-wide counter.
/// Includes live objects and is not a leak detector.
pub fn allocatedByteCount() i32 {
    return c.b3GetByteCount();
}

/// Allocation callback: `size` is bytes and `alignment` is a power of two.
/// Return null on failure; Box3D reports allocation failure (`include/box3d/base.h:88`).
pub const AllocFn = c.b3AllocFcn;
/// Free callback paired with `AllocFn` (`include/box3d/base.h:91`).
pub const FreeFn = c.b3FreeFcn;
/// Assert callback; return zero to skip the debugger break (`include/box3d/base.h:95`).
pub const AssertFn = c.b3AssertFcn;
/// Log callback, used for warnings (`include/box3d/base.h:98`).
pub const LogFn = c.b3LogFcn;

/// Replace the process-wide allocator pair; call once before creating worlds.
/// Both callbacks must be non-null and provide 64-byte alignment (`src/core.c:141-142`).
pub fn setAllocator(alloc: AllocFn, free: FreeFn) void {
    c.b3SetAllocator(alloc, free);
}

/// Replace the non-null assert callback; it returns whether to break into the debugger.
/// Box3D's assertion callback, not a Zig panic; real failures must break (`src/core.c:75-80`).
pub fn setAssertFcn(assert_fn: AssertFn) void {
    c.b3SetAssertFcn(assert_fn);
}

/// Replace the non-null log callback (`src/core.c:100-104`).
pub fn setLogFcn(log_fn: LogFn) void {
    c.b3SetLogFcn(log_fn);
}

/// Read the platform tick counter; values are only comparable within that clock.
/// Use `milliseconds` for elapsed time.
pub fn ticks() u64 {
    return c.b3GetTicks();
}

/// Convert a tick interval to milliseconds (`include/box3d/base.h:173-174`).
pub fn milliseconds(ticks_value: u64) f32 {
    return c.b3GetMilliseconds(ticks_value);
}

/// Return elapsed milliseconds and reset `ticks_value` to now.
/// This also resets the profiler's timing interval.
pub fn millisecondsAndReset(ticks_value: *u64) f32 {
    return c.b3GetMillisecondsAndReset(ticks_value);
}

pub fn yieldThread() void {
    c.b3Yield();
}

pub fn sleep(milliseconds_to_sleep: c_int) void {
    c.b3Sleep(milliseconds_to_sleep);
}

/// djb2 seed used for Box3D determinism checks (`include/box3d/base.h:186`).
pub const hashInit: u32 = c.B3_HASH_INIT;

/// Hash the first `count` bytes with Box3D's simulation checksum.
/// Not cryptographic; upstream compares it across simulation runs.
pub fn hash(seed: u32, data: []const u8) u32 {
    return c.b3Hash(seed, data.ptr, @intCast(data.len));
}

/// Current global length scale; defaults to 1.
pub fn lengthUnitsPerMeter() f32 {
    return c.b3GetLengthUnitsPerMeter();
}

/// Set the process-wide length scale before any Box3D call; change it only once.
/// It scales collision length constants, not just unit conversion (`include/box3d/constants.h:8-12`).
pub fn setLengthUnitsPerMeter(length_units: f32) void {
    c.b3SetLengthUnitsPerMeter(length_units);
}

/// Threshold above which a step is logged as a stall (`include/box3d/constants.h:17-18`).
pub fn stallThreshold() f32 {
    return c.b3GetStallThreshold();
}

/// Set the stall logging threshold; it must be positive.
pub fn setStallThreshold(seconds: f32) void {
    c.b3SetStallThreshold(seconds);
}

/// Sentinel for “no index”, `B3_NULL_INDEX` (`include/box3d/base.h:82-83`).
pub const nullIndex: c_int = c.B3_NULL_INDEX;

/// Maximum concurrent worlds. Exceeding it asserts instead of returning a null id
/// (`src/physics_world.c:223-228`).
pub const maxWorlds: c_int = c.B3_MAX_WORLDS;

/// Maximum workers per world; counts above 1 enable threading.
/// `WorldDef.workerCount` clamps to `[1, maxWorkers]` (`include/box3d/types.h:182-185`).
pub const maxWorkers: c_int = c.B3_MAX_WORKERS;

/// Maximum body-name bytes, including the terminator (`include/box3d/constants.h:100-104`).
/// Recordings need non-empty body names to remain replayable.
pub const bodyNameLength: usize = c.B3_BODY_NAME_LENGTH;

/// Maximum shape-name bytes, including the terminator (`include/box3d/constants.h:106-111`).
pub const shapeNameLength: usize = c.B3_SHAPE_NAME_LENGTH;

pub const WorldTransform = math.WorldTransform;
pub const Pos = math.Pos;
pub const Vec3 = math.Vec3;
