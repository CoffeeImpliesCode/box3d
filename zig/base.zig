// SPDX-License-Identifier: MIT
//
//! Process-wide services: the version, the allocator, the assert and log hooks,
//! the clock, the length scale, and the hash Box3D uses for its own
//! determinism checks.
//!
//! Everything here reaches Box3D through the process-global state it declares,
//! not through any world. That is upstream's shape and it is worth being plain
//! about what it means:
//!
//!   * `setAllocator` replaces the allocator for **every** Box3D object in the
//!     process, including objects that already exist
//!     (`include/box3d/base.h:88-102`, `src/core.c:130-139`). It is read on
//!     every allocation, so changing it while a world is being built is a race
//!     and changing it while a world exists leaves that world split between two
//!     allocators. Set it once at startup, before the first world.
//!   * The two allocator callbacks take **no context**
//!     (`include/box3d/base.h:88-92`). A `std.mem.Allocator` cannot be carried
//!     through them, so an application that wants Box3D's allocations to come
//!     from a Zig allocator has to reach that allocator through its own global
//!     state inside the two callbacks. This module does not wrap them in
//!     anything, because anything it wrapped would have to invent that global.
//!   * `setAssertFcn` and `setLogFcn` take no context either
//!     (`include/box3d/base.h:95,98`), are single process-wide slots, and must
//!     be given non-null functions. The default assert handler prints and
//!     returns non-zero, which means `B3_BREAKPOINT`; the default log handler
//!     prints. Both may be called from a worker thread, because a worker can
//!     reach an assertion.
//!   * `lengthUnitsPerMeter` must be set before any other Box3D call
//!     (`include/box3d/constants.h:8-11`) and is a process-wide scale factor on
//!     several collision constants; `math.zig`'s length-dependent functions read
//!     it.
//!   * `b3GetByteCount` counts every byte Box3D has allocated through the
//!     current allocator pair (`include/box3d/base.h:104-105`). It is a counter,
//!     not a leak oracle: it cannot tell a leak from a world that is still
//!     alive, and it says nothing about memory a user allocator served from its
//!     own pool.

const c = @import("c");
const math = @import("math.zig");

/// Box3D's version, `b3Version` (`include/box3d/base.h:148-158`).
///
/// Significant, incremental and bug-fix numbers, by upstream's own semver
/// scheme (`include/box3d/base.h:146`).
pub const Version = c.b3Version;

/// The version of the Box3D that is actually linked, or loaded.
///
/// Read out of the library rather than compiled in, so this answers for the
/// provider this build reached rather than for the header it was compiled
/// against. In a runtime-loaded build that is the difference between the
/// library you asked for and the one you would have got by accident.
pub fn version() Version {
    return c.b3GetVersion();
}

/// True when the library was built with `BOX3D_DOUBLE_PRECISION`
/// (`include/box3d/base.h:163-164`), in which case `math.Pos` is a
/// double-translation struct rather than `math.Vec3`
/// (`include/box3d/math_functions.h:70-95`).
///
/// A header and a library that disagree here are two different ABIs, not a
/// version to work around; upstream renames `b3CreateWorld` in that mode so the
/// mismatch fails at link time (`include/box3d/box3d.h:25-30`).
pub fn isDoublePrecision() bool {
    return c.b3IsDoublePrecision();
}

/// Total bytes Box3D has allocated through the current allocator pair
/// (`include/box3d/base.h:104-105`).
///
/// A process-wide counter. It rises and falls as worlds, bodies, shapes and
/// joints are created and destroyed, and it is the number to read to find out
/// whether a `destroyWorld` gave everything back.
pub fn allocatedByteCount() i32 {
    return c.b3GetByteCount();
}

/// The allocator pair signature, `b3AllocFcn` (`include/box3d/base.h:88`).
///
/// `size` is in bytes and `alignment` is a power of two, guaranteed by
/// Box3D. Returns null when it cannot allocate, which Box3D turns into its own
/// failure rather than trapping.
pub const AllocFn = c.b3AllocFcn;
/// The free callback that pairs with `AllocFn`
/// (`include/box3d/base.h:91`).
pub const FreeFn = c.b3FreeFcn;
/// The assert callback signature (`include/box3d/base.h:95`). Return 0 to skip
/// the debugger break.
pub const AssertFn = c.b3AssertFcn;
/// The log callback signature (`include/box3d/base.h:98`). Used for warnings.
pub const LogFn = c.b3LogFcn;

/// Replace the allocator every Box3D object in this process uses.
///
/// Both arguments must be non-null. Box3D takes 64-byte alignment for
/// everything it allocates (`src/core.c:141-142`), so a pair that cannot
/// satisfy that is not a usable pair.
///
/// See the module comment: this is process-wide, it is read on every
/// allocation, and the callbacks carry no context.
pub fn setAllocator(alloc: AllocFn, free: FreeFn) void {
    c.b3SetAllocator(alloc, free);
}

/// Override the assert callback. Must be non-null
/// (`include/box3d/base.h:107-109`, `src/core.c:75-80`).
///
/// The callback is Box3D's `b3AssertHandler` slot, not a Zig panic: it returns
/// whether to break into the debugger, and it must not return without doing so
/// if the condition is a real failure.
pub fn setAssertFcn(assert_fn: AssertFn) void {
    c.b3SetAssertFcn(assert_fn);
}

