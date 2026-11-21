//! Drawing: a canvas that takes SVG fragments (resvg) and bitmaps placed at
//! whole pixels, the bundled Roboto, Lanczos downscaling and PNG files.
//! The layouts in `scene` never touch resvg, fonts or files directly.

use std::fs;
use std::path::Path;
use std::sync::Arc;

use image::codecs::png::{CompressionType, PngEncoder};
use image::imageops::{self, FilterType};
use image::{ImageEncoder, RgbImage, Rgba32FImage, RgbaImage};
use resvg::{tiny_skia, usvg};

/// The family name in the bundled faces.
pub const FAMILY: &str = "Roboto";

/// Roboto Bold and Regular (Apache 2.0, `fonts/LICENSE-Roboto.txt`).
const BOLD: &[u8] = include_bytes!("../fonts/Roboto-Bold.ttf");
const REGULAR: &[u8] = include_bytes!("../fonts/Roboto-Regular.ttf");

/// Font weight of a line of text.
#[derive(Clone, Copy, Debug)]
pub enum Weight {
    Regular,
    Bold,
}

/// Where `x` sits on a line of text.
#[derive(Clone, Copy, Debug)]
pub enum Anchor {
    Start,
    Middle,
}

/// One line of text: content, size, weight, colour and anchor.
pub struct Line<'a> {
    pub text: &'a str,
    pub size: f32,
    pub weight: Weight,
    pub fill: &'a str,
    pub anchor: Anchor,
}

impl Line<'_> {
    /// The line as SVG with `x` at the anchor and the baseline at `y`.
    pub fn svg(&self, x: f32, y: f32) -> String {
        let weight = match self.weight {
            Weight::Regular => "normal",
            Weight::Bold => "bold",
        };
        let anchor = match self.anchor {
            Anchor::Start => "start",
            Anchor::Middle => "middle",
        };
        format!(
            r#"<text x="{x}" y="{y}" font-family="{FAMILY}" font-size="{}" font-weight="{weight}" fill="{}" text-anchor="{anchor}">{}</text>"#,
            self.size,
            self.fill,
            escape(self.text),
        )
    }
}

/// Text with the characters XML reserves escaped.
fn escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

/// An opaque picture being drawn.
pub struct Canvas {
    pixmap: tiny_skia::Pixmap,
    fonts: Arc<usvg::fontdb::Database>,
}

impl Canvas {
    pub fn new(width: u32, height: u32) -> Result<Canvas, String> {
        let pixmap = tiny_skia::Pixmap::new(width, height).ok_or("empty canvas")?;
        Ok(Canvas {
            pixmap,
            fonts: fonts(),
        })
    }

    pub fn width(&self) -> u32 {
        self.pixmap.width()
    }

    pub fn height(&self) -> u32 {
        self.pixmap.height()
    }

    /// Draws an SVG fragment in canvas coordinates.
    pub fn svg(&mut self, body: &str) -> Result<(), String> {
        let tree = tree(&self.fonts, (self.width(), self.height()), body)?;
        resvg::render(
            &tree,
            tiny_skia::Transform::identity(),
            &mut self.pixmap.as_mut(),
        );
        Ok(())
    }

    /// Draws `image` with its top-left corner at a whole pixel.
    pub fn picture(&mut self, image: &RgbaImage, x: i32, y: i32) -> Result<(), String> {
        self.place(image, (x, y), None)
    }

    /// Draws `image` at a whole pixel, only inside the SVG `shape`.
    pub fn clipped(
        &mut self,
        image: &RgbaImage,
        at: (i32, i32),
        shape: &str,
    ) -> Result<(), String> {
        let mut outline =
            tiny_skia::Pixmap::new(self.width(), self.height()).ok_or("empty mask")?;
        let tree = tree(&self.fonts, (self.width(), self.height()), shape)?;
        resvg::render(
            &tree,
            tiny_skia::Transform::identity(),
            &mut outline.as_mut(),
        );
        let mask = tiny_skia::Mask::from_pixmap(outline.as_ref(), tiny_skia::MaskType::Alpha);
        self.place(image, at, Some(&mask))
    }

