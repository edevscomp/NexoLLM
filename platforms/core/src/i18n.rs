//! Six active languages (`EN`, `IT`, `ES`, `FR`, `DE`, `PT`), `{0}` template interpolation
//! backed by the repository's canonical `scripts/i18n/*.json` catalogs, device-neutral copy,
//! and universal jurisdiction-neutral `AudioPlugin` consent (`v2`).

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::OnceLock;

/// Consent version 2: universal, jurisdiction-neutral notice with zero country/statute citations.
pub const AUDIO_CONSENT_VERSION: u32 = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Language {
    English,
    Italian,
    Spanish,
    French,
    German,
    Portuguese,
}

impl Language {
    pub const ALL: [Language; 6] = [
        Self::English,
        Self::Italian,
        Self::Spanish,
        Self::French,
        Self::German,
        Self::Portuguese,
    ];

    pub fn iso(&self) -> &'static str {
        match self {
            Self::English => "en",
            Self::Italian => "it",
            Self::Spanish => "es",
            Self::French => "fr",
            Self::German => "de",
            Self::Portuguese => "pt",
        }
    }

    pub fn code(&self) -> &'static str {
        match self {
            Self::English => "EN",
            Self::Italian => "IT",
            Self::Spanish => "ES",
            Self::French => "FR",
            Self::German => "DE",
            Self::Portuguese => "PT",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::English => "English",
            Self::Italian => "Italiano",
            Self::Spanish => "Español",
            Self::French => "Français",
            Self::German => "Deutsch",
            Self::Portuguese => "Português",
        }
    }

    pub fn flag(&self) -> &'static str {
        match self {
            Self::English => "🇬🇧",
            Self::Italian => "🇮🇹",
            Self::Spanish => "🇪🇸",
            Self::French => "🇫🇷",
            Self::German => "🇩🇪",
            Self::Portuguese => "🇵🇹",
        }
    }
}

static ES_TABLE: OnceLock<HashMap<String, String>> = OnceLock::new();
static FR_TABLE: OnceLock<HashMap<String, String>> = OnceLock::new();
static DE_TABLE: OnceLock<HashMap<String, String>> = OnceLock::new();
static PT_TABLE: OnceLock<HashMap<String, String>> = OnceLock::new();

pub fn catalog(lang: Language) -> Option<&'static HashMap<String, String>> {
    match lang {
        Language::English | Language::Italian => None,
        Language::Spanish => Some(ES_TABLE.get_or_init(|| {
            serde_json::from_str(include_str!("../../../scripts/i18n/es.json")).unwrap_or_default()
        })),
        Language::French => Some(FR_TABLE.get_or_init(|| {
            serde_json::from_str(include_str!("../../../scripts/i18n/fr.json")).unwrap_or_default()
        })),
        Language::German => Some(DE_TABLE.get_or_init(|| {
            serde_json::from_str(include_str!("../../../scripts/i18n/de.json")).unwrap_or_default()
        })),
        Language::Portuguese => Some(PT_TABLE.get_or_init(|| {
            serde_json::from_str(include_str!("../../../scripts/i18n/pt.json")).unwrap_or_default()
        })),
    }
}

/// Resolves an `(en_template, it_template)` pair in any of the 6 languages and substitutes `{0}`, `{1}`, …
pub fn tr(lang: Language, en: &str, it: &str, args: &[&str]) -> String {
    let base: &str = match lang {
        Language::English => en,
        Language::Italian => it,
        other => catalog(other)
            .and_then(|m| m.get(en).map(String::as_str))
            .unwrap_or(en),
    };
    let mut out = base.to_string();
    for (idx, val) in args.iter().enumerate().rev() {
        out = out.replace(&format!("{{{idx}}}"), val);
    }
    out
}

/// Universal, jurisdiction-neutral Audio Context legal notice (`v2`) — identical across Windows, Linux & macOS.
#[derive(Debug, Clone, Serialize)]
pub struct UniversalAudioNotice {
    pub how_it_works: String,
    pub your_responsibility: String,
    pub safeguards: String,
    pub consent_local: String,
    pub consent_lawful: String,
}

impl UniversalAudioNotice {
    pub fn for_language(lang: Language) -> Self {
        Self {
            how_it_works: tr(
                lang,
                "Speech from the microphone (and, when screen capture is allowed, from calls and videos) is transcribed on this computer by Whisper. Nothing is sent anywhere. Audio is kept in memory only for the few seconds it takes to transcribe a phrase and is overwritten with zeros; the rolling transcript lives in memory only and is erased when listening stops, when the screen locks, or when the computer sleeps.",
                "La voce dal microfono (e, se la registrazione schermo è consentita, da chiamate e video) viene trascritta su questo computer da Whisper. Non viene inviato nulla da nessuna parte. L'audio resta in memoria solo per i pochi secondi necessari a trascrivere una frase e viene sovrascritto con zeri; la trascrizione resta solo in memoria e viene cancellata quando l'ascolto si ferma, quando lo schermo si blocca o quando il computer va in stop.",
                &[],
            ),
            your_responsibility: tr(
                lang,
                "Capturing or transcribing other people's voices may be subject to privacy and consent rules. Use this feature only for your own voice, for public content, when participants are informed and consent, or when you have appropriate authorization (such as from an academic institution or workplace). Never use it to capture private conversations covertly.",
                "Acquisire o trascrivere la voce di altre persone può essere soggetto a regole su privacy e consenso. Usa questa funzione solo per la tua voce, per contenuti pubblici, quando i partecipanti sono informati e acconsentono, o quando disponi di un'autorizzazione adeguata (ad esempio da un istituto accademico o dal luogo di lavoro). Non usarla mai per acquisire conversazioni private di nascosto.",
                &[],
            ),
            safeguards: tr(
                lang,
                "Listening is always off at launch, keeps the status bar indicator visible while active alongside the operating system's microphone indicator, and stops automatically on screen lock, system sleep, or after one hour without typing. You can clear the transcript or remove the plugin at any time.",
                "L'ascolto è sempre spento all'avvio, mantiene visibile l'indicatore nella barra di stato mentre è attivo insieme all'indicatore del microfono del sistema operativo, e si ferma automaticamente al blocco dello schermo, allo stop del sistema o dopo un'ora senza digitare. Puoi cancellare la trascrizione o rimuovere il plugin in qualsiasi momento.",
                &[],
            ),
            consent_local: tr(
                lang,
                "I understand that this experimental feature transcribes nearby speech on this computer to give context to suggestions.",
                "Comprendo che questa funzione sperimentale trascrive il parlato circostante su questo computer per dare contesto ai suggerimenti.",
                &[],
            ),
            consent_lawful: tr(
                lang,
                "I will use it only for my own voice, for public content, or when participants are informed and consent in accordance with applicable privacy rules.",
                "La userò solo per la mia voce, per contenuti pubblici, o quando i partecipanti sono informati e acconsentono nel rispetto delle regole sulla privacy applicabili.",
                &[],
            ),
        }
    }
}