/// Override the log callback. Must be non-null
/// (`include/box3d/base.h:143-144`, `src/core.c:100-104`).
pub fn setLogFcn(log_fn: LogFn) void {
    c.b3SetLogFcn(log_fn);
}

/// The absolute tick counter, `b3GetTicks` (`include/box3d/base.h:170-171`).
///
/// Platform specific and only comparable with itself; the unit is whatever the
/// platform's clock uses. The millisecond helpers below are the portable way to
/// read it.
pub fn ticks() u64 {
    return c.b3GetTicks();
}

/// Milliseconds since `ticks` was taken (`include/box3d/base.h:173-174`).
pub fn milliseconds(ticks_value: u64) f32 {
    return c.b3GetMilliseconds(ticks_value);
}

/// Milliseconds since `ticks_value`, and reset `ticks_value` to now
/// (`include/box3d/base.h:176-177`).
///
/// This is the interval the profiler uses, so a program that reads it has also
/// just disturbed Box3D's own step timing.
pub fn millisecondsAndReset(ticks_value: *u64) f32 {
    return c.b3GetMillisecondsAndReset(ticks_value);
}

/// Yield the current thread (`include/box3d/base.h:179-180`).
pub fn yieldThread() void {
    c.b3Yield();
}

/// Sleep the current thread (`include/box3d/base.h:182-183`).
pub fn sleep(milliseconds_to_sleep: c_int) void {
    c.b3Sleep(milliseconds_to_sleep);
}

/// The djb2 seed upstream uses for its determinism checks
/// (`include/box3d/base.h:186`).
pub const hashInit: u32 = c.B3_HASH_INIT;

/// Box3D's own content hash over `data[0..count]`
/// (`include/box3d/base.h:185-187`).
///
/// A simulation checksum, not a cryptographic digest and not a general-purpose
/// hash: it is what upstream compares across platforms to decide that two runs
/// of the same world produced the same simulation.
pub fn hash(seed: u32, data: []const u8) u32 {
    return c.b3Hash(seed, data.ptr, @intCast(data.len));
}

/// The current length scale, `b3GetLengthUnitsPerMeter`
/// (`include/box3d/constants.h:14-15`).
///
/// Default 1. Box3D works in meters; set this if your game does not.
pub fn lengthUnitsPerMeter() f32 {
    return c.b3GetLengthUnitsPerMeter();
}

/// Set the length scale, `b3SetLengthUnitsPerMeter`
/// (`include/box3d/constants.h:8-12`).
///
/// Must be called before any other Box3D call, and only modified once. It
/// scales `B3_HUGE`, `B3_LINEAR_SLOP`, `B3_MAX_AABB_MARGIN` and the other
/// length constants, so changing it mid-run changes collision behaviour and
/// not only a unit conversion.
pub fn setLengthUnitsPerMeter(length_units: f32) void {
    c.b3SetLengthUnitsPerMeter(length_units);
}

/// The threshold above which a step is logged as a stall
/// (`include/box3d/constants.h:17-18`).
pub fn stallThreshold() f32 {
    return c.b3GetStallThreshold();
}

/// Set the stall logging threshold, `b3SetStallThreshold`
/// (`include/box3d/constants.h:17-18`). Must be positive.
pub fn setStallThreshold(seconds: f32) void {
    c.b3SetStallThreshold(seconds);
}

/// The value that means "no index", `B3_NULL_INDEX`
/// (`include/box3d/base.h:82-83`).
///
/// Box3D works with indices rather than pointers in its tree and graph APIs, and
/// `-1` is how those APIs say "nothing".
pub const nullIndex: c_int = c.B3_NULL_INDEX;

/// The maximum number of worlds that can exist at once,
/// `B3_MAX_WORLDS` (`include/box3d/constants.h:62-64`).
///
/// Worlds are independent and may be simulated in parallel, so this is the
/// process-wide ceiling on `world.create`.
///
/// Asking for one more is not a recoverable error: upstream asserts inside
/// `b3CreateWorld` rather than returning a null id
/// (`src/physics_world.c:223-228`), which `world.Error.WorldLimitExceeded`
/// documents.
pub const maxWorlds: c_int = c.B3_MAX_WORLDS;

/// The maximum number of parallel workers, `B3_MAX_WORKERS`
/// (`include/box3d/constants.h:32-33`).
///
/// A world worker count is clamped to `[1, maxWorkers]`
/// (`include/box3d/types.h:182-185`), and a value above 1 turns on
/// multithreading.
pub const maxWorkers: c_int = c.B3_MAX_WORKERS;

/// The longest body name, including the terminator, `B3_BODY_NAME_LENGTH`
/// (`include/box3d/constants.h:100-104`).
///
/// Non-zero body names are what make a recording replayable, upstream's note
/// on that line.
pub const bodyNameLength: usize = c.B3_BODY_NAME_LENGTH;

/// The longest shape name, including the terminator, `B3_SHAPE_NAME_LENGTH`
/// (`include/box3d/constants.h:106-111`).
pub const shapeNameLength: usize = c.B3_SHAPE_NAME_LENGTH;

/// A world position and a rotation in one value, upstream's `b3WorldTransform`,
/// re-exported here so `math` need not be imported for it.
pub const WorldTransform = math.WorldTransform;
/// A world position, upstream's `b3Pos`.
pub const Pos = math.Pos;
/// A 3D vector, upstream's `b3Vec3`.
pub const Vec3 = math.Vec3;