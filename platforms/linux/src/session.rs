//! `org.freedesktop.login1` (`Session.Lock` and `Manager.PrepareForSleep`) D-Bus listener.
//! Stops Audio Context immediately, overwrites PCM/transcript buffers with zeros, and drops the AES key.

pub const LOGIN1_BUS_NAME: &str = "org.freedesktop.login1";
pub const LOGIN1_MANAGER_PATH: &str = "/org/freedesktop/login1";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Login1SecuritySignal {
    SessionLocked,
    PrepareForSleep,
}
