{
  description = "AnkiQuest development environment: dev shells, NixOS on WSL, NixOS and nix-darwin modules";

  inputs = {
    # The channel tarball of nixos-unstable, the same nixpkgs float3/nixos
    # locks.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

    nixos-wsl = {
      url = "git+https://github.com/nix-community/NixOS-WSL?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Rust toolchains at the exact versions the repositories pin.
    rust-overlay = {
      url = "git+https://github.com/oxalica/rust-overlay?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Intel Macs only: nixpkgs 26.11 dropped x86_64-darwin, and 26.05 is the
    # last release that builds it (supported until the end of 2026).
    nixpkgs-x86_64-darwin.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz";

    # Only for checks.darwin-module, which evaluates darwinModules on a
    # nix-darwin system. Consumers of the module bring their own.
    nix-darwin = {
      url = "git+https://github.com/nix-darwin/nix-darwin?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-x86_64-darwin,
    rust-overlay,
    nix-darwin,
    ...
  }: let
    lib = nixpkgs.lib;
    username = "hill";

    # Linux (also WSL, arm64 Windows and the dev container), Apple silicon
    # and Intel Macs. Intel Macs take their packages from
    # nixpkgs-x86_64-darwin.
    supportedSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];

    nixpkgsFor = system:
      {x86_64-darwin = nixpkgs-x86_64-darwin;}.${system} or nixpkgs;

    # rust-overlay plus the pinned toolchains as pkgs.ankiquest.
    overlay = lib.composeExtensions rust-overlay.overlays.default (final: _: {
      ankiquest = import ./shells/toolchains.nix {
        pkgs = final;
        inherit (final) lib;
      };
    });

    pkgsFor = system:
      import (nixpkgsFor system) {
        inherit system;
        overlays = [overlay];
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
          # 26.05 warns on every evaluation for x86_64-darwin otherwise.
          allowDeprecatedx86_64Darwin = true;
        };
      };

    forAllSystems = f:
      lib.genAttrs supportedSystems (system: f (pkgsFor system));

    shellsFor = pkgs:
      import ./shells {
        inherit pkgs lib;
        toolchains = pkgs.ankiquest;
      };

    # alejandra over a source tree, for other flakes' checks.
    formatCheck = pkgs: src:
      pkgs.runCommand "alejandra-check" {
        nativeBuildInputs = [pkgs.alejandra];
        inherit src;
      } ''
        alejandra --check "$src"
        touch "$out"
      '';

    # The store path of a derivation as a check, without building it.
    evalCheck = pkgs: name: drv:
      pkgs.writeText "${name}-eval" (builtins.unsafeDiscardStringContext drv.drvPath);

    mkNixosConfig = {
      hostName,
      system ? "x86_64-linux",
    }:
      lib.nixosSystem {
        inherit system;
        specialArgs = inputs // {inherit username;};
        modules = [./nixos/hosts/${hostName}/configuration.nix];
      };
  in {
    # For other flakes: the systems the shells exist for, the pins as plain
    # values, the formatter check, and the toolchains as an overlay
    # (pkgs.ankiquest).
    lib = {
      inherit formatCheck;
      systems = supportedSystems;
      versions = (pkgsFor "x86_64-linux").ankiquest.versions;
    };

    overlays.default = overlay;

    # The package sets the shells use, with the overlay: nixpkgs 26.11, or
    # 26.05 on x86_64-darwin. Other flakes that loop over lib.systems take
    # pkgs from here, since their own nixpkgs cannot evaluate x86_64-darwin.
    legacyPackages = forAllSystems (pkgs: pkgs);

    formatter = forAllSystems (pkgs: pkgs.alejandra);

    devShells = forAllSystems shellsFor;

    # The pinned toolchains on their own, for other flakes and for
    # `nix build .#android-sdk`; the generated Windows configuration; the
    # dev container's profile.
    packages = forAllSystems (pkgs: let
      toolchains = pkgs.ankiquest;
    in {
      inherit (toolchains) jbr;
      rust = toolchains.rust.current;
      rust-anki = toolchains.rust.anki;
      android-sdk = toolchains.androidSdk.app;
      android-sdk-ndk = toolchains.androidSdk.backend;
      windows-configuration = import ./windows {
        inherit pkgs lib toolchains;
      };
      devcontainer = import ./.devcontainer {inherit pkgs;};
    });

    # What a machine needs for the AnkiQuest checkouts: flakes, direnv, git,
    # gh and, on NixOS, nix-ld and kept dev shells (ankiquest.dev.shells).
    nixosModules = {
      ankiquest-dev = {
        imports = [
          ./nixos/roles/dev.nix
          (import ./nixos/modules/dev-shells.nix self.devShells)
        ];
      };
      default = self.nixosModules.ankiquest-dev;
    };

    darwinModules = {
      ankiquest-dev = ./darwin/module.nix;
      default = self.darwinModules.ankiquest-dev;
    };

    nixosConfigurations = {
      ankiquest-wsl = mkNixosConfig {hostName = "ankiquest-wsl";};

      # The image the nightly release publishes: ankiquest-wsl without kept
      # dev shells, so the .wsl file stays under GitHub's 2 GiB asset limit.
      # Shells build on first `nix develop`, or all at once after
      # `nixos-rebuild switch` to ankiquest-wsl.
      ankiquest-wsl-release = self.nixosConfigurations.ankiquest-wsl.extendModules {
        modules = [{ankiquest.dev.shells = lib.mkForce [];}];
      };
    };

    checks = forAllSystems (pkgs: {
      formatting = formatCheck pkgs self;

      # No job can send pull_request code to the self-hosted runners.
      runner-routing = pkgs.callPackage ./checks/runners.nix {} ./.github/workflows;
      runner-routing-cases = pkgs.callPackage ./checks/runner-cases.nix {};

      # The checked-in Windows configuration is the generated one.
      windows-configuration = pkgs.runCommand "windows-configuration-check" {} ''
        diff -u ${./windows/configuration.dsc.yaml} ${self.packages.${pkgs.stdenv.hostPlatform.system}.windows-configuration}
        touch "$out"
      '';

      # The WSL systems' image builders and a nix-darwin system with the
      # module, evaluated without building them.
      ankiquest-wsl = evalCheck pkgs "ankiquest-wsl" self.nixosConfigurations.ankiquest-wsl.config.system.build.tarballBuilder;
      ankiquest-wsl-release = evalCheck pkgs "ankiquest-wsl-release" self.nixosConfigurations.ankiquest-wsl-release.config.system.build.tarballBuilder;
      darwin-module =
        evalCheck pkgs "darwin-module"
        (nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            self.darwinModules.ankiquest-dev
            {system.stateVersion = 6;}
          ];
        }).system;
    });
  };
}
