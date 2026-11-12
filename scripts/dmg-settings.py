# dmgbuild configuration for NexoLLM's custom Aurora/Glass installer DMG.
# Deterministically writes binary .DS_Store records (bwsp, icvp, pBBk, Iloc) and HFS+ aliases
# without requiring AppleScript or Finder Automation permissions (works headless in CI and locally).

import os.path

app_path = defines["app"]
app_name = os.path.basename(app_path)

format = defines.get("format", "UDRW")
compression_level = 9
filesystem = "HFS+"
size = None

files = [app_path]
symlinks = {"Applications": "/Applications"}

if "icon" in defines and os.path.exists(defines["icon"]):
    icon = defines["icon"]

background = defines["background"]

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 180

# Content area is 660x420 pt; +28 pt Finder titlebar = 660x448 pt window bounds.
window_rect = ((240, 220), (660, 448))
default_view = "icon-view"
show_icon_preview = False
include_icon_view_settings = "auto"
include_list_view_settings = "auto"

arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 13
icon_size = 108

icon_locations = {
    app_name: (185, 206),
    "Applications": (475, 206),
}
