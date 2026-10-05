# Source-only package derivation for the box3d SDK.
#
# One file, called by both flake.nix and devenv.nix, so the two entry points
# cannot describe different packages. It builds nothing but this repository and
# downloads nothing: the native sources are already in `src/`, upstream's CMake
# project is not executed, and `build.zig` owns the source list, the C flags,
# the header configuration and the installed layout.
#
# No lock file is created here. flake.lock and devenv.lock belong to the driver.
#
# SPDX-License-Identifier: MIT

{ lib
, stdenv
, zig
  # Zig's own `std.builtin.LinkMode` spelling, passed straight through as
  # `-Dlinkage`. Static is the default because it is what this SDK builds by
  # default; the entry points expose `.shared` as a separate variant.
, linkage ? "static"
, optimize ? "ReleaseSafe"
}:

let
  requestedLinkage =
    if builtins.elem linkage [ "" "static" "dynamic" ] then linkage
    else throw "package.nix: linkage must be \"\", \"static\" or \"dynamic\", not ${toString linkage}";
in

# This package builds for the compiler's own native target. A cross build here
# would mean hand-building a libc-suffixed triple that has to track nixpkgs, so
# this derivation refuses one instead of silently producing a host-architecture
# library under a foreign name. The comparison is against stdenv's own
# platforms, which is evaluable in a pure sandbox; `builtins.currentSystem` is
# not, and is not used. A remote builder is unaffected: this is a
# build-versus-host comparison, not a check against any particular machine.
assert stdenv.buildPlatform.system == stdenv.hostPlatform.system;

let
  # Everything except build outputs, version control and developer-tool state.
  # Filtering by directory name rather than by an allow list means a source
  # file added to this repository later is packaged without editing this file,
  # while `.git`, `.zig-cache`, `zig-out`, `.devenv` and `.direnv` stay out of a
  # published output at any depth, including under consumer/.
  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: _type:
      let name = builtins.baseNameOf (toString path);
      in
      !(lib.elem name [
        ".git"
        ".jj"
        ".direnv"
        ".devenv"
        ".devenv.flake.nix"
        ".zig-cache"
        "zig-cache"
        "zig-out"
        "zig-pkg"
      ])
      && name != "result"
      && !(lib.hasPrefix "result-" name);
  };
in

stdenv.mkDerivation {
  pname = "box3d";
  version = "0.1.0";

  inherit src;

  strictDeps = true;
  dontPatch = true;

  nativeBuildInputs = [ zig ];

  # Box3D's `src/timer.c` uses POSIX threads and unnamed semaphores on Linux and
  # Apple, and libm for `sqrtf` and friends on non-Apple Unix
  # (`src/CMakeLists.txt:218-221`). Both live in the platform C library, which
  # is what a consumer's own link line needs named. Nothing else is propagated.
  propagatedBuildInputs = [ stdenv.cc.libc ];

  # The build is one `zig build install`. Configuring and building separately
  # would run the graph twice, once with default flags and once with this
  # variant's, and the first result is the one that gets thrown away.
  dontConfigure = true;
  dontBuild = true;

  # The driver owns every gate for this SDK, and a Nix build is not a
  # verification receipt. No check phase runs here rather than a check phase
  # that runs something weaker than the real gates.
  doCheck = false;
  # Without this the Zig setup hook substitutes its own `zig build test` for the
  # check phase, which is a second, differently-flagged build of the same tree.
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Both caches go under the Nix-provided TMPDIR, outside the unpacked source
    # tree, so nothing build-generated can end up in $out or in the store path.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"

    # The native build graph owns every C flag, the source list and the header
    # configuration. Restating them here would create a second place where they
    # can disagree.
    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      ${lib.optionalString (requestedLinkage != "") "-Dlinkage=${requestedLinkage}"}

    runHook postInstall
  '';

  # The layout this derivation produces is the build graph's, not this file's:
  #   $out/include/box3d/{base,box3d,collision,config,constants,id,math_functions,types}.h
  #   $out/lib/libbox3d.a                          (linkage = "static")
  #   $out/lib/libbox3d.so.0.1.0, .so.0, .so      (linkage = "dynamic", ELF)
  #   $out/lib/pkgconfig/box3d.pc
  #   $out/share/licenses/box3d/{LICENSE,README.upstream.md,NOTICE.md,UPSTREAM.md,FORK-LICENSE.md}
  # Both variants keep that layout; only the artifact kind differs. Upstream's
  # own CMake project sets VERSION 0.1.0 and SOVERSION 0
  # (`src/CMakeLists.txt:128-129`), so the shared object keeps that soname
  # series. Nothing is copied or generated here.

  enableParallelBuilding = true;

  passthru = {
    inherit linkage optimize;
  };

  meta = {
    description = "Box3D, a 3D physics engine for games";
    longDescription = ''
      Box3D v0.1.0 packaged for Zig 0.16: the complete upstream C17 core, its
      eight public headers, the generated pkg-config metadata and the licence
      and provenance records, with a typed Zig module and a runtime-loading
      build alongside. The samples, benchmarks and Doxygen manual are retained
      in the source tree and are not compiled.
    '';
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    # No `mainProgram`: build.zig installs the library, its headers, its
    # pkg-config file and its licence records, and compiles the smoke program
    # without installing it, so this output has no executable to name.
  };
}