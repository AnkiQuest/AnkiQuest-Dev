# AnkiQuest-Dev

The development environment for the AnkiQuest repositories: a NixOS-on-WSL
system (`ankiquest-wsl`) and one dev shell per kind of repository.

| Shell | Repositories | Main tools |
|---|---|---|
| `server` | AnkiQuest-Server, AnkiQuest.github.io | Rust 1.100.0 (wasm32 and Android targets), cargo-ndk, Node 22, esbuild, wasm-ld, SQLite, Python 3.13, uv, JBR 21, Gradle 9 |
| `desktop` | AnkiQuest-Desktop | Rust 1.100.0, Python 3.12, pyflakes, uv, Node 22 |
| `android` | AnkiQuest-Android, AnkiQuest-Android-Backend, ankiquest-android-mcp, AnkiQuestconnectAndroid, garmankiquest (`android/`) | JBR 21, Android SDK (platforms 33, 36, 37.0; build tools 35.0.0, 36.0.0, 37.0.0), NDK r28c and r29, Rust 1.97.1 (Android targets), cargo-ndk, Anki's build tools |
| `android-emulator` | the same | `android` plus the emulator and an Android 36 system image |
| `anki` | AnkiQuest/anki | Rust 1.97.1, Node 22, Yarn 4, protoc, uv, n2, ninja, just, rsync |
| `default` | this repository | alejandra, nixd, gh |

AnkiQuest-Sync and AnkiQuest-Agents hold only workflows and Markdown and need
no shell.

Every version is in `shells/toolchains.nix`, next to the repository file it
follows.

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
| AnkiQuest-Android, AnkiQuest-Android-Backend, ankiquest-android-mcp, AnkiQuestconnectAndroid | `use flake github:AnkiQuest/AnkiQuest-Dev#android` |
| garmankiquest | `use flake github:AnkiQuest/AnkiQuest-Dev#android` |
| anki | `use flake github:AnkiQuest/AnkiQuest-Dev#anki` |
| AnkiQuest-Dev | `use flake` (checked in) |

To try local changes to this repository, use `path:` instead:
`use flake path:$HOME/src/AnkiQuest-Dev#android`. `.envrc` is not ignored in
every repository; add it to `.git/info/exclude` instead of committing it.

Without direnv: `nix develop github:AnkiQuest/AnkiQuest-Dev#android`.

### Notes per repository

- **AnkiQuest-Server.** `crates/rules` builds Android libraries with NDK r28c,
  which only the `android` shell carries. In the `server` shell:
  `export ANDROID_NDK_HOME=$(nix build --no-link --print-out-paths github:AnkiQuest/AnkiQuest-Dev#android-sdk)/libexec/android-sdk/ndk/28.2.13676358`.
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
- **Rust, Android SDK, NDK, JBR**: change the value in `shells/toolchains.nix`
  when the file named in its comment changes. For a new JBR build, set
  `jbrBuild`, put `lib.fakeHash` in the hashes, and copy the hashes `nix build
  .#jbr` reports (do this on x86_64 and arm64, or with
  `nix store prefetch-file`).
- **Node, Python, Gradle, protoc and the rest** come from nixpkgs and move with
  `nix flake update nixpkgs`.

Then `nix flake check`, `nix fmt`, and enter each shell you touched.
