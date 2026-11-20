# The build tools the AnkiQuest repositories pin, in one place. Each value
# names the file in the repository it follows; change both together, then
# regenerate windows/configuration.dsc.yaml (see README.md).
{
  pkgs,
  lib,
}: let
  inherit (pkgs.stdenv.hostPlatform) system isLinux;

  # crates/rules/rust-toolchain.toml in AnkiQuest-Server. The server and the
  # desktop tools pin nothing and build with it too.
  rustCurrent = "1.100.0";

  # rust-toolchain.toml on the `ankiquest` branches of AnkiQuest/anki and
  # AnkiQuest-Android-Backend.
  rustAnki = "1.97.1";

  rustComponents = ["clippy" "rustfmt" "rust-src" "rust-analyzer"];

  # The Android ABIs both cargo-ndk builds (rules libraries and the backend)
  # produce.
  androidRustTargets = [
    "aarch64-linux-android"
    "armv7-linux-androideabi"
    "i686-linux-android"
    "x86_64-linux-android"
  ];

  # compileSdk across the Android repositories: 36 (AnkiQuestconnectAndroid,
  # ankiquest-android-mcp, AnkiQuest-Android-Backend) and 37.0
  # (AnkiQuest-Android, compileSdk 37 with compileSdkMinor 0; garmankiquest,
  # compileSdk 37).
  androidPlatforms = ["36" "37.0"];

  # The build tools each AGP in use defaults to (35.0.0 for AGP 8.10 and 8.13,
  # 36.0.0 for AGP 9.4 and 9.5) and SDK_BUILD_TOOLS_VERSION in
  # AnkiQuest-Android's .github/workflows/tests_emulator.yml.
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

  # Node: setup-node in AnkiQuest-Server's and AnkiQuest-Desktop's CI. Python:
  # the server's bindings test on 3.13, the add-on on Anki 26.9's 3.12.
  nodejs = pkgs.nodejs_22;
  python = {
    server = pkgs.python313;
    desktop = pkgs.python312;
  };

  # gradle/gradle-daemon-jvm.properties asks for a JetBrains 21 runtime and
  # nixpkgs only builds the newest JBR, so take JetBrains' own build. The same
  # build and hashes as AnkiQuest-Android's flake.nix had. nixpkgs no longer
  # supports x86_64-darwin, so there is no osx-x64 entry.
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
    aarch64-darwin = {
      arch = "osx-aarch64";
      hash = "sha256-bBpsT5NDwIUmzHh/OGd7WpiSgbeb9e5emy//2iVdZEE=";
    };
  };

  # One toolchain with the given extra targets.
  rustWith = version: targets:
    pkgs.rust-bin.stable.${version}.minimal.override {
      extensions = rustComponents;
      inherit targets;
    };

  # The SDK for one kind of Android repository. The NDKs (backend and rules
  # libraries) and the emulator are several GB each, so only the shells that
  # need them carry them.
  androidSdkWith = {
    ndk,
    emulator,
  }: let
    included = {
      excluded = false;
      included = true;
    };
  in
    (pkgs.androidenv.composeAndroidPackages {
      platformVersions = androidPlatforms;
      buildToolsVersions = androidBuildTools;
      includeNDK = included.${ndk};
      ndkVersions = [ndkRules ndkBackend];
      includeEmulator = included.${emulator};
      includeSystemImages = included.${emulator};
      systemImageTypes = [emulatorImage.type];
      abiVersions = [
        {
          x86_64-linux = "x86_64";
          aarch64-linux = "arm64-v8a";
          aarch64-darwin = "arm64-v8a";
        }
        .${
          system
        }
      ];
    })
    .androidsdk;

  jbr = let
    download = jbrDownloads.${system};
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
      nativeBuildInputs = lib.optional isLinux pkgs.autoPatchelfHook;
      buildInputs = lib.optionals isLinux (with pkgs; [
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
      ]);
      # Only the desktop and debugger libraries miss anything; Gradle needs
      # none of them.
      autoPatchelfIgnoreMissingDeps = true;
      dontStrip = true;
      # The macOS archive is a bundle; JAVA_HOME is its Contents/Home.
      installPhase = ''
        runHook preInstall
        mkdir -p $out
        if [ -d Contents/Home ]; then cp -r Contents/Home/. $out/; else cp -r . $out/; fi
        runHook postInstall
      '';
    };
in {
  inherit jbr aapt2BuildTools ndkRules ndkBackend nodejs python;

  rust = {
    current = rustWith rustCurrent (["wasm32-unknown-unknown"] ++ androidRustTargets);
    anki = rustWith rustAnki androidRustTargets;
  };

  androidSdk = {
    app = androidSdkWith {
      ndk = "excluded";
      emulator = "excluded";
    };
    emulator = androidSdkWith {
      ndk = "excluded";
      emulator = "included";
    };
    backend = androidSdkWith {
      ndk = "included";
      emulator = "excluded";
    };
  };

  # The same pins as plain values, for the Windows configuration and other
  # tools that are not Nix.
  versions = {
    rust = {
      current = rustCurrent;
      anki = rustAnki;
      components = rustComponents;
      targets = {
        current = ["wasm32-unknown-unknown"] ++ androidRustTargets;
        anki = androidRustTargets;
      };
    };
    android = {
      platforms = androidPlatforms;
      buildTools = androidBuildTools;
      ndk = [ndkRules ndkBackend];
    };
    jdk = lib.versions.major (lib.head (lib.splitString "-" jbrBuild));
    node = lib.versions.major nodejs.version;
    python = map (p: lib.versions.majorMinor p.version) [python.server python.desktop];
  };
}
