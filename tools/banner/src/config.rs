//! The repository's inputs, read from its `docs/graphics/banner.toml`:
//! text, the companion pose, the screens and where the two images go.
//! Paths are relative to the repository root, the companion pose's to the
//! AnkiQuest-Server checkout.

use std::fs;
use std::path::{Path, PathBuf};

use serde::Deserialize;

/// Where a repository keeps its banner configuration.
pub const DEFAULT_PATH: &str = "docs/graphics/banner.toml";

/// One repository's banner and social preview.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    /// The title and the line below it, on both images.
    pub title: String,
    pub tagline: String,

    /// The command that regenerates the screens, run by `--record`.
    #[serde(default)]
    pub record: Vec<String>,

    pub companion: Companion,

    /// Where the images are committed.
    pub readme: PathBuf,
    pub social: PathBuf,

    /// The screens on the README banner, back to front.
    #[serde(rename = "screen")]
    pub screens: Vec<Screen>,
}

/// The companion pose beside the title.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Companion {
    /// The pose master, relative to an AnkiQuest-Server checkout.
    pub pose: PathBuf,

    /// Its height on the README banner, in pixels.
    pub height: u32,
}

/// One screenshot on the README banner and the frame drawn around it.
/// Positions and sizes are banner pixels; `x` and `y` are the frame's
/// top-left corner.
#[derive(Debug, Deserialize)]
#[serde(tag = "frame", rename_all = "lowercase", deny_unknown_fields)]
pub enum Screen {
    /// A desktop window with its title in the title bar. The screenshot is
    /// `width` wide and cut off below `max_height`.
    Window {
        shot: PathBuf,
        title: String,
        x: i32,
        y: i32,
        width: u32,
        max_height: u32,
    },

    /// A browser window with an address field in the title bar.
    Browser {
        shot: PathBuf,
        address: String,
        x: i32,
        y: i32,
        width: u32,
        max_height: u32,
    },

    /// A phone with a status bar; `width` is the screen's width.
    Phone {
        shot: PathBuf,
        x: i32,
        y: i32,
        width: u32,
    },
}

impl Screen {
    /// The screenshot file.
    pub fn shot(&self) -> &Path {
        match self {
            Screen::Window { shot, .. }
            | Screen::Browser { shot, .. }
            | Screen::Phone { shot, .. } => shot,
        }
    }
}

impl Config {
    /// Reads and checks the configuration at `path`.
    pub fn load(path: &Path) -> Result<Config, String> {
        let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
        Config::parse(&text).map_err(|e| format!("{}: {e}", path.display()))
    }

    /// Parses a configuration and checks what serde cannot.
    pub fn parse(text: &str) -> Result<Config, String> {
        let config: Config = toml::from_str(text).map_err(|e| e.to_string())?;
        if config.screens.is_empty() {
            return Err("no [[screen]]".into());
        }
        if config.companion.height == 0 {
            return Err("companion.height is 0".into());
        }
        Ok(config)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const DESKTOP: &str = r#"
title = "AnkiQuest"
tagline = "Study together"
record = ["python", "tests/draw_screenshots.py"]
readme = "docs/graphics/banner_readme.png"
social = "docs/graphics/social_preview.png"

[companion]
pose = "static/duo/friends.png"
height = 138

[[screen]]
frame = "window"
shot = "docs/screenshots/a.png"
title = "Today"
x = 1
y = 2
width = 440
max_height = 600

[[screen]]
frame = "phone"
shot = "b.png"
x = 3
y = 4
width = 240
"#;

    #[test]
    fn reads_every_frame() {
        let config = Config::parse(DESKTOP).unwrap();
        assert_eq!(vec!["python", "tests/draw_screenshots.py"], config.record);
        assert_eq!(138, config.companion.height);
        assert!(matches!(&config.screens[0], Screen::Window { title, .. } if title == "Today"));
        assert!(matches!(
            config.screens[1],
            Screen::Phone { width: 240, .. }
        ));
        assert_eq!(Path::new("b.png"), config.screens[1].shot());
    }

    #[test]
    fn refuses_unknown_keys_and_frames() {
        let typo = DESKTOP.replace("max_height = 600", "max_height = 600\nmaxheight = 1");
        assert!(Config::parse(&typo).is_err());
        let frame = DESKTOP.replace("\"phone\"", "\"tablet\"");
        assert!(Config::parse(&frame).is_err());
    }

    #[test]
    fn refuses_a_banner_without_screens() {
        let end = DESKTOP.find("[[screen]]").unwrap();
        assert!(Config::parse(&DESKTOP[..end]).is_err());
    }
}
