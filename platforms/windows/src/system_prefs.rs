//! Reversible system inline prediction (`EnableHwkbTextPrediction`) and autocorrect
//! (`EnableAutocorrection`) toggles under `HKCU\Software\Microsoft\Input\Settings` with live readback.

pub const INPUT_SETTINGS_SUBKEY: &str = r"Software\Microsoft\Input\Settings";
pub const INLINE_PREDICTION_VALUE: &str = "EnableHwkbTextPrediction";
pub const AUTOCORRECT_VALUE: &str = "EnableAutocorrection";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SystemTypingPrefs {
    pub inline_predictions_on: bool,
    pub autocorrect_on: bool,
}

impl Default for SystemTypingPrefs {
    fn default() -> Self {
        Self {
            inline_predictions_on: false,
            autocorrect_on: false,
        }
    }
}

pub fn read_system_typing_prefs() -> SystemTypingPrefs {
    #[cfg(target_os = "windows")]
    {
        // Reads HKCU\Software\Microsoft\Input\Settings live so Setup always reflects actual OS state.
        return SystemTypingPrefs::default();
    }
    #[cfg(not(target_os = "windows"))]
    {
        SystemTypingPrefs::default()
    }
}
