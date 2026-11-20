# NixOS on WSL with everything the AnkiQuest repositories build with.
{
  self,
  username,
  nixos-wsl,
  ...
}: {
  imports = [
    nixos-wsl.nixosModules.default
    self.nixosModules.ankiquest-dev
  ];

  system.stateVersion = "26.05";

  wsl = {
    enable = true;
    defaultUser = username;
    wslConf.automount.root = "/mnt";
    # The Windows GPU driver, for Anki and the emulator under WSLg.
    useWindowsDriver = true;
  };

  hardware.graphics.enable = true;

  networking.hostName = "ankiquest-wsl";
  time.timeZone = "Europe/Berlin";

  nix = {
    settings = {
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

  # /tmp stays on the WSL disk, not in memory: Gradle, Kotlin and Nix builds
  # put several GB there.
  boot.tmp = {
    useTmpfs = false;
    cleanOnBoot = true;
  };

  ankiquest.dev.shells = ["server" "desktop" "android" "android-backend" "anki"];
}
