#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use nexollm_core::engine::{EngineState, GpuBackend, LocalAiRuntime, SUPPORTED_LANGUAGES};
use nexollm_core::i18n::{Language, UniversalAudioNotice, AUDIO_CONSENT_VERSION};

fn main() {
    let runtime = LocalAiRuntime::new(GpuBackend::Vulkan);
    let (status, _ready) = match runtime.state {
        EngineState::NoModel => runtime.state.status_badge(),
        ref other => other.status_badge(),
    };
    let notice = UniversalAudioNotice::for_language(Language::English);
    println!(
        "NexoLLM 0.9.0 desktop host initialized | {status} | langs={:?} | audio_consent_v={AUDIO_CONSENT_VERSION} | notice_len={}",
        SUPPORTED_LANGUAGES,
        notice.your_responsibility.len()
    );
}
