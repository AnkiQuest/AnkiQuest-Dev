//! Draws and checks an AnkiQuest repository's README banner and social
//! preview, the same way in every repository. The repository keeps only
//! its inputs, in `docs/graphics/banner.toml`: the text, its screens and
//! the command that records them, and which companion pose to show; the
//! pose comes from its master in an AnkiQuest-Server checkout.
//!
//! ```sh
//! ankiquest-banner --server <AnkiQuest-Server checkout> [--config <file>]
//!                  [--record] [--check] [--out <dir>]
//! ```
//!
//! Run it from the repository root. It draws both images and writes them
//! where the configuration says they are committed. `--record` first runs
//! the configuration's `record` command, which regenerates the screens.
//! `--check` writes nothing there and fails unless each committed image
//! has the drawing's size and pixels, and the social preview is small
//! enough for GitHub. `--out` writes the drawings to a folder instead, also
//! with `--check`, so CI can upload them.
//!
//! Vector parts are SVG drawn with resvg, text in the bundled Roboto;
//! screenshots and art are downscaled with Lanczos and placed at whole
//! pixels, so every run gives the same pixels.

mod config;
mod draw;
mod scene;

use std::path::{Path, PathBuf};
use std::process::{self, ExitCode};

use image::RgbImage;

use config::Config;
use scene::Kind;

const USAGE: &str = "usage: ankiquest-banner --server <AnkiQuest-Server checkout> [--config <file>] [--record] [--check] [--out <dir>]

  --server  checkout with the companion pose masters (static/)
  --config  the repository's inputs, default docs/graphics/banner.toml
  --record  run the configuration's record command first
  --check   fail unless the committed images have the drawn pixels
  --out     write the drawings to this folder instead";

/// GitHub refuses a social preview of this many bytes or more.
const SOCIAL_LIMIT: usize = 1_000_000;

/// Whether to regenerate the screens before drawing.
#[derive(Debug, PartialEq)]
enum Screens {
    /// Use the screens as they are.
    Recorded,
    /// Run the configuration's record command first.
    Record,
}

/// What to do with the drawings.
#[derive(Debug, PartialEq)]
enum Mode {
    /// Write them over the committed images.
    Write,
    /// Compare them with the committed images.
    Check,
}

/// Exit codes, as diff's: 1 when a committed image is stale, 2 when the
/// images could not be drawn or read.
const STALE: u8 = 1;
const BROKEN: u8 = 2;

/// How the committed images compare with the drawings.
#[derive(Debug, PartialEq)]
enum Outcome {
    /// Written, or checked and the same.
    Current,
    /// Checked, and these differ.
    Stale(Vec<String>),
}

/// The parsed command line.
#[derive(Debug)]
struct Args {
    server: PathBuf,
    config: PathBuf,
    screens: Screens,
    mode: Mode,
    out: Option<PathBuf>,
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.iter().any(|arg| arg == "-h" || arg == "--help") {
        println!("{USAGE}");
        return ExitCode::SUCCESS;
    }
    let args = match parse(&args) {
        Ok(args) => args,
        Err(error) => {
            eprintln!("{error}\n{USAGE}");
            return ExitCode::from(BROKEN);
        }
    };

    match run(&args) {
        Ok(Outcome::Current) => ExitCode::SUCCESS,
        Ok(Outcome::Stale(images)) => {
            eprintln!(
                "{}\nRedraw with `ankiquest-banner --server <AnkiQuest-Server checkout>` and commit the result.",
                images.join("\n")
            );
            ExitCode::from(STALE)
        }
        Err(error) => {
            eprintln!("{error}");
            ExitCode::from(BROKEN)
        }
    }
}

/// Reads the command line.
fn parse(args: &[String]) -> Result<Args, String> {
    let mut server = None;
    let mut config = PathBuf::from(config::DEFAULT_PATH);
    let mut screens = Screens::Recorded;
    let mut mode = Mode::Write;
    let mut out = None;
    let mut args = args.iter();
    while let Some(arg) = args.next() {
        let mut value = || {
            args.next()
                .map(PathBuf::from)
                .ok_or(format!("{arg} needs a value"))
        };
        match arg.as_str() {
            "--server" => server = Some(value()?),
            "--config" => config = value()?,
            "--out" => out = Some(value()?),
            "--record" => screens = Screens::Record,
            "--check" => mode = Mode::Check,
            other => return Err(format!("unknown argument {other}")),
        }
    }
    Ok(Args {
        server: server.ok_or("--server is required")?,
        config,
        screens,
        mode,
        out,
    })
}

fn run(args: &Args) -> Result<Outcome, String> {
    let config = Config::load(&args.config)?;
    if args.screens == Screens::Record {
        record(&config.record)?;
    }

    // Draw both images, then write or compare each; a check reports every
    // stale image before failing.
    let mut stale = Vec::new();
    for kind in Kind::ALL {
        let image = scene::render(kind, &config, &args.server)?;
        let committed = kind.path(&config);
        let bytes = draw::encode(&image)?;
        // The drawing goes to `--out`, or over the committed image when
        // writing.
        let target = match &args.out {
            Some(dir) => {
                let name = committed
                    .file_name()
                    .ok_or("an image path has no file name")?;
                Some(dir.join(name))
            }
            None if args.mode == Mode::Write => Some(committed.to_path_buf()),
            None => None,
        };
        if let Some(target) = &target {
            draw::write(target, &bytes)?;
            println!("Drew {}", target.display());
        }

        match args.mode {
            Mode::Write => {
                fits(kind, bytes.len()).map_err(|e| format!("{}: {e}", committed.display()))?
            }
            Mode::Check => match compare(kind, &image, committed) {
                Ok(()) => println!("{} is current", committed.display()),
                Err(error) => stale.push(error),
            },
        }
    }

    if stale.is_empty() {
        return Ok(Outcome::Current);
    }
    Ok(Outcome::Stale(stale))
}

