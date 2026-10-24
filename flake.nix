{
  description = "Goose dev environment";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-intel-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    flake-utils.url = "github:numtide/flake-utils";

    # Goose development moved into Perennial; the `lean` branch is primary.
    # flake.lock pins the revision, so `nix flake update perennial` bumps the
    # goose translator and the Lean toolchain it targets together.
    perennial = {
      url = "github:mit-pdos/perennial/lean";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-intel-darwin,
      flake-utils,
      perennial,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        # 26.05 is the last supported nixpkgs release for Intel macOS.
        nixpkgsForSystem = if system == "x86_64-darwin" then nixpkgs-intel-darwin else nixpkgs;
        pkgs = import nixpkgsForSystem { inherit system; };

        # Perennial's go.mod requires Go 1.26.
        go = pkgs.go_1_26;
        buildGoModule = pkgs.buildGo126Module;

        # The Lean release Perennial's proofs elaborate with. elan installs it
        # on demand from a project's `lean-toolchain`; this is the version a
        # project depending on Perennial should pin.
        leanToolchain = pkgs.lib.trim (builtins.readFile "${perennial}/lean-toolchain");

        goose = buildGoModule {
          pname = "goose";
          version = "0-unstable-${perennial.lastModifiedDate}";
          src = perennial;

          vendorHash = "sha256-TCyayL7bhLYNXkNxc/mJJ+WmAhJGa/MS1pENMxzAhzk=";

          # go.work pulls in the testdata modules, which the CLIs don't need.
          env.GOWORK = "off";
          subPackages = [
            "goose/cmd/goose"
            "goose/cmd/proofgen"
          ];

          # The translator's tests compare against gold files across the whole
          # workspace; run them from a Perennial checkout instead.
          doCheck = false;

          meta = {
            description = "Translate a subset of Go into GooseLang for Perennial";
            homepage = "https://github.com/mit-pdos/perennial/tree/lean/goose";
            license = pkgs.lib.licenses.mit;
            mainProgram = "goose";
          };
        };
      in
      {
        packages.default = goose;
        apps.default = flake-utils.lib.mkApp { drv = goose; };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            go
            goose
            elan
            git
            python3 # Perennial's etc/*.py helpers (update-goose-new.py, gen-link.py)

            # Go checks / lints / tools
            gopls
            gotools
            golangci-lint
            delve
            just
          ];

          shellHook = ''
            # Use the pinned Go; never let `go` download another toolchain.
            export GOTOOLCHAIN=local
            export PERENNIAL_LEAN_TOOLCHAIN=${leanToolchain}
          '';
        };
      }
    );
}
