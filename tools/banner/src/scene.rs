//! The two layouts. The README banner: the companion beside the title and
//! tagline, the repository's screens below in window, browser or phone
//! frames. The social preview: the companion large on the left, title and
//! tagline on the right. Both share the blue gradient and a soft light.

use std::path::Path;

use image::{RgbImage, RgbaImage};

use crate::config::{Config, Screen};
use crate::draw::{self, Anchor, Canvas, Line, Weight};

/// Which image to draw.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Kind {
    Readme,
    Social,
}

impl Kind {
    pub const ALL: [Kind; 2] = [Kind::Readme, Kind::Social];

    /// Pixel size: the README banner's, or GitHub's social preview.
    pub fn size(self) -> (u32, u32) {
        match self {
            Kind::Readme => (1280, 741),
            Kind::Social => (1280, 640),
        }
    }

    /// Where the repository commits this image.
    pub fn path(self, config: &Config) -> &Path {
        match self {
            Kind::Readme => &config.readme,
            Kind::Social => &config.social,
        }
    }
}

/// Gradient top and bottom, the tagline's colour.
const TOP: &str = "#2b66d9";
const BOTTOM: &str = "#18427c";
const TAGLINE_INK: &str = "#fff0e0";

/// README banner: title and tagline sizes and baselines, the companion's
/// gap to the text and its top.
const TITLE_SIZE: f32 = 66.0;
const TAGLINE_SIZE: f32 = 32.0;
const TITLE_BASELINE: f32 = 67.0;
const TAGLINE_BASELINE: f32 = 107.0;
const HERO_GAP: f32 = 14.0;
const HERO_TOP: i32 = 4;

/// Social preview: text sizes and baselines, the companion's height and
/// left margin.
const SOCIAL_TITLE_SIZE: f32 = 112.0;
const SOCIAL_TAGLINE_SIZE: f32 = 38.0;
const SOCIAL_TITLE_BASELINE: f32 = 318.0;
const SOCIAL_TAGLINE_BASELINE: f32 = 382.0;
const SOCIAL_HERO: u32 = 470;
const SOCIAL_MARGIN: u32 = 80;

/// A blurred ellipse of light: centre, radii, colour and opacity.
struct Glow {
    centre: (f32, f32),
    radii: (f32, f32),
    colour: &'static str,
    opacity: f32,
}

/// Blur of both lights.
const GLOW_BLUR: f32 = 120.0;

/// Warm light behind the banner's front screens (70/255).
const WARM: Glow = Glow {
    centre: (640.0, 575.0),
    radii: (300.0, 325.0),
    colour: "#ffa200",
    opacity: 0.275,
};

/// White light behind the social preview's companion: warm light on the
/// blue turns grey around the art.
const SPOTLIGHT: Glow = Glow {
    centre: (350.0, 330.0),
    radii: (300.0, 280.0),
    colour: "#ffffff",
    opacity: 0.3,
};

/// Frame shadow: opacity (110/255), blur and drop.
const SHADOW_OPACITY: f32 = 0.43;
const SHADOW_BLUR: f32 = 16.0;
const SHADOW_DROP: f32 = 6.0;

/// Window chrome: title bar height, corner radius, title bar colour and
/// ink, title size.
const BAR: u32 = 28;
const RADIUS: f32 = 9.0;
const CHROME: &str = "#e3e6ea";
const CHROME_INK: &str = "#3c4043";
const WINDOW_TITLE: f32 = 13.0;

/// Title bar buttons, left to right: close, minimise, zoom.
const BUTTONS: [&str; 3] = ["#ff5f57", "#febc2e", "#28c840"];

/// Browser address field: left edge after the buttons, right margin,
/// height, text size.
const ADDRESS_LEFT: f32 = 66.0;
const ADDRESS_MARGIN: f32 = 12.0;
const ADDRESS_HEIGHT: f32 = 18.0;
const ADDRESS_TEXT: f32 = 12.0;

/// Phone bezels around the screen, status bar height, corner radius of
/// the body's shadow.
const BEZEL_X: u32 = 12;
const BEZEL_TOP: u32 = 40;
const BEZEL_BOTTOM: u32 = 36;
const STATUS_H: u32 = 14;
const PHONE_RADIUS: f32 = 44.0;

