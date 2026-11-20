# The build tools the AnkiQuest repositories pin, in one place. Each value
# names the file in the repository it follows; change both together.
{
  pkgs,
  lib,
}: let
  # crates/rules/rust-toolchain.toml in AnkiQuest-Server. The server and the
  # desktop tools pin nothing and build with it too.
  rustCurrent = "1.100.0";

  # rust-toolchain.toml on the `ankiquest` branches of AnkiQuest/anki and
  # AnkiQuest-Android-Backend.
  rustAnki = "1.97.1";

  # The Android ABIs both cargo-ndk builds (rules libraries and the backend)
  # produce.
  androidRustTargets = [
    "aarch64-linux-android"
    "armv7-linux-androideabi"
    "i686-linux-android"
    "x86_64-linux-android"
  ];

  # compileSdk across the Android repositories: 33 (AnkiQuestconnectAndroid),
  # 36 (ankiquest-android-mcp, garmankiquest, AnkiQuest-Android-Backend) and
  # 37.0 (AnkiQuest-Android, compileSdk 37 with compileSdkMinor 0).
  androidPlatforms = ["33" "36" "37.0"];

  # The build tools each AGP in use defaults to (35.0.0 for AGP 8.10 and 8.13,
  # 36.0.0 for AGP 9.4) and SDK_BUILD_TOOLS_VERSION in AnkiQuest-Android's
  # .github/workflows/tests_emulator.yml.
  androidBuildTools = ["35.0.0" "36.0.0" "37.0.0"];
  aapt2BuildTools = "37.0.0";

  # NDK r28c: NDK_VERSION in AnkiQuest-Server .github/workflows/rules.yml.
  ndkRules = "28.2.13676358";
  # NDK r29: `ndk` in AnkiQuest-Android-Backend gradle/libs.versions.toml.
  ndkBackend = "29.0.14206865";

  # The system image the optional emulator runs.
  emulatorImage = {
    platform = "36";
    type = "google_apis";
  };

  # gradle/gradle-daemon-jvm.properties asks for a JetBrains 21 runtime and
  # nixpkgs only builds the newest JBR, so take JetBrains' own build. The same
  # build and hashes as AnkiQuest-Android's flake.nix.
  jbrBuild = "21.0.11-b1163.125";
  jbrDownloads = {
    x86_64-linux = {
      arch = "linux-x64";
      hash = "sha256-JV5HF1hj7XvhCNo+rjEz6PGnjv9H+TjUR6zsEaVVaxQ=";
    };
    aarch64-linux = {
      arch = "linux-aarch64";
      hash = "sha256-bC0WkbHeSFrc5aSKzlPMbTY46gNqfk8ASzdnksPzaMI=";
    };
  };

  # One toolchain with the given extra targets.
  rustWith = version: targets:
    pkgs.rust-bin.stable.${version}.minimal.override {
      extensions = ["clippy" "rustfmt" "rust-src" "rust-analyzer"];
      inherit targets;
    };

  # The SDK with or without the emulator, which is several GB and only runs
  # under WSL with nested virtualisation.
  androidSdkWith = emulator: let
    withEmulator =
      {
        excluded = false;
        included = true;
      }
      .${
        emulator
      };
  in
    (pkgs.androidenv.composeAndroidPackages {
      platformVersions = androidPlatforms;
      buildToolsVersions = androidBuildTools;
      includeNDK = true;
      ndkVersions = [ndkRules ndkBackend];
      includeEmulator = withEmulator;
      includeSystemImages = withEmulator;
      systemImageTypes = [emulatorImage.type];
      abiVersions = [
        {
          x86_64-linux = "x86_64";
          aarch64-linux = "arm64-v8a";
        }
        .${
          pkgs.stdenv.hostPlatform.system
        }
      ];
    })
    .androidsdk;

  jbr = let
    download = jbrDownloads.${pkgs.stdenv.hostPlatform.system};
    version = lib.head (lib.splitString "-" jbrBuild);
    build = lib.last (lib.splitString "-" jbrBuild);
  in
    pkgs.stdenv.mkDerivation {
      pname = "jbrsdk";
      version = jbrBuild;
      src = pkgs.fetchurl {
        url = "https://cache-redirector.jetbrains.com/intellij-jbr/jbrsdk-${version}-${download.arch}-${build}.tar.gz";
        inherit (download) hash;
      };
      nativeBuildInputs = [pkgs.autoPatchelfHook];
      buildInputs = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        alsa-lib
        freetype
        fontconfig
        libx11
        libxext
        libxi
        libxrender
        libxtst
        wayland
      ];
      # Only the desktop and debugger libraries miss anything; Gradle needs
      # none of them.
      autoPatchelfIgnoreMissingDeps = true;
      dontStrip = true;
      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -r . $out/
        runHook postInstall
      '';
    };
in {
  inherit jbr aapt2BuildTools ndkRules ndkBackend;

  rust = {
    current = rustWith rustCurrent (["wasm32-unknown-unknown"] ++ androidRustTargets);
    anki = rustWith rustAnki androidRustTargets;
  };

  androidSdk = {
    excluded = androidSdkWith "excluded";
    included = androidSdkWith "included";
  };
}
