# AnkiQuest-Dev

The development environment for the AnkiQuest repositories, on any machine:
one dev shell per kind of repository, a NixOS-on-WSL system (`ankiquest-wsl`),
modules for NixOS and nix-darwin, a winget configuration for Windows and a dev
container.

| Shell | Repositories | Main tools |
|---|---|---|
| `server` | AnkiQuest-Server | Rust 1.100.0 (wasm32 and Android targets), cargo-ndk, Node 22, esbuild, wasm-ld, SQLite, Python 3.13, uv, JBR 21, Gradle 9 |
| `desktop` | AnkiQuest-Desktop | Rust 1.100.0, Python 3.12, pyflakes, uv, Node 22 |
| `android` | AnkiQuest-Android, AnkiQuest-Android-MCP, AnkiQuest-AnkiConnectAndroid, AnkiQuest-GarmAnki (`android/`) | JBR 21, Android SDK (platforms 36, 37.0; build tools 35.0.0, 36.0.0, 37.0.0), Node 22 |
| `android-emulator` | the same | `android` plus the emulator and an Android 36 system image |
| `android-backend` | AnkiQuest-Android-Backend | `android` plus NDK r28c and r29, Rust 1.99.0 (Android targets), cargo-ndk, Anki's build tools |
| `anki` | AnkiQuest-Anki | Rust 1.99.0, Node 22, Yarn 4, protoc, uv, n2, ninja, just, rsync |
| `gallery` | AnkiQuest.github.io | Node 22, cwebp |
| `default` | this repository, AnkiQuest-Sync, AnkiQuest-Agents | actionlint, alejandra, gh, jq, nixd |

