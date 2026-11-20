# AnkiQuest-Dev

The development environment for the AnkiQuest repositories, on any machine:
one dev shell per kind of repository, a NixOS-on-WSL system (`ankiquest-wsl`),
modules for NixOS and nix-darwin, a winget configuration for Windows and a dev
container.

| Shell | Repositories | Main tools |
|---|---|---|
| `server` | AnkiQuest-Server, AnkiQuest.github.io | Rust 1.100.0 (wasm32 and Android targets), cargo-ndk, Node 22, esbuild, wasm-ld, SQLite, Python 3.13, uv, JBR 21, Gradle 9 |
| `desktop` | AnkiQuest-Desktop | Rust 1.100.0, Python 3.12, pyflakes, uv, Node 22 |
| `android` | AnkiQuest-Android, ankiquest-android-mcp, AnkiQuestconnectAndroid, garmankiquest (`android/`) | JBR 21, Android SDK (platforms 36, 37.0; build tools 35.0.0, 36.0.0, 37.0.0), Node 22 |
| `android-emulator` | the same | `android` plus the emulator and an Android 36 system image |
| `android-backend` | AnkiQuest-Android-Backend | `android` plus NDK r28c and r29, Rust 1.97.1 (Android targets), cargo-ndk, Anki's build tools |
| `anki` | AnkiQuest/anki | Rust 1.97.1, Node 22, Yarn 4, protoc, uv, n2, ninja, just, rsync |
| `default` | this repository | alejandra, nixd, gh |

AnkiQuest-Sync and AnkiQuest-Agents hold only workflows and Markdown and need
no shell.

Every version is in `shells/toolchains.nix`, next to the repository file it
follows. The shells exist for `x86_64-linux`, `aarch64-linux` and
`aarch64-darwin`. nixpkgs dropped `x86_64-darwin` in 26.11, so Intel Macs use
the dev container.

## Pick a setup

