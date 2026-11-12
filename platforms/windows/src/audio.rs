//! WASAPI microphone capture (with `AmbientGain`) + `AUDCLNT_STREAMFLAGS_LOOPBACK` call/media capture,
//! feeding 16 kHz mono float samples into `SpeechSegmenter` + local `whisper.cpp` and wiping RAM on stop.

use nexollm_core::engine::{AmbientGain, SpeechSegmenter};
use zeroize::Zeroize;

pub struct WasapiAudioCapture {
    gain: AmbientGain,
    mic_segmenter: SpeechSegmenter,
    loopback_segmenter: SpeechSegmenter,
    pending_mic: Vec<f32>,
    pending_loopback: Vec<f32>,
    pub listening: bool,
}

impl Default for WasapiAudioCapture {
    fn default() -> Self {
        Self::new()
    }
}

impl WasapiAudioCapture {
    pub fn new() -> Self {
        Self {
            gain: AmbientGain::default(),
            mic_segmenter: SpeechSegmenter::new(0.02),
            loopback_segmenter: SpeechSegmenter::new(0.008),
            pending_mic: Vec::new(),
            pending_loopback: Vec::new(),
            listening: false,
        }
    }

    pub fn push_mic_samples(&mut self, raw: &mut [f32], sample_rate: f64) -> f32 {
        let level = self.gain.process_mono(raw, sample_rate);
        self.pending_mic.extend_from_slice(raw);
        level
    }

    /// Stops capture and overwrites every queued audio buffer in RAM with zeros.
    pub fn stop_and_wipe(&mut self) {
        self.listening = false;
        self.pending_mic.zeroize();
        self.pending_mic.clear();
        self.pending_loopback.zeroize();
        self.pending_loopback.clear();
        self.mic_segmenter.reset();
        self.loopback_segmenter.reset();
        self.gain.reset();
    }
}

impl Drop for WasapiAudioCapture {
    fn drop(&mut self) {
        self.stop_and_wipe();
    }
}
