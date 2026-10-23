# Fork notes: box3d

Upstream C sources under `src/`, `include/`, `test/` and `shared/` are unmodified.

## Source adaptations

| File | Change and reason |
|---|---|
| `build_support/box3d_abi_bridge.c` | Adds pointer-argument wrappers for ten `b3Pos`-by-value APIs because Zig's x86-64 double-precision call lowering misplaces later floating-point arguments. |
| `build_support/box3d_abi_bridge.h` | Declares the bridge exports used by the typed and runtime dispatch. |
| `zig/query.zig` | Both `*Collect` queries count all hits and return the total, since output capacity does not define query cardinality. |
| `zig/world.zig` | Maps an invalid returned world ID to `error.WorldLimitExceeded`; upstream may assert on an exhausted pool before returning. |
| `zig/body.zig` | Checks the world ID before body creation so a stale ID returns a facade error instead of reaching an upstream assertion. |
| `zig/joint.zig` | Checks parent validity before joint creation so stale IDs return facade errors instead of reaching upstream assertions. |
| `zig/shape.zig` | Checks the body ID before shape creation so stale IDs return facade errors instead of reaching upstream assertions. |
| `zig/translate.h` | Includes the public umbrella header and supplies compiler `__int128` aliases needed to translate NetBSD AArch64 headers. |

## Build graph

- `build.zig` replaces CMake with one Zig graph; it compiles the 49 upstream C units and the ABI bridge, and translates the public umbrella header.
- `-Dlinkage` selects static or shared delivery; `-Druntime` selects direct linking or runtime dispatch independently. There is no system-library mode.
- Package-owned Zig roots, including the standalone consumer, select LLVM; external consumers control their executable or test root.
- `zig build consumer` runs the nested `consumer/` package through `dep.module("box3d")` with a local `.path = ".."` dependency.
- The Zig 0.17 nested build uses `--build-file`, separate `--cache-dir` arguments and `ZIG_GLOBAL_CACHE_DIR`/`ZIG_LIB_DIR` environment variables.
- `upstream-test` builds the 21 upstream test C files and 12 shared helpers unchanged against a static core, even when the delivered library is shared.
- Samples, benchmarks and the Doxygen manual are retained but not built; they require fetched dependencies or Doxygen. The Tracy-backed profile option is omitted to keep builds offline.
- The graph installs the library, public headers, a generated `box3d.pc`, and licence and provenance records.
- Nix static and shared outputs use the same Zig install derivation.

## Platform boundaries

- 32-bit ARM (`arm`, `armeb`, `thumb`, `thumbeb`) defaults to scalar SIMD because upstream's NEON path uses AArch64-only float divide and square-root intrinsics. Forcing SIMD does not make that path compile.
- NetBSD translation preprocesses the umbrella header with the target C compiler before parsing to handle libc `_Pragma` declarations. NetBSD AArch64 also needs compiler-provided `__int128` aliases.
- WASI has no dynamic linker, so shared linkage is refused; static linkage remains available.
- The Nix flake does not package Windows. Upstream's `BOX3D_EXPORT` macro cannot express both sides of a Windows DLL import/export boundary with one value.
- Zig-to-C calls have known argument or world-ID failures on `aarch64_be-linux`, `mips64-linux`, `powerpc64-linux`, `x86-linux`, `powerpc-linux`, `s390x-linux`, `hexagon-linux`, `loongarch64-linux`, `mips64el-linux`, `powerpc64le-linux`, `riscv32-linux`; no common cause is established.
- `src/timer.c` uses pthreads and unnamed POSIX semaphores on Linux and Emscripten; other platforms use its single-threaded path.
