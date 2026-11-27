#!/usr/bin/env python3
# tasks.py - Todo CLI v2 (Python, stdlib only)
# Same spec + same tasks.md as all other languages.
# Run: python3 tasks.py  |  python3 tasks.py list  |  python3 tasks.py add "Buy milk #home"
# Audit fix (2026-11-27): prompt uses get_wch key-by-key only.
# No fixed-size prompt buffer, no truncated read. Dynamic list, 4096 cap.

import sys
import os
import re
import shutil
import curses
from datetime import date

TASKS_FILE = "tasks.md"
BACKUP_FILE = "tasks.md.bak"
MAX_INPUT = 4096

class Task:
    def __init__(self, done=False, priority="", due="", text=""):
        self.done = done
        self.priority = priority
        self.due = due
        self.text = text

tasks = []

def trim(s):
    return s.strip()

def collapse_spaces(s):
    return " ".join(s.split())

def today_str():
    return date.today().isoformat()

def is_overdue(t):
    return bool(t.due) and t.due < today_str()

def is_today(t):
    return bool(t.due) and t.due == today_str()

def parse_line(line):
    if not line.startswith("- ["):
        return None
    if len(line) < 5:
        return None
    mark = line[3]
    if mark not in (" ", "x"):
        return None
    if line[4] != "]":
        return None
    t = Task(done=(mark == "x"))
    rest = trim(line[5:])
    if rest.startswith("(P1)") or rest.startswith("(P2)") or rest.startswith("(P3)"):
        t.priority = rest[1:3]
        rest = trim(rest[4:])
    if rest.startswith("due:") and len(rest) >= 14:
        d = rest[4:14]
        if len(d) == 10 and d[4] == "-" and d[7] == "-":
            t.due = d
            rest = trim(rest[14:])
    t.text = trim(rest)
    return t

def format_task(t):
    s = "- [" + ("x" if t.done else " ") + "]"
    if t.priority:
        s += " (" + t.priority + ")"
    if t.due:
        s += " due:" + t.due
    s += " " + t.text
    return s

