# dmgbuild の設定。scripts/make-dmg.sh が -D app=… -D guide=… -D background=… を渡す。
# 窓の大きさとアイコンの位置は scripts/make-dmg-background.swift の絵と合わせる
import os
import plistlib

app = defines["app"]
guide = defines["guide"]

format = "UDZO"
filesystem = "HFS+"
files = [app, guide]
icon_locations = {
    os.path.basename(app): (200, 190),
    os.path.basename(guide): (440, 190),
}
# .app の拡張子は Finder が最初から隠す。app に隠す印（FinderInfo）を付けると codesign --verify --strict が通らない
hide_extensions = [os.path.basename(guide)]

background = defines["background"]
window_rect = ((200, 160), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
arrange_by = None
icon_size = 112
text_size = 13

# アプリにアイコンがあれば、ボリュームのアイコンにも使う
with open(os.path.join(app, "Contents", "Info.plist"), "rb") as f:
    icon_file = plistlib.load(f).get("CFBundleIconFile")
if icon_file:
    path = os.path.join(app, "Contents", "Resources", icon_file)
    if not path.endswith(".icns"):
        path += ".icns"
    if os.path.exists(path):
        icon = path
