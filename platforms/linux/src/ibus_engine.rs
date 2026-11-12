//! Native `IBus` Input Method module (`nexollm-ibus`) providing first-class Wayland and X11 support.
//! Receives surrounding text, exact cursor screen coordinates (`set_cursor_location`), and key events
//! (`Tab`, `Shift+Tab`, `Alt+Tab`, `Esc`) while immediately bypassing `Password` and `Pin` fields.

use serde::{Deserialize, Serialize};

pub const IBUS_CAP_PREEDIT_TEXT: u32 = 1 << 0;
pub const IBUS_CAP_SURROUNDING_TEXT: u32 = 1 << 5;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum InputPurpose {
    FreeForm,
    Alpha,
    Email,
    Url,
    Password,
    Pin,
    Terminal,
}

#[derive(Debug, Clone, Default)]
pub struct IbusEngineState {
    pub surrounding_prefix: String,
    pub surrounding_suffix: String,
    pub cursor_rect: (i32, i32, i32, i32),
    pub ghost_text: String,
    pub purpose: Option<InputPurpose>,
}

impl IbusEngineState {
    pub fn capabilities() -> u32 {
        IBUS_CAP_PREEDIT_TEXT | IBUS_CAP_SURROUNDING_TEXT
    }

    pub fn is_blocked(&self) -> bool {
        matches!(self.purpose, Some(InputPurpose::Password | InputPurpose::Pin))
    }

    pub fn set_surrounding_text(&mut self, text: &str, cursor_char_pos: usize) {
        if self.is_blocked() {
            self.surrounding_prefix.clear();
            self.surrounding_suffix.clear();
            return;
        }
        let mut split_byte = text.len();
        for (char_idx, (byte_idx, _)) in text.char_indices().enumerate() {
            if char_idx == cursor_char_pos {
                split_byte = byte_idx;
                break;
            }
        }
        self.surrounding_prefix = text[..split_byte].to_string();
        self.surrounding_suffix = text[split_byte..].to_string();
    }

    /// Generates the `/usr/share/ibus/component/nexollm.xml` component descriptor for Linux packaging.
    pub fn component_xml(libexec_path: &str) -> String {
        format!(
            r#"<?xml version="1.0" encoding="utf-8"?>
<component>
  <name>org.edevs.NexoLLM</name>
  <description>NexoLLM On-Device Writing Assistant</description>
  <exec>{libexec_path}/nexollm-ibus --ibus</exec>
  <version>0.9.0</version>
  <author>EdevS</author>
  <license>GPL-3.0-only</license>
  <engines>
    <engine>
      <name>nexollm</name>
      <language>other</language>
      <license>GPL-3.0-only</license>
      <author>EdevS</author>
      <layout>default</layout>
      <longname>NexoLLM</longname>
      <description>On-device AI inline completion (EN, IT, ES, FR, DE, PT)</description>
      <rank>50</rank>
    </engine>
  </engines>
</component>
"#
        )
    }
}