/// Phone colours: body, outer and inner rim, earpiece and speaker, camera.
const BODY: &str = "#1c1e21";
const RIM: &str = "#464a50";
const INNER_RIM: &str = "#303338";
const GRILLE: &str = "#373a3f";
const LENS: &str = "#282c34";

/// Status bar: clock text, size and baseline below the bar's top, the
/// dimming of the screen's top colour, the brightness above which the bar
/// takes dark ink, the inks, and how many top rows give the colour.
const CLOCK: &str = "15:11";
const CLOCK_SIZE: f32 = 10.0;
const CLOCK_BASELINE: f32 = 10.5;
const STATUS_DIM: f32 = 0.82;
const LIGHT: u32 = 150;
const DARK_INK: [u8; 3] = [40, 44, 52];
const LIGHT_INK: [u8; 3] = [255, 255, 255];
const TOP_ROWS: u32 = 4;

/// Draws `kind` from the repository's inputs and the Server checkout.
pub fn render(kind: Kind, config: &Config, server: &Path) -> Result<RgbImage, String> {
    let (width, height) = kind.size();
    let mut canvas = Canvas::new(width, height)?;
    let hero = draw::trim(draw::load(&server.join(&config.companion.pose))?);
    match kind {
        Kind::Readme => readme(&mut canvas, config, hero)?,
        Kind::Social => social(&mut canvas, config, hero)?,
    }
    Ok(canvas.into_rgb())
}

/// The README banner: screens back to front, then the heading above them.
fn readme(canvas: &mut Canvas, config: &Config, hero: RgbaImage) -> Result<(), String> {
    background(canvas, &WARM)?;
    for screen in &config.screens {
        frame(canvas, screen)?;
    }

    // Companion, title and tagline centred together.
    let hero = draw::to_height(hero, config.companion.height);
    let title = heading(&config.title, TITLE_SIZE, Weight::Bold, "white");
    let tagline = heading(&config.tagline, TAGLINE_SIZE, Weight::Regular, TAGLINE_INK);
    let text = canvas.text_width(&title)?.max(canvas.text_width(&tagline)?);
    let centre = canvas.width() as f32 / 2.0 + (hero.width() as f32 + HERO_GAP) / 2.0;
    let left = (centre - text / 2.0 - HERO_GAP - hero.width() as f32).round();
    canvas.picture(&hero, left as i32, HERO_TOP)?;
    canvas.svg(&format!(
        "{}{}",
        title.svg(centre, TITLE_BASELINE),
        tagline.svg(centre, TAGLINE_BASELINE)
    ))
}

/// The social preview: the companion large on the left, the text right.
fn social(canvas: &mut Canvas, config: &Config, hero: RgbaImage) -> Result<(), String> {
    background(canvas, &SPOTLIGHT)?;
    let hero = draw::to_height(hero, SOCIAL_HERO);
    let top = (canvas.height() - hero.height()) / 2;
    canvas.picture(&hero, SOCIAL_MARGIN as i32, top as i32)?;

    // Text centred in the space right of the companion.
    let centre = (SOCIAL_MARGIN + hero.width() + canvas.width()) as f32 / 2.0;
    let title = heading(&config.title, SOCIAL_TITLE_SIZE, Weight::Bold, "white");
    let tagline = heading(
        &config.tagline,
        SOCIAL_TAGLINE_SIZE,
        Weight::Regular,
        TAGLINE_INK,
    );
    canvas.svg(&format!(
        "{}{}",
        title.svg(centre, SOCIAL_TITLE_BASELINE),
        tagline.svg(centre, SOCIAL_TAGLINE_BASELINE)
    ))
}

/// A centred heading line.
fn heading<'a>(text: &'a str, size: f32, weight: Weight, fill: &'a str) -> Line<'a> {
    Line {
        text,
        size,
        weight,
        fill,
        anchor: Anchor::Middle,
    }
}

