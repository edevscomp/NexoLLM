//! Pure X11 fallback (`XInput2` key listener + `XTest` / clipboard paste synthesis)
//! used when an X11 desktop session runs without `IBus`.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DisplayProtocol {
    Wayland,
    X11,
}

pub fn detect_display_protocol() -> DisplayProtocol {
    if std::env::var_os("WAYLAND_DISPLAY").is_some()
        || std::env::var("XDG_SESSION_TYPE")
            .map(|v| v.eq_ignore_ascii_case("wayland"))
            .unwrap_or(false)
    {
        DisplayProtocol::Wayland
    } else {
        DisplayProtocol::X11
    }
}
