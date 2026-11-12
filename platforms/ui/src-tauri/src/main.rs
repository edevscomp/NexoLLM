#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use nexollm_core::engine::{EngineState, GpuBackend, LocalAiRuntime, SUPPORTED_LANGUAGES};
use nexollm_core::i18n::{Language, UniversalAudioNotice, AUDIO_CONSENT_VERSION};
use tao::dpi::LogicalSize;
use tao::event::{Event, WindowEvent};
use tao::event_loop::{ControlFlow, EventLoop};
use tao::window::WindowBuilder;
use wry::WebViewBuilder;

const UI_HTML: &str = include_str!("ui_bundle.html");

fn main() {
    let runtime = LocalAiRuntime::new(GpuBackend::Vulkan);
    let (status, _ready) = match runtime.state {
        EngineState::NoModel => runtime.state.status_badge(),
        ref other => other.status_badge(),
    };
    let notice = UniversalAudioNotice::for_language(Language::English);

    if std::env::args().any(|a| a == "--selftest" || a == "--version") {
        println!(
            "NexoLLM {} desktop host OK | {status} | langs={:?} | audio_consent_v={AUDIO_CONSENT_VERSION} | notice_len={}",
            env!("CARGO_PKG_VERSION"),
            SUPPORTED_LANGUAGES,
            notice.your_responsibility.len()
        );
        return;
    }

    let event_loop = EventLoop::new();
    let window = WindowBuilder::new()
        .with_title("NexoLLM")
        .with_inner_size(LogicalSize::new(980.0, 720.0))
        .with_min_inner_size(LogicalSize::new(820.0, 580.0))
        .build(&event_loop)
        .expect("failed to create NexoLLM desktop window");

    #[cfg(not(target_os = "linux"))]
    let _webview = WebViewBuilder::new()
        .with_html(UI_HTML)
        .build(&window)
        .expect("failed to initialize system WebView");

    #[cfg(target_os = "linux")]
    let _webview = {
        use tao::platform::unix::WindowExtUnix;
        use wry::WebViewBuilderExtUnix;
        let vbox = window.default_vbox().expect("failed to access GTK container");
        WebViewBuilder::new()
            .with_html(UI_HTML)
            .build_gtk(vbox)
            .expect("failed to initialize WebKitGTK WebView")
    };

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;
        if let Event::WindowEvent {
            event: WindowEvent::CloseRequested,
            ..
        } = event
        {
            *control_flow = ControlFlow::Exit;
        }
    });
}
