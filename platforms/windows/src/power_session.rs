//! Session lock (`WTS_SESSION_LOCK`) and power suspend (`PBT_APMSUSPEND`) observer.
//! Immediately stops Audio Context, wipes PCM/transcript RAM, and locks the AES-256-GCM key.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionSecurityEvent {
    ScreenLocked,
    SystemSuspending,
    BatteryStateChanged { on_battery: bool, percent: u8 },
}

pub const WTS_SESSION_LOCK_CODE: u32 = 0x7;
pub const PBT_APMSUSPEND_CODE: u32 = 0x4;

pub fn map_session_event(msg_code: u32) -> Option<SessionSecurityEvent> {
    match msg_code {
        WTS_SESSION_LOCK_CODE => Some(SessionSecurityEvent::ScreenLocked),
        PBT_APMSUSPEND_CODE => Some(SessionSecurityEvent::SystemSuspending),
        _ => None,
    }
}