/// Runs the record command from the repository root.
fn record(command: &[String]) -> Result<(), String> {
    let Some((program, args)) = command.split_first() else {
        return Err("--record: the configuration has no record command".into());
    };
    println!("Running {}", command.join(" "));
    let status = process::Command::new(program)
        .args(args)
        .status()
        .map_err(|e| format!("{program}: {e}"))?;
    if !status.success() {
        return Err(format!("{} failed: {status}", command.join(" ")));
    }
    Ok(())
}

/// Whether the committed image at `path` has the drawing's pixels and,
/// for the social preview, fits GitHub's limit.
fn compare(kind: Kind, image: &RgbImage, path: &Path) -> Result<(), String> {
    let committed = image::open(path)
        .map_err(|e| format!("{}: {e}", path.display()))?
        .into_rgb8();
    if committed != *image {
        return Err(format!("{} differs from the drawing", path.display()));
    }
    let bytes = std::fs::metadata(path)
        .map_err(|e| format!("{}: {e}", path.display()))?
        .len();
    fits(kind, bytes as usize).map_err(|e| format!("{}: {e}", path.display()))
}

/// Whether an image of `bytes` can be uploaded: GitHub limits the social
/// preview.
fn fits(kind: Kind, bytes: usize) -> Result<(), String> {
    if kind != Kind::Social || bytes < SOCIAL_LIMIT {
        return Ok(());
    }
    Err(format!(
        "{bytes} bytes; GitHub takes a social preview under {SOCIAL_LIMIT}"
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parsed(list: &[&str]) -> Result<Args, String> {
        let args: Vec<String> = list.iter().map(|s| s.to_string()).collect();
        parse(&args)
    }

    #[test]
    fn the_server_checkout_is_required() {
        assert!(parsed(&["--check"]).is_err());
        let args = parsed(&["--server", "../server"]).unwrap();
        assert_eq!(PathBuf::from("../server"), args.server);
        assert_eq!(PathBuf::from(config::DEFAULT_PATH), args.config);
        assert_eq!(Screens::Recorded, args.screens);
        assert_eq!(Mode::Write, args.mode);
        assert!(args.out.is_none());
    }

    #[test]
    fn reads_every_flag() {
        let args = parsed(&[
            "--server", "s", "--config", "c.toml", "--record", "--check", "--out", "o",
        ])
        .unwrap();
        assert_eq!(PathBuf::from("c.toml"), args.config);
        assert_eq!(Screens::Record, args.screens);
        assert_eq!(Mode::Check, args.mode);
        assert_eq!(Some(PathBuf::from("o")), args.out);
    }

    #[test]
    fn refuses_unknown_and_incomplete_flags() {
        assert!(parsed(&["--server", "s", "--social"]).is_err());
        assert!(parsed(&["--server", "s", "--out"]).is_err());
        assert!(parsed(&["--server"]).is_err());
    }

    #[test]
    fn a_social_preview_must_stay_under_githubs_limit() {
        assert!(fits(Kind::Social, SOCIAL_LIMIT - 1).is_ok());
        assert!(fits(Kind::Social, SOCIAL_LIMIT).is_err());
        assert!(fits(Kind::Readme, SOCIAL_LIMIT).is_ok());
    }

    #[test]
    fn a_check_finds_what_a_write_left_and_what_changed() {
        let dir = scene::tests::scratch("check");
        let config = scene::tests::sample(&dir);
        let path = dir.join("sample.toml");
        let args = |mode| Args {
            server: dir.clone(),
            config: path.clone(),
            screens: Screens::Recorded,
            mode,
            out: None,
        };

        // A check before the images exist, after writing them, and after
        // one changed.
        assert!(matches!(run(&args(Mode::Check)), Ok(Outcome::Stale(images)) if images.len() == 2));
        assert_eq!(Ok(Outcome::Current), run(&args(Mode::Write)));
        assert_eq!(Ok(Outcome::Current), run(&args(Mode::Check)));
        std::fs::copy(&config.social, &config.readme).unwrap();
        assert!(matches!(run(&args(Mode::Check)), Ok(Outcome::Stale(images)) if images.len() == 1));
    }

    #[test]
    fn a_missing_configuration_is_broken() {
        let args = Args {
            server: PathBuf::from("."),
            config: PathBuf::from("nowhere/banner.toml"),
            screens: Screens::Recorded,
            mode: Mode::Check,
            out: None,
        };
        assert!(run(&args).is_err());
    }

    #[test]
    fn record_needs_a_command() {
        assert!(record(&[]).is_err());
        assert!(record(&["false".into()]).is_err());
        assert!(record(&["true".into()]).is_ok());
    }
}
