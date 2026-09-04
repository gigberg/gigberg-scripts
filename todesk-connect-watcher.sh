#!/usr/bin/env bash

#
# ToDesk / GNOME RDP 远程连接监听器
#
# 作用：
#   持续监听 ToDesk 日志，在远程桌面会话建立或断开时执行 COMMAND。
#   可选监听 GNOME Remote Desktop，在 RDP 客户端建立或断开时执行同一个 COMMAND。
#
# ToDesk 日志每天会生成新的 service*.log 和 session*.log，脚本会自动寻找并切换到最新日志；
# tail 异常退出时也会自动重新启动。
#
# GNOME RDP 通过 systemd journal 监听，不需要处理日志文件轮转。
# 设置 ENABLE_GNOME_RDP=false 可以完全关闭 GNOME RDP 的监听和 hook。
#
# 整个脚本以普通用户运行，不需要 sudo。
# 前提是当前用户具有 ToDesk service*.log 的读取权限。
#

set -u

LOG_DIR="/var/log/todesk"
TODESK_CONNECTED_PATTERN="CSeviceEventHandler LaunchSession desktop"
TODESK_DISCONNECTED_PATTERN="CLocalSession::processSessionCloseEvent: Received close event"
GNOME_RDP_CONNECTED_PATTERN="[RDP.CLIPRDR] Client capabilities:"
GNOME_RDP_DISCONNECTED_PATTERN="Unable to check file descriptor, closing connection"

COMMAND="/home/charming/bin/shell_scripts/gigberg-scripts/toggle-brightness.sh --dark"

# true：同时监听 GNOME RDP
# false：只监听 ToDesk
ENABLE_GNOME_RDP="${ENABLE_GNOME_RDP:-true}"

# 返回最近修改的指定 ToDesk 日志。
get_latest_todesk_log() {
  local pattern="$1"

  find "$LOG_DIR" \
    -maxdepth 1 \
    -type f \
    -name "$pattern" \
    -printf '%T@ %p\n' 2>/dev/null |
    sort -nr |
    head -1 |
    cut -d' ' -f2-
}

# 执行远程桌面事件后的统一 hook。
run_hook() {
  local source="$1"
  local event="$2"

  echo "$(date '+%F %T') $source remote desktop session $event"
  bash -c "$COMMAND" &
}

# 持续监听 ToDesk。
watch_todesk() {
  while true; do
    local service_log session_log newest_service_log newest_session_log line

    service_log="$(get_latest_todesk_log 'service*.log')"
    session_log="$(get_latest_todesk_log 'session*.log')"

    if [[ -z "$service_log" || -z "$session_log" ]]; then
      sleep 2
      continue
    fi

    echo "$(date '+%F %T') Watching ToDesk: $service_log, $session_log"

    coproc TODESK_TAIL {
      tail -n 0 -q -F "$service_log" "$session_log"
    }

    exec {TODESK_FD}<&"${TODESK_TAIL[0]}"

    while true; do
      if IFS= read -r -t 10 -u "$TODESK_FD" line; then
        if [[ "$line" == *"$TODESK_CONNECTED_PATTERN"* ]]; then
          run_hook "ToDesk" "connected"
        elif [[ "$line" == *"$TODESK_DISCONNECTED_PATTERN"* ]]; then
          run_hook "ToDesk" "disconnected"
        fi
      fi

      newest_service_log="$(get_latest_todesk_log 'service*.log')"
      newest_session_log="$(get_latest_todesk_log 'session*.log')"

      if [[ -n "$newest_service_log" && -n "$newest_session_log" &&
        ( "$newest_service_log" != "$service_log" || "$newest_session_log" != "$session_log" ) ]]; then
        echo "$(date '+%F %T') ToDesk log changed: $service_log, $session_log -> $newest_service_log, $newest_session_log"

        kill "$TODESK_TAIL_PID" 2>/dev/null || true
        wait "$TODESK_TAIL_PID" 2>/dev/null || true
        exec {TODESK_FD}<&-
        break
      fi

      if ! kill -0 "$TODESK_TAIL_PID" 2>/dev/null; then
        echo "$(date '+%F %T') ToDesk tail exited, restarting"

        exec {TODESK_FD}<&-
        break
      fi
    done
  done
}

# 持续监听 GNOME Remote Desktop 的 journal。
watch_gnome_rdp() {
  while true; do
    echo "$(date '+%F %T') Watching GNOME RDP"

    journalctl \
      --user \
      -fn0 \
      -u gnome-remote-desktop.service |
      while IFS= read -r line; do
        if [[ "$line" == *"$GNOME_RDP_CONNECTED_PATTERN"* ]]; then
          run_hook "GNOME RDP" "connected"
        elif [[ "$line" == *"$GNOME_RDP_DISCONNECTED_PATTERN"* ]]; then
          run_hook "GNOME RDP" "disconnected"
        fi
      done

    echo "$(date '+%F %T') GNOME RDP journal watcher exited, restarting"
    sleep 2
  done
}

# 退出时同时停止所有后台 watcher。
cleanup() {
  [[ -n "${TODESK_WATCHER_PID:-}" ]] &&
    kill "$TODESK_WATCHER_PID" 2>/dev/null || true

  [[ -n "${GNOME_RDP_WATCHER_PID:-}" ]] &&
    kill "$GNOME_RDP_WATCHER_PID" 2>/dev/null || true

  wait 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# ToDesk 始终启用。
watch_todesk &
TODESK_WATCHER_PID=$!

# GNOME RDP 根据配置决定是否启用。
if [[ "$ENABLE_GNOME_RDP" == "true" ]]; then
  watch_gnome_rdp &
  GNOME_RDP_WATCHER_PID=$!
else
  echo "$(date '+%F %T') GNOME RDP watcher disabled"
fi

wait
