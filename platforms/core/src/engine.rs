//! Local GGUF (`llama.cpp`) and speech (`whisper.cpp`) engines, `AmbientGain` far-field DSP,
//! and `SpeechSegmenter` with mandatory RAM zeroization on stop, screen lock, or sleep.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};
use zeroize::Zeroize;

/// Supported speech-to-text and interface ISO 639-1 language codes.
pub const SUPPORTED_LANGUAGES: [&str; 6] = ["en", "it", "es", "fr", "de", "pt"];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum GpuBackend {
    Vulkan,
    Cuda,
    DirectMl,
    Rocm,
    CpuSimd,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum EngineState {
    NoModel,
    Downloading { name: String, percent: u8 },
    Verifying { name: String },
    Loading { path: String },
    Ready { model_name: String },
    Error { message: String },
}

impl EngineState {
    /// Never reports a fake "model not found" error on a fresh install with no GGUF file yet.
    pub fn status_badge(&self) -> (String, bool) {
        match self {
            Self::NoModel => ("No model installed · download one in Models".into(), false),
            Self::Downloading { name, percent } => (format!("Downloading {name} · {percent}%"), false),
            Self::Verifying { name } => (format!("Verifying {name}…"), false),
            Self::Loading { path } => (format!("Loading {path}…"), false),
            Self::Ready { model_name } => (format!("Ready · {model_name}"), true),
            Self::Error { message } => (format!("Error · {message}"), false),
        }
    }
}

/// Curated GGUF model entry verified by SHA-256 before loading.
#[derive(Debug, Clone, Serialize)]
pub struct CatalogModel {
    pub id: &'static str,
    pub name: &'static str,
    pub bytes: u64,
    pub sha256: &'static str,
    pub min_ram_gb: u32,
}

/// Optional downloadable Whisper model for the Audio Context plugin.
#[derive(Debug, Clone, Serialize)]
pub struct WhisperCatalogModel {
    pub id: &'static str,
    pub name: &'static str,
    pub bytes: u64,
    pub sha256: &'static str,
}

pub const WHISPER_TURBO: WhisperCatalogModel = WhisperCatalogModel {
    id: "ggml-large-v3-turbo-q5_0.bin",
    name: "Whisper Large v3 Turbo",
    bytes: 574_041_195,
    sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
};

pub const WHISPER_SMALL: WhisperCatalogModel = WhisperCatalogModel {
    id: "ggml-small-q5_1.bin",
    name: "Whisper Small",
    bytes: 190_085_487,
    sha256: "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb",
};

pub fn verify_file_sha256(path: &Path, expected_hex: &str) -> std::io::Result<bool> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = file.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    let digest = hasher
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<String>();
    Ok(digest.eq_ignore_ascii_case(expected_hex))
}

/// Far-field automatic gain control: 120 Hz high-pass, 0.55 consonant pre-emphasis,
/// adaptive gain and soft `tanh` peak limiting.
pub struct AmbientGain {
    pub gain: f32,
    hp_prev_in: f32,
    hp_prev_out: f32,
    emph_prev: f32,
}

impl Default for AmbientGain {
    fn default() -> Self {
        Self {
            gain: 10.0,
            hp_prev_in: 0.0,
            hp_prev_out: 0.0,
            emph_prev: 0.0,
        }
    }
}

impl AmbientGain {
    pub const TARGET_RMS: f32 = 0.20;
    pub const NOISE_FLOOR: f32 = 0.00025;
    pub const MAX_GAIN: f32 = 45.0;
    pub const MIN_GAIN: f32 = 1.0;
    pub const HIGH_PASS_HZ: f64 = 120.0;
    pub const PRE_EMPHASIS: f32 = 0.55;

    pub fn next_gain(current: f32, rms: f32) -> f32 {
        if rms <= Self::NOISE_FLOOR {
            return current;
        }
        let desired = (Self::TARGET_RMS / rms).clamp(Self::MIN_GAIN, Self::MAX_GAIN);
        let rate = if desired > current {
            0.22
        } else if rms * current > 0.6 {
            0.50
        } else {
            0.08
        };
        current + (desired - current) * rate
    }

    pub fn meter_level(rms: f32) -> f32 {
        let db = 20.0 * rms.max(0.000_01).log10();
        ((db + 48.0) / 42.0).clamp(0.0, 1.0)
    }

