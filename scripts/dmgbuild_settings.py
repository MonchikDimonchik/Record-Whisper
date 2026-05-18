from pathlib import Path

ROOT_DIR = Path(defines["root"])
DIST_DIR = ROOT_DIR / "dist"

format = "UDZO"
size = "32M"
compression_level = 9

files = [
    str(DIST_DIR / "Whisper Local.app"),
    str(ROOT_DIR / "INSTALL.md"),
]

symlinks = {
    "Applications": "/Applications",
}

background = str(DIST_DIR / "dmg-background.png")
window_rect = ((180, 120), (760, 440))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

icon_size = 104
text_size = 14
arrange_by = None

icon_locations = {
    "Whisper Local.app": (180, 230),
    "Applications": (580, 230),
    "INSTALL.md": (380, 352),
}
