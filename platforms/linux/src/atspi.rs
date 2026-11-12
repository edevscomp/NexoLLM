//! `AT-SPI2` (`org.a11y.atspi.Text` / `EditableText`) caret & sibling-field context reader.
//! Strictly refuses `ATSPI_ROLE_PASSWORD_TEXT` and sensitive terminal/locker windows.

use serde::{Deserialize, Serialize};

pub const ATSPI_ROLE_PASSWORD_TEXT: u32 = 42;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AtspiSnapshot {
    pub app_id: String,
    pub prefix: String,
    pub suffix: String,
    pub selection: String,
    pub caret_rect: (i32, i32, i32, i32),
    pub password_blocked: bool,
}

pub fn should_block_role(role: u32, app_id: &str) -> bool {
    if role == ATSPI_ROLE_PASSWORD_TEXT {
        return true;
    }
    matches!(
        app_id.to_ascii_lowercase().as_str(),
        "1password" | "bitwarden" | "keepassxc" | "gcr-prompter" | "polkit-gnome-authentication-agent-1"
    )
}
