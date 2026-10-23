# SPDX-License-Identifier: MIT

{ pkgs, ... }:

let
  # Share the compiler binding between the version check and package list.
  zig = pkgs.zig_0_17;

  box3d = linkage: pkgs.callPackage ./package.nix {
    inherit linkage;
    zig = zig;
  };

  # Resolve the SDK root from this module, not the caller's working directory.
  sdkRoot = builtins.toString ./.;

  # Keep the SDK cache separate from variant install prefixes.
  cacheDir = "$ZIG_LOCAL_CACHE_DIR/box3d-cache";

  # Task bodies set their root and caches because single-mode tasks skip shell hooks.
  # Preserve exported cache paths and keep defaults outside the checkout.
  cdSdkRoot = ''
    sdkRoot=${pkgs.lib.escapeShellArg sdkRoot}
    cd "$sdkRoot" || exit 1
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ] || [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      box3d_cache_root=
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        box3d_cache_root="$XDG_CACHE_HOME"
      elif [ -n "''${TMPDIR:-}" ]; then
        box3d_cache_root="$TMPDIR"
      else
        echo "box3d: XDG_CACHE_HOME and TMPDIR are both unset and no Zig cache" >&2
        echo "was exported, so no cache outside this checkout is known and the" >&2
        echo "compiler is not run. Export ZIG_LOCAL_CACHE_DIR and" >&2
        echo "ZIG_GLOBAL_CACHE_DIR at an approved scratch mount." >&2
        exit 1
      fi
      : "''${ZIG_GLOBAL_CACHE_DIR:=$box3d_cache_root/zig-global-cache}"
      : "''${ZIG_LOCAL_CACHE_DIR:=$box3d_cache_root/zig-local-cache}"
    fi
    export ZIG_GLOBAL_CACHE_DIR ZIG_LOCAL_CACHE_DIR
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR" "${cacheDir}"
  '';

  # Shared Zig flags precede caller arguments, so caller overrides remain effective.
  buildFlags = ''-j8 --summary all --cache-dir "${cacheDir}" "$@"'';

  # Use an external prefix unless the caller supplied one.
  deliveryBuild = linkageFlag: subdirectory: ''
    ${cdSdkRoot}
    prefix="$ZIG_LOCAL_CACHE_DIR/box3d/${subdirectory}"
    caller_prefix=
    previous=
    for argument in "$@"; do
      case "$previous" in
        --prefix|-p) caller_prefix="$argument" ;;
      esac
      case "$argument" in
        --prefix=*) caller_prefix="''${argument#--prefix=}" ;;
        -p?*) caller_prefix="''${argument#-p}" ;;
      esac
      previous="$argument"
    done
    if [ -n "$caller_prefix" ]; then
      mkdir -p "$caller_prefix"
      zig build ${linkageFlag} ${buildFlags}
    else
      mkdir -p "$prefix"
      zig build ${linkageFlag} --prefix "$prefix" ${buildFlags}
    fi
  '';
