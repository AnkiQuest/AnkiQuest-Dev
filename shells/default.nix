# The dev shells, one per kind of AnkiQuest repository. Enter one with
# `nix develop .#<name>` or a repository's `.envrc` (see README.md).
{
  pkgs,
  lib,
  toolchains,
}: let
  inherit (toolchains) jbr rust nodejs python;
  inherit (pkgs.stdenv.hostPlatform) isLinux;

  # Gradle may not download a JDK: the ones foojay offers are linked for a
  # usual Linux. The local JBR is the toolchain and the daemon JVM.
  jvmEnv = {
    JAVA_HOME = "${jbr}";
    GRADLE_OPTS = lib.concatStringsSep " " [
      "-Dorg.gradle.java.installations.auto-download=false"
      "-Dorg.gradle.java.installations.paths=${jbr}"
    ];
  };

  # Anki's build downloads node, yarn, protoc and uv unless told where they
  # are. Python stays a uv-managed CPython from .python-version, which runs
  # through nix-ld like the PyQt wheels it loads.
  ankiBuildEnv = {
    NODE_BINARY = lib.getExe nodejs;
    YARN_BINARY = lib.getExe pkgs.yarn-berry;
    PROTOC_BINARY = lib.getExe pkgs.protobuf;
    PROTOC = lib.getExe pkgs.protobuf;
    UV_BINARY = lib.getExe pkgs.uv;
  };

  ankiBuildTools = with pkgs; [
    git
    just
    n2
    ninja
    nodejs
    openssl
    pkg-config
    protobuf
    rsync
    unzip
    uv
    yarn-berry
    zstd
  ];

  # AnkiQuest-Android-Backend's build_rust runs `rustup target add` before
  # cargo-ndk. Here the toolchain is fixed, so only accept targets it has.
  rustupTargets = pkgs.writeShellScriptBin "rustup" ''
    if [ "$1 $2" != "target add" ]; then
      echo "rustup: not used here; AnkiQuest-Dev pins the toolchain" >&2
      exit 1
    fi
    shift 2
    sysroot=$(rustc --print sysroot)
    for target in "$@"; do
      if [ ! -d "$sysroot/lib/rustlib/$target" ]; then
        echo "rustup: target $target is not in the pinned toolchain" >&2
        exit 1
      fi
    done
  '';

  # An Android shell around one of the SDKs in toolchains.androidSdk.
  androidShell = {
    sdk,
    packages ? [],
    env ? {},
  }: let
    sdkPackage = toolchains.androidSdk.${sdk};
    sdkRoot = "${sdkPackage}/libexec/android-sdk";
  in
    pkgs.mkShell (jvmEnv
      // env
      // {
        packages = [jbr sdkPackage nodejs] ++ packages;
        ANDROID_HOME = sdkRoot;
        ANDROID_SDK_ROOT = sdkRoot;
        GRADLE_OPTS = lib.concatStringsSep " " ([jvmEnv.GRADLE_OPTS]
          # The aapt2 AGP fetches from Maven is linked for a usual Linux, so
          # use the SDK's own. On macOS Maven's runs.
          ++ lib.optional isLinux
          "-Dorg.gradle.project.android.aapt2FromMavenOverride=${sdkRoot}/build-tools/${toolchains.aapt2BuildTools}/aapt2");
        # The Rust backend's test library expects libstdc++ and libgcc_s.
        LD_LIBRARY_PATH = lib.optionalString isLinux (lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib]);
        # stdenv sets SOURCE_DATE_EPOCH to 1980 when unset, and Gradle reads
        # it as the build time.
        shellHook = ''
          unset SOURCE_DATE_EPOCH
        '';
      });
in {
  # This repository: formatting and the GitHub CLI.
  default = pkgs.mkShell {
    packages = with pkgs; [alejandra gh nixd];
  };

  # AnkiQuest-Server and AnkiQuest.github.io: the server, the web pages,
  # crates/rules and its Kotlin and Python bindings.
  server = pkgs.mkShell (jvmEnv
    // {
      packages = with pkgs; [
        rust.current
        cargo-ndk
        esbuild
        lld
        nodejs
        pkg-config
        sqlite
        python.server
        uv
        jbr
        gradle_9
      ];
      # build.rs links the translation module for wasm32 with wasm-ld.
      CARGO_TARGET_WASM32_UNKNOWN_UNKNOWN_LINKER = "${pkgs.lld}/bin/wasm-ld";
      LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
    });

  # AnkiQuest-Desktop: the add-on tests, pyflakes, the packager and xtask.
  # Real-Anki tests run in a uv venv from tests/requirements-anki-*.txt.
  desktop = pkgs.mkShell {
    packages = [
      rust.current
      nodejs
      python.desktop
      python.desktop.pkgs.pyflakes
      pkgs.uv
    ];
  };

  # AnkiQuest-Android, ankiquest-android-mcp, AnkiQuestconnectAndroid and
  # garmankiquest's companion: platforms and build tools, no NDK.
  android = androidShell {sdk = "app";};
  android-emulator = androidShell {sdk = "emulator";};

  # AnkiQuest-Android-Backend: the app SDK plus NDK r28c and r29, Rust for
  # the Android targets and Anki's build tools.
  android-backend = androidShell {
    sdk = "backend";
    packages = [rust.anki rustupTargets pkgs.cargo-ndk] ++ ankiBuildTools;
    env =
      ankiBuildEnv
      // {
        ANDROID_NDK_HOME = "${toolchains.androidSdk.backend}/libexec/android-sdk/ndk/${toolchains.ndkBackend}";
      };
  };

  # AnkiQuest/anki: ./ninja, ./run and just.
  anki = pkgs.mkShell (ankiBuildEnv
    // {
      packages = [rust.anki] ++ ankiBuildTools;
    });
}
