//! `nexollm-core` — shared cross-platform engine, security, statistics, and 6-language localization.

pub mod crypto_store;
pub mod engine;
pub mod i18n;
pub mod rewrite_guard;
pub mod stats;
pub mod updater;

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::NaiveDate;
    use ed25519_dalek::{Signer, SigningKey};

    #[test]
    fn stats_per_app_and_legacy_json_fallback() {
        let legacy: stats::Day = serde_json::from_str(r#"{"words":180,"completions":12}"#).unwrap();
        assert!(legacy.by_app.is_empty());
        assert_eq!(legacy.app_breakdown().get(stats::OTHER_APP), Some(&180));

        let mut s = stats::Stats::default();
        let d1 = NaiveDate::from_ymd_opt(2026, 11, 10).unwrap();
        let d2 = NaiveDate::from_ymd_opt(2026, 11, 11).unwrap();
        s.record(d1, "code", 120);
        s.record(d1, "thunderbird", 45);
        s.record(d2, "code", 90);
        assert_eq!(s.streak(d2), 2);

        let totals = stats::Stats::app_totals(s.days.values());
        assert_eq!(totals[0], ("code".to_string(), 210));
        let palette = stats::AppPalette::new(totals.iter().map(|t| t.0.clone()));
        assert_eq!(palette.color("code").light_hex, "#B8B5F4");
        assert_eq!(stats::nice_ceiling(185) % 4, 0);
    }

    #[test]
    fn ed25519_release_verification_and_anti_downgrade() {
        let signing_key = SigningKey::from_bytes(&[7u8; 32]);
        let pub_b64 = base64::Engine::encode(
            &base64::engine::general_purpose::STANDARD,
            signing_key.verifying_key().to_bytes(),
        );
        let tmp = std::env::temp_dir().join("nexollm_core_test_installer.bin");
        std::fs::write(&tmp, b"NexoLLM 0.9.1 installer payload").unwrap();
        let sha = updater::sha256_hex(&tmp).unwrap();
        let msg = updater::signed_message("0.9.1", &sha);
        let sig = signing_key.sign(&msg);

        assert_eq!(
            updater::verify_release_file(&tmp, &sig.to_bytes(), "0.9.1", "0.9.0", &pub_b64),
            updater::VerifyVerdict::Valid
        );
        assert_eq!(
            updater::verify_release_file(&tmp, &sig.to_bytes(), "0.9.1", "0.9.5", &pub_b64),
            updater::VerifyVerdict::NotNewer
        );
        std::fs::write(&tmp, b"tampered").unwrap();
        assert_eq!(
            updater::verify_release_file(&tmp, &sig.to_bytes(), "0.9.1", "0.9.0", &pub_b64),
            updater::VerifyVerdict::BadSignature
        );
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn all_six_languages_and_whisper_filters_work() {
        assert_eq!(engine::SUPPORTED_LANGUAGES, ["en", "it", "es", "fr", "de", "pt"]);
        for lang in i18n::Language::ALL {
            let rendered = i18n::tr(lang, "Downloading {0}…", "Download di {0}…", &["Gemma 4"]);
            assert!(rendered.contains("Gemma 4"));
            let contrib = i18n::tr(lang, "Contributors: {0}", "Contributors: {0}", &["EdevS · Claude · Gemini"]);
            assert!(contrib.contains("Claude") && contrib.contains("Gemini"));
            let notice = i18n::UniversalAudioNotice::for_language(lang);
            assert!(!notice.your_responsibility.to_lowercase().contains("gdpr"));
            assert!(!notice.your_responsibility.to_lowercase().contains("615-bis"));
        }
        assert_eq!(engine::clean_whisper_transcript("Gracias por ver el video"), "");
        assert_eq!(engine::clean_whisper_transcript("Merci d'avoir regardé"), "");
        assert_eq!(engine::clean_whisper_transcript("Vielen Dank fürs Zuschauen"), "");
        assert_eq!(engine::clean_whisper_transcript("Obrigado por assistir"), "");
    }

    #[test]
    fn encrypted_store_locks_and_zeroizes_key() {
        let mut store = crypto_store::EncryptedStore::unlocked(crypto_store::EncryptedStore::generate_key());
        let blob = store.seal(b"secret memory note").unwrap();
        assert_eq!(store.open(&blob).unwrap(), b"secret memory note");
        store.lock();
        assert!(store.is_locked());
        assert!(store.open(&blob).is_err());
    }
}
