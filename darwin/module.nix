# nix-darwin: what every AnkiQuest checkout needs from a Mac, the same as
# nixosModules.ankiquest-dev without nix-ld, which macOS does not need.
# Shells are fetched the first time they are entered and rooted by
# nix-direnv.
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.ankiquest.dev;
  cache = import ../cache.nix;
in {
  options.ankiquest.dev.direnv = lib.mkOption {
    type = lib.types.enum ["system" "user"];
    default = "system";
    description = ''
      Who sets up direnv and nix-direnv: "system" enables them here; "user"
      leaves them to the user's own configuration, such as home-manager.
    '';
  };

  config = {
    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      # AnkiQuest's Cachix cache; it holds Linux builds only so far.
      extra-substituters = [cache.substituter];
      extra-trusted-public-keys = [cache.publicKey];
    };

    programs.direnv = lib.mkIf (cfg.direnv == "system") {
      enable = true;
      nix-direnv.enable = true;
    };

    environment.systemPackages = with pkgs; [
      gh
      git
      git-lfs
      jq
      ripgrep
    ];
  };
}
