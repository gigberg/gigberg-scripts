#!/usr/bin/env bash

set -euo pipefail

show_brightness() {
  xrandr --verbose | awk '
        / connected/ { output = $1 }
        /Brightness/ { printf "%-15s %s\n", output, $2 }
    '
}

show_help() {
  cat <<EOF
Usage:
  $(basename "$0") [OPTION]

Options:
  --light     Set all connected displays to brightness 1
  --dark      Set all connected displays to brightness 0
  --toggle    Toggle between light and dark
  --show, -s  Show current brightness
  --help, -h  Show this help

With no option, --toggle is used.
EOF
}

set_brightness() {
  local target="$1"

  xrandr --query | awk '/ connected/ {print $1}' | while read -r output; do
    echo "Setting $output -> Brightness $target"
    xrandr --output "$output" --brightness "$target"
  done

  echo
  show_brightness
}

is_dark() {
  xrandr --verbose | awk '
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
  '
}

main() {
  if [[ "$#" -gt 1 ]]; then
    echo "Error: too many arguments." >&2
    echo
    show_help
    return 1
  fi

  case "${1:---toggle}" in
  --light)
    set_brightness 1
    ;;

  --dark)
    set_brightness 0
    ;;

  --toggle)
    if is_dark; then
      set_brightness 1
    else
      set_brightness 0
    fi
    ;;

  --show|-s)
    show_brightness
    ;;

  --help|-h)
    show_help
    ;;

  *)
    echo "Error: unknown option: $1" >&2
    echo
    show_help
    return 1
    ;;
  esac
}

main "$@"