    fn place(
        &mut self,
        image: &RgbaImage,
        (x, y): (i32, i32),
        mask: Option<&tiny_skia::Mask>,
    ) -> Result<(), String> {
        let mut pixmap =
            tiny_skia::Pixmap::new(image.width(), image.height()).ok_or("empty image")?;
        for (target, source) in pixmap.pixels_mut().iter_mut().zip(image.pixels()) {
            let [r, g, b, a] = source.0;
            *target = tiny_skia::ColorU8::from_rgba(r, g, b, a).premultiply();
        }
        self.pixmap.draw_pixmap(
            x,
            y,
            pixmap.as_ref(),
            &tiny_skia::PixmapPaint::default(),
            tiny_skia::Transform::identity(),
            mask,
        );
        Ok(())
    }

    /// The drawn width of a line of text.
    pub fn text_width(&self, line: &Line) -> Result<f32, String> {
        let tree = tree(&self.fonts, (1, 1), &line.svg(0.0, 0.0))?;

        // resvg has no bounding box for a fragment that draws nothing.
        Ok(tree
            .root()
            .abs_bounding_box()
            .map_or(0.0, |bounds| bounds.width()))
    }

    /// The finished picture; the background makes every pixel opaque.
    pub fn into_rgb(self) -> RgbImage {
        let bytes = self
            .pixmap
            .pixels()
            .iter()
            .flat_map(|pixel| {
                let colour = pixel.demultiply();
                [colour.red(), colour.green(), colour.blue()]
            })
            .collect();
        RgbImage::from_raw(self.pixmap.width(), self.pixmap.height(), bytes).unwrap_or_default()
    }
}

/// The bundled Roboto as resvg's font database.
fn fonts() -> Arc<usvg::fontdb::Database> {
    let mut fonts = usvg::fontdb::Database::new();
    fonts.load_font_data(BOLD.to_vec());
    fonts.load_font_data(REGULAR.to_vec());
    fonts.set_sans_serif_family(FAMILY);
    Arc::new(fonts)
}

/// Parses an SVG fragment the size of the canvas.
fn tree(
    fonts: &Arc<usvg::fontdb::Database>,
    (w, h): (u32, u32),
    body: &str,
) -> Result<usvg::Tree, String> {
    let svg = format!(
        r#"<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>"#
    );
    let options = usvg::Options {
        font_family: FAMILY.into(),
        fontdb: fonts.clone(),
        ..usvg::Options::default()
    };
    usvg::Tree::from_str(&svg, &options).map_err(|e| format!("SVG: {e}"))
}

/// An image file as RGBA.
pub fn load(path: &Path) -> Result<RgbaImage, String> {
    let image = image::open(path).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(image.into_rgba8())
}

/// Lanczos downscale in premultiplied alpha, so fully transparent pixels do
/// not bleed their colour into the edges. The same as `shrink` in
/// AnkiQuest-Server's `ankiquest-art`, which the art exporters use.
pub fn shrink(image: RgbaImage, width: u32, height: u32) -> RgbaImage {
    if image.dimensions() == (width, height) {
        return image;
    }
    let mut linear = Rgba32FImage::from(image::DynamicImage::ImageRgba8(image));
    for pixel in linear.pixels_mut() {
        let alpha = pixel[3];
        pixel.0[..3].iter_mut().for_each(|c| *c *= alpha);
    }
    let mut small = imageops::resize(&linear, width, height, FilterType::Lanczos3);
    for pixel in small.pixels_mut() {
        unpremultiply(&mut pixel.0);
    }
    image::DynamicImage::ImageRgba32F(small).into_rgba8()
}

/// Divides colour by alpha, clamping Lanczos overshoot.
fn unpremultiply(pixel: &mut [f32; 4]) {
    let alpha = pixel[3].clamp(0.0, 1.0);
    pixel[3] = alpha;
    if alpha == 0.0 {
        pixel[..3].fill(0.0);
        return;
    }
    pixel[..3]
        .iter_mut()
        .for_each(|c| *c = (*c / alpha).clamp(0.0, 1.0));
}