Every version is in `shells/toolchains.nix`, next to the repository file it
follows. The shells exist for `x86_64-linux`, `aarch64-linux`,
`aarch64-darwin` and `x86_64-darwin` (see [Intel Macs](#intel-macs)).

## Pick a setup

| Machine | Setup | Verify |
|---|---|---|
| Ubuntu, other Linux | [Nix and the shells](#ubuntu-and-other-linux) | `nix develop github:AnkiQuest/AnkiQuest-Dev#desktop --command rustc --version` |
| NixOS | [the NixOS module](#nixos) | `direnv version && nix develop github:AnkiQuest/AnkiQuest-Dev#desktop --command rustc --version` |
| macOS (Apple silicon, Intel) | [Nix and the shells](#macos), optionally nix-darwin | `nix develop github:AnkiQuest/AnkiQuest-Dev#desktop --command rustc --version` |
| Windows, WSL | [NixOS on WSL](#install-nixos-on-wsl) | `wsl -d ankiquest -- nix develop github:AnkiQuest/AnkiQuest-Dev#desktop --command rustc --version` |
| Windows, native | [winget](#windows) | `rustup run 1.100.0 rustc --version; node --version; uv python list --only-installed; java -version; & "$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat" --list_installed` |
| Any OS with Docker or Podman | [the dev images](#dev-container) | `docker run --rm ghcr.io/ankiquest/ankiquest-dev-desktop:nightly rustc --version` |

`rustc 1.100.0` from the shell means Nix, the flake and the pinned toolchain
work. Repositories are then cloned and entered as in
[Clone the repositories](#clone-the-repositories) and
[Enter a shell with direnv](#enter-a-shell-with-direnv).

## Binary cache

Every push to `master` puts the shells' closures for `x86_64-linux` in the
Cachix cache `ankiquest`, so entering a shell downloads instead of building.
The NixOS and nix-darwin modules trust it; the flake offers it as
`nixConfig`, which Nix uses for trusted users or with `--accept-flake-config`.
Elsewhere, add it to `/etc/nix/nix.conf`:

```
extra-substituters = https://ankiquest.cachix.org
extra-trusted-public-keys = ankiquest.cachix.org-1:dX/Nw24o2NazxbWxwc2Fmav2YpCkBSMiQIpaNHhH4gY=
```

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

On Apple silicon and Intel Macs, install Nix the same way (`sh <(curl -L
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

### Intel Macs

nixpkgs 26.11 dropped `x86_64-darwin`, so Intel Macs take every package from
the `nixpkgs-x86_64-darwin` input, NixOS 26.05, the last release that builds
it (supported until the end of 2026). The pins in `shells/toolchains.nix` hold
there: Rust 1.100.0 and 1.99.0, platforms 36 and 37.0, build tools 35.0.0 to
37.0.0, NDK r28c and r29, Node 22.23.5, Python 3.12 and 3.13. Gaps:

- No pinned JBR. JetBrains' `osx-x64` build has no hash in
  `shells/toolchains.nix` yet; the shells use nixpkgs' JDK 21 (Zulu) as
  `JAVA_HOME` and let Gradle download the JBR its daemon asks for.
  `packages.x86_64-darwin.jbr` is that JDK. To pin it, add an `x86_64-darwin`
  entry with `arch = "osx-x64"` and the hash `nix build .#jbr` reports.
- Other tools (gh, uv, esbuild, Gradle) are 26.05's versions, not the
  unstable ones the other systems get.
- When 26.05 goes out of support, `x86_64-darwin` and the input are removed;
  Intel Macs then use the dev container.

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
`shells/toolchains.nix`. Download it from the
[nightly release](https://github.com/AnkiQuest/AnkiQuest-Dev/releases/tag/nightly)
or use the one in a checkout. In an elevated PowerShell:

```powershell
winget configure --file windows\configuration.dsc.yaml --accept-configuration-agreements
```

Open a new terminal afterwards, so `ANDROID_HOME` and the new `PATH` apply.
Gradle downloads the JetBrains runtime its daemon asks for. Anki's own build
(`./ninja`) and AnkiQuest-Android-Backend's are not set up here; use WSL for
those.

## Dev container

The nightly workflow publishes one image per shell, built with Nix:
`ghcr.io/ankiquest/ankiquest-dev-{server,desktop,android,anki}`, tagged
`nightly` and with each commit of `master`. Each holds the shell's environment,
a user `dev` and `/work`:

```sh
docker run -it -v "$PWD:/work" ghcr.io/ankiquest/ankiquest-dev-android:nightly
```

`.devcontainer/<shell>/devcontainer.json` opens a checkout in one of them, for
VS Code, JetBrains Gateway, `devcontainer up` or anything else that reads
`devcontainer.json`, on Docker or Podman; copy it into another repository's
`.devcontainer/` to use it there. Binaries Gradle, npm and uv download run
through nix-ld, as on NixOS.

The alternative is `.devcontainer/nix/`: an Ubuntu image with Nix and direnv
from this flake, which builds the shells itself. Open this repository in it;
clone the other repositories under `/workspaces` and enter them with `.envrc`
as below. Use it for `android-backend` and `android-emulator`, which have no
image, or to try local changes to the shells. The emulator does not run in a
container.

## Install NixOS on WSL

On Windows, in PowerShell:

```powershell
wsl --install --no-distribution
wsl --update
```

Then download `ankiquest-wsl.wsl` from the
[nightly release](https://github.com/AnkiQuest/AnkiQuest-Dev/releases/tag/nightly),
built from every commit to `master`, check it against `SHA256SUMS`, and import
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
for repo in AnkiQuest-Server AnkiQuest-Desktop AnkiQuest-Android AnkiQuest-Android-Backend AnkiQuest-Anki \
    AnkiQuest-Android-MCP AnkiQuest-AnkiConnectAndroid AnkiQuest-GarmAnki AnkiQuest-Sync AnkiQuest-Agents \
    AnkiQuest.github.io AnkiQuest-Dev; do gh repo clone "AnkiQuest/$repo"; done
git -C AnkiQuest-Android-Backend submodule update --init
git -C AnkiQuest.github.io submodule update --init
```

Sign in first with `gh auth login`.

## Enter a shell with direnv

Every repository's `flake.nix` takes its shell from here, so one line in an
`.envrc` in each checkout does it; run `direnv allow` there:

```sh
echo "use flake" > .envrc
```

| Repository | Shell its flake takes |
|---|---|
| AnkiQuest-Server | `server` |
| AnkiQuest-Desktop | `desktop` |
| AnkiQuest-Android, AnkiQuest-Android-MCP, AnkiQuest-AnkiConnectAndroid, AnkiQuest-GarmAnki | `android` |
| AnkiQuest-Android-Backend | `android-backend` |
| AnkiQuest-Anki | `anki` |
| AnkiQuest.github.io | `gallery` |
| AnkiQuest-Dev, AnkiQuest-Sync, AnkiQuest-Agents | `default` |

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

- **Garmin Connect IQ SDK** (AnkiQuest-GarmAnki `watch/`). Proprietary and not in
  nixpkgs. Download the SDK manager from
  https://developer.garmin.com/connect-iq/sdk/, install SDK 9.x to
  `~/connectiq-sdk`, and add its `bin` to `PATH` as AnkiQuest-GarmAnki's
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

A flake that loops over `ankiquest-dev.lib.systems` takes `pkgs` from
`ankiquest-dev.legacyPackages.${system}`, not from its own nixpkgs, which
cannot evaluate `x86_64-darwin`.

`overlays.default` adds the pinned toolchains as `pkgs.ankiquest` (`jbr`,
`rust.current`, `rust.anki`, `androidSdk.{app,emulator,backend}`), and
`lib.versions` holds the pins as plain values.

## Licence

AGPL-3.0-or-later ([LICENSE](LICENSE)).

## Shared workflows

Workflows more than one repository runs are reusable workflows in
`.github/workflows/`, called with
`uses: AnkiQuest/AnkiQuest-Dev/.github/workflows/<name>.yml@master`:

| Workflow | Does | Inputs |
|---|---|---|
| `android-ci.yml` | Gradle build, lint and unit tests with Temurin 17; `nix flake check` and a debug build in the repository's dev shell | `working-directory`, `jobs` (`gradle nix`, or one of them) |
| `android-nightly.yml` | A debug APK published as the `nightly` pre-release | `name`, `working-directory`; secret `NIGHTLY_DEBUG_KEYSTORE`; the caller grants `contents: write` |
| `banner.yml` | Draws the README banner and social preview with `ankiquest-banner` and fails unless the committed images have the same pixels; uploads the drawings as the `banner` artifact | `server-sha-file` (the pinned AnkiQuest-Server commit; empty in AnkiQuest-Server), `screens-artifact` and `screens-path` (screens not committed), `on-stale` (`fail` or `report`; output `stale`) |
| `labels.yml`, `pr-labels.yml`, `issue-labels.yml` | The shared label set (`labels.json`), "Needs Review", "New contributor", area labels from the caller's `.github/labeler.yml`, "Needs Triage" | none; `ankiquest-labels.yml` is the caller every repository copies |

The conflict scan ("Has Conflicts") is an action, `.github/actions/conflict-scan`, run by the caller's own job named `scan`: the rulesets require a check with that exact name, and a job that calls a reusable workflow reports as `<job> / scan`.

`tests/labels.test.ts` tests the label set and the scripts:
`nix develop .#gallery -c node --experimental-strip-types --test tests/*.test.ts`.

## README banner and social preview

Every repository with a README banner draws it, and its social preview,
with one tool: `ankiquest-banner` (`tools/banner`, also
`nix run github:AnkiQuest/AnkiQuest-Dev#banner`). The repository keeps
only its inputs in `docs/graphics/banner.toml`: title and tagline, the
companion pose (a master in AnkiQuest-Server's `static/`), its screens
with their frames (`window`, `browser` or `phone`) and the command that
records them. Both images are 1280x741 and 1280x640 pixels, in the same
gradient, light, Roboto and layout everywhere.

```sh
# From the repository root: redraw both images.
cargo run --release --manifest-path ../AnkiQuest-Dev/tools/banner/Cargo.toml -- --server ../AnkiQuest-Server
# Record the screens first, with the configuration's record command.
... -- --server ../AnkiQuest-Server --record
# Compare with the committed images, as CI does; write the drawings to a folder.
... -- --server ../AnkiQuest-Server --check --out /tmp/banner
```

`--check` exits 1 when a committed image differs from the drawing in any
pixel, or the social preview is 1,000,000 bytes or more (GitHub's limit),
and 2 when an input cannot be read. `banner.yml` runs it in CI. A change
to the tool that changes pixels changes every caller's images: redraw them
in each repository.
