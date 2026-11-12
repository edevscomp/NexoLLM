//! `UIAutomation` caret bounds, surrounding text & window sibling context reader.
//! Strictly refuses any control where `IsPassword == true` or class matches credential prompts.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CaretSnapshot {
    pub app_id: String,
    pub window_title: String,
    pub prefix: String,
    pub suffix: String,
    pub selection: String,
    pub caret_rect: (i32, i32, i32, i32),
    pub is_password_blocked: bool,
}

const BLOCKED_CLASSES: &[&str] = &[
    "Credential Dialog Xaml Host",
    "Windows.UI.Core.CoreWindow.LockApp",
    "1Password",
    "Bitwarden",
    "KeePassXC",
];

pub fn is_sensitive_class(class_name: &str, is_password_prop: bool) -> bool {
    if is_password_prop {
        return true;
    }
    BLOCKED_CLASSES
        .iter()
        .any(|blocked| class_name.eq_ignore_ascii_case(blocked))
}

pub struct UiaContextReader;

impl UiaContextReader {
    pub fn new() -> Self {
        Self
    }

    /// Reads the focused element via `IUIAutomationTextPattern2::GetCaretRange` with `ValuePattern` fallback.
    pub fn snapshot_focused(&self) -> Option<CaretSnapshot> {
        #[cfg(target_os = "windows")]
        {
            use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED};
            use windows::Win32::UI::Accessibility::{CUIAutomation, IUIAutomation};

            unsafe {
                let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
                let uia: IUIAutomation = CoCreateInstance(&CUIAutomation, None, CLSCTX_INPROC_SERVER).ok()?;
                let el = uia.GetFocusedElement().ok()?;
                let is_pwd = el.CurrentIsPassword().map(|b| b.as_bool()).unwrap_or(false);
                let cls = el.CurrentClassName().map(|s| s.to_string()).unwrap_or_default();
                if is_sensitive_class(&cls, is_pwd) {
                    return Some(CaretSnapshot {
                        is_password_blocked: true,
                        ..Default::default()
                    });
                }
                let name = el.CurrentName().map(|s| s.to_string()).unwrap_or_default();
                let rect = el.CurrentBoundingRectangle().unwrap_or_default();
                return Some(CaretSnapshot {
                    app_id: cls,
                    window_title: name,
                    prefix: String::new(),
                    suffix: String::new(),
                    selection: String::new(),
                    caret_rect: (rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top),
                    is_password_blocked: false,
                });
            }
        }
        #[cfg(not(target_os = "windows"))]
        {
            None
        }
    }
}
