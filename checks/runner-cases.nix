# The runner routing check accepts runner-cases/good and rejects every
# runner-cases/bad-* workflow directory.
{
  lib,
  callPackage,
  runCommand,
}: let
  cases = ./runner-cases;
  accepts = name: (builtins.tryEval (callPackage ./runners.nix {} (cases + "/${name}")).drvPath).success;
  wrong = builtins.filter (name: accepts name != (name == "good")) (builtins.attrNames (builtins.readDir cases));
in
  assert lib.assertMsg (wrong == []) "runner routing check is wrong for: ${toString wrong}";
    runCommand "runner-routing-cases" {} "touch $out"
