//! `PipeWire` microphone stream (with `AmbientGain` far-field DSP) and default sink `.monitor`
//! stream for call/meeting audio, transcribed locally by `whisper.cpp` and zeroized on stop.

use nexollm_core::engine::{AmbientGain, SpeechSegmenter};
use zeroize::Zeroize;

pub struct PipeWireAudioCapture {
    gain: AmbientGain,
    mic_segmenter: SpeechSegmenter,
    monitor_segmenter: SpeechSegmenter,
    mic_ring: Vec<f32>,
    monitor_ring: Vec<f32>,
    pub listening: bool,
}

impl Default for PipeWireAudioCapture {
    fn default() -> Self {
        Self::new()
    }
}

impl PipeWireAudioCapture {
    pub fn new() -> Self {
        Self {
            gain: AmbientGain::default(),
            mic_segmenter: SpeechSegmenter::new(0.02),
            monitor_segmenter: SpeechSegmenter::new(0.008),
            mic_ring: Vec::new(),
            monitor_ring: Vec::new(),
            listening: false,
        }
    }

    pub fn ingest_mic(&mut self, samples: &mut [f32], sample_rate: f64) -> f32 {
        let level = self.gain.process_mono(samples, sample_rate);
        self.mic_ring.extend_from_slice(samples);
        level
    }

    pub fn stop_and_wipe(&mut self) {
        self.listening = false;
        self.mic_ring.zeroize();
        self.mic_ring.clear();
        self.monitor_ring.zeroize();
        self.monitor_ring.clear();
        self.mic_segmenter.reset();
        self.monitor_segmenter.reset();
        self.gain.reset();
    }
}

impl Drop for PipeWireAudioCapture {
    fn drop(&mut self) {
        self.stop_and_wipe();
    }
}
