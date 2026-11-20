# Keeps pull request code off AnkiQuest's self-hosted runners. Their
# runner group admits every workflow and ref (float3/nixos
# nixos/runner-policy.nix), so only a job's runs-on decides where it
# runs. Every runs-on in .github/workflows/ must be a GitHub-hosted
# label, `${{ matrix.<key> }}` with only GitHub-hosted values in the
# file, or the routing expression: self-hosted for merge groups and
# pushes to the default branch, GitHub-hosted for every other event,
# pull_request and pull_request_target included. Anything else fails,
# as do reusable workflows from other repositories, except
# AnkiQuest-Dev's own on its default branch, master: this check guards
# their runs-on there, and only reviewed code reaches master. The same
# rules as crates/xtask's runners test in AnkiQuest-Server and
# AnkiQuest-Desktop.
{
  lib,
  runCommand,
}: workflows: let
  selfHostedEvents = "(github.event_name == 'merge_group' || (github.event_name == 'push' && github.ref == format('refs/heads/{0}', github.event.repository.default_branch)))";
  # AnkiQuest-Dev's reusable workflows on master, which every repository calls.
  shared = uses: builtins.match "AnkiQuest/AnkiQuest-Dev/\\.github/workflows/[A-Za-z0-9_.-]+\\.ya?ml@master" uses != null;
  hosted = label: builtins.match "(ubuntu|macos|windows)-[A-Za-z0-9.-]+" label != null;

  # A line's value after `key:`, without a trailing comment, or null.
  value = key: line: let
    found = builtins.match " *(- +)?${key}:(.*)" line;
  in
    if found == null
    then null
    else lib.trim (builtins.head (lib.splitString " #" (builtins.elemAt found 1)));
  values = key: text: builtins.filter (v: v != null) (map (value key) (lib.splitString "\n" text));

  # The fallback label of the routing expression, the matrix key read.
  routed = builtins.match "\\$\\{\\{ ${lib.escapeRegex selfHostedEvents} && fromJSON\\('[^']*'\\) \\|\\| '([^']*)' }}";
  matrixKey = builtins.match "\\$\\{\\{ matrix\\.([A-Za-z0-9_-]+) }}";

  # Whether every value of the matrix key in the file is hosted.
  hostedMatrix = text: key: let
    labels = lib.concatMap (v: let
      list = builtins.match "\\[(.*)]" v;
    in
      if list == null
      then [v]
      else lib.splitString "," (builtins.head list))
    (values key text);
    clean = label: lib.removeSuffix "'" (lib.removePrefix "'" (lib.removeSuffix "\"" (lib.removePrefix "\"" (lib.trim label))));
  in
    labels != [] && lib.all (label: hosted (clean label)) labels;

  # The problem with one runs-on value, or null.
  runsOnProblem = text: runsOn: let
    fallback = routed runsOn;
    key = matrixKey runsOn;
  in
    if hosted runsOn
    then null
    else if fallback != null
    then lib.optionalString (!hosted (builtins.head fallback)) "fallback ${builtins.head fallback} is not GitHub-hosted"
    else if key != null
    then lib.optionalString (!hostedMatrix text (builtins.head key)) "matrix.${builtins.head key} has values that are not GitHub-hosted labels"
    else "`${runsOn}` is not a GitHub-hosted label or the routing expression";

  # The problems in one workflow file.
  problems = name: let
    text = builtins.readFile (workflows + "/${name}");
    runsOn = map (runsOnProblem text) (values "runs-on" text);
    remote = builtins.filter (uses: lib.hasInfix ".github/workflows/" uses && !(lib.hasPrefix "./" uses) && !(shared uses)) (values "uses" text);
  in
    map (problem: "${name}: ${problem}") (builtins.filter (p: p != null && p != "") runsOn ++ map (uses: "reusable workflow ${uses} is not local") remote);

  files = builtins.filter (name: lib.hasSuffix ".yml" name || lib.hasSuffix ".yaml" name) (builtins.attrNames (builtins.readDir workflows));
  found = lib.concatMap problems files;
in
  assert lib.assertMsg (files != []) "no workflows in ${toString workflows}";
  assert lib.assertMsg (found == []) (lib.concatLines found);
    runCommand "runner-routing" {} "touch $out"
