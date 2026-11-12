//! Composited ARGB overlay surfaces (GTK4 / `gtk4-layer-shell` on wlroots/KDE Wayland,
//! `IBus` preedit/candidate popup on GNOME Wayland, override-redirect X11 window on X11).
//! Closes Web Lookup cards automatically when the user clicks outside the card bounds.

pub struct LinuxOverlayState {
    pub lookup_visible: bool,
    pub lookup_bounds: Option<(i32, i32, i32, i32)>,
}

impl Default for LinuxOverlayState {
    fn default() -> Self {
        Self {
            lookup_visible: false,
            lookup_bounds: None,
        }
    }
}

impl LinuxOverlayState {
    pub fn on_pointer_press_outside(&mut self, x: i32, y: i32) -> bool {
        if !self.lookup_visible {
            return false;
        }
        if let Some((bx, by, bw, bh)) = self.lookup_bounds {
            if x < bx || x > bx + bw || y < by || y > by + bh {
                self.lookup_visible = false;
                self.lookup_bounds = None;
                return true;
            }
        }
        false
    }
}
