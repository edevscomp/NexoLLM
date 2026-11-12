//! `org.kde.StatusNotifierItem` system tray indicator.
//! Safeguard: stays visible whenever Audio Context listening is active, regardless of user preference.

pub struct StatusNotifierTray {
    pub user_show_in_bar: bool,
    pub audio_listening: bool,
}

impl StatusNotifierTray {
    pub fn effective_visible(&self) -> bool {
        self.user_show_in_bar || self.audio_listening
    }
}
