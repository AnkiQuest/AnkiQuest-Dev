# What every AnkiQuest checkout needs from the system: flakes, direnv with
# nix-direnv for the per-repository .envrc, nix-ld for the binaries Gradle,
# npm and uv download, git and the GitHub CLI.
{
  pkgs,
  lib,
  username,
  ...
}: {
  imports = [
    ../modules/dev-shells.nix
  ];

  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["root" username];
      auto-optimise-store = true;
    };
    # nix-direnv roots each repository's shell, so collection only removes
    # shells no checkout uses any more.
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # The Android SDK and the JetBrains runtime are unfree.
  nixpkgs.config = {
    allowUnfree = true;
    android_sdk.accept_license = true;
  };

  programs = {
    direnv = {
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

  # /tmp stays on the WSL disk, not in memory: Gradle, Kotlin and Nix builds
  # put several GB there.
  boot.tmp = {
    useTmpfs = false;
    cleanOnBoot = true;
  };
}
