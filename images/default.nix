# Docker images of the dev shells, built without a Dockerfile. Each holds one
# shell's environment as `nix develop` sets it up, a non-root user `dev` and
# /work as the working directory:
#
#   docker run -it -v "$PWD:/work" ghcr.io/ankiquest/ankiquest-dev-android
#
# Binaries that Gradle, npm and uv download run through nix-ld, with the
# same libraries as the NixOS module.
{
  pkgs,
  lib,
  shells,
}: let
  # The shells published as images. android-emulator needs KVM and a display,
  # android-backend is built on the machines that publish it, and default is
  # this repository's own.
  published = ["server" "desktop" "android" "anki"];

  user = "dev";
  uid = 1000;
  home = "/home/${user}";
  bash = pkgs.bashInteractive;
  certs = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  # What an interactive container needs besides the shell's own tools.
  base = with pkgs; [
    bash
    cacert
    coreutils
    curl
    diffutils
    findutils
    gawk
    git
    gnugrep
    gnused
    gnutar
    gzip
    less
    openssh
    procps
    unzip
    which
    xz
  ];

  # nix-ld in place of the usual dynamic loader, as on NixOS.
  loader =
    if pkgs.stdenv.hostPlatform.isx86_64
    then "lib64/ld-linux-x86-64.so.2"
    else "lib/ld-linux-aarch64.so.1";
  nixLdEnv = {
    NIX_LD = pkgs.stdenv.cc.bintools.dynamicLinker;
    NIX_LD_LIBRARY_PATH = lib.makeLibraryPath (import ../shells/nix-ld-libraries.nix pkgs);
  };

  # Variables stdenv sets for building, not for a shell.
  buildOnly = [
    "HOME"
    "NIX_BUILD_CORES"
    "NIX_BUILD_TOP"
    "NIX_ENFORCE_PURITY"
    "NIX_LOG_FD"
    "NIX_SSL_CERT_FILE"
    "OLDPWD"
    "PWD"
    "SHLVL"
    "SOURCE_DATE_EPOCH"
    "SSL_CERT_FILE"
    "TEMP"
    "TEMPDIR"
    "TERM"
    "TMP"
    "TMPDIR"
    "buildPhase"
    "builder"
    "name"
    "out"
    "outputs"
    "phases"
    "shellHook"
  ];

  # The shell's environment after stdenv's setup hooks ran (PATH,
  # PKG_CONFIG_PATH, the shell's own variables), as exports, followed by
  # its shellHook. The same as `nix develop`, without bash functions.
  capture = name: shell:
    shell.overrideAttrs (_: {
      name = "ankiquest-${name}-env";
      buildPhase = ''
        target=$out
        hook=$shellHook
        (
          unset ${toString buildOnly}
          export -p
        ) > "$target"
        printf '%s\n' "$hook" >> "$target"
      '';
    });

  # Sourced by the entrypoint and by bash's rc file, once per process tree.
  envScript = name: shell:
    pkgs.writeText "ankiquest-${name}-env.sh" ''
      if [ -n "''${ANKIQUEST_SHELL:-}" ]; then
        return 0
      fi
      source ${capture name shell}
      export PATH="$PATH:${lib.makeBinPath base}"
      export HOME=${home} USER=${user} SHELL=${bash}/bin/bash
      # The compiler wrappers expect a build directory.
      export NIX_BUILD_TOP=/tmp TMPDIR=/tmp
      export SSL_CERT_FILE=${certs} NIX_SSL_CERT_FILE=${certs}
      export NIX_LD=${nixLdEnv.NIX_LD} NIX_LD_LIBRARY_PATH=${nixLdEnv.NIX_LD_LIBRARY_PATH}
      export ANKIQUEST_SHELL=${name}
    '';

  mkImage = name: shell: labels: let
    env = envScript name shell;
    entrypoint = pkgs.writeShellScript "ankiquest-entrypoint" ''
      source /etc/ankiquest/env.sh
      exec "$@"
    '';
    users = pkgs.dockerTools.fakeNss.override {
      extraPasswdLines = ["${user}:x:${toString uid}:${toString uid}::${home}:${bash}/bin/bash"];
      extraGroupLines = ["${user}:x:${toString uid}:"];
    };
  in
    pkgs.dockerTools.streamLayeredImage {
      name = "ankiquest-dev-${name}";
      tag = "nightly";
      contents = base ++ [users pkgs.dockerTools.usrBinEnv pkgs.dockerTools.binSh];

      # Writable /tmp, the user's home with an rc file that loads the
      # environment, /work, and nix-ld as the system's dynamic loader.
      fakeRootCommands = ''
        mkdir -p tmp work .${home} etc/ankiquest $(dirname ${loader})
        chmod 1777 tmp
        ln -s ${env} etc/ankiquest/env.sh
        echo 'source /etc/ankiquest/env.sh' > .${home}/.bashrc
        ln -s ${pkgs.nix-ld}/libexec/nix-ld ${loader}
        chown -R ${toString uid}:${toString uid} work .${home}
      '';

      # Env makes the tools reachable for processes that skip the entrypoint,
      # such as `docker exec` and dev container tooling.
      config = {
        User = user;
        WorkingDir = "/work";
        Entrypoint = [entrypoint];
        Cmd = ["${bash}/bin/bash"];
        Env = lib.mapAttrsToList (k: v: "${k}=${v}") ({
            PATH = lib.makeBinPath (shell.nativeBuildInputs ++ shell.buildInputs ++ base);
            HOME = home;
            USER = user;
            SSL_CERT_FILE = certs;
            NIX_SSL_CERT_FILE = certs;
          }
          // nixLdEnv);
        Labels =
          {
            "org.opencontainers.image.source" = "https://github.com/AnkiQuest/AnkiQuest-Dev";
            "org.opencontainers.image.description" = "AnkiQuest-Dev ${name} shell";
          }
          // labels;
      };
    };

  # The image labelled with the derivation of the same image without the
  # label: equal labels mean equal images, so the nightly workflow skips
  # rebuilding and pushing a shell whose label matches the last pushed one.
  image = name: let
    shell = shells.${name};
    drv = builtins.unsafeDiscardStringContext (mkImage name shell {}).drvPath;
  in
    mkImage name shell {"org.ankiquest.drv" = drv;} // {ankiquestDrv = drv;};
in
  lib.genAttrs published image