/// The gradient and a light.
fn background(canvas: &mut Canvas, glow: &Glow) -> Result<(), String> {
    let (w, h) = (canvas.width(), canvas.height());
    let ((cx, cy), (rx, ry)) = (glow.centre, glow.radii);
    let (colour, opacity) = (glow.colour, glow.opacity);
    canvas.svg(&format!(
        r#"<defs>
<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="{TOP}"/><stop offset="1" stop-color="{BOTTOM}"/>
</linearGradient>
<filter id="glow" filterUnits="userSpaceOnUse" x="0" y="0" width="{w}" height="{h}">
<feGaussianBlur stdDeviation="{GLOW_BLUR}"/>
</filter>
</defs>
<rect width="{w}" height="{h}" fill="url(#sky)"/>
<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{colour}" fill-opacity="{opacity}" filter="url(#glow)"/>"#
    ))
}

/// One screen in its frame.
fn frame(canvas: &mut Canvas, screen: &Screen) -> Result<(), String> {
    let shot = draw::load(screen.shot())?;
    match screen {
        Screen::Window {
            title,
            x,
            y,
            width,
            max_height,
            ..
        } => {
            let label = Line {
                text: title,
                size: WINDOW_TITLE,
                weight: Weight::Regular,
                fill: CHROME_INK,
                anchor: Anchor::Middle,
            };
            let at = (*x, *y);
            let text = label.svg(*x as f32 + *width as f32 / 2.0, bar_middle(*y) + 4.5);
            window(canvas, &shot, (at, *width, *max_height), &text)
        }
        Screen::Browser {
            address,
            x,
            y,
            width,
            max_height,
            ..
        } => {
            let at = (*x, *y);
            let text = field(address, at, *width);
            window(canvas, &shot, (at, *width, *max_height), &text)
        }
        Screen::Phone { x, y, width, .. } => phone(canvas, &shot, (*x, *y), *width),
    }
}

/// The vertical middle of a title bar whose top is `y`.
fn bar_middle(y: i32) -> f32 {
    y as f32 + BAR as f32 / 2.0
}

/// A browser's address field with `address` centred in it.
fn field(address: &str, (x, y): (i32, i32), width: u32) -> String {
    let left = x as f32 + ADDRESS_LEFT;
    let w = width as f32 - ADDRESS_LEFT - ADDRESS_MARGIN;
    let top = y as f32 + (BAR as f32 - ADDRESS_HEIGHT) / 2.0;
    let text = Line {
        text: address,
        size: ADDRESS_TEXT,
        weight: Weight::Regular,
        fill: CHROME_INK,
        anchor: Anchor::Middle,
    };
    format!(
        r##"<rect x="{left}" y="{top}" width="{w}" height="{ADDRESS_HEIGHT}" rx="{}" fill="#ffffff"/>{}"##,
        ADDRESS_HEIGHT / 2.0,
        text.svg(left + w / 2.0, bar_middle(y) + 4.0),
    )
}

/// A window: shadow, chrome with the title bar's `text`, and the
/// screenshot `width` wide, cut off below `max_height`.
fn window(
    canvas: &mut Canvas,
    shot: &RgbaImage,
    ((x, y), width, max_height): ((i32, i32), u32, u32),
    text: &str,
) -> Result<(), String> {
    let scaled = draw::to_width(shot.clone(), width);
    let shot = draw::top(&scaled, max_height);
    let (w, h) = (width, BAR + shot.height());

    // Shadow and chrome behind the screenshot.
    let buttons: String = BUTTONS
        .iter()
        .enumerate()
        .map(|(i, colour)| {
            let cx = x as f32 + 16.0 + 18.0 * i as f32;
            let cy = bar_middle(y);
            format!(r#"<circle cx="{cx}" cy="{cy}" r="5.5" fill="{colour}"/>"#)
        })
        .collect();
    canvas.svg(&format!(
        r#"{}<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{RADIUS}" fill="{CHROME}"/>{buttons}{text}"#,
        shadow((x, y), (w, h), RADIUS)
    ))?;

    // The screenshot, its lower corners rounded like the window's.
    let outline = format!(r#"<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{RADIUS}"/>"#);
    canvas.clipped(&shot, (x, y + BAR as i32), &outline)?;

    // A thin outline keeps light windows apart where they overlap.
    canvas.svg(&format!(
        r#"<rect x="{}" y="{}" width="{}" height="{}" rx="{RADIUS}" fill="none" stroke="black" stroke-opacity="0.35"/>"#,
        x as f32 + 0.5,
        y as f32 + 0.5,
        w - 1,
        h - 1,
    ))
}

/// The blurred shadow below a frame at `(x, y)` of size `(w, h)`.
fn shadow((x, y): (i32, i32), (w, h): (u32, u32), radius: f32) -> String {
    let drop = y as f32 + SHADOW_DROP;
    format!(
        r#"<defs><filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
<feGaussianBlur stdDeviation="{SHADOW_BLUR}"/></filter></defs>
<rect x="{x}" y="{drop}" width="{w}" height="{h}" rx="{radius}" fill="black" fill-opacity="{SHADOW_OPACITY}" filter="url(#shadow)"/>"#
    )
}

/// A phone with its top-left corner at `(x, y)` and a screen `width`
/// wide: shadow, body, status bar and the screenshot.
fn phone(
    canvas: &mut Canvas,
    shot: &RgbaImage,
    (x, y): (i32, i32),
    width: u32,
) -> Result<(), String> {
    // The screen, opaque as recorded.
    let mut opaque = shot.clone();
    opaque.pixels_mut().for_each(|pixel| pixel[3] = u8::MAX);
    let screen = draw::to_width(opaque, width);
    let size = (
        width + 2 * BEZEL_X,
        BEZEL_TOP + STATUS_H + screen.height() + BEZEL_BOTTOM,
    );

    // Shadow and body, then the status bar tinted like the screen's top.
    let (sx, sy) = (x + BEZEL_X as i32, y + BEZEL_TOP as i32);
    canvas.svg(&format!(
        "{}{}{}",
        shadow((x, y), (size.0 + 1, size.1 + 1), PHONE_RADIUS),
        body((x, y), size),
        status(shot, (sx, sy), width),
    ))?;
    canvas.picture(&screen, sx, sy + STATUS_H as i32)
}

/// The phone body: rims, earpiece, camera and the lower speaker.
fn body((x, y): (i32, i32), (w, h): (u32, u32)) -> String {
    let (w, h) = (w as f32, h as f32);
    let centre = w / 2.0;
    format!(
        r#"<g transform="translate({x} {y})">
<rect x="1" y="1" width="{}" height="{}" rx="33" fill="{BODY}" stroke="{RIM}" stroke-width="2"/>
<rect x="6" y="6" width="{}" height="{}" rx="29" fill="none" stroke="{INNER_RIM}" stroke-width="2"/>
<rect x="{}" y="18" width="69" height="6" rx="3" fill="{GRILLE}"/>
<circle cx="{}" cy="20.5" r="6" fill="{LENS}" stroke="{RIM}"/>
<rect x="{}" y="{}" width="97" height="6" rx="3" fill="{GRILLE}"/>
</g>"#,
        w - 2.0,
        h - 2.0,
        w - 12.0,
        h - 12.0,
        centre - 34.0,
        centre - 63.5,
        centre - 48.0,
        h - 21.0,
    )
}

/// The status bar at `(x, y)`: clock, battery and signal in ink that
/// contrasts with the bar.
fn status(shot: &RgbaImage, (x, y): (i32, i32), width: u32) -> String {
    let (bar, ink) = bar_colours(shot);
    let (bar, ink) = (hex(bar), hex(ink));
    let (x, y) = (x as f32, y as f32);
    let (right, bottom) = (x + width as f32 - 8.0, y + STATUS_H as f32);
    let clock = Line {
        text: CLOCK,
        size: CLOCK_SIZE,
        weight: Weight::Regular,
        fill: &ink,
        anchor: Anchor::Start,
    };
    format!(
        r#"<rect x="{x}" y="{y}" width="{width}" height="{STATUS_H}" fill="{bar}"/>{}
<rect x="{}" y="{}" width="11" height="7" fill="{ink}"/>
<rect x="{}" y="{}" width="2" height="3" fill="{ink}"/>
<polygon points="{},{} {},{} {},{}" fill="{ink}"/>"#,
        clock.svg(x + 8.0, y + CLOCK_BASELINE),
        right - 12.0,
        y + 4.0,
        right - 1.0,
        y + 6.0,
        right - 28.0,
        bottom - 3.0,
        right - 17.0,
        bottom - 3.0,
        right - 17.0,
        y + 3.0,
    )
}

/// The status bar's colour, the screen's top rows dimmed, and its ink.
fn bar_colours(screen: &RgbaImage) -> ([u8; 3], [u8; 3]) {
    // Average of the top rows, rounded.
    let rows = TOP_ROWS.min(screen.height());
    let mut sums = [0u64; 3];
    for y in 0..rows {
        for x in 0..screen.width() {
            let pixel = screen.get_pixel(x, y);
            sums.iter_mut()
                .zip(pixel.0)
                .for_each(|(s, c)| *s += u64::from(c));
        }
    }
    let count = u64::from(rows * screen.width()).max(1);
    let top = sums.map(|s| ((s + count / 2) / count) as u8);

    // Dimmed for the bar; dark ink on light screens.
    let bar = top.map(|c| (f32::from(c) * STATUS_DIM).round_ties_even() as u8);
    let brightness = top.iter().map(|&c| u32::from(c)).sum::<u32>();
    let ink = if brightness > 3 * LIGHT {
        DARK_INK
    } else {
        LIGHT_INK
    };
    (bar, ink)
}

fn hex([r, g, b]: [u8; 3]) -> String {
    format!("#{r:02x}{g:02x}{b:02x}")
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::fs;

    /// A configuration with one screen of each frame, in `dir`, writing
    /// its images there too.
    pub(crate) fn sample(dir: &Path) -> Config {
        let shot = dir.join("shot.png");
        let image = RgbaImage::from_fn(720, 1560, |x, y| {
            if y < 160 {
                return image::Rgba([40, 90, 200, 255]);
            }
            let shade = ((x / 30 + y / 40) % 2) as u8 * 30;
            image::Rgba([230 - shade, 235 - shade, 240, 255])
        });
        image.save(&shot).unwrap();
        let hero = RgbaImage::from_fn(300, 200, |x, y| {
            let inside = (20..280).contains(&x) && (30..190).contains(&y);
            image::Rgba([250, 120, 30, if inside { 255 } else { 0 }])
        });
        fs::create_dir_all(dir.join("static/duo")).unwrap();
        hero.save(dir.join("static/duo/friends.png")).unwrap();
        let shot = shot.display();
        let readme = dir.join("banner.png").display().to_string();
        let social = dir.join("social.png").display().to_string();
        let text = format!(
            r#"
title = "AnkiQuest"
tagline = "Study together, keep your streak"
readme = "{readme}"
social = "{social}"
[companion]
pose = "static/duo/friends.png"
height = 116
[[screen]]
frame = "window"
shot = "{shot}"
title = "Today"
x = 24
y = 178
width = 440
max_height = 600
[[screen]]
frame = "browser"
shot = "{shot}"
address = "ankiquest.example/"
x = 620
y = 318
width = 440
max_height = 600
[[screen]]
frame = "phone"
shot = "{shot}"
x = 508
y = 124
width = 240
"#
        );
        fs::write(dir.join("sample.toml"), &text).unwrap();
        Config::parse(&text).unwrap()
    }

    pub(crate) fn scratch(name: &str) -> std::path::PathBuf {
        let dir =
            std::env::temp_dir().join(format!("ankiquest-banner-{name}-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn renders_both_sizes_the_same_every_time() {
        let dir = scratch("sizes");
        let config = sample(&dir);
        for kind in Kind::ALL {
            let first = render(kind, &config, &dir).unwrap();
            assert_eq!(kind.size(), first.dimensions());
            assert!(first == render(kind, &config, &dir).unwrap());
        }
    }

    #[test]
    fn phone_screens_fill_their_frames() {
        let dir = scratch("phone");
        let banner = render(Kind::Readme, &sample(&dir), &dir).unwrap();
        let (left, top) = (508 + BEZEL_X, 124 + BEZEL_TOP + STATUS_H);
        assert_eq!(&[40, 90, 200], &banner.get_pixel(left + 5, top + 5).0);
    }

    #[test]
    fn a_missing_companion_fails() {
        let dir = scratch("companion");
        let config = sample(&dir);
        let error = render(Kind::Social, &config, &dir.join("nowhere")).unwrap_err();
        assert!(error.contains("friends.png"), "{error}");
    }

    #[test]
    fn bar_ink_contrasts() {
        let light = RgbaImage::from_pixel(8, 8, image::Rgba([240, 240, 240, 255]));
        let dark = RgbaImage::from_pixel(8, 8, image::Rgba([20, 60, 120, 255]));
        assert_eq!(([197, 197, 197], DARK_INK), bar_colours(&light));
        assert_eq!(([16, 49, 98], LIGHT_INK), bar_colours(&dark));
    }
}
