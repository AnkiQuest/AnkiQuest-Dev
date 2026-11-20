# NixOS on WSL with everything the AnkiQuest repositories build with.
{
  username,
  nixos-wsl,
  ...
}: {
  imports = [
    nixos-wsl.nixosModules.default
    ../../roles/dev.nix
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

  ankiquest.dev.shells = ["server" "desktop" "android" "anki"];
}
