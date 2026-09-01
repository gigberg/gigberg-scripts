#!/usr/bin/env bash

set -u

SCRIPT_NAME="$(basename "$0")"

MOUSE_SETTING="org.gnome.desktop.peripherals.mouse"
MOUSE_KEY="left-handed"

GDBUS_DEST="org.gnome.Shell"
GDBUS_OBJECT="/raiden_fumo/InputSources"
GDBUS_INTERFACE="raiden_fumo.InputSources"

show_help() {
  cat <<EOF
Usage:
  $SCRIPT_NAME [OPTION]

Options:
  --normal    Switch to normal mode
                Mouse: right-handed
                Input: libpinyin

  --custom    Switch to custom mode
                Mouse: left-handed
                Input: rime

  --toggle    Toggle between normal and custom mode

  --show      Show current status

  --help      Show this help
EOF
}

set_input_source() {
  local input_source="$1"

  gdbus call \
    --session \
    --dest "$GDBUS_DEST" \
    --object-path "$GDBUS_OBJECT" \
    --method "$GDBUS_INTERFACE.Set" \
    "$input_source" >/dev/null
}

get_input_source() {
  gdbus call \
    --session \
    --dest "$GDBUS_DEST" \
    --object-path "$GDBUS_OBJECT" \
    --method "$GDBUS_INTERFACE.Get"
}

set_mouse_mode() {
  local left_handed="$1"

  gsettings set \
    "$MOUSE_SETTING" \
    "$MOUSE_KEY" \
    "$left_handed"
}

get_mouse_mode() {
  gsettings get \
    "$MOUSE_SETTING" \
    "$MOUSE_KEY"
}

set_normal() {
  echo "Switching to normal mode..."

  if ! set_mouse_mode false; then
    echo "Error: failed to set mouse to right-handed." >&2
    return 1
  fi

  if ! set_input_source libpinyin; then
    echo "Error: failed to switch input source to libpinyin." >&2
    return 1
  fi

  echo "Normal mode enabled."
  echo "  Mouse: right-handed"
  echo "  Input: libpinyin"
}

set_custom() {
  echo "Switching to custom mode..."

  if ! set_mouse_mode true; then
    echo "Error: failed to set mouse to left-handed." >&2
    return 1
  fi

  if ! set_input_source rime; then
    echo "Error: failed to switch input source to rime." >&2
    return 1
  fi

  echo "Custom mode enabled."
  echo "  Mouse: left-handed"
  echo "  Input: rime"
}

toggle_mode() {
  local mouse_mode

  mouse_mode="$(get_mouse_mode)" || {
    echo "Error: failed to get mouse status." >&2
    return 1
  }

  if [[ "$mouse_mode" == "true" ]]; then
    set_normal
  else
    set_custom
  fi
}

show_status() {
  local mouse_mode
  local input_source

  mouse_mode="$(get_mouse_mode)" || {
    echo "Error: failed to get mouse status." >&2
    return 1
  }

  input_source="$(get_input_source)" || {
    echo "Error: failed to get input source." >&2
    return 1
  }

  echo "Current status:"

  if [[ "$mouse_mode" == "true" ]]; then
    echo "  Mode : custom"
    echo "  Mouse: left-handed"
  else
    echo "  Mode : normal"
    echo "  Mouse: right-handed"
  fi

  echo "  Input: $input_source"
}

main() {
  if [[ $# -eq 0 ]]; then
    show_help
    return 1
  fi

  if [[ $# -gt 1 ]]; then
    echo "Error: too many arguments." >&2
    echo
    show_help
    return 1
  fi

  case "$1" in
  --normal)
    set_normal
    ;;

  --custom)
    set_custom
    ;;

  --toggle)
    toggle_mode
    ;;

  --show)
    show_status
    ;;

  --help)
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
