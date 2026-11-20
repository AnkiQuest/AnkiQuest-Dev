# What the dev container adds to its Ubuntu image: direnv with nix-direnv,
# hooked into bash, so a checkout's .envrc enters its shell as on any other
# machine. Installed into the user's profile by postCreateCommand.
{pkgs}: let
  setup = pkgs.writeShellApplication {
    name = "ankiquest-devcontainer-setup";
    text = ''
      profile="$HOME/.nix-profile"
      mkdir -p "$HOME/.config/direnv"
      echo "source $profile/share/nix-direnv/direnvrc" > "$HOME/.config/direnv/direnvrc"
      if ! grep -q 'direnv hook bash' "$HOME/.bashrc"; then
        echo "eval \"\$($profile/bin/direnv hook bash)\"" >> "$HOME/.bashrc"
      fi
    '';
  };
in
  pkgs.buildEnv {
    name = "ankiquest-devcontainer";
    paths = with pkgs; [direnv nix-direnv gh setup];
  }
