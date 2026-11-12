//! On-device screen context via `Windows.Graphics.Capture` and `Windows.Media.Ocr`
//! across all 6 supported languages (`en`, `it`, `es`, `fr`, `de`, `pt`). Bitmaps are dropped immediately.

use nexollm_core::engine::SUPPORTED_LANGUAGES;
use zeroize::Zeroize;

pub fn preferred_ocr_bcp47_tags(primary_iso: &str) -> Vec<&'static str> {
    let map = |iso: &str| match iso {
        "it" => "it-IT",
        "es" => "es-ES",
        "fr" => "fr-FR",
        "de" => "de-DE",
        "pt" => "pt-PT",
        _ => "en-US",
    };
    let mut tags = vec![map(primary_iso)];
    for iso in SUPPORTED_LANGUAGES {
        let tag = map(iso);
        if !tags.contains(&tag) {
            tags.push(tag);
        }
    }
    tags
}

pub fn wipe_frame_bytes(frame: &mut Vec<u8>) {
    frame.zeroize();
    frame.clear();
}