/// Downscales to `width`, keeping the aspect ratio.
pub fn to_width(image: RgbaImage, width: u32) -> RgbaImage {
    let ratio = f64::from(image.height()) / f64::from(image.width());
    let height = (f64::from(width) * ratio).round() as u32;
    shrink(image, width, height)
}

/// Downscales to `height`, keeping the aspect ratio.
pub fn to_height(image: RgbaImage, height: u32) -> RgbaImage {
    let ratio = f64::from(image.width()) / f64::from(image.height());
    let width = (f64::from(height) * ratio).round() as u32;
    shrink(image, width, height)
}

/// The top `height` rows of `image`.
pub fn top(image: &RgbaImage, height: u32) -> RgbaImage {
    imageops::crop_imm(image, 0, 0, image.width(), height.min(image.height())).to_image()
}

/// The art cropped to its visible pixels.
pub fn trim(image: RgbaImage) -> RgbaImage {
    let visible: Vec<(u32, u32)> = image
        .enumerate_pixels()
        .filter(|(_, _, pixel)| pixel[3] > 0)
        .map(|(x, y, _)| (x, y))
        .collect();
    let Some(left) = visible.iter().map(|p| p.0).min() else {
        return image;
    };
    let right = visible.iter().map(|p| p.0).max().unwrap_or(left);
    let top = visible.iter().map(|p| p.1).min().unwrap_or(0);
    let bottom = visible.iter().map(|p| p.1).max().unwrap_or(top);
    imageops::crop_imm(&image, left, top, right - left + 1, bottom - top + 1).to_image()
}

/// An image as a compact PNG.
pub fn encode(image: &RgbImage) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    let encoder =
        PngEncoder::new_with_quality(&mut bytes, CompressionType::Best, Default::default());
    encoder
        .write_image(
            image,
            image.width(),
            image.height(),
            image::ExtendedColorType::Rgb8,
        )
        .map_err(|e| format!("PNG encoding failed: {e}"))?;
    Ok(bytes)
}

/// Writes `bytes` to `path`, creating its folder.
pub fn write(path: &Path, bytes: &[u8]) -> Result<(), String> {
    if let Some(folder) = path.parent() {
        fs::create_dir_all(folder).map_err(|e| format!("{}: {e}", folder.display()))?;
    }
    fs::write(path, bytes).map_err(|e| format!("{}: {e}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trim_drops_transparent_margins() {
        let mut image = RgbaImage::new(10, 8);
        image.put_pixel(3, 2, image::Rgba([1, 2, 3, 255]));
        image.put_pixel(6, 5, image::Rgba([1, 2, 3, 9]));
        assert_eq!((4, 4), trim(image).dimensions());
    }

    #[test]
    fn shrink_keeps_transparent_pixels_from_bleeding() {
        let mut image = RgbaImage::from_pixel(4, 4, image::Rgba([255, 0, 0, 0]));
        image.put_pixel(0, 0, image::Rgba([0, 0, 255, 255]));
        let small = shrink(image, 2, 2);
        assert_eq!((2, 2), small.dimensions());
        assert!(small.pixels().all(|pixel| pixel[0] == 0));
    }

    #[test]
    fn text_is_escaped() {
        let line = Line {
            text: "A & B <c>",
            size: 10.0,
            weight: Weight::Regular,
            fill: "white",
            anchor: Anchor::Start,
        };
        assert!(line.svg(0.0, 0.0).contains(">A &amp; B &lt;c&gt;<"));
    }

    #[test]
    fn bundled_roboto_draws_text() {
        let canvas = Canvas::new(1, 1).unwrap();
        let line = Line {
            text: "AnkiQuest",
            size: 66.0,
            weight: Weight::Bold,
            fill: "white",
            anchor: Anchor::Middle,
        };
        assert!(canvas.text_width(&line).unwrap() > 100.0);
    }
}
