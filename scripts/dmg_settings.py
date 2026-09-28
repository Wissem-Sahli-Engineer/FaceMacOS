# dmgbuild settings for the drag-to-install window. Used by scripts/release.sh:
#   dmgbuild -s scripts/dmg_settings.py -D app=build/FaceMacOS.app "FaceMacOS" out.dmg
# Layout must match scripts/make_dmg_background.swift.
import os

app = defines["app"]  # noqa: F821 (provided by dmgbuild)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
size = None

files = [app, ("Resources/DMG/Terminal command.txt", "Terminal command.txt")]
symlinks = {"Applications": "/Applications"}
icon = "Resources/AppIcon.icns"

background = "Resources/dmg-background.tiff"
# Outer window size; taller than the content so Finder's optional path/status bars never cover the icons.
window_rect = ((200, 100), (660, 560))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

icon_size = 112
text_size = 13
arrange_by = None
icon_locations = {
    app_name: (170, 160),
    "Applications": (490, 160),
    "Terminal command.txt": (580, 330),
}
