from pathlib import Path

ROOT_DIR = Path(defines["root"])
DIST_DIR = ROOT_DIR / "dist"

format = "UDZO"
size = "512M"
compression_level = 9

files = [
    str(DIST_DIR / "Record-Whisper.app"),
]

symlinks = {
    "Applications": "/Applications",
}

background = str(DIST_DIR / "dmg-background.png")
window_rect = ((220, 140), (640, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

icon_size = 96
text_size = 14
arrange_by = None

icon_locations = {
    "Record-Whisper.app": (160, 190),
    "Applications": (480, 190),
}
