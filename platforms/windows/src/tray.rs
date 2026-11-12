//! System tray indicator (`Shell_NotifyIconW`).
//! Safeguard: the tray icon cannot be hidden while Audio Context listening is active.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrayBadgeState {
    Idle,
    ScreenReading,
    AudioListening,
    Paused,
}

pub struct SystemTray {
    pub user_wants_visible: bool,
    pub state: TrayBadgeState,
}

impl SystemTray {
    pub fn new(user_wants_visible: bool) -> Self {
        Self {
            user_wants_visible,
            state: TrayBadgeState::Idle,
        }
    }

    /// Enforces the mandatory visibility safeguard whenever microphone/call listening is active.
    pub fn effective_visible(&self) -> bool {
        self.user_wants_visible || self.state == TrayBadgeState::AudioListening
    }
}
