# The winget configuration for native Windows, generated from the pins in
# shells/toolchains.nix and the tool versions of the locked nixpkgs. Build it
# with `nix build .#windows-configuration`; checks.windows-configuration
# fails while windows/configuration.dsc.yaml differs.
{
  pkgs,
  lib,
  toolchains,
}: let
  inherit (toolchains) versions;

  # The Android command-line tools nixpkgs' androidenv locks, with the URL
  # and checksum of their Windows archive.
  androidRepo = lib.importJSON (pkgs.path + "/pkgs/development/mobile/androidenv/repo.json");
  cmdlineTools = let
    latest = lib.last (lib.sort lib.versionOlder (lib.attrNames androidRepo.packages.cmdline-tools));
    archive = lib.findFirst (a: a.os == "windows") null androidRepo.packages.cmdline-tools.${latest}.archives;
  in {
    inherit (archive) url sha1;
  };

  # The packages sdkmanager installs: the same SDK as the android and
  # android-backend shells.
  sdkPackages =
    ["platform-tools"]
    ++ map (p: "platforms;android-${p}") versions.android.platforms
    ++ map (b: "build-tools;${b}") versions.android.buildTools
    ++ map (n: "ndk;${n}") versions.android.ndk;

  # Temurin's build of the OpenJDK release the pinned JBR is based on. Gradle
  # downloads the JBR itself for its daemon; this JDK only starts Gradle.
  temurinBuild = "10";
  jdkVersion = "${lib.head (lib.splitString "-" toolchains.jbr.version)}.${temurinBuild}";

  # winget packages, each at the version the shells use.
  packages = [
    {
      name = "git";
      id = "Git.Git";
      version = pkgs.git.version;
    }
    {
      name = "rustup";
      id = "Rustlang.Rustup";
      version = pkgs.rustup.version;
    }
    {
      name = "node";
      id = "OpenJS.NodeJS.${versions.node}";
      version = toolchains.nodejs.version;
    }
    {
      name = "uv";
      id = "astral-sh.uv";
      version = pkgs.uv.version;
    }
    {
      name = "jdk";
      id = "EclipseAdoptium.Temurin.${versions.jdk}.JDK";
      version = jdkVersion;
    }
  ];

  # PowerShell glue run after the packages: the Rust toolchains, the Python
  # versions and the Android SDK. Each is a test plus a set step.
  rustupExe = ''"$env:USERPROFILE\.cargo\bin\rustup.exe"'';
  rustInstall = version: targets: "& ${rustupExe} toolchain install ${version} --profile minimal --component ${lib.concatStringsSep "," versions.rust.components} --target ${lib.concatStringsSep "," targets}";
  uvExe = ''"$env:LOCALAPPDATA\Microsoft\WinGet\Links\uv.exe"'';
  sdkRoot = ''"$env:LOCALAPPDATA\Android\Sdk"'';
  sdkmanager = ''"$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat"'';

  scripts = [
    {
      name = "rust-toolchains";
      dependsOn = "rustup";
      test = "(& ${rustupExe} toolchain list) -match '^${versions.rust.current}-' -and (& ${rustupExe} toolchain list) -match '^${versions.rust.anki}-'";
      set = [
        (rustInstall versions.rust.current versions.rust.targets.current)
        (rustInstall versions.rust.anki versions.rust.targets.anki)
      ];
    }
    {
      name = "python";
      dependsOn = "uv";
      test = "$false";
      set = ["& ${uvExe} python install ${lib.concatStringsSep " " versions.python}"];
    }
    {
      name = "android-sdk";
      dependsOn = "jdk";
      # Done when every package's directory exists, so a changed pin installs
      # the new packages on the next run.
      test = lib.concatMapStringsSep " -and " (p: "(Test-Path (Join-Path ${sdkRoot} '${lib.replaceStrings [";"] ["\\"] p}'))") sdkPackages;
      set = [
        "$env:JAVA_HOME = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')"
        "if (-not (Test-Path ${sdkmanager})) {"
        "  $zip = Join-Path $env:TEMP 'android-cmdline-tools.zip'"
        "  Invoke-WebRequest -Uri '${cmdlineTools.url}' -OutFile $zip"
        "  if ((Get-FileHash -Algorithm SHA1 $zip).Hash -ne '${lib.toUpper cmdlineTools.sha1}') { throw 'cmdline-tools checksum mismatch' }"
        "  Expand-Archive $zip -DestinationPath (Join-Path $env:TEMP 'android-cmdline-tools') -Force"
        "  New-Item -ItemType Directory -Force (Join-Path ${sdkRoot} 'cmdline-tools') | Out-Null"
        "  Move-Item (Join-Path $env:TEMP 'android-cmdline-tools\\cmdline-tools') (Join-Path ${sdkRoot} 'cmdline-tools\\latest')"
        "}"
        "[Environment]::SetEnvironmentVariable('ANDROID_HOME', ${sdkRoot}, 'User')"
        "1..20 | ForEach-Object { 'y' } | & ${sdkmanager} --licenses"
        "& ${sdkmanager} ${lib.concatMapStringsSep " " (p: "'${p}'") sdkPackages}"
      ];
    }
  ];

  # YAML by hand, so the scripts stay readable block scalars.
  indent = n: text: lib.concatMapStringsSep "\n" (line: lib.strings.replicate n " " + line) (lib.splitString "\n" text);

  packageResource = p: ''
    - resource: Microsoft.WinGet.DSC/WinGetPackage
      id: ${p.name}
      directives:
        description: Install ${p.id} ${p.version}
      settings:
        id: ${p.id}
        version: "${p.version}"
        source: winget'';

  scriptResource = s: ''
    - resource: PSDscResources/Script
      id: ${s.name}
      dependsOn:
        - ${s.dependsOn}
      directives:
        description: Set up ${s.name}
      settings:
        GetScript: "@{ Result = '${s.name}' }"
        TestScript: |
    ${indent 6 s.test}
        SetScript: |
    ${indent 6 (lib.concatStringsSep "\n" s.set)}'';

  yaml = ''
    # Generated from shells/toolchains.nix by `nix build .#windows-configuration`.
    # Do not edit; change the pins there and copy the result here.
    # yaml-language-server: $schema=https://aka.ms/configuration-dsc-schema/0.2
    properties:
      configurationVersion: 0.2.0
      resources:
    ${indent 4 (lib.concatMapStringsSep "\n" packageResource packages)}
    ${indent 4 (lib.concatMapStringsSep "\n" scriptResource scripts)}
  '';
in
  pkgs.writeText "configuration.dsc.yaml" yaml
