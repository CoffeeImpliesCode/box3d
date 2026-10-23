// SPDX-License-Identifier: MIT
//
//! Box3D-specific synchronization and provider checks for the runtime loader.
//! Providers must export Box3D's translated symbols and match its version, precision and ABI.
//! Callback pointers must remain live while their worlds use them.

const rt = @import("rt");

/// Namespaced synchronization bindings used by the loader.
/// Keep the prefix aligned with `runtime/graph.zig` and `runtime/sync.c`.
pub const Sync = struct {
    extern fn box3d_rt_lock() void;
    extern fn box3d_rt_unlock() void;
    extern fn box3d_rt_wait() void;
    extern fn box3d_rt_broadcast() void;
    // C's `unsigned long long` is 64 bits on every supported ABI.
    extern fn box3d_rt_thread_self() u64;

    pub fn lock() void {
        box3d_rt_lock();
    }
    pub fn unlock() void {
        box3d_rt_unlock();
    }
    pub fn wait() void {
        box3d_rt_wait();
    }
    pub fn broadcast() void {
        box3d_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return box3d_rt_thread_self();
    }
};

/// ABI version a compatible provider must report.
pub const abi_version: struct { major: c_int, minor: c_int, revision: c_int } = .{
    .major = 0,
    .minor = 1,
    .revision = 0,
};

/// Builds the loader configuration for the generated dispatch.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Name used in the pre-load panic.
        pub const library_name = "box3d";

        /// Table and symbol lists generated from the translated header.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// This project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Validates the provider before the table is published.
        pub fn validate(dst: *const table) ?[]const u8 {
            const version = dst.b3GetVersion();
            if (version.major != abi_version.major or
                version.minor != abi_version.minor or
                version.revision != abi_version.revision)
            {
                return "b3GetVersion() reported a revision other than 0.1.0, so this " ++
                    "provider is not the library this header describes";
            }

            // Compare translated types directly: `@TypeOf` would yield `type` for both and always compare equal.
            // In large-world mode, `b3Pos` and `b3Vec3` differ (`include/box3d/math_functions.h`).
            const translated_single_precision =
                dispatch.b3Pos == dispatch.b3Vec3 and
                dispatch.b3WorldTransform == dispatch.b3Transform;
            const provider_is_double = dst.b3IsDoublePrecision();
            const headers_are_double = !translated_single_precision;
            if (provider_is_double != headers_are_double) {
                return "b3IsDoublePrecision() disagrees with the precision mode these " ++
                    "headers were translated for; the two sides were built with " ++
                    "different BOX3D_DOUBLE_PRECISION settings, so every position in " ++
                    "the API has a different width";
            }
            return null;
        }
    };
}
