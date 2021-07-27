{
  description = "Short-lived VMs for hermetic computation.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, fenix, flake-utils, nixpkgs, pre-commit-hooks }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = nixpkgs.lib;
        fenixPkgs = fenix.packages.${system};
        rustFull = with fenixPkgs; combine [
          (latest.withComponents [
            "cargo"
            "clippy-preview"
            "rust-src"
            "rust-std"
            "rustc"
            "rustfmt-preview"
          ])
        ];
        buildRustPkg = (pkgs.makeRustPlatform { cargo = rustFull; rustc = rustFull; }).buildRustPackage;

        collectInputs = type:
          lib.flatten
            (lib.mapAttrsToList
              (_: drv: drv.${type})
              self.packages.${system}
            )
        ;
      in
      {
        packages.quasar = buildRustPkg {
          pname = "quasar";
          version = "0.1.0";

          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;

          buildInputs = with pkgs; [
            firecracker
          ];
        };

        defaultPackage = self.packages.${system}.quasar;

        devShell = pkgs.mkShell {
          inherit (self.checks.${system}.pre-commit-check) shellHook;

          name = "quasar";

          nativeBuildInputs = with pkgs; (collectInputs "nativeBuildInputs") ++ [
            cargo-edit
            fenixPkgs.rust-analyzer
            nix-linter
            nixpkgs-fmt
          ];

          buildInputs = collectInputs "buildInputs";
        };

        checks.pre-commit-check = (pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            nix-linter.enable = true;
            nixpkgs-fmt.enable = true;
            rustfmt = {
              enable = true;
              entry = lib.mkForce ''
                bash -c 'PATH="${rustFull}/bin" cargo fmt -- --check --color always'
              '';
            };
          };
        });
      });
}
