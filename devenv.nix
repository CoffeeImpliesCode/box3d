# Canonical development environment for the box3d SDK.
#
# This is the environment a contributor should be in. It installs tools and
# nothing else: `packages` deliberately does not contain the SDK's own package,
# because entering a shell must not require building a library to have it.
#
# The package itself is defined once, in ./package.nix, and shared with
# flake.nix, so the two entry points cannot describe different builds. `outputs`
# below name that same derivation lazily -- they are attributes, not builds, so
# nothing is realised until `devenv build outputs.static` or
# `devenv build outputs.shared` is actually run.
#
# Every task body that names a file in this SDK begins `cdSdkRoot`, which is
# `cd "$sdkRoot"` followed by the cache fill below. devenv
# runs a task as a generated shell program that inherits the working directory of
# the project the shell was entered from, and that project is not this SDK: it
# holds `.devenv/` and `devenv.lock` and none of `build.zig`, `consumer/` or
# `tools/`. `./.` is relative to the module that writes it, so it is this
# module's own directory whatever the caller started from. `$DEVENV_ROOT` is
# never used to find it: that names the project directory, which is the thing
# that is already wrong.
#
# A command that installs a delivery passes `--prefix` to a directory under
# `ZIG_LOCAL_CACHE_DIR`, so an installed artifact never lands in the working
# tree. `build.zig` already writes its whole install closure, the generated
# pkg-config file and the licence material wherever `--prefix` points, so the
# prefix is an input it honours rather than a rewrite of its install layout.
#
# Every `zig build` this file can reach by name ends with the same three flags,
# from one `buildFlags` value: `-j8`, `--summary all`, and an explicit
# `--cache-dir` under `$ZIG_LOCAL_CACHE_DIR`, so no gate silently drops to a
# single job and none falls back to the SDK default `.zig-cache` in this working
# tree. They are written before `"$@"`, so a caller naming its own `-j` or
# `--cache-dir` still wins by being after them. The step that installs
# something carries the external `--prefix`; the steps that install nothing
# carry none.
#
# devenv.lock is not written here: the driver owns locks.
#
# Two devenv runs have touched this file. Run 20261004T212645Z failed during
# evaluation at `env.BOX3D_SDK_VERSION`, before any task body ran; run
# 20261004T214134Z evaluated, entered the shell and ran task bodies, and its
# consumer and integrity tasks failed on a bare `$sdkRoot` that this file never
# materialised. Every statement about the build graph is SOURCE-CONFIRMED by
# reading `build.zig`, `package.nix` and `flake.nix`; the derivations, the task
# names and the shells are PENDING-VERIFICATION.
#
# SPDX-License-Identifier: MIT

{ pkgs, ... }:

