# Changelog

## Unreleased

- The nested `consumer` step forwards the caller's target query, CPU, build options, executor, caches, prefix and arguments; it installs targets the host cannot run.
- devenv tasks resolve the SDK root and external caches in shell and single-task runs; task names use underscores where required by the task runner.
- Runtime precision validation compares the translated type declarations, allowing a runtime provider built with matching double-precision headers.
- NetBSD translation preprocesses system headers before parsing; `zig/translate.h` declares the compiler `__int128` aliases used by NetBSD headers.
- Zig-owned `test`, `smoke` and `check` executables use LLVM.
- SIMD defaults off on 32-bit ARM targets; other targets keep upstream's default, and an explicit `-Ddisable-simd` value overrides the default.
- Typed body and joint creators return `error.InvalidWorld` for invalid worlds; shape creators return `error.ShapeCreationFailed` for invalid bodies.
- `B3_MAX_WORLDS` (128) and `B3_MAX_SHAPES` (`1 << 22`) remain caller preconditions; exhausting either can trigger an upstream assertion.
- `overlapAabbCollect` and `castShapeCollect` return total hits; only the first `min(count, out.len)` results are written.
- On Zig 0.16.0 x86-64, ten typed wrappers bridge `b3Pos`-by-value signatures through pointer forms; raw C declarations remain unchanged.
- The bridged wrappers are `query.castRay`, `query.castRayClosest` (also used by `castRayClosestShape`), `query.castShape`, `query.castMover`, `query.castRayAgainstBody`, `query.castShapeAgainstBody`, `body.setTransform`, `body.localPoint`, `body.worldPointVelocity` and `shape.rayCast`.
- `runtime/graph.zig` provides `createModule` and `createCoreModule` for runtime-loaded modules.
- `zig/root.zig` provides a typed Zig API and the complete raw C API.
- The native build compiles all 49 upstream C17 source files without CMake, autotools or build-time downloads.
- The build exposes `-Ddouble-precision` (default `false`), `-Dvalidate` (default `true`) and target-resolved `-Ddisable-simd`.
- `-Dlinkage=static|dynamic` selects the delivery artifact and defaults to `static`.
- `-Druntime=true` selects runtime-loaded dispatch independently of the linkage option.
- The upstream `BOX3D_PROFILE` option is not exposed because it downloads Tracy through `FetchContent`.
- The install includes `include/box3d/`, the library (`libbox3d.a` or `libbox3d.so.0`), `box3d.pc` and licence/provenance files under `share/licenses/box3d/`.
- `package.nix` builds static or shared delivery; the flake exposes matching outputs.

## Initial import

- Imported upstream Box3D v0.1.0 with its eight public headers and native library sources.
