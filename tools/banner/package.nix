# ankiquest-banner: draws and checks a repository's README banner and
# social preview. Building it runs its tests.
{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "ankiquest-banner";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
      ./fonts
    ];
  };
  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Draws and checks an AnkiQuest repository's README banner and social preview";
    license = lib.licenses.agpl3Plus;
    mainProgram = "ankiquest-banner";
  };
}
