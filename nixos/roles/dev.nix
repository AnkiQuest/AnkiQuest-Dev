# What every AnkiQuest checkout needs from the system: flakes, direnv with
# nix-direnv for the per-repository .envrc, nix-ld for the binaries Gradle,
# npm and uv download, git and the GitHub CLI. Exported as
# nixosModules.ankiquest-dev together with ../modules/dev-shells.nix.
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.ankiquest.dev;
  cache = import ../../cache.nix;
in {
  options.ankiquest.dev.direnv = lib.mkOption {
    type = lib.types.enum ["system" "user"];
    default = "system";
    description = ''
      Who sets up direnv and nix-direnv: "system" enables them here for every
      shell; "user" leaves them to the user's own configuration, such as
      home-manager's programs.direnv.
    '';
  };

  config = {
    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      # The shells' prebuilt closures from AnkiQuest's Cachix cache.
      extra-substituters = [cache.substituter];
      extra-trusted-public-keys = [cache.publicKey];
    };

    programs = {
      direnv = lib.mkIf (cfg.direnv == "system") {
        enable = true;
        nix-direnv.enable = true;
      };

      git = {
        enable = true;
        lfs.enable = true;
      };

      # Binaries linked for a usual Linux; the dev images carry the same
      # libraries.
      nix-ld = {
        enable = true;
        libraries = import ../../shells/nix-ld-libraries.nix pkgs;
      };
    };

    environment.systemPackages = with pkgs; [
      curl
      gh
      jq
      ripgrep
      unzip
      wget
    ];
  };
}
