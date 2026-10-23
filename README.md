# box3d

Box3D v0.1.0 is Erin Catto's 3D physics engine, packaged for Zig 0.16.
This package builds the upstream C17 library and provides a typed Zig facade.

## Source deviations from upstream

No upstream source file is modified. The fork adds `build_support/box3d_abi_bridge.c` and its header. With double precision on x86-64, Zig 0.16 mis-lowers ten calls that pass `b3Pos` by value before a floating-point argument or return. The bridge uses pointer arguments and forwards to the unchanged C functions. The typed facade uses the bridge; `README.zig.md` lists the affected calls.

## Build deviations from upstream

`build.zig` replaces upstream's CMake build. It compiles the 49 upstream C translation units, translates the public headers through `zig/translate.h`, and builds a static archive or shared library. The build installs the headers and generates `box3d.pc`.

`zig build upstream-test` builds upstream's C test application and its shared support files. The package does not build samples, benchmarks, or the Doxygen manual. It has no `-Dprofile` option because upstream's profiler fetches Tracy; the package downloads no build dependencies. The build keeps upstream's `-ffp-contract=off` flag on MinGW, Apple, and Unix.

## Support matrix

| Surface | Targets |
|---|---|
| Nix `static` and `shared` outputs | `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin` |
| `zig build check` compile targets | `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu`, `wasm32-wasi` |

`zig build check` compiles and links; it does not run target binaries. Static builds are available for all six check targets. Shared builds need a dynamic linker; WASI has none. Windows is in the compile-check list but has no Nix output: upstream's single `BOX3D_EXPORT` macro cannot distinguish the library's exports from a consumer's imports. Upstream's timer uses pthreads and unnamed POSIX semaphores on Linux and Emscripten; other platforms use its single-threaded timer path.

## Consumption

### Zig

Add the package to `build.zig.zon`:

```zig
.dependencies = .{
    .box3d = .{ .path = "../box3d" },
},
```

Import the module from `build.zig`:

```zig
const dep = b.dependency("box3d", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("box3d", dep.module("box3d"));
```

The dependency, module, and native artifact are named `box3d`. Zig consumers use `dep.module("box3d")`; C consumers use `dep.artifact("box3d")`, which adds `include/box3d/` to the include path.

### Artifacts and options

The installed files include `include/box3d/`, `lib/pkgconfig/box3d.pc`, and one library:

- Static: `libbox3d.a`.
- ELF shared: `libbox3d.so.0.1.0`, `libbox3d.so.0`, and `libbox3d.so`.
- Darwin shared: `libbox3d.0.dylib` and `libbox3d.dylib`.

On Unix, `box3d.pc` records `-lm -pthread` as private link flags; for shared builds it also sets `-DBOX3D_DLL`. Nix provides `nix build .#static` and `nix build .#shared`.

| Option | Default | Effect |
|---|---|---|
| `-Dlinkage=static\|dynamic` | `static` | Selects the library artifact. |
| `-Druntime=true` | `false` | Resolves symbols at runtime; independent of linkage. |
| `-Ddouble-precision=true` | `false` | Changes type layout and the world-creation symbol; match the library configuration. |
| `-Ddisable-simd=true` | Target-dependent | Selects scalar kernels. Unset, SIMD follows upstream defaults except on 32-bit ARM, which uses scalar kernels. |
| `-Dvalidate=false` | `true` | Disables validation. Validation is effective only when `NDEBUG` is absent. |

`-Dtarget` and `-Doptimize` are standard Zig build options. There is no system-library mode. Useful steps include `zig build`, `zig build test`, `zig build upstream-test`, and `zig build check`.
