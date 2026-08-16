# Lightweight Bash Ctrl+R history picker in one file.
# Usage:
#   source ~/.bash_history_ctrl_r_single.sh
#
# Keys:
#   Ctrl+R        open history picker
#   type text     filter commands
#   Up/Down       move selection
#   PageUp/Down   move faster
#   Tab           fill selected command into prompt
#   Enter         run selected command
#   Esc/Ctrl+C    cancel

# Only run in interactive Bash.
[[ -n ${BASH_VERSION:-} && $- == *i* ]] || return 0

__history_picker() {
    local result mode cmd
    local had_histtimeformat=0 old_histtimeformat=""

    # Ctrl+R queues this action after the picker callback. Redraw is the safe
    # default for fill, cancel, and picker failures; run switches it below.
    bind '"\e[998~": redraw-current-line'

    # Keep Bash history fresh across terminals when possible.
    builtin history -a 2>/dev/null
    builtin history -n 2>/dev/null

    # Make `history` output easier to parse: number + command, no timestamp.
    if [[ ${HISTTIMEFORMAT+x} ]]; then
        had_histtimeformat=1
        old_histtimeformat=$HISTTIMEFORMAT
    fi
    HISTTIMEFORMAT=

    result="$(HISTORY_PICKER_QUERY="$READLINE_LINE" builtin history | python3 -c '
import curses
import locale
import os
import re
import sys


def parse_history(text):
    commands = []
    for line in text.splitlines():
        match = re.match(r"^\s*\d+\s+(.*)$", line)
        command = match.group(1) if match else line.strip()
        if command:
            commands.append(command)

    # Bash prints oldest first. Show newest first, while removing duplicates.
    seen = set()
    unique = []
    for command in reversed(commands):
        if command not in seen:
            seen.add(command)
            unique.append(command)
    return unique


def matches(command, query):
    query = query.strip().lower()
    if not query:
        return True
    command = command.lower()
    return all(part in command for part in query.split())


def short(text, width):
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    if width <= 1:
        return text[:width]
    return text[: width - 1] + "…"


def draw(stdscr, query, filtered, selected, offset):
    stdscr.erase()
    height, width = stdscr.getmaxyx()

    title = "Ctrl+R history search  Enter: run  Tab: fill  Esc: cancel"
    stdscr.addnstr(0, 0, short(title, width - 1), width - 1, curses.A_BOLD)

    prompt = "search> " + query
    stdscr.addnstr(1, 0, short(prompt, width - 1), width - 1)

    list_top = 3
    list_height = max(1, height - list_top - 1)

    if not filtered:
        stdscr.addnstr(list_top, 0, "(no matches)", width - 1, curses.A_DIM)
    else:
        for row in range(list_height):
            index = offset + row
            if index >= len(filtered):
                break
            attr = curses.A_REVERSE if index == selected else curses.A_NORMAL
            line = short(filtered[index], width - 1)
            stdscr.addnstr(list_top + row, 0, line, width - 1, attr)

    footer = f"{len(filtered)} match(es)"
    stdscr.addnstr(height - 1, 0, short(footer, width - 1), width - 1, curses.A_DIM)
    stdscr.refresh()


def picker(stdscr, commands):
    curses.curs_set(0)
    stdscr.keypad(True)
    curses.noecho()
    curses.cbreak()

    query = os.environ.get("HISTORY_PICKER_QUERY", "")
    selected = 0
    offset = 0

    while True:
        filtered = [command for command in commands if matches(command, query)]
        if selected >= len(filtered):
            selected = max(0, len(filtered) - 1)
        if selected < 0:
            selected = 0

        height, _ = stdscr.getmaxyx()
        list_height = max(1, height - 4)
        if selected < offset:
            offset = selected
        if selected >= offset + list_height:
            offset = selected - list_height + 1
        offset = max(0, offset)

        draw(stdscr, query, filtered, selected, offset)
        key = stdscr.get_wch()

        if key in ("\x03", "\x1b"):
            return None
        if key in ("\n", "\r") or key == curses.KEY_ENTER:
            if filtered:
                return ("run", filtered[selected])
            continue
        if key == "\t":
            if filtered:
                return ("fill", filtered[selected])
            continue
        if key in (curses.KEY_UP, "\x10"):
            selected -= 1
            continue
        if key in (curses.KEY_DOWN, "\x0e"):
            selected += 1
            continue
        if key == curses.KEY_PPAGE:
            selected -= list_height
            continue
        if key == curses.KEY_NPAGE:
            selected += list_height
            continue
        if key in (curses.KEY_BACKSPACE, "\b", "\x7f"):
            query = query[:-1]
            selected = 0
            offset = 0
            continue
        if key == "\x15":  # Ctrl+U
            query = ""
            selected = 0
            offset = 0
            continue
        if key == "\x17":  # Ctrl+W
            query = query.rstrip()
            query = query[: query.rfind(" ") + 1] if " " in query else ""
            selected = 0
            offset = 0
            continue
        if isinstance(key, str) and key.isprintable():
            query += key
            selected = 0
            offset = 0


def run_on_tty(commands):
    # stdout is captured by Bash command substitution. Curses needs the real tty,
    # so temporarily attach stdin/stdout to /dev/tty, then write only the final
    # result back to the captured stdout fd.
    result_fd = os.dup(1)
    old_stdin = os.dup(0)
    old_stdout = os.dup(1)
    tty_fd = None
    try:
        tty_fd = os.open("/dev/tty", os.O_RDWR)
        os.dup2(tty_fd, 0)
        os.dup2(tty_fd, 1)
        result = curses.wrapper(picker, commands)
    finally:
        os.dup2(old_stdin, 0)
        os.dup2(old_stdout, 1)
        os.close(old_stdin)
        os.close(old_stdout)
        if tty_fd is not None:
            os.close(tty_fd)

    if result:
        mode, command = result
        os.write(result_fd, (mode + "\t" + command).encode())
    os.close(result_fd)


def main():
    locale.setlocale(locale.LC_ALL, "")
    commands = parse_history(sys.stdin.read())
    if not commands:
        return 0
    try:
        run_on_tty(commands)
    except KeyboardInterrupt:
        return 130
    return 0


raise SystemExit(main())
')"

    if (( had_histtimeformat )); then
        HISTTIMEFORMAT=$old_histtimeformat
    else
        unset HISTTIMEFORMAT
    fi

    [[ -n $result && $result == *$'\t'* ]] || return 0

    mode=${result%%$'\t'*}
    cmd=${result#*$'\t'}

    case "$mode" in
        fill)
            READLINE_LINE=$cmd
            READLINE_POINT=${#READLINE_LINE}
            ;;
        run)
            READLINE_LINE=$cmd
            READLINE_POINT=${#READLINE_LINE}
            bind '"\e[998~": accept-line'
            ;;
    esac
}

# A Readline macro can continue with accept-line after the bind -x callback
# returns. This submits the selected command through Bash's normal input path.
bind -x '"\e[999~":__history_picker'
bind '"\C-r":"\e[999~\e[998~"'
