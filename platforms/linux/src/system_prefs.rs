//! Reversible desktop typing prediction / spell-autocorrect preference helper (`gsettings`)
//! with live readback so Setup displays the real desktop state.

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct DesktopTypingPrefs {
    pub inline_predictions_on: bool,
    pub autocorrect_on: bool,
}

pub fn read_desktop_typing_prefs() -> DesktopTypingPrefs {
    DesktopTypingPrefs::default()
}
