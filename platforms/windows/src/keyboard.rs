//! Low-level keyboard hook (`WH_KEYBOARD_LL`) for `Tab`, `Shift+Tab`, `Alt+Tab`, `Esc`,
//! `Ctrl+Alt+M/L/S/R`, and Unicode text insertion (`SendInput` `KEYEVENTF_UNICODE`) with
//! clipboard-history exclusion (`ExcludeClipboardContentFromMonitorProcessing`).

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HotkeyAction {
    AcceptNextWord,
    AcceptFullSuggestion,
    DismissOverlay,
    ToggleAlternatives,
    OpenQuickMenu,
    SmartWebLookup,
    ReadScreenContext,
    RestartServices,
}

/// Self-injected `dwExtraInfo` tag so `WH_KEYBOARD_LL` never re-processes NexoLLM's own keystrokes.
pub const SELF_INJECTED_TAG: usize = 0x4E45_584F; // "NEXO"

pub fn insert_unicode_text(text: &str) -> bool {
    if text.is_empty() {
        return true;
    }
    #[cfg(target_os = "windows")]
    {
        use windows::Win32::UI::Input::KeyboardAndMouse::{
            SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP, KEYEVENTF_UNICODE, VIRTUAL_KEY,
        };
        let utf16: Vec<u16> = text.encode_utf16().collect();
        let mut inputs: Vec<INPUT> = Vec::with_capacity(utf16.len() * 2);
        for unit in utf16 {
            inputs.push(INPUT {
                r#type: INPUT_KEYBOARD,
                Anonymous: INPUT_0 {
                    ki: KEYBDINPUT {
                        wVk: VIRTUAL_KEY(0),
                        wScan: unit,
                        dwFlags: KEYEVENTF_UNICODE,
                        time: 0,
                        dwExtraInfo: SELF_INJECTED_TAG,
                    },
                },
            });
            inputs.push(INPUT {
                r#type: INPUT_KEYBOARD,
                Anonymous: INPUT_0 {
                    ki: KEYBDINPUT {
                        wVk: VIRTUAL_KEY(0),
                        wScan: unit,
                        dwFlags: KEYEVENTF_UNICODE | KEYEVENTF_KEYUP,
                        time: 0,
                        dwExtraInfo: SELF_INJECTED_TAG,
                    },
                },
            });
        }
        unsafe {
            let sent = SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
            return sent as usize == inputs.len();
        }
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = text;
        false
    }
}
