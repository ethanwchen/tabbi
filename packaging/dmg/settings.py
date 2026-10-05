# dmgbuild settings for a Tabbi edition's DMG. make-dmg.sh passes the inputs:
#
#   dmgbuild -s packaging/dmg/settings.py -D app=<path to .app> \
#       -D background=<background.tiff> -D icon=<volume .icns> "<Volume>" <out.dmg>
#
# dmgbuild writes the window layout straight into .DS_Store, so no Finder or
# AppleScript is involved and the build runs headless in CI. The geometry here
# must match packaging/dmg/render-background.swift.
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
app_name = os.path.basename(app)

# APFS with lzfse: Sparkle recommends it for quick mounting, and macOS 14 (the
# minimum) reads it natively. ULMO (lzma) would be smaller but slower to open.
filesystem = "APFS"
format = defines.get("format", "ULFO")  # noqa: F821

files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [app_name]

icon = defines["icon"]  # noqa: F821
background = defines["background"]  # noqa: F821

# A 660x400 window with nothing but the two icons on the art.
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
show_item_info = False
include_list_view_settings = False

arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {
    app_name: (150, 180),
    "Applications": (510, 180),
}