in
{
  packages = [
    zig
    pkgs.gnumake
    pkgs.pkg-config
    pkgs.valgrind
  ];

  assertions = [
    {
      assertion = zig.version == "0.17.0";
      message = "The box3d SDK requires Zig 0.17.0; nixpkgs resolved zig_0_17 to ${zig.version}";
    }
  ];

  outputs.static = box3d "static";
  outputs.shared = box3d "dynamic";
  outputs.default = box3d "static";

  # Fill only missing cache roots and keep Zig caches outside the checkout.
  enterShell = ''
    box3d_cache_root=
    if [ -n "''${XDG_CACHE_HOME:-}" ]; then
      box3d_cache_root="$XDG_CACHE_HOME"
    elif [ -n "''${TMPDIR:-}" ]; then
      box3d_cache_root="$TMPDIR"
    fi
    if [ -n "$box3d_cache_root" ]; then
      : "''${ZIG_GLOBAL_CACHE_DIR:=$box3d_cache_root/zig-global-cache}"
      : "''${ZIG_LOCAL_CACHE_DIR:=$box3d_cache_root/zig-local-cache}"
      export ZIG_GLOBAL_CACHE_DIR ZIG_LOCAL_CACHE_DIR
      mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"
    else
      echo "box3d devenv: XDG_CACHE_HOME and TMPDIR are both unset, so no Zig" >&2
      echo "cache location is chosen here. Export ZIG_GLOBAL_CACHE_DIR and" >&2
      echo "ZIG_LOCAL_CACHE_DIR at an approved mount." >&2
    fi

    echo "Box3D SDK development environment"
    echo "  sdk:       $BOX3D_SDK_NAME $BOX3D_SDK_VERSION (upstream v0.1.0)"
    echo "  sdk root:  $BOX3D_SDK_ROOT"
    echo "  cache:     ''${ZIG_LOCAL_CACHE_DIR:-unset} (global ''${ZIG_GLOBAL_CACHE_DIR:-unset})"
    echo "  compiler:  $(zig version)"
    echo "  build:     zig build | zig build test | zig build smoke | zig build check"
    echo "  linkage:   zig build -Dlinkage=static | zig build -Dlinkage=dynamic"
    echo "  integrity: tools/check-provenance.sh"
    echo "  package:   devenv build outputs.static | devenv build outputs.shared"
  '';

  env = {
    BOX3D_SDK_NAME = "box3d";
    BOX3D_SDK_VERSION = (box3d "static").version;
    BOX3D_SDK_ROOT = sdkRoot;
  };

  tasks = {
    "sdk:build" = {
      description = "Compile and install the native library, then compile the smoke example (default step)";
      exec = deliveryBuild "" "static";
    };

    "sdk:build_shared" = {
      description = "Compile and install the native library as a shared object instead of an archive";
      exec = deliveryBuild "-Dlinkage=dynamic" "shared";
    };

    "sdk:test" = {
      description = "Run the fork's behavioural tests";
      exec = ''
        ${cdSdkRoot}
        zig build test ${buildFlags}
      '';
    };

    "sdk:test_release_safe" = {
      description = "Run the fork's behavioural tests in ReleaseSafe";
      exec = ''
        ${cdSdkRoot}
        zig build test -Doptimize=ReleaseSafe ${buildFlags}
      '';
    };

    "sdk:upstream-test" = {
      description = "Build and run Box3D's own unit-test application from test/ and shared/, unmodified";
      exec = ''
        ${cdSdkRoot}
        zig build upstream-test ${buildFlags}
      '';
    };

    "sdk:smoke" = {
      description = "Run the deterministic example";
      exec = ''
        ${cdSdkRoot}
        zig build smoke ${buildFlags}
      '';
    };

    "sdk:check" = {
      description = "Compile and link every public entry point for the six compile-only targets without running any of them";
      exec = ''
        ${cdSdkRoot}
        zig build check ${buildFlags}
      '';
    };

    "sdk:check_shared" = {
      description = "The same six-target compile check against the shared object";
      exec = ''
        ${cdSdkRoot}
        zig build check -Dlinkage=dynamic ${buildFlags}
      '';
    };

    "sdk:consumer" = {
      description = "Build and run the separate consumer package against this SDK";
      exec = ''
        ${cdSdkRoot}
        cd consumer
        zig build run ${buildFlags}
      '';
    };

    "sdk:provenance" = {
      description = ''
        Check the 349 recorded upstream digests, the four licence-bearing
        vendored files and the preserved upstream README bytes. This is a
        source-integrity check, not a build gate.
      '';
      # Pass the SDK path explicitly; the script resolves itself from `$0`.
      exec = ''
        bash ${pkgs.lib.escapeShellArg (sdkRoot + "/tools/check-provenance.sh")} "$@"
      '';
    };

    # Use `--from` so devenv build keeps project state outside this checkout.
    "sdk:package_static" = {
      description = "Build the static Nix variant through devenv's own lazy output";
      exec = ''
        devenv build outputs.static --from ${pkgs.lib.escapeShellArg ("path:" + sdkRoot)} "$@"
      '';
    };

    "sdk:package_shared" = {
      description = "Build the shared Nix variant through devenv's own lazy output";
      exec = ''
        devenv build outputs.shared --from ${pkgs.lib.escapeShellArg ("path:" + sdkRoot)} "$@"
      '';
    };
  };
}