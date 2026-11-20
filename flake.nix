{
  description = "AnkiQuest development environment: NixOS on WSL and dev shells";

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
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    rust-overlay,
    ...
  }: let
    lib = nixpkgs.lib;
    username = "hill";

    # WSL runs on x86_64 and on arm64 Windows.
    supportedSystems = ["x86_64-linux" "aarch64-linux"];

    pkgsFor = system:
      import nixpkgs {
        inherit system;
        overlays = [rust-overlay.overlays.default];
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };

    forAllSystems = f:
      lib.genAttrs supportedSystems (system: f (pkgsFor system));

    toolchainsFor = pkgs: import ./shells/toolchains.nix {inherit pkgs lib;};

    shellsFor = pkgs:
      import ./shells {
        inherit pkgs lib;
        toolchains = toolchainsFor pkgs;
      };

    mkNixosConfig = {
      hostName,
      system ? "x86_64-linux",
    }:
      lib.nixosSystem {
        inherit system;
        specialArgs =
          inputs
          // {
            inherit username;
            devShells = self.devShells.${system};
          };
        modules = [
          ./nixos/hosts/${hostName}/configuration.nix
          {nixpkgs.overlays = [rust-overlay.overlays.default];}
        ];
      };
  in {
    formatter = forAllSystems (pkgs: pkgs.alejandra);

    devShells = forAllSystems shellsFor;

    # The pinned toolchains on their own, for other flakes and for
    # `nix build .#android-sdk`.
    packages = forAllSystems (pkgs: let
      toolchains = toolchainsFor pkgs;
    in {
      inherit (toolchains) jbr;
      rust = toolchains.rust.current;
      rust-anki = toolchains.rust.anki;
      android-sdk = toolchains.androidSdk.excluded;
    });

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

    checks = forAllSystems (pkgs:
      {
        formatting =
          pkgs.runCommand "alejandra-check" {
            nativeBuildInputs = [pkgs.alejandra];
            src = self;
          } ''
            alejandra --check "$src"
            touch "$out"
          '';
      }
      # Evaluates each WSL system and its image builder without building
      # them: the store path of the builder's derivation, with the dependency
      # on it dropped.
      // lib.mapAttrs (name: system: let
        drvPath = system.config.system.build.tarballBuilder.drvPath;
      in
        pkgs.writeText "${name}-eval" (builtins.unsafeDiscardStringContext drvPath))
      self.nixosConfigurations);
  };
}
