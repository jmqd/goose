{
  description = "Goose dev environment";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-intel-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-intel-darwin,
      flake-utils,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      # pkgs/by-name/<shard>/<name>/package.nix, as in nixpkgs, so a package
      # moves upstream by copying its directory.
      byName =
        let
          root = ./pkgs/by-name;
        in
        lib.concatMapAttrs (
          shard: _:
          lib.mapAttrs (name: _: root + "/${shard}/${name}/package.nix") (
            builtins.readDir (root + "/${shard}")
          )
        ) (builtins.readDir root);
    in
    {
      overlays.default = final: _prev: lib.mapAttrs (_: path: final.callPackage path { }) byName;
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        # 26.05 is the last supported nixpkgs release for Intel macOS.
        nixpkgsForSystem = if system == "x86_64-darwin" then nixpkgs-intel-darwin else nixpkgs;
        pkgs = import nixpkgsForSystem {
          inherit system;
          overlays = [ self.overlays.default ];
        };

        packages = lib.filterAttrs (_: lib.meta.availableOn pkgs.stdenv.hostPlatform) (
          lib.mapAttrs (name: _: pkgs.${name}) byName
        );
        goose = packages.goose-compiler;
      in
      {
        packages = packages // {
          default = goose;
        };
        apps.default = flake-utils.lib.mkApp { drv = goose; };

        # Each package, and the passthru.tests nixpkgs' CI would run for it.
        checks =
          packages
          // lib.concatMapAttrs (
            name: pkg: lib.mapAttrs' (test: lib.nameValuePair "${name}-${test}") (pkg.passthru.tests or { })
          ) packages
          // {
            hello-world = pkgs.runCommand "hello-world" { nativeBuildInputs = [ goose ]; } ''
              export HOME=$(mktemp -d)
              [ "$(goose ${./hello_world.goose})" = "Hello, world!" ]
              touch $out
            '';
          };

        formatter = pkgs.nixfmt-tree;

        devShells.default = pkgs.mkShell {
          # mkShell's stdenv already puts a C compiler on PATH for `goose build`.
          packages = with pkgs; [
            goose
            git
            cmake

            # Package maintenance
            nixfmt
            nix-update
          ];
        };
      }
    );
}
