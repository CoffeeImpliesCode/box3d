# SPDX-License-Identifier: MIT

{ lib
, stdenv
, zig
, linkage ? "static"
, optimize ? "ReleaseSafe"
}:

let
  requestedLinkage =
    if builtins.elem linkage [ "" "static" "dynamic" ] then linkage
    else throw "package.nix: linkage must be \"\", \"static\" or \"dynamic\", not ${toString linkage}";
in

# Nix builds are native-only; reject a build/host platform mismatch.
assert stdenv.buildPlatform.system == stdenv.hostPlatform.system;

let
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

  # Propagate the platform C library for pthread and math symbols.
  propagatedBuildInputs = [ stdenv.cc.libc ];

  dontConfigure = true;
  dontBuild = true;

  doCheck = false;
  # Avoid the Zig setup hook's default test build.
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Keep Zig caches outside the source and install output.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"

    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      ${lib.optionalString (requestedLinkage != "") "-Dlinkage=${requestedLinkage}"}

    runHook postInstall
  '';


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
  };
}