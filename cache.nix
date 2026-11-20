# AnkiQuest's Cachix cache: the nightly workflow pushes the dev shells and
# the WSL image's closure to it. flake.nix's nixConfig repeats these values,
# because Nix reads nixConfig without evaluating anything.
{
  substituter = "https://ankiquest.cachix.org";
  publicKey = "ankiquest.cachix.org-1:dX/Nw24o2NazxbWxwc2Fmav2YpCkBSMiQIpaNHhH4gY=";
}
