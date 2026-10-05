# Flake interface for the box3d SDK.
#
# Portable counterpart to devenv.nix. Both call ./package.nix, so the package a
# flake builds and the package devenv builds are the same derivation; this file
# only decides which systems are exposed and which variants of that derivation
# they get.
#
# Canonical development is `devenv shell` (see devenv.nix and .envrc). This
# flake exists so the SDK can be built and consumed off this host. `nix develop`
# here is parity, not the canonical entry point, and it deliberately does not
# build the SDK: entering a shell must not require building a library.
#
# flake.lock is not written here: the driver owns locks.
#
# SPDX-License-Identifier: MIT

{
  description = "Box3D v0.1.0, Erin Catto's 3D physics engine, packaged for Zig 0.16";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";
  };

  outputs = { self, nixpkgs }:
    let
      # Box3D is portable C17, and these are the systems package.nix asserts and
      # the ones a native build is defined for. A Windows package is not exposed
      # here for two separate reasons, and neither of them is a workaround: the
      # derivation builds for the compiler's own native target rather than a
      # hand-assembled cross triple, and on Windows `BOX3D_EXPORT` resolves from
      # `box3d_EXPORTS`/`BOX3D_DLL` with no way to select dllexport and
      # dllimport from one value (`include/box3d/base.h:21-35`), so a Windows
      # shared variant needs its own export story before it can be packaged.
      # The Windows *compile* check is a different thing and is in the matrix in
      # README.md.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs:
        let
          mk = linkage: pkgs.callPackage ./package.nix {
            inherit linkage;
            zig = pkgs.zig_0_16;
          };
        in
        {
          # The SDK's existing linkage policy: this fork builds a static library
          # by default, and `default` stays that way.
          static = mk "static";

          # A separate variant of the same derivation, not a second SDK.
          # "shared" names the artefact; the flag it passes is Zig's own
          # `-Dlinkage=dynamic`.
          shared = mk "dynamic";

          default = mk "static";
        });

      # Parity only. The canonical development environment is devenv.nix.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.zig_0_16 pkgs.gnumake pkgs.pkg-config ];
        };
      });
    };
}