| Machine | Setup | Verify |
|---|---|---|
| Ubuntu, other Linux | [Nix and the shells](#ubuntu-and-other-linux) | `nix develop github:AnkiQuest/AnkiQuest-Dev#desktop --command rustc --version` |
| NixOS | [the NixOS module](#nixos) | `direnv version && nix develop github:AnkiQuest/AnkiQuest-Dev#desktop --command rustc --version` |
| macOS (Apple silicon) | [Nix and the shells](#macos), optionally nix-darwin | `nix develop github:AnkiQuest/AnkiQuest-Dev#desktop --command rustc --version` |
| Windows, WSL | [NixOS on WSL](#install-nixos-on-wsl) | `wsl -d ankiquest -- nix develop github:AnkiQuest/AnkiQuest-Dev#desktop --command rustc --version` |
| Windows, native | [winget](#windows) | `rustup run 1.100.0 rustc --version; node --version; uv python list --only-installed; java -version; & "$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat" --list_installed` |
| Any OS with Docker or Podman | [the dev container](#dev-container) | `nix develop .#desktop --command rustc --version` in the container |

`rustc 1.100.0` from the shell means Nix, the flake and the pinned toolchain
work. Repositories are then cloned and entered as in
[Clone the repositories](#clone-the-repositories) and
[Enter a shell with direnv](#enter-a-shell-with-direnv).

## Ubuntu and other Linux

Install Nix with flakes, then direnv with nix-direnv:

```sh
sh <(curl -L https://nixos.org/nix/install) --daemon
echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf
sudo systemctl restart nix-daemon
nix profile install nixpkgs#direnv nixpkgs#nix-direnv
echo 'source $HOME/.nix-profile/share/nix-direnv/direnvrc' > ~/.config/direnv/direnvrc
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
```

Binaries Gradle, npm and uv download run as they do on any Linux. The emulator
needs `/dev/kvm` (`sudo usermod -aG kvm $USER`).

## macOS

On Apple silicon, install Nix the same way (`sh <(curl -L
https://nixos.org/nix/install)`), add the `experimental-features` line to
`/etc/nix/nix.conf`, and install direnv and nix-direnv as above (`zsh` users
hook `direnv hook zsh` into `~/.zshrc`).

With nix-darwin, import the module instead of installing direnv by hand:

```nix
# flake.nix of your nix-darwin configuration
inputs.ankiquest-dev.url = "github:AnkiQuest/AnkiQuest-Dev";
# in darwinSystem's modules:
inputs.ankiquest-dev.darwinModules.ankiquest-dev
```

It enables flakes, direnv with nix-direnv, git with LFS and gh. Set
`ankiquest.dev.direnv = "user";` when home-manager already sets up direnv. On
macOS Gradle uses AGP's own aapt2; the JBR comes from JetBrains as on Linux.

## NixOS

Import the module in your system flake:

```nix
inputs.ankiquest-dev = {
  url = "github:AnkiQuest/AnkiQuest-Dev";
  inputs.nixpkgs.follows = "nixpkgs";
};
# in nixosSystem's modules:
inputs.ankiquest-dev.nixosModules.ankiquest-dev
{ankiquest.dev.shells = ["server" "android"];}
```

It enables flakes, direnv with nix-direnv, nix-ld with the libraries the
downloaded binaries need, git with LFS, gh and a few command-line tools.
`ankiquest.dev.shells` keeps those shells built (see
[Keep only some shells](#keep-only-some-shells)), and
`ankiquest.dev.direnv = "user"` leaves direnv to home-manager. `ankiquest-wsl`
is this module plus NixOS-WSL.

## Windows

Native Windows uses no Nix: `windows/configuration.dsc.yaml` installs Git,
rustup with the pinned toolchains and targets, Node, uv with the pinned Python
versions, a JDK 21 for Gradle, the Android command-line tools and the SDK
packages the shells carry. The versions are generated from
`shells/toolchains.nix`. In an elevated PowerShell, from a checkout:

```powershell
winget configure --file windows\configuration.dsc.yaml --accept-configuration-agreements
```

Open a new terminal afterwards, so `ANDROID_HOME` and the new `PATH` apply.
Gradle downloads the JetBrains runtime its daemon asks for. Anki's own build
(`./ninja`) and AnkiQuest-Android-Backend's are not set up here; use WSL for
those.

## Dev container

`.devcontainer/` is an Ubuntu image with Nix and direnv from this flake, for
VS Code, JetBrains Gateway, `devcontainer up` or anything else that reads
`devcontainer.json`, on Docker or Podman. Open this repository in it; clone the
other repositories under `/workspaces` and enter them with `.envrc` as below.
The emulator does not run in the container.

## Install NixOS on WSL

On Windows, in PowerShell:

```powershell
wsl --install --no-distribution
wsl --update
```

Then download `ankiquest-wsl.wsl` from the
[nightly release](https://github.com/AnkiQuest/AnkiQuest-Dev/releases/tag/nightly),
built from every commit to `main`, check it against `SHA256SUMS`, and import
it:

```powershell
wsl --install --from-file ankiquest-wsl.wsl --name ankiquest
wsl -d ankiquest
```

The user is `hill`. The image is `ankiquest-wsl-release`: `ankiquest-wsl`
without kept dev shells, to stay under GitHub's 2 GiB asset limit. Each shell
is fetched on its first `nix develop`; to keep all of them built, as
`ankiquest.dev.shells` lists (see below), switch once:

```sh
sudo nixos-rebuild switch --flake github:AnkiQuest/AnkiQuest-Dev#ankiquest-wsl
```

Or build the image yourself on any Linux machine with Nix:

```sh
nix build .#nixosConfigurations.ankiquest-wsl-release.config.system.build.tarballBuilder
sudo ./result/bin/nixos-wsl-tarball-builder ankiquest-wsl.wsl
# install it as above
```

Use `ankiquest-wsl` instead of `ankiquest-wsl-release` for an image with every
shell in `ankiquest.dev.shells` built in; it is several GB and needs the
Android SDK and JetBrains downloads.

### Memory and swap

Gradle (AnkiDroid asks for a 3 GB heap, plus Kotlin and test workers) and the
Anki build need more memory than WSL gives by default. WSL sets memory and swap
from Windows, not from NixOS, in `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
memory=16GB
swap=16GB
processors=8

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
```

Run `wsl --shutdown` after changing it. With 16 GB of RAM or less on the
machine, give WSL half and keep the swap; if Gradle still runs out, add
`org.gradle.workers.max=4` to `~/.gradle/gradle.properties`.

`/tmp` is on the WSL disk, not in memory, and is emptied at boot.

## Clone the repositories

```sh
mkdir -p ~/src && cd ~/src
for repo in AnkiQuest-Server AnkiQuest-Desktop AnkiQuest-Android AnkiQuest-Android-Backend anki \
    ankiquest-android-mcp AnkiQuestconnectAndroid garmankiquest AnkiQuest-Sync AnkiQuest-Agents \
    AnkiQuest.github.io AnkiQuest-Dev; do gh repo clone "AnkiQuest/$repo"; done
git -C anki switch ankiquest
git -C AnkiQuest-Android-Backend switch ankiquest && git -C AnkiQuest-Android-Backend submodule update --init
```

Sign in first with `gh auth login`.

## Enter a shell with direnv

Put one line in an `.envrc` in each checkout and run `direnv allow` there:

| Repository | `.envrc` |
|---|---|
| AnkiQuest-Server, AnkiQuest.github.io | `use flake github:AnkiQuest/AnkiQuest-Dev#server` |
| AnkiQuest-Desktop | `use flake github:AnkiQuest/AnkiQuest-Dev#desktop` |
| AnkiQuest-Android, ankiquest-android-mcp, AnkiQuestconnectAndroid | `use flake github:AnkiQuest/AnkiQuest-Dev#android` |
| AnkiQuest-Android-Backend | `use flake github:AnkiQuest/AnkiQuest-Dev#android-backend` |
| garmankiquest | `use flake github:AnkiQuest/AnkiQuest-Dev#android` |
| anki | `use flake github:AnkiQuest/AnkiQuest-Dev#anki` |
| AnkiQuest-Dev | `use flake` (checked in) |

To try local changes to this repository, use `path:` instead:
`use flake path:$HOME/src/AnkiQuest-Dev#android`. `.envrc` is not ignored in
every repository; add it to `.git/info/exclude` instead of committing it.

Without direnv: `nix develop github:AnkiQuest/AnkiQuest-Dev#android`.

### Notes per repository

- **AnkiQuest-Server.** `crates/rules` builds Android libraries with NDK r28c,
  which only the `android-backend` shell carries. In the `server` shell:
  `export ANDROID_NDK_HOME=$(nix build --no-link --print-out-paths github:AnkiQuest/AnkiQuest-Dev#android-sdk-ndk)/libexec/android-sdk/ndk/28.2.13676358`.
  The binding tests on Python 3.9: `uv run --python 3.9 ...`. CI runs the
  Kotlin bindings with Gradle 9.8.0; nixpkgs has 9.9.
- **AnkiQuest-Desktop.** The add-on tests that load Anki need `aqt` in a venv:
  `uv venv --python 3.12 && uv pip install -r tests/requirements-anki-26.9.4.txt`
  (or `--python 3.9` with `requirements-anki-23.10.txt`), then
  `.venv/bin/python -m unittest discover -s tests`. uv's CPython and the PyQt6
  wheels run through nix-ld.
- **AnkiQuest-Android-Backend.** Its build runs `rustup target add` and
  `cargo install cargo-ndk@4.1.2`. The shell's `rustup` only accepts targets
  the pinned toolchain has; cargo-ndk 4.1.2 is on the path, and `cargo install`
  builds it once more into `~/.cargo/bin`. `ANDROID_NDK_HOME` is NDK r29.
- **anki.** `NODE_BINARY`, `YARN_BINARY`, `PROTOC_BINARY` and `UV_BINARY`
  point at Nix's tools, so `./ninja` downloads none of them. uv still installs
  the CPython `.python-version` names.

## Manual steps

These never go into this or any other repository:

- **Garmin Connect IQ SDK** (garmankiquest `watch/`). Proprietary and not in
  nixpkgs. Download the SDK manager from
  https://developer.garmin.com/connect-iq/sdk/, install SDK 9.x to
  `~/connectiq-sdk`, and add its `bin` to `PATH` as garmankiquest's
  `CLAUDE.md` says. Its binaries run through nix-ld; the simulator needs WSLg.
  `watch/developer_key` is yours to generate and keep.
- **Signing keys and service files**: release keystores,
  `keystore.properties`, `google-services.json`, Play and Maven Central
  credentials. Copy them in from your password manager.
- **`gh auth login`** and your git identity.

## Keep only some shells

`ankiquest.dev.shells` in `nixos/hosts/ankiquest-wsl/configuration.nix` lists
the shells the system keeps built: `nixos-rebuild` fetches them, garbage
collection keeps them and they open offline. Any other shell is fetched when
first entered. A weekly collection removes anything older than 14 days that no
system generation or direnv checkout uses.

## Update the pins

- **nixpkgs, NixOS-WSL, rust-overlay**: `nix flake update <input>`, then
  `nix flake check` and commit `flake.lock`. rust-overlay has to be new enough
  to know a Rust version before `shells/toolchains.nix` can name it.
- **Rust, Android SDK, NDK, JBR, Node, Python**: change the value in
  `shells/toolchains.nix` when the file named in its comment changes, then
  regenerate the Windows configuration:
  `cp $(nix build --no-link --print-out-paths .#windows-configuration) windows/configuration.dsc.yaml`
  (`checks.windows-configuration` fails until they match). For a new JBR build, set
  `jbrBuild`, put `lib.fakeHash` in the hashes, and copy the hashes `nix build
  .#jbr` reports (do this on x86_64 and arm64, or with
  `nix store prefetch-file`).
- **Node, Python, Gradle, protoc and the rest** come from nixpkgs and move with
  `nix flake update nixpkgs`.

Then `nix flake check --all-systems`, `nix fmt`, and enter each shell you
touched.

## Other flakes

The other AnkiQuest repositories take their shells and formatter from here
instead of pinning their own:

```nix
inputs.ankiquest-dev = {
  url = "github:AnkiQuest/AnkiQuest-Dev";
  inputs.nixpkgs.follows = "nixpkgs";
};
# outputs:
devShells = ankiquest-dev.devShells;            # or pick one: .${system}.android
formatter = ankiquest-dev.formatter;
checks.${system}.formatting = ankiquest-dev.lib.formatCheck pkgs ./.;
```

`overlays.default` adds the pinned toolchains as `pkgs.ankiquest` (`jbr`,
`rust.current`, `rust.anki`, `androidSdk.{app,emulator,backend}`), and
`lib.versions` holds the pins as plain values.
