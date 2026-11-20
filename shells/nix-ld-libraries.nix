# The libraries nix-ld offers binaries linked for a usual Linux: Gradle's
# aapt2 and Robolectric's native runtime, foojay JDKs, uv's CPython builds
# with the PyQt6 wheels Anki and aqt load, Playwright's Chromium and rustup
# toolchains. Used by the NixOS module and the dev images.
pkgs:
with pkgs; [
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
]
