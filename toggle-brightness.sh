#!/usr/bin/env bash

set -euo pipefail

show_brightness() {
  xrandr --verbose | awk '
        / connected/ { output = $1 }
        /Brightness/ { printf "%-15s %s\n", output, $2 }
    '
}

# 仅显示当前亮度
if [[ "${1:-}" == "--show" || "${1:-}" == "-s" ]]; then
  show_brightness
  exit 0
fi

# 判断是否所有显示器都已调暗
if xrandr --verbose | awk '
    / connected/ { connected = 1; next }
    connected && /Brightness:/ {
        print $2
        connected = 0
    }
' | awk '
    BEGIN { dimmed = 1; seen = 0 }
    {
        seen = 1
        if ($1 > 0.01)
            dimmed = 0
    }
    END {
        exit !(seen && dimmed)
    }
'; then
  target=1
else
  target=0
fi

# 设置所有显示器
xrandr --query | awk '/ connected/ {print $1}' | while read -r output; do
  echo "Setting $output -> Brightness $target"
  xrandr --output "$output" --brightness "$target"
done

echo
show_brightness