    pub fn process_mono(&mut self, samples: &mut [f32], sample_rate: f64) -> f32 {
        if samples.is_empty() {
            return 0.0;
        }
        let sr = if sample_rate > 0.0 { sample_rate } else { 48_000.0 };
        let rc = 1.0 / (2.0 * std::f64::consts::PI * Self::HIGH_PASS_HZ);
        let alpha = (rc / (rc + 1.0 / sr)) as f32;

        let mut sum = 0.0f32;
        for s in samples.iter_mut() {
            let x = *s;
            let hp = alpha * (self.hp_prev_out + x - self.hp_prev_in);
            self.hp_prev_in = x;
            self.hp_prev_out = hp;
            let cleaned = hp - Self::PRE_EMPHASIS * self.emph_prev;
            self.emph_prev = hp;
            sum += cleaned * cleaned;
            *s = cleaned;
        }
        let rms = (sum / samples.len() as f32).sqrt();
        self.gain = Self::next_gain(self.gain, rms);
        for s in samples.iter_mut() {
            *s = (*s * self.gain).tanh();
        }
        Self::meter_level((rms * self.gain).min(1.0))
    }

    pub fn reset(&mut self) {
        self.hp_prev_in = 0.0;
        self.hp_prev_out = 0.0;
        self.emph_prev = 0.0;
        self.gain = 10.0;
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum SegmentEvent {
    None,
    Partial(Vec<f32>),
    Final(Vec<f32>),
}

/// 16 kHz utterance segmenter that discards silence and overwrites RAM buffers with zeros on reset.
pub struct SpeechSegmenter {
    pub threshold: f32,
    pub pause_seconds: f64,
    pub max_seconds: f64,
    pub partial_every: f64,
    pub min_speech_seconds: f64,
    buffer: Vec<f32>,
    pre_roll: Vec<f32>,
    speech_samples: usize,
    silence_run: usize,
    since_emit: usize,
    noise_level: f32,
}

impl SpeechSegmenter {
    pub const RATE: usize = 16_000;

    pub fn new(threshold: f32) -> Self {
        Self {
            threshold,
            pause_seconds: 0.7,
            max_seconds: 12.0,
            partial_every: 2.5,
            min_speech_seconds: 0.3,
            buffer: Vec::new(),
            pre_roll: Vec::new(),
            speech_samples: 0,
            silence_run: 0,
            since_emit: 0,
            noise_level: threshold / 3.0,
        }
    }

    pub fn append(&mut self, samples: &[f32]) -> SegmentEvent {
        let frame = Self::RATE / 50; // 20 ms
        let mut idx = 0;
        let mut event = SegmentEvent::None;
        while idx < samples.len() {
            let end = (idx + frame).min(samples.len());
            let chunk = &samples[idx..end];
            idx = end;
            let sum: f32 = chunk.iter().map(|v| v * v).sum();
            let rms = (sum / chunk.len().max(1) as f32).sqrt();
            self.noise_level = if rms < self.noise_level {
                self.noise_level * 0.9 + rms * 0.1
            } else {
                self.noise_level * 0.998 + rms * 0.002
            };
            let speech = rms > self.threshold.max(self.noise_level * 3.0);
            if self.buffer.is_empty() {
                if speech {
                    self.buffer.extend_from_slice(&self.pre_roll);
                    self.buffer.extend_from_slice(chunk);
                    self.speech_samples = chunk.len();
                    self.silence_run = 0;
                    self.since_emit = self.buffer.len();
                } else {
                    self.pre_roll.extend_from_slice(chunk);
                    let keep = Self::RATE * 3 / 10;
                    if self.pre_roll.len() > keep {
                        let drop_n = self.pre_roll.len() - keep;
                        self.pre_roll[..drop_n].zeroize();
                        self.pre_roll.drain(..drop_n);
                    }
                }
                continue;
            }
            self.buffer.extend_from_slice(chunk);
            self.since_emit += chunk.len();
            if speech {
                self.speech_samples += chunk.len();
                self.silence_run = 0;
            } else {
                self.silence_run += chunk.len();
            }
            let paused = self.silence_run as f64 >= self.pause_seconds * Self::RATE as f64;
            let too_long = self.buffer.len() as f64 >= self.max_seconds * Self::RATE as f64;
            if paused || too_long {
                let enough = self.speech_samples as f64 >= self.min_speech_seconds * Self::RATE as f64;
                let out = if enough { Some(self.buffer.clone()) } else { None };
                self.reset();
                if let Some(phrase) = out {
                    event = SegmentEvent::Final(phrase);
                }
            } else if self.since_emit as f64 >= self.partial_every * Self::RATE as f64 {
                self.since_emit = 0;
                if !matches!(event, SegmentEvent::Final(_)) {
                    event = SegmentEvent::Partial(self.buffer.clone());
                }
            }
        }
        event
    }

    /// Overwrites all in-memory PCM samples with zeros before freeing.
    pub fn reset(&mut self) {
        self.buffer.zeroize();
        self.buffer.clear();
        self.pre_roll.zeroize();
        self.pre_roll.clear();
        self.speech_samples = 0;
        self.silence_run = 0;
        self.since_emit = 0;
    }

    pub fn is_empty(&self) -> bool {
        self.buffer.is_empty()
    }
}

impl Drop for SpeechSegmenter {
    fn drop(&mut self) {
        self.reset();
    }
}

/// Ordered candidate languages for Whisper automatic mode across all 6 active languages.
pub fn allowed_whisper_languages(starting_with: &str) -> Vec<&'static str> {
    let prefix: String = starting_with.chars().take(2).collect::<String>().to_ascii_lowercase();
    let head = SUPPORTED_LANGUAGES
        .iter()
        .copied()
        .find(|c| *c == prefix)
        .unwrap_or("en");
    let mut out = vec![head];
    for lang in SUPPORTED_LANGUAGES {
        if lang != head {
            out.push(lang);
        }
    }
    out
}

/// Filters Whisper silence hallucinations and bracketed non-speech tags across EN, IT, ES, FR, DE, PT.
pub fn clean_whisper_transcript(raw: &str) -> String {
    let mut stripped = String::with_capacity(raw.len());
    let mut in_square = 0usize;
    let mut in_paren = 0usize;
    for ch in raw.chars() {
        match ch {
            '[' => in_square += 1,
            ']' if in_square > 0 => in_square -= 1,
            '(' => in_paren += 1,
            ')' if in_paren > 0 => in_paren -= 1,
            '♪' => stripped.push(' '),
            _ if in_square == 0 && in_paren == 0 => stripped.push(ch),
            _ => stripped.push(' '),
        }
    }
    let collapsed = stripped.split_whitespace().collect::<Vec<_>>().join(" ");
    let lower = collapsed
        .to_lowercase()
        .trim_matches(|c: char| c.is_ascii_punctuation() || c.is_whitespace() || c == '¡' || c == '¿')
        .to_string();

    const HALLUCINATIONS: &[&str] = &[
        "thank you for watching",
        "thanks for watching",
        "grazie per la visione",
        "grazie a tutti per la visione",
        "sottotitoli creati dalla comunità amara.org",
        "sottotitoli a cura di qtss",
        "sottotitoli e revisione a cura di qtss",
        "subtitles by the amara.org community",
        "please subscribe",
        "iscriviti al canale",
        "you",
        "grazie",
        "thank you",
        "gracias por ver",
        "gracias por ver el video",
        "subtítulos realizados por la comunidad de amara.org",
        "suscríbete al canal",
        "gracias",
        "merci d'avoir regardé",
        "merci d'avoir regarde",
        "sous-titres réalisés par la communauté d'amara.org",
        "abonnez-vous",
        "merci",
        "vielen dank fürs zuschauen",
        "untertitel der amara.org-community",
        "untertitel im auftrag des zdf",
        "danke fürs zuschauen",
        "obrigado por assistir",
        "legendas pela comunidade amara.org",
        "inscreva-se no canal",
    ];
    if HALLUCINATIONS.contains(&lower.as_str()) || lower.contains("amara.org") || lower.contains("qtss") {
        return String::new();
    }
    if !collapsed.chars().any(|c| c.is_alphabetic()) {
        return String::new();
    }
    collapsed
}

/// Manages the local `llama.cpp` GGUF session and `whisper.cpp` speech context.
pub struct LocalAiRuntime {
    pub model_path: Option<PathBuf>,
    pub backend: GpuBackend,
    pub state: EngineState,
    transcript: String,
    pub is_listening: bool,
}

impl LocalAiRuntime {
    pub fn new(backend: GpuBackend) -> Self {
        Self {
            model_path: None,
            backend,
            state: EngineState::NoModel,
            transcript: String::new(),
            is_listening: false,
        }
    }

    pub fn select_model(&mut self, path: PathBuf) {
        if path.exists() {
            let name = path
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("model.gguf")
                .to_string();
            self.model_path = Some(path);
            self.state = EngineState::Ready { model_name: name };
        } else {
            self.model_path = None;
            self.state = EngineState::NoModel;
        }
    }

    /// Stops audio listening and wipes the rolling transcript from RAM immediately.
    pub fn stop_listening_and_wipe(&mut self) {
        self.is_listening = false;
        self.transcript.zeroize();
        self.transcript.clear();
    }

    pub fn transcript(&self) -> &str {
        &self.transcript
    }
}
