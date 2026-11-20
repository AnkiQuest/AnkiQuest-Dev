# Agent instructions

AnkiQuest adds XP, streaks, friends, leaderboards and moments to Anki.

These rules apply to every agent (Claude, Codex, others) and to people too, in every AnkiQuest repository. Everything above "This repository" is the same in all of them. The source is [AnkiQuest/AnkiQuest-Agents](https://github.com/AnkiQuest/AnkiQuest-Agents): `shared.md` for the shared part, `repos/<repository>.md` for each "This repository" section. Edit it there, never `AGENTS.md` in a repository; AnkiQuest-Sync opens a pull request in each repository whose `AGENTS.md` differs.

## Repositories

All under [github.com/AnkiQuest](https://github.com/AnkiQuest).

| Repository | Upstream | Purpose |
|---|---|---|
| AnkiQuest-Server | none | The server (Rust), its web pages (TypeScript), the API examples, the shared fixtures and the pose masters. |
| AnkiQuest-Desktop | none | The Anki desktop add-on (Python). |
| AnkiQuest-Android | ankidroid/Anki-Android | The Android app (Kotlin): AnkiDroid with AnkiQuest added. |
| anki | ankitects/anki | Anki's core for the Android app, with our changes on `ankiquest`. |
| AnkiQuest-Android-Backend | ankidroid/Anki-Android-Backend | The app's Rust backend, built from our anki; published to Maven Central. |
| garmankiquest | sypianski/garmanki | Garmin watch app and its Android companion. |
| ankiquest-android-mcp | ankimcp/ankidroid-mcp | MCP server on Android for AnkiDroid and AnkiQuest. |
| AnkiQuestconnectAndroid | KamWithK/AnkiconnectAndroid | AnkiConnect on Android for AnkiDroid and AnkiQuest. |
| AnkiQuest-Sync | none | Scheduled jobs: fork sync, watched sources, `AGENTS.md` distribution. |
| AnkiQuest-Agents | none | The source of every `AGENTS.md`. |
| AnkiQuest.github.io | none | The art gallery (coming). |

## People

- hill (GitHub float3).
- Aldana (GitHub AldanaBRZ).
- The owners: hill and Aldana together. They decide and approve, with equal rights and responsibilities in the project.
- Claude: Claude Code agents.
- Astra: Aldana's Codex agent, which posts as AldanaBRZ.

Never call a person "the owner"; name them. "Code owner" describes how you treat the code, not who decides. "The owners" means hill and Aldana together. Name the person who approved something: "hill approved…", "Aldana approved…". An agent passing on an approval links the person's own words.

When a decision or action is left for hill, ask hill a question with the options, the recommended one first, instead of listing it as an open item. In chat, use the tool for questions with options, if there is one.

## Glossary

- Companion: a character (Aki, Ankilope, Bluma, Anki-tan).
- Pose: one picture of a companion. Its master is `static/<companion>/<pose>.png` in AnkiQuest-Server; every other copy (Android drawable, add-on art, share card) is an exported copy of that pose, generated and hash-checked. A pose exists only when it is drawn for every live companion.
- Mood: today's streak state, computed by the shared rule in `tests/fixtures/streak_moods.json`. Each mood names the pose it shows; several moods may show the same pose (`frozen_1` and `thawing` both show `frozen`). That is a mapping, not a fallback.
- Moment: something that happened worth telling (milestone, level up, place, deck conquered), shown as a card.
- Share: send a moment, board place or deck to friends in AnkiQuest or to another app. Don't say "shareable".
- "Drawable" and "art" are only platform file names in code. In docs and discussion, say "the pose's exported copy".

## Code ownership

You are the code owner and long-term maintainer of this codebase. The design is yours to decide, unless hill or Aldana overrules it.

Act like it: consolidate duplicated code instead of copying it, fix what you find instead of only reporting it, and leave the code better than you found it. List every change, including small ones, in the PR description; reviewers read the diff against it.

Don't hold on to the past. Deprecate and remove old code, tools, docs and layouts instead of keeping shims, aliases or "moved to" stubs, and make breaking changes when they make the design clearer. Pull requests that remove code are especially welcome. Say in the PR what breaks and who has to act. Two limits still apply: released apps keep working, so old endpoints, fields and API examples stay until no supported client uses them; and pose masters and their exported copies are never deleted (see below).

## Bugs: test first

1. Write a regression test that reproduces the bug.
2. Run it and watch it fail for the expected reason.
3. Fix the bug.
4. Run it again and watch it pass, together with the rest of the suite.

Say in the PR that the test failed before the fix. Never skip, disable or loosen a test to get CI green.

## Languages

Write new code in Rust, or TypeScript for the web, when the platform allows it. Use other languages only where the host demands them: Kotlin for the Android app, Python for the Anki desktop add-on. Do not add new Python tools or scripts; when you change an existing one substantially, port it to Rust.

## Code

- Name values: extract recurring or meaningful values into constants or enums; values from a spec (HTTP status codes, for example) always get a constant. Keep obvious one-off values inline.
- Return early; avoid deep nesting.
- Always use braces, even for one-line `if`s.
- Short function names, under 30 characters.
- Enums instead of booleans for function parameters.
- Blank lines between logical blocks, and a short comment saying what a block does and why.
- Keep members private by default. Widening visibility to share code instead of duplicating it is welcome; no approval is needed. Say in the PR what was widened and why.
- Layer the code: low-level mechanics (HTTP, database, files, platform APIs) sit behind an abstraction, and each layer talks only to the one directly below it.
- Prefer targeted edits over rewriting whole files.
- Keep all state explicit. Model a lifecycle or mode as one enum or sealed type with named states and named transitions, not as several booleans, nullable fields and timestamps whose combination means something. Every state is visible in one place, impossible combinations can't be represented, and tests cover each transition.

## Git and pull requests

- Start each session with `git fetch` and work from the latest default branch.
- Never push to the default branch; open a pull request.
- Pull requests by hill or Claude need an approving review from Aldana or Astra (the AldanaBRZ account). Pull requests by Aldana or Astra need an approving review from hill or Claude (the float3 account). One approval from the other side is enough; merge only once it is given and every check is green on the final commit. hill may merge trivially correct changes (documentation, AGENTS.md, README, labels, search and replace) without that review.
- Commit messages: subject in the imperative, capitalised, at most 50 characters (72 hard limit), no full stop; a blank line; a body wrapped at 72 characters that explains what and why, not how.
- Name the model that did the work. Every commit, pull request, issue, comment and review an agent writes ends with `Assisted-by: <tool> (<model and version>)`, such as `Assisted-by: Claude Code (Opus 5.5)` or `Assisted-by: Codex (GPT-6)`. In a GitHub post with a generated footer (`---`, then `_Generated by [Claude Code](https://claude.ai/code)_`), the `Assisted-by` line comes directly above the footer, the order the GitHub tools write (hill, 2026-11-20). Don't edit old posts to reorder them. Generated images name the model that drew them in the pull request and in their generation record. If the tool does not say which model it used, write that instead of guessing.
- Never link to an agent session (such as `claude.ai/code/session_…`) in commits, pull requests, issues or comments.
- No emoji in commits, pull requests, issues or comments.
- Never commit secrets, tokens or personal data. Secrets live on the servers, outside the repositories.

## Forks and wiring

```
ankitects/anki                  --mirror-->  AnkiQuest/anki main
                                             AnkiQuest/anki ankiquest
                                                 | git submodule
ankidroid/Anki-Android-Backend  --mirror-->  AnkiQuest/AnkiQuest-Android-Backend main
                                             AnkiQuest/AnkiQuest-Android-Backend ankiquest
                                                 | Maven Central: org.ankiquest:anki-backend-android
ankidroid/Anki-Android          --pr------>  AnkiQuest/AnkiQuest-Android main  --HTTPS-->  AnkiQuest-Server
                                                 | content provider, through org.ankiquest:api
sypianski/garmanki              --pr------>  AnkiQuest/garmankiquest master
ankimcp/ankidroid-mcp           --pr------>  AnkiQuest/ankiquest-android-mcp main
KamWithK/AnkiconnectAndroid     --pr------>  AnkiQuest/AnkiQuestconnectAndroid master
```

- **Core forks** (anki, AnkiQuest-Android-Backend): `main` mirrors upstream and only the sync job writes it. Our changes live on `ankiquest`: work from it and open pull requests against it. anki `ankiquest` is the Anki release AnkiDroid uses, plus the RWKV engine and FSRS-7 carried from JSchoreels' and kuma3's forks. AnkiQuest-Android-Backend `ankiquest` is the backend with its `anki` submodule on AnkiQuest/anki `ankiquest`; it publishes `org.ankiquest:anki-backend-android`, `anki-backend-core` and `anki-android-backend-testing` to Maven Central on a `*-ankiquest.*` tag. For each new Anki release AnkiDroid adopts, merge it forward into both `ankiquest` branches, then publish.
- **App forks** (AnkiQuest-Android, garmankiquest, ankiquest-android-mcp, AnkiQuestconnectAndroid): the default branch carries our changes. Upstream comes in through the sync job's pull request, merged as a merge commit; never squash or rebase it.
- **Third-party app forks** (garmankiquest, ankiquest-android-mcp, AnkiQuestconnectAndroid): the default branch is our version, with CI, Nix and the AnkiQuest API library `org.ankiquest:api` (coming). The branches `ankidroid-provider-check` and `ankiquest-support` stay ready to propose upstream: upstream's style and languages, no AnkiQuest-only changes. Keep upstream's languages for upstream's code in every fork.
- **Sync job** (AnkiQuest-Sync, daily and on demand): mirror mode fast-forwards a mirror and opens an issue if it has commits of its own; pr mode opens one pull request from upstream. The `watch` job opens an issue in the fork a watched source feeds when it moves past the reviewed commit or version: JSchoreels/anki, JSchoreels/fsrs-rs, open-spaced-repetition/fsrs-rs, kuma3's core, backend and app, and new upstream backend versions (`watched.json`). The `agents` job opens the `AGENTS.md` pull requests.

## Desktop and Android parity

AnkiQuest has two clients: the Android app ([AnkiQuest/AnkiQuest-Android](https://github.com/AnkiQuest/AnkiQuest-Android)) and the Anki desktop add-on (`addon/` in [AnkiQuest/AnkiQuest-Desktop](https://github.com/AnkiQuest/AnkiQuest-Desktop)). A player should get the same AnkiQuest on both.

- A user-facing feature or behaviour change lands on both clients, unless the platform can't do it (home-screen widgets, for example). Do both in one go when you can. Otherwise open an issue in the other repository, labelled `parity`, and link it from the PR.
- Rules both clients compute (streak verdicts, heatmap, card labels, deck names) are defined once, as cases in `tests/fixtures/*.json` in [AnkiQuest/AnkiQuest-Server](https://github.com/AnkiQuest/AnkiQuest-Server/tree/master/tests/fixtures). Both clients test against the same cases. Change the fixture first, then both implementations.
- Use the same names, wording and order for the same thing on both clients.
- When you find a gap between the clients, open a `parity` issue for it.

## Companion art

Every picture of a companion is a pose, including those on moments, share cards, widgets and notifications. The section and tool names keep "art"; the rules speak of poses, masters and exported copies.

- Masters live only in `static/<companion>/` in AnkiQuest-Server. Every exported copy (share cards, add-on, Android, docs) is generated from its master by the exporters and hash-checked in CI; never commit a hand-made copy.
- Never delete a master or an exported copy, even when nothing uses it any more. Remove the references, keep the files, so they can be reused or merged later.
- Every live companion has every pose listed in [`tests/fixtures/companion_poses.json`](https://github.com/AnkiQuest/AnkiQuest-Server/blob/master/tests/fixtures/companion_poses.json) in AnkiQuest-Server; both clients use that list.
- A new companion goes live only with every pose drawn.
- A PR that adds a pose to the list adds its master for every live companion. CI fails a PR that adds a pose without them. A mood that needs a new picture adds a pose this way; otherwise it maps to an existing pose.
- No placeholder pictures: no stand-in, recoloured or borrowed picture for a missing pose.
- One exception (hill, 2026-11-19): Anki-tan goes live before her missing extensions are drawn (`streak_hot`, `streak_blazing`, `frozen_2`, `frozen_3`, `abandoned`, `leech_defeated`, `winner`); they show their fallbacks until then. Drawing them comes first in AnkiQuest/AnkiQuest-Server#57. No other companion goes live with missing poses.
- Until the missing poses are drawn (AnkiQuest/AnkiQuest-Server#57), the clients keep the current fallbacks: a missing extension shows the fallback the list gives it (a streak tier shows streak, frozen 3 shows frozen), and Bluma shows Ankilope's poses recoloured where hers are missing. These are the only poses not drawn for every live companion, and they are temporary. Once every live companion has every pose, remove the fallbacks from the list and both clients.

## Writing

Write comments, commit messages, issues and PR descriptions with as few words as needed. No praise, no filler, no superlatives. Em dashes take no spaces around them.

Mannered prose substitutes metaphor and flourish for direct statement. Instead of "a parameter worth varying," the mannered writer produces "a dial worth turning." Instead of "this point still matters," they write "this point earns its keep." The phrases exist to display the writer, not to convey the idea, and readers can tell. That is why mannered prose irritates: it makes the reader work harder so the writer can perform. It is also imprecise. Metaphors drag in connotations the writer did not choose and cannot control. The fix is to say what you mean. When a literal phrase is available, use it.

## This repository

AnkiQuest-Dev is the development environment for every AnkiQuest repository: NixOS on WSL (`nixosConfigurations.ankiquest-wsl`) and one dev shell per kind of repository (`devShells.<system>.{default,server,desktop,android,android-emulator,anki}`).

- **Layout.** `flake.nix`: the outputs. `shells/toolchains.nix`: every pinned version (Rust, Android SDK and NDK, JBR), each next to the repository file it follows. `shells/default.nix`: the dev shells. `nixos/hosts/ankiquest-wsl`: the WSL host; `nixos/roles` and `nixos/modules`: what it is made of, laid out as in float3/nixos.
- **Pins follow the repositories.** When a repository changes a version it pins (`rust-toolchain.toml`, `gradle/libs.versions.toml`, `gradle/gradle-daemon-jvm.properties`, a CI workflow), change the matching value in `shells/toolchains.nix`. Update one flake input at a time with `nix flake update <input>`.
- **Nix only.** Configuration is Nix, formatted with alejandra. Shell stays a few lines of glue; anything larger becomes Rust.
- **Nothing private.** Signing keys, `keystore.properties`, `google-services.json`, tokens and proprietary SDKs (the Garmin Connect IQ SDK) are installed by hand, as the README says, and never committed.
- **Checks to run** before pushing: `nix flake check`, `alejandra --check .`, and `nix develop .#<shell>` for each shell you changed.
