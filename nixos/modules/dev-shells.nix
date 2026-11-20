# Which dev shells the system keeps built. A kept shell is fetched by
# nixos-rebuild, survives garbage collection and opens offline; any other
# shell is fetched the first time it is entered.
{
  config,
  lib,
  devShells,
  ...
}: let
  cfg = config.ankiquest.dev;
  names = lib.attrNames devShells;
in {
  options.ankiquest.dev.shells = lib.mkOption {
    type = lib.types.listOf (lib.types.enum names);
    default = [];
    example = ["server" "desktop" "android"];
    description = "Dev shells to keep built in the system closure: any of ${lib.concatStringsSep ", " names}.";
  };

  config.system.extraDependencies =
    map (name: devShells.${name}.inputDerivation) cfg.shells;
}
