#!/usr/bin/env bash

#
# ToDesk 远程连接监听器
#
# 作用：
#   持续监听 ToDesk 服务日志。
#   当日志中出现：
#
#       CSeviceEventHandler LaunchSession desktop
#
#   说明 ToDesk 正在启动一次远程桌面会话，
#   此时自动执行：
#
#       /home/charming/bin/shell_scripts/gigberg-scripts/toggle-brightness.sh --dark
#
# 设计说明：
#
#   ToDesk 的日志文件每天都会生成新的文件，例如：
#
#       /var/log/todesk/servicebgivfhtt_2026_09_03.log
#       /var/log/todesk/servicebgivfhtt_2026_09_04.log
#
#   因此不能永久写死某一天的日志文件。
#
#   这个脚本的逻辑是：
#
#       1. 找到 /var/log/todesk 下最新的 service*.log
#       2. 从文件末尾开始监听新日志
#       3. 发现远程桌面连接事件后执行 COMMAND
#       4. 每隔一段时间检查 ToDesk 是否生成了新的日志文件
#       5. 如果跨天产生新日志，则停止旧 tail，重新监听新文件
#       6. 如果 tail 意外退出，也自动重新启动
#
#   整个脚本以普通用户 charming 运行，不需要 sudo。
#   前提是 charming 用户拥有 /var/log/todesk/service*.log 的读取权限。
#

set -u

LOG_DIR="/var/log/todesk"
PATTERN="CSeviceEventHandler LaunchSession desktop"
COMMAND="/home/charming/bin/shell_scripts/gigberg-scripts/toggle-brightness.sh --dark"

CHECK_INTERVAL=10
COOLDOWN=5
LAST_TRIGGER=0

get_latest_log() {
  find "$LOG_DIR" \
    -maxdepth 1 \
    -type f \
    -name 'service*.log' \
    -printf '%T@ %p\n' 2>/dev/null |
    sort -nr |
    head -1 |
    cut -d' ' -f2-
}

cleanup() {
  if [[ -n "${TAILPROC_PID:-}" ]]; then
    kill "$TAILPROC_PID" 2>/dev/null || true
    wait "$TAILPROC_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

while true; do
  log="$(get_latest_log)"

  if [[ -z "$log" ]]; then
    sleep 2
    continue
  fi

  echo "$(date '+%F %T') Watching: $log"

  coproc TAILPROC {
    tail -n 0 -F "$log"
  }

  exec {TAIL_FD}<&"${TAILPROC[0]}"

  while true; do
    if IFS= read -r -t "$CHECK_INTERVAL" -u "$TAIL_FD" line; then
      if [[ "$line" == *"$PATTERN"* ]]; then
        now="$(date +%s)"

        if ((now - LAST_TRIGGER >= COOLDOWN)); then
          LAST_TRIGGER="$now"

          echo "$(date '+%F %T') ToDesk desktop session detected"

          bash -c "$COMMAND" &
        fi
      fi
    fi

    newest="$(get_latest_log)"

    if [[ -n "$newest" && "$newest" != "$log" ]]; then
      echo "$(date '+%F %T') Log changed: $log -> $newest"

      kill "$TAILPROC_PID" 2>/dev/null || true
      wait "$TAILPROC_PID" 2>/dev/null || true
      exec {TAIL_FD}<&-
      break
    fi

    if ! kill -0 "$TAILPROC_PID" 2>/dev/null; then
      echo "$(date '+%F %T') tail exited, restarting watcher"

      exec {TAIL_FD}<&-
      break
    fi
  done
done
