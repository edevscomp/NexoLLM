//! Non-activating layered Win32 overlays (`WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TOPMOST`)
//! for inline ghost suggestions, the `Ctrl+Alt+M` Quick Menu, and Web Lookup cards
//! (which automatically close on outside mouse click once results are shown).

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OverlayPlacement {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub click_through: bool,
    pub dismiss_on_outside_click: bool,
}

pub struct OverlayManager {
    pub ghost_visible: bool,
    pub lookup_open: bool,
    pub lookup_bounds: Option<(i32, i32, i32, i32)>,
}

impl Default for OverlayManager {
    fn default() -> Self {
        Self::new()
    }
}

impl OverlayManager {
    pub fn new() -> Self {
        Self {
            ghost_visible: false,
            lookup_open: false,
            lookup_bounds: None,
        }
    }

    pub fn show_lookup(&mut self, bounds: (i32, i32, i32, i32)) {
        self.lookup_open = true;
        self.lookup_bounds = Some(bounds);
    }

    /// Invoked by global mouse-down monitor: closes Web Lookup if the click lands outside the card.
    pub fn handle_global_click(&mut self, screen_x: i32, screen_y: i32) -> bool {
        if !self.lookup_open {
            return false;
        }
        if let Some((x, y, w, h)) = self.lookup_bounds {
            let inside = screen_x >= x && screen_x <= x + w && screen_y >= y && screen_y <= y + h;
            if !inside {
                self.lookup_open = false;
                self.lookup_bounds = None;
                return true;
            }
        }
        false
    }
}
