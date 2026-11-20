# Which dev shells the system keeps built. A kept shell is fetched by
# nixos-rebuild, survives garbage collection and opens offline; any other
# shell is fetched the first time it is entered. Takes the flake's devShells
# first, so the module carries them to other flakes.
devShells: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ankiquest.dev;

  # The shell names are the same on every system.
  names = lib.attrNames (lib.head (lib.attrValues devShells));
  shells = devShells.${pkgs.stdenv.hostPlatform.system};
in {
  options.ankiquest.dev.shells = lib.mkOption {
    type = lib.types.listOf (lib.types.enum names);
    default = [];
    example = ["server" "desktop" "android"];
    description = "Dev shells to keep built in the system closure: any of ${lib.concatStringsSep ", " names}.";
  };

  config.system.extraDependencies =
    map (name: shells.${name}.inputDerivation) cfg.shells;
}