let
  # Kept as a value rather than inlined, so the version assertion below and the
  # package list cannot disagree about which compiler is meant.
  zig = pkgs.zig_0_16;

  box3d = linkage: pkgs.callPackage ./package.nix {
    inherit linkage;
    zig = zig;
  };

  # This SDK's own directory, as one shell word. `./.` is relative to the module
  # that writes it, so it resolves to the directory holding this file rather
  # than to the caller's working directory.
  sdkRoot = builtins.toString ./.;

  # The one cache directory every `zig build` below writes to. It is named
  # after this SDK and kept beside the install prefixes rather than above
  # them: those are `$ZIG_LOCAL_CACHE_DIR/box3d/<variant>` and stay exactly
  # where they are, and a Zig cache directory is not somewhere to keep an
  # install tree.
  cacheDir = "$ZIG_LOCAL_CACHE_DIR/box3d-cache";

  # Every body that reaches the compiler opens with this, and it is in the
  # body rather than only in `enterShell` because `devenv tasks run --mode
  # single` runs the body and not the shell hooks. The `cd` is this module's
  # own directory, `./.` resolved at evaluation time, so the working directory
  # is right from whatever directory the caller started in.
  #
  # `sdkRoot` is a Nix binding, not a shell variable, so it is materialised
  # into the body here, quoted, once. A bare `$sdkRoot` written into a body is
  # literal text Nix does not interpolate: the shell then expands an unset
  # variable and the path collapses to nothing.
  #
  # The two Zig caches are filled only where the caller left them out: their
  # own exported value always wins, and a missing one comes from
  # `$XDG_CACHE_HOME` first and `$TMPDIR` second. With neither exported the
  # body stops here and says why, because the alternative is the compiler's own
  # default `.zig-cache` inside this checkout. Nothing below this point creates
  # a directory under the checkout, and no `ZIG_LOCAL_CACHE_DIR`,
  # `ZIG_GLOBAL_CACHE_DIR`, `XDG_CACHE_HOME` or `TMPDIR` value is ever
  # overwritten here.
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

  # The one flag tail every `zig build` below ends with, written once so no
  # route can carry a different one: this workspace's `-j8`, the
  # `--summary all` AGENTS.md:157-158 asks of every library and consumer gate,
  # and an explicit `--cache-dir` so no run falls back to the SDK default
  # `.zig-cache` in this working tree.
  #
  # `"$@"` is last and stays last, so a caller naming its own `-j`,
  # `--cache-dir` or step name still wins by being after this one rather than
  # being dropped. `cdSdkRoot` has already filled the caches by the time these
  # reach the command line, which is what makes `cacheDir` a real location
  # rather than an unset variable.
  buildFlags = ''-j8 --summary all --cache-dir "${cacheDir}" "$@"'';

  # The one delivery body both linkage variants run. A default `zig build`
  # installs: `build.zig:1773-1786` puts the artifact, the generated
  # pkg-config file, the licence records and the compiled smoke program behind
  # `getInstallStep()`. The `test`, `smoke`, `check`, `upstream-test` and
  # `consumer` steps do not depend on the install step
  # (`build.zig:1788-1861`), so they carry no prefix.
  #
  # The prefix is a subdirectory of the cache `cdSdkRoot` resolved, never this
  # working tree. `--prefix` and `-p` are both honoured, in the separated,
  # `=`-joined and attached-value spellings; when the caller supplied one, that
  # prefix is used and this file's is not added at all, so no duplicate option
  # is ever passed and every other argument still reaches `zig build` as
  # written. Where no prefix was given, this file's is written *before* `"$@"`,
  # so even a spelling this scan did not recognise wins by being last rather
  # than being silently overridden; `buildFlags` is written there for the same
  # reason, so a caller naming its own `-j` or `--cache-dir` still gets it.
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
      assertion = zig.version == "0.16.0";
      message = "The box3d SDK requires Zig 0.16.0; nixpkgs resolved zig_0_16 to ${zig.version}";
    }
  ];

  # Lazy on purpose: naming a derivation realises nothing, and entering the
  # shell does not build either variant. `devenv build outputs.<name>` is the
  # real packaging route.
  outputs.static = box3d "static";
  outputs.shared = box3d "dynamic";
  outputs.default = box3d "static";

  # Defaults for the two Zig caches, never overrides: a value the caller already
  # exported wins, and only a missing one is filled in, from `$XDG_CACHE_HOME`
  # first and `$TMPDIR` second. With neither exported the shell says so on
  # stderr rather than being handed a location on a small system temporary
  # filesystem, and it never names one under this checkout. This is what an
  # interactive shell sees; `cdSdkRoot` repeats the same rule inside every
  # task body, because `devenv tasks run --mode single` runs the body without
  # these hooks, and both then hand the same `cacheDir` to `zig build` as an
  # explicit `--cache-dir` rather than leaving the default in the checkout.
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

  # Namespaced, and `namespace:name`: devenv rejects a task name carrying
  # anything outside alphanumerics, `:`, `-` and `_`, so the variants once
  # written `sdk:build.shared` and `sdk:package.static` are spelled with `_`.
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
      # The script resolves its own repository from its own `$0`
      # (`tools/check-provenance.sh:24`), so the SDK path is handed to it
      # directly instead of being assumed to be the working directory.
      exec = ''
        bash ${pkgs.lib.escapeShellArg (sdkRoot + "/tools/check-provenance.sh")} "$@"
      '';
    };

    # `--from` rather than a `cd` into this SDK: a `devenv build` started inside
    # the SDK makes the SDK its project root and leaves `.devenv/` and
    # `devenv.lock` in the working tree. `--from` names the module to evaluate
    # and leaves the project root where the caller put it, which is how this SDK
    # is already entered.
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