//! Screen Context via `xdg-desktop-portal` (`org.freedesktop.portal.ScreenCast` / `Screenshot`
//! with persistent session restore token) + local `Tesseract` OCR in all 6 languages (`eng+ita+spa+fra+deu+por`).

use zeroize::Zeroize;

pub const TESSERACT_SIX_LANG_SPEC: &str = "eng+ita+spa+fra+deu+por";

pub fn tesseract_lang_for_iso(iso: &str) -> &'static str {
    match iso {
        "it" => "ita",
        "es" => "spa",
        "fr" => "fra",
        "de" => "deu",
        "pt" => "por",
        _ => "eng",
    }
}

pub fn wipe_portal_frame(pixels: &mut Vec<u8>) {
    pixels.zeroize();
    pixels.clear();
}
