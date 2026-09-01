#!/usr/bin/env bash

# no-sandbox: paseo, AnotherRedisDesktopManager, env:ghostty-ibus-gtk
# sed -i 's|^Exec=\(.*\)|Exec=env GTK_PATH=/usr/lib/x86_64-linux-gnu/gtk-4.0 \1|' "$HOME/.local/share/applications/ghostty-AM.desktop"
# 帮我写一个脚本，做两件事情，一个是解压包并修改apprun添加--no-snadbox选项，
# 另一个是修改desktop并添加 no snadbox选项，脚本接收一个参数，读取程序名。比如当前是paseo程序
set -e

prog="$1"

bin_path="$(which "$prog")"
desktop_file="$HOME/.local/share/applications/${prog}-AM.desktop"

tmp="/tmp/${prog}-appimage-patch"

rm -rf "$tmp"
mkdir -p "$tmp"

cp "$bin_path" "$tmp/appimage"

cd "$tmp"

chmod +x appimage
./appimage --appimage-extract >/dev/null

sed -i \
  -e 's|exec "$BIN"|exec "$BIN" --no-sandbox|g' \
  -e 's|exec ":$BIN" --no-sandbox "${args\[@\]}"|exec "$BIN" --no-sandbox "${args[@]}"|g' \
  squashfs-root/AppRun

appimagetool squashfs-root patched.AppImage >/dev/null

chmod +x patched.AppImage

cp patched.AppImage "$bin_path"

sed -i \
  's|^Exec=.*|& --no-sandbox|g' \
  "$desktop_file"

rm -rf "$tmp"

echo done
