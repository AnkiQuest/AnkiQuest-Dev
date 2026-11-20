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
    nix.settings.experimental-features = ["nix-command" "flakes"];

    programs = {
      direnv = lib.mkIf (cfg.direnv == "system") {
        enable = true;
        nix-direnv.enable = true;
      };

      git = {
        enable = true;
        lfs.enable = true;
      };

      # Gradle's aapt2 and Robolectric's native runtime, foojay JDKs, uv's
      # CPython builds with the PyQt6 wheels Anki and aqt load, Playwright's
      # Chromium and rustup toolchains are all linked for a usual Linux.
      nix-ld = {
        enable = true;
        libraries = with pkgs; [
          alsa-lib
          at-spi2-atk
          cairo
          cups
          dbus
          expat
          fontconfig
          freetype
          glib
          icu
          krb5
          libdrm
          libGL
          libgbm
          libpulseaudio
          libuuid
          libx11
          libxcb
          libxcb-cursor
          libxcb-image
          libxcb-keysyms
          libxcb-render-util
          libxcb-wm
          libxcomposite
          libxcursor
          libxdamage
          libxext
          libxfixes
          libxi
          libxkbcommon
          libxkbfile
          libxrandr
          libxrender
          libxshmfence
          libxtst
          nspr
          nss
          openssl
          pango
          portaudio
          stdenv.cc.cc.lib
          systemd
          wayland
          zlib
          zstd
        ];
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