def load_tasks():
    tasks.clear()
    if not os.path.exists(TASKS_FILE):
        return
    with open(TASKS_FILE, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n").rstrip("\r")
            if not trim(line):
                continue
            t = parse_line(line)
            if t is not None:
                tasks.append(t)

def save_tasks():
    if os.path.exists(TASKS_FILE):
        try:
            shutil.copyfile(TASKS_FILE, BACKUP_FILE)
        except OSError:
            pass
    with open(TASKS_FILE, "w", encoding="utf-8") as f:
        for t in tasks:
            f.write(format_task(t) + "\n")

def parse_add_text(full):
    t = Task()
    text = trim(full)
    if text.startswith("P1 ") or text.startswith("P2 ") or text.startswith("P3 "):
        t.priority = text[:2]
        text = trim(text[3:])
    elif text.startswith("(P1)") or text.startswith("(P2)") or text.startswith("(P3)"):
        t.priority = text[1:3]
        text = trim(text[4:])
    pos = text.find("due:")
    if pos != -1 and len(text) >= pos + 14:
        cand = text[pos + 4:pos + 14]
        if len(cand) == 10 and cand[4] == "-" and cand[7] == "-":
            t.due = cand
            before = trim(text[:pos])
            after = trim(text[pos + 14:])
            text = trim(before + " " + after)
    t.text = collapse_spaces(text)
    return t

def parse_task_number(s, n):
    try:
        v = int(trim(s))
    except ValueError:
        return None
    if v < 1 or v > n:
        return None
    return v - 1

def matches_mode(t, mode):
    if mode == "todo":
        return not t.done
    if mode == "done":
        return t.done
    if mode == "overdue":
        return (not t.done) and is_overdue(t)
    if mode == "today":
        return (not t.done) and is_today(t)
    return True

def matches_search(t, q):
    if not q:
        return True
    return q.lower() in t.text.lower()

def filtered_indices(mode, search):
    out = []
    for i, t in enumerate(tasks):
        if not matches_mode(t, mode):
            continue
        if not matches_search(t, search):
            continue
        out.append(i)
    return out

def count_done():
    return sum(1 for t in tasks if t.done)

def count_overdue():
    return sum(1 for t in tasks if (not t.done) and is_overdue(t))

def has_tag(t, tag):
    want = tag[1:] if tag.startswith("#") else tag
    for tok in t.text.split():
        if len(tok) > 1 and tok[0] == "#":
            if tok == tag or tok[1:] == want:
                return True
    return False

def has_project(t, proj):
    want = proj[1:] if proj.startswith("+") else proj
    for tok in t.text.split():
        if len(tok) > 1 and tok[0] == "+":
            if tok == proj or tok[1:] == want:
                return True
    return False

def print_task(idx, t):
    mark = "x" if t.done else " "
    s = f"{idx + 1}. [{mark}] "
    if t.priority:
        s += t.priority + " "
    if t.due:
        s += t.due + " "
    s += t.text
    print(s)

def cli_list(args):
    tag = ""; project = ""; priority = ""; search = ""; mode = "all"
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--tag" and i + 1 < len(args):
            tag = args[i + 1]; i += 2; continue
        if a == "--project" and i + 1 < len(args):
            project = args[i + 1]; i += 2; continue
        if a == "--priority" and i + 1 < len(args):
            priority = args[i + 1]; i += 2; continue
        if a == "--search" and i + 1 < len(args):
            search = args[i + 1]; i += 2; continue
        if a == "--overdue":
            mode = "overdue"
        elif a == "--today":
            mode = "today"
        elif a == "--done":
            mode = "done"
        elif a == "--todo":
            mode = "todo"
        i += 1
    shown = 0
    for idx in filtered_indices(mode, search):
        t = tasks[idx]
        if tag and not has_tag(t, tag):
            continue
        if project and not has_project(t, project):
            continue
        if priority and t.priority != priority:
            continue
        print_task(idx, t)
        shown += 1
    if shown == 0:
        print("No tasks.")

# --- TUI ---
# AUDITED FIXES:
# 1. Prompt: reads keys one-by-one via get_wch into a growing list,
#    4096 cap only, horizontal scroll. No fixed-size prompt buffer.
# 2. Exit: q / Q / Esc / Ctrl-C / Ctrl-D / Ctrl-Q quit from main list.
#    Footer always shows it. In prompt, Enter saves, Esc / Ctrl-C cancels.
#    curses.wrapper restores terminal on exit.

def prompt_input(stdscr, label):
    chars = []
    cursor = 0
    offset = 0
    label_len = len(label) + 1
    while True:
        rows, cols = stdscr.getmaxyx()
        avail = cols - label_len - 1
        if avail < 10:
            avail = 10
        if cursor < offset:
            offset = cursor
        if cursor >= offset + avail:
            offset = cursor - avail + 1
        stdscr.move(rows - 2, 0)
        stdscr.clrtoeol()
        stdscr.addstr(rows - 2, 0, "Enter=save  Esc / Ctrl-C=cancel"[:max(0, cols - 1)])
        stdscr.move(rows - 1, 0)
        stdscr.clrtoeol()
        stdscr.addstr(rows - 1, 0, label + " " + "".join(chars[offset:offset + avail])[:max(0, cols - 1)])
        cx = label_len + (cursor - offset)
        if cx >= cols:
            cx = cols - 1
        if cx < 0:
            cx = 0
        stdscr.move(rows - 1, cx)
        stdscr.refresh()
        try:
            k = stdscr.get_wch()
        except curses.error:
            continue
        if isinstance(k, int):
            if k in (10, 13, curses.KEY_ENTER):
                break
            if k == 27:
                return None
            if k in (3, 4, 17):
                return None
            if k in (curses.KEY_BACKSPACE, 127, 8):
                if cursor > 0:
                    del chars[cursor - 1]
                    cursor -= 1
                continue
            if k == curses.KEY_DC:
                if cursor < len(chars):
                    del chars[cursor]
                continue
            if k == curses.KEY_LEFT:
                if cursor > 0:
                    cursor -= 1
                continue
            if k == curses.KEY_RIGHT:
                if cursor < len(chars):
                    cursor += 1
                continue
            if k == curses.KEY_HOME:
                cursor = 0
                continue
            if k == curses.KEY_END:
                cursor = len(chars)
                continue
            if k == curses.KEY_UP or k == curses.KEY_DOWN:
                continue
            continue
        # str key
        if k in ("\r", "\n"):
            break
        if k == "\x1b":
            return None
        if k in ("\x03", "\x04", "\x11"):
            return None
        if k in ("\x7f", "\x08"):
            if cursor > 0:
                del chars[cursor - 1]
                cursor -= 1
            continue
        if k == "\x01":
            cursor = 0
            continue
        if k == "\x05":
            cursor = len(chars)
            continue
        if k == "\x15":
            chars = []; cursor = 0; offset = 0
            continue
        if k == "\x0b":
            chars = chars[:cursor]
            continue
        if k == "\x17":
            while cursor > 0 and chars[cursor - 1] == " ":
                del chars[cursor - 1]; cursor -= 1
            while cursor > 0 and chars[cursor - 1] != " ":
                del chars[cursor - 1]; cursor -= 1
            continue
        if len(k) == 1 and ord(k) >= 32:
            if len(chars) < MAX_INPUT:
                chars.insert(cursor, k)
                cursor += 1
            continue
    return trim("".join(chars))

def run_tui(stdscr):
    curses.curs_set(1)
    stdscr.keypad(True)
    try:
        curses.use_default_colors()
    except curses.error:
        pass
    selected = 0
    filters = ["all", "todo", "done", "overdue", "today"]
    filter_idx = 0
    search = ""
    status = "Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter"
    while True:
        rows, cols = stdscr.getmaxyx()
        mode = filters[filter_idx]
        visible = filtered_indices(mode, search)
        if not visible:
            selected = 0
        else:
            if selected >= len(visible):
                selected = len(visible) - 1
            if selected < 0:
                selected = 0
        stdscr.erase()
        total = len(tasks)
        done_n = count_done()
        overdue_n = count_overdue()
        header = f"tasks - {total} total | {done_n} done | {overdue_n} overdue | filter: {mode} | search: {search}"
        stdscr.addstr(0, 0, header[:max(0, cols - 1)])
        stdscr.addstr(1, 0, "#    []  P    Due         Text"[:max(0, cols - 1)])
        stdscr.addstr(2, 0, ("-" * min(80, cols))[:max(0, cols - 1)])
        max_rows = max(5, rows - 5)
        for i, idx in enumerate(visible[:max_rows]):
            t = tasks[idx]
            mark = "x" if t.done else " "
            line = f"{idx + 1:<4} [{mark}] "
            if t.priority:
                line += f"({t.priority}) "
            if t.due:
                line += f"due:{t.due} "
            line += t.text
            line = line[:max(0, cols - 1)]
            y = 3 + i
            if y >= rows - 2:
                break
            if i == selected:
                stdscr.addstr(y, 0, line, curses.A_REVERSE)
            elif t.done:
                stdscr.addstr(y, 0, line, curses.A_DIM)
            else:
                stdscr.addstr(y, 0, line)
        stdscr.move(rows - 2, 0)
        stdscr.clrtoeol()
        stdscr.addstr(rows - 2, 0, status[:max(0, cols - 1)])
        stdscr.move(rows - 1, 0)
        stdscr.clrtoeol()
        stdscr.addstr(rows - 1, 0, "q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats"[:max(0, cols - 1)])
        stdscr.move(rows - 1, 0)
        stdscr.refresh()
        try:
            k = stdscr.get_wch()
        except curses.error:
            continue
        # EXIT - checked FIRST
        if isinstance(k, int):
            if k == 27:
                break
            if k in (3, 4, 17):
                break
            if k == curses.KEY_DOWN:
                if selected + 1 < len(visible):
                    selected += 1
            elif k == curses.KEY_UP:
                if selected > 0:
                    selected -= 1
            continue
        if k == "\x1b" or k in ("\x03", "\x04", "\x11"):
            break
        if k in ("q", "Q"):
            break
        if k == "j":
            if selected + 1 < len(visible):
                selected += 1
        elif k == "k":
            if selected > 0:
                selected -= 1
        elif k == "g":
            selected = 0
        elif k == "G":
            if visible:
                selected = len(visible) - 1
        elif k == " ":
            if visible:
                idx = visible[selected]
                tasks[idx].done = not tasks[idx].done
                save_tasks()
                status = "Marked done" if tasks[idx].done else "Marked todo"
        elif k == "a":
            s = prompt_input(stdscr, "Add:")
            if s:
                nt = parse_add_text(s)
                tasks.append(nt)
                save_tasks()
                selected = len(tasks) - 1
                status = "Added: " + nt.text
            else:
                status = "Add cancelled - press q or Esc to quit"
        elif k == "e":
            if visible:
                idx = visible[selected]
                old = tasks[idx]
                s = prompt_input(stdscr, "Edit [" + old.text + "]:")
                if s:
                    nt = parse_add_text(s)
                    if not nt.priority:
                        nt.priority = old.priority
                    if not nt.due:
                        nt.due = old.due
                    nt.done = old.done
                    tasks[idx] = nt
                    save_tasks()
                    status = "Edited"
        elif k == "d":
            if visible:
                idx = visible[selected]
                removed = tasks[idx].text
                del tasks[idx]
                save_tasks()
                status = "Deleted: " + removed
                if selected >= len(visible) - 1 and selected > 0:
                    selected -= 1
        elif k == "/":
            s = prompt_input(stdscr, "Search:")
            if s is not None:
                search = s
                selected = 0
                status = ("Search: " + search) if search else "Search cleared - press q or Esc to quit"
        elif k == "f":
            filter_idx = (filter_idx + 1) % len(filters)
            selected = 0
            status = "Filter: " + filters[filter_idx]
        elif k == "u":
            if os.path.exists(BACKUP_FILE):
                shutil.copyfile(BACKUP_FILE, TASKS_FILE)
                load_tasks()
                status = "Undone"
            else:
                status = "No backup to undo"
        elif k == "c":
            before = len(tasks)
            tasks[:] = [t for t in tasks if not t.done]
            save_tasks()
            status = f"Cleared {before - len(tasks)} done"
            selected = 0
        elif k == "s":
            total2 = len(tasks); done2 = count_done(); over2 = count_overdue()
            status = f"Total {total2} - Done {done2} - Todo {total2 - done2} - Overdue {over2}"
        elif k == "?":
            status = "Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats"

def print_help():
    print("Usage:")
    print("  tasks tui                    Interactive TUI (default, no args = tui)")
    print("  tasks add [--priority P1] [--due YYYY-MM-DD] <text>")
    print("  tasks list [--tag X] [--project Y] [--priority P1] [--search Q] [--overdue|--today|--done|--todo]")
    print("  tasks done <n>")
    print("  tasks undone <n>")
    print("  tasks rm <n>")
    print("  tasks edit <n> <new text>")
    print("  tasks search <query>")
    print("  tasks clear")
    print("  tasks stats")
    print("  tasks undo")
    print("  tasks help")
    print()
    print("Format: tasks.md lines are - [ ] (P1) due:2026-11-30 Buy milk #home +groceries")
    print("Tags start with #, projects with +. Priority P1/P2/P3, due YYYY-MM-DD.")
    print("TUI keys: j/k or arrows move, Space toggle, a add, e edit, d delete,")
    print("  / search, f filter, u undo, c clear done, s stats, q / Esc / Ctrl-C to quit")
    print("  In a prompt: Enter saves, Esc / Ctrl-C cancels")

def main():
    load_tasks()
    args = sys.argv[1:]
    if not args or args[0] == "tui":
        curses.wrapper(run_tui)
        print("Exited TUI - back to shell. Use: python3 tasks.py list")
        return
    cmd = args[0]
    if cmd in ("help", "--help", "-h"):
        print_help()
    elif cmd == "add":
        priority = ""; due = ""; parts = []
        i = 1
        while i < len(args):
            if args[i] == "--priority" and i + 1 < len(args):
                priority = args[i + 1]; i += 2; continue
            if args[i] == "--due" and i + 1 < len(args):
                due = args[i + 1]; i += 2; continue
            parts.append(args[i]); i += 1
        buf = " ".join(parts)
        if not trim(buf):
            print("Usage: tasks add <text>"); return
        t = parse_add_text(buf)
        if priority:
            t.priority = priority
        if due:
            t.due = due
        tasks.append(t); save_tasks()
        print("Added: " + t.text)
    elif cmd == "list":
        cli_list(args[1:])
    elif cmd == "done":
        if len(args) < 2:
            print("Usage: tasks done <n>"); return
        idx = parse_task_number(args[1], len(tasks))
        if idx is None:
            print("Invalid task number"); return
        tasks[idx].done = True; save_tasks()
        print("Done: " + tasks[idx].text)
    elif cmd == "undone":
        if len(args) < 2:
            print("Usage: tasks undone <n>"); return
        idx = parse_task_number(args[1], len(tasks))
        if idx is None:
            print("Invalid task number"); return
        tasks[idx].done = False; save_tasks()
        print("Todo: " + tasks[idx].text)
    elif cmd == "rm":
        if len(args) < 2:
            print("Usage: tasks rm <n>"); return
        idx = parse_task_number(args[1], len(tasks))
        if idx is None:
            print("Invalid task number"); return
        removed = tasks[idx].text
        del tasks[idx]; save_tasks()
        print("Deleted: " + removed)
    elif cmd == "edit":
        if len(args) < 3:
            print("Usage: tasks edit <n> <new text>"); return
        idx = parse_task_number(args[1], len(tasks))
        if idx is None:
            print("Invalid task number"); return
        nt = parse_add_text(" ".join(args[2:]))
        old = tasks[idx]
        if not nt.priority:
            nt.priority = old.priority
        if not nt.due:
            nt.due = old.due
        nt.done = old.done
        tasks[idx] = nt; save_tasks()
        print(f"Edited {idx + 1}: {nt.text}")
    elif cmd == "search":
        if len(args) < 2:
            print("Usage: tasks search <query>"); return
        q = " ".join(args[1:])
        found = False
        for i, t in enumerate(tasks):
            if matches_search(t, q):
                print_task(i, t); found = True
        if not found:
            print("No matches.")
    elif cmd == "clear":
        before = len(tasks)
        tasks[:] = [t for t in tasks if not t.done]
        save_tasks()
        print(f"Cleared {before - len(tasks)} done tasks")
    elif cmd == "stats":
        total = len(tasks); done_n = count_done(); over_n = count_overdue()
        today_n = sum(1 for t in tasks if (not t.done) and is_today(t))
        print(f"Total: {total}\nDone: {done_n}\nTodo: {total - done_n}\nOverdue: {over_n}\nDue today: {today_n}")
        c1 = sum(1 for t in tasks if t.priority == "P1")
        c2 = sum(1 for t in tasks if t.priority == "P2")
        c3 = sum(1 for t in tasks if t.priority == "P3")
        if c1 or c2 or c3:
            print("By priority:")
            if c1:
                print(f"  P1: {c1}")
            if c2:
                print(f"  P2: {c2}")
            if c3:
                print(f"  P3: {c3}")
        tag_counts = {}
        for t in tasks:
            for tok in t.text.split():
                if len(tok) > 1 and tok[0] == "#":
                    tag_counts[tok] = tag_counts.get(tok, 0) + 1
        if tag_counts:
            print("By tag:")
            for k in sorted(tag_counts):
                print(f"  {k}: {tag_counts[k]}")
    elif cmd == "undo":
        if not os.path.exists(BACKUP_FILE):
            print("No backup to undo"); return
        shutil.copyfile(BACKUP_FILE, TASKS_FILE)
        print("Undone - restored from backup")
    else:
        print("Unknown command: " + cmd)
        print_help()

if __name__ == "__main__":
    main()
