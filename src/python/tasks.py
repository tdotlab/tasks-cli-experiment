#!/usr/bin/env python3
"""tasks v2 - CLI + modern TUI, same tasks.md file.
Format: - [ ] (P1) 2026-12-01 Buy ass cream #personal +shopping
Priority and due are optional. Tags #tag and projects +project live in the text.
Run with no args to open the TUI: python3 tasks.py
Run python3 tasks.py help for CLI commands.
"""
import os
import re
import shutil
import sys
from dataclasses import dataclass, field
from datetime import date

TASKS_FILE = "tasks.md"
BACKUP_FILE = "tasks.md.bak"

HELP = """Usage: tasks <command> [args]  (no args = open TUI)

Commands:
  tui                          Open modern TUI
  add "Buy milk" [--priority P1] [--due 2026-12-01]
                               Add a task. You can also write (P1) and 2026-12-01 inline.
  list [--tag personal] [--project shopping] [--priority P1] [--overdue] [--today] [--done] [--todo] [--search cream]
                               Show tasks
  done 2                       Mark task 2 complete
  undone 2                     Mark task 2 not done
  rm 2                         Delete task 2
  edit 2 "New text"            Replace task 2 text (keeps priority/due unless you include new ones)
  search cream                 Search text / tags
  clear                        Remove completed tasks
  stats                        Show totals + by tag / priority
  undo                         Restore last backup
"""

TAG_RE = re.compile(r"#(\w+)")
PROJECT_RE = re.compile(r"\+(\w+)")
LINE_RE = re.compile(r"^- \[( |x)\] (?:\((P[123])\) )?(\d{4}-\d{2}-\d{2} )?(.+)$")


@dataclass
class Task:
    done: bool = False
    priority: str = ""  # "", "P1", "P2", "P3"
    due: str = ""  # "", "YYYY-MM-DD"
    text: str = ""

    @property
    def tags(self):
        return TAG_RE.findall(self.text)

    @property
    def projects(self):
        return PROJECT_RE.findall(self.text)


def today_str():
    return date.today().isoformat()


def is_overdue(t):
    return bool(t.due) and not t.done and t.due < today_str()


def is_today(t):
    return t.due == today_str()


def parse_line(line):
    line = line.rstrip("\n").rstrip("\r")
    m = LINE_RE.match(line)
    if not m:
        return None
    done = m.group(1) == "x"
    priority = m.group(2) or ""
    if priority:
        priority = "P" + priority[-1]
    due = m.group(3) or ""
    text = m.group(4) or ""
    return Task(done=done, priority=priority, due=due, text=text)


def format_task(t):
    parts = ["- [x] " if t.done else "- [ ] "]
    if t.priority:
        parts.append(f"({t.priority}) ")
    if t.due:
        parts.append(f"{t.due} ")
    parts.append(t.text)
    return "".join(parts)


def load_tasks():
    tasks = []
    if not os.path.exists(TASKS_FILE):
        return tasks
    with open(TASKS_FILE, encoding="utf-8") as f:
        for line in f:
            if line.strip() == "":
                continue
            t = parse_line(line)
            if t:
                tasks.append(t)
    return tasks


def save_tasks(tasks, backup=True):
    if backup and os.path.exists(TASKS_FILE):
        try:
            shutil.copyfile(TASKS_FILE, BACKUP_FILE)
        except OSError:
            pass
    with open(TASKS_FILE, "w", encoding="utf-8") as f:
        for t in tasks:
            f.write(format_task(t) + "\n")


def parse_add_text(full_text):
    """Pull (P1) / P1 / due:DATE / DATE out of free text."""
    priority = ""
    due = ""
    text = full_text

    m = re.search(r"\(P([123])\)", text)
    if m:
        priority = "P" + m.group(1)
        text = text.replace(m.group(0), "", 1)
    else:
        m = re.search(r"\bP([123])\b", text)
        if m:
            priority = "P" + m.group(1)
            text = text.replace(m.group(0), "", 1)

    m = re.search(r"due:(\d{4}-\d{2}-\d{2})", text)
    if m:
        due = m.group(1)
        text = text.replace(m.group(0), "", 1)
    else:
        m = re.search(r"\b(\d{4}-\d{2}-\d{2})\b", text)
        if m:
            due = m.group(1)
            text = text.replace(m.group(0), "", 1)

    text = re.sub(r"\s+", " ", text).strip()
    return Task(done=False, priority=priority, due=due, text=text)


def parse_task_number(s, count):
    try:
        n = int(s)
    except ValueError:
        return None
    if n < 1 or n > count:
        return None
    return n - 1


def apply_filter(tasks, mode="all", search=""):
    out = tasks
    if mode == "todo":
        out = [t for t in out if not t.done]
    elif mode == "done":
        out = [t for t in out if t.done]
    elif mode == "overdue":
        out = [t for t in out if is_overdue(t)]
    elif mode == "today":
        out = [t for t in out if is_today(t)]
    elif mode in ("P1", "P2", "P3"):
        out = [t for t in out if t.priority == mode]
    if search:
        q = search.lower()
        out = [t for t in out if q in t.text.lower() or q in " ".join(t.tags).lower()]
    return out


# ---------- CLI pretty printing ----------

def use_color():
    return sys.stdout.isatty() and os.environ.get("NO_COLOR") is None


def c(text, code):
    if not use_color():
        return text
    return f"\033[{code}m{text}\033[0m"


def priority_str(t):
    if t.priority == "P1":
        return c("(P1)", "91;1")
    if t.priority == "P2":
        return c("(P2)", "93;1")
    if t.priority == "P3":
        return c("(P3)", "92;1")
    return ""


def due_str(t):
    if not t.due:
        return ""
    if is_overdue(t):
        return c(t.due, "91;1")
    if is_today(t):
        return c(t.due, "93;1")
    return c(t.due, "90")


def text_colored(t):
    # color #tags cyan, +projects magenta
    out = []
    for tok in t.text.split(" "):
        if tok.startswith("#"):
            out.append(c(tok, "96"))
        elif tok.startswith("+"):
            out.append(c(tok, "95"))
        else:
            out.append(tok)
    return " ".join(out)


def print_task(i, t):
    mark = "x" if t.done else " "
    parts = [f"{i+1:>2}. [{mark}]"]
    if t.priority:
        parts.append(priority_str(t))
    if t.due:
        parts.append(due_str(t))
    parts.append(text_colored(t))
    print(" ".join(p for p in parts if p))


def cli_list(tasks, args):
    # parse --tag X --project X --priority X --overdue --today --done --todo --search X
    tag = project = priority = search = ""
    mode = "all"
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--tag" and i + 1 < len(args):
            tag = args[i + 1]; i += 2; continue
        if a == "--project" and i + 1 < len(args):
            project = args[i + 1]; i += 2; continue
        if a == "--priority" and i + 1 < len(args):
            priority = args[i + 1].upper(); i += 2; continue
        if a == "--search" and i + 1 < len(args):
            search = args[i + 1]; i += 2; continue
        if a == "--overdue":
            mode = "overdue"; i += 1; continue
        if a == "--today":
            mode = "today"; i += 1; continue
        if a == "--done":
            mode = "done"; i += 1; continue
        if a == "--todo":
            mode = "todo"; i += 1; continue
        i += 1

    filtered = apply_filter(tasks, mode, search)
    if tag:
        filtered = [t for t in filtered if tag.lstrip("#") in t.tags]
    if project:
        filtered = [t for t in filtered if project.lstrip("+") in t.projects]
    if priority:
        filtered = [t for t in filtered if t.priority == priority]

    if not filtered:
        print("No tasks yet.")
        return
    # show index in full list, not filtered position, so done/rm numbers still work
    for t in filtered:
        idx = tasks.index(t)
        print_task(idx, t)


# ---------- TUI ----------

def run_tui(tasks):
    try:
        import curses
    except ImportError:
        print("Error: curses is not available on this platform. Use CLI commands instead.")
        return

    def prompt(stdscr, h, w, label):
        curses.echo()
        curses.curs_set(1)
        stdscr.addstr(h - 1, 0, " " * (w - 1))
        stdscr.addstr(h - 1, 0, label[: w - 1])
        stdscr.refresh()
        try:
            raw = stdscr.getstr(h - 1, min(len(label), w - 1), w - len(label) - 1)
            s = raw.decode("utf-8", errors="ignore").strip()
        except Exception:
            s = ""
        curses.noecho()
        curses.curs_set(0)
        return s

    def main(stdscr):
        curses.curs_set(0)
        stdscr.keypad(True)
        if curses.has_colors():
            curses.start_color()
            curses.use_default_colors()
            curses.init_pair(1, curses.COLOR_WHITE, curses.COLOR_BLUE)   # header
            curses.init_pair(2, curses.COLOR_RED, -1)                    # P1
            curses.init_pair(3, curses.COLOR_YELLOW, -1)                 # P2
            curses.init_pair(4, curses.COLOR_GREEN, -1)                  # P3
            curses.init_pair(5, curses.COLOR_RED, -1)                    # overdue
            curses.init_pair(6, curses.COLOR_YELLOW, -1)                 # today
            curses.init_pair(7, curses.COLOR_CYAN, -1)                   # #tag
            curses.init_pair(8, curses.COLOR_MAGENTA, -1)                # +project
            curses.init_pair(9, curses.COLOR_BLACK, curses.COLOR_WHITE)  # selected
            curses.init_pair(10, curses.COLOR_WHITE, curses.COLOR_BLUE)  # footer
            curses.init_pair(11, curses.COLOR_YELLOW, -1)                 # status

        selected = 0
        filter_mode = "all"
        search = ""
        status = "Welcome - j/k move, space done, a add, e edit, x delete, / search, f filter, u undo, q quit"
        filters = ["all", "todo", "done", "overdue", "today", "P1", "P2", "P3"]

        while True:
            h, w = stdscr.getmaxyx()
            stdscr.clear()

            total = len(tasks)
            done_n = sum(1 for t in tasks if t.done)
            overdue_n = sum(1 for t in tasks if is_overdue(t))
            header = f"  TASKS  •  Total {total}  •  Done {done_n}  •  Overdue {overdue_n}  •  Filter: {filter_mode}" + (f"  •  Search: {search}" if search else "")
            try:
                stdscr.addstr(0, 0, header.ljust(w)[: w - 1], curses.color_pair(1) | curses.A_BOLD)
            except curses.error:
                pass

            visible = apply_filter(tasks, filter_mode, search)
            if selected >= len(visible):
                selected = max(0, len(visible) - 1)

            # column header
            if h > 3:
                stdscr.addstr(1, 0, "  #  DONE  PRI  DUE         TASK", curses.A_DIM)

            for idx, t in enumerate(visible):
                y = idx + 2
                if y >= h - 2:
                    break
                is_sel = idx == selected
                row_attr = curses.color_pair(9) if is_sel else curses.A_NORMAL
                if t.done and not is_sel:
                    row_attr |= curses.A_DIM
                # clear row
                try:
                    stdscr.addstr(y, 0, " " * (w - 1), row_attr)
                except curses.error:
                    continue
                x = 0
                prefix = f" {idx+1:>2}. [{'x' if t.done else ' '}] "
                stdscr.addstr(y, x, prefix, row_attr)
                x += len(prefix)
                if t.priority:
                    col = 2 if t.priority == "P1" else 3 if t.priority == "P2" else 4
                    p = f"({t.priority}) "
                    stdscr.addstr(y, x, p, curses.color_pair(col) | curses.A_BOLD | (row_attr if is_sel else 0))
                    x += len(p)
                else:
                    stdscr.addstr(y, x, "      ", row_attr)
                    x += 6
                if t.due:
                    dcol = 5 if is_overdue(t) else 6 if is_today(t) else 0
                    attr = (curses.color_pair(dcol) | curses.A_BOLD) if dcol and not is_sel else row_attr
                    stdscr.addstr(y, x, f"{t.due} ", attr)
                    x += len(t.due) + 1
                else:
                    stdscr.addstr(y, x, "           ", row_attr)
                    x += 11
                # text tokens with #tag / +project colors
                for tok in t.text.split(" "):
                    if x >= w - 2:
                        break
                    tok_s = tok + " "
                    if tok.startswith("#"):
                        a = curses.color_pair(7) | (row_attr if is_sel else 0)
                    elif tok.startswith("+"):
                        a = curses.color_pair(8) | (row_attr if is_sel else 0)
                    else:
                        a = row_attr
                    try:
                        stdscr.addstr(y, x, tok_s[: w - x - 1], a)
                    except curses.error:
                        break
                    x += len(tok_s)

            footer = " j/k move  •  space done  •  a add  •  e edit  •  x delete  •  / search  •  f filter  •  u undo  •  c clear done  •  q quit "
            try:
                stdscr.addstr(h - 2, 0, footer.ljust(w)[: w - 1], curses.color_pair(10))
                stdscr.addstr(h - 1, 0, status.ljust(w)[: w - 1], curses.color_pair(11))
            except curses.error:
                pass
            stdscr.refresh()

            key = stdscr.getch()

            if key in (ord("q"), 27):
                break
            elif key in (curses.KEY_DOWN, ord("j")):
                if visible:
                    selected = min(selected + 1, len(visible) - 1)
            elif key in (curses.KEY_UP, ord("k")):
                selected = max(selected - 1, 0)
            elif key in (ord("g"),):
                selected = 0
            elif key in (ord("G"),):
                selected = max(0, len(visible) - 1)
            elif key == ord(" "):
                if visible:
                    t = visible[selected]
                    t.done = not t.done
                    save_tasks(tasks)
                    status = f"{'Done' if t.done else 'Undone'}: {t.text}"
            elif key == ord("a"):
                s = prompt(stdscr, h, w, "Add (e.g. (P1) 2026-12-01 Buy ass cream #personal): ")
                if s:
                    nt = parse_add_text(s)
                    tasks.append(nt)
                    save_tasks(tasks)
                    selected = len(apply_filter(tasks, filter_mode, search)) - 1
                    status = f"Added: {nt.text}"
                else:
                    status = "Add cancelled"
            elif key == ord("e"):
                if visible:
                    t = visible[selected]
                    s = prompt(stdscr, h, w, f"Edit: [{t.text}] -> ")
                    if s:
                        nt = parse_add_text(s)
                        # keep old priority/due if new one didn't specify them
                        if not nt.priority:
                            nt.priority = t.priority
                        if not nt.due:
                            nt.due = t.due
                        t.text = nt.text
                        t.priority = nt.priority
                        t.due = nt.due
                        save_tasks(tasks)
                        status = f"Edited: {t.text}"
            elif key in (ord("x"), ord("D")):
                if visible:
                    t = visible[selected]
                    tasks.remove(t)
                    save_tasks(tasks)
                    status = f"Removed: {t.text}"
                    selected = max(0, selected - 1)
            elif key == ord("/"):
                s = prompt(stdscr, h, w, "Search (empty to clear): ")
                search = s
                selected = 0
                status = f"Search: {search}" if search else "Search cleared"
            elif key == ord("f"):
                idx = filters.index(filter_mode)
                filter_mode = filters[(idx + 1) % len(filters)]
                selected = 0
                status = f"Filter: {filter_mode}"
            elif key == ord("u"):
                if os.path.exists(BACKUP_FILE):
                    shutil.copyfile(BACKUP_FILE, TASKS_FILE)
                    tasks.clear()
                    tasks.extend(load_tasks())
                    status = "Undone - restored backup"
                else:
                    status = "No backup to undo"
            elif key == ord("c"):
                before = len(tasks)
                tasks[:] = [t for t in tasks if not t.done]
                save_tasks(tasks)
                status = f"Cleared {before - len(tasks)} completed task(s)"
            elif key == ord("s"):
                total = len(tasks)
                done_n = sum(1 for t in tasks if t.done)
                status = f"Stats - Total {total} | Done {done_n} | Remaining {total - done_n} | Overdue {overdue_n}"

    curses.wrapper(main)


# ---------- main CLI ----------

def main():
    args = sys.argv[1:]
    tasks = load_tasks()

    if not args or args[0] == "tui":
        run_tui(tasks)
        return

    cmd = args[0]

    if cmd in ("help", "-h", "--help"):
        print(HELP)
        return

    if cmd == "add":
        rest = args[1:]
        priority = ""
        due = ""
        text_parts = []
        i = 0
        while i < len(rest):
            if rest[i] == "--priority" and i + 1 < len(rest):
                priority = rest[i + 1].upper(); i += 2; continue
            if rest[i] == "--due" and i + 1 < len(rest):
                due = rest[i + 1]; i += 2; continue
            text_parts.append(rest[i]); i += 1
        full = " ".join(text_parts)
        if not full.strip():
            print("Error: task text is required.")
            return
        t = parse_add_text(full)
        if priority:
            t.priority = priority
        if due:
            t.due = due
        tasks.append(t)
        save_tasks(tasks)
        print(f"Added: {format_task(t)}")
        return

    if cmd == "list":
        cli_list(tasks, args[1:])
        return

    if cmd == "done":
        if len(args) < 2:
            print("Error: invalid task number."); return
        idx = parse_task_number(args[1], len(tasks))
        if idx is None:
            print("Error: invalid task number."); return
        tasks[idx].done = True
        save_tasks(tasks)
        print(f"Done: {tasks[idx].text}")
        return

    if cmd == "undone":
        if len(args) < 2:
            print("Error: invalid task number."); return
        idx = parse_task_number(args[1], len(tasks))
        if idx is None:
            print("Error: invalid task number."); return
        tasks[idx].done = False
        save_tasks(tasks)
        print(f"Undone: {tasks[idx].text}")
        return

    if cmd == "rm":
        if len(args) < 2:
            print("Error: invalid task number."); return
        idx = parse_task_number(args[1], len(tasks))
        if idx is None:
            print("Error: invalid task number."); return
        removed = tasks.pop(idx)
        save_tasks(tasks)
        print(f"Removed: {removed.text}")
        return

    if cmd == "edit":
        if len(args) < 3:
            print("Error: edit needs a number and new text."); return
        idx = parse_task_number(args[1], len(tasks))
        if idx is None:
            print("Error: invalid task number."); return
        nt = parse_add_text(" ".join(args[2:]))
        old = tasks[idx]
        if not nt.priority:
            nt.priority = old.priority
        if not nt.due:
            nt.due = old.due
        nt.done = old.done
        tasks[idx] = nt
        save_tasks(tasks)
        print(f"Edited: {format_task(nt)}")
        return

    if cmd == "search":
        if len(args) < 2:
            print("Error: search needs text."); return
        q = " ".join(args[1:]).lower()
        found = [t for t in tasks if q in t.text.lower()]
        if not found:
            print("No matches.")
            return
        for t in found:
            print_task(tasks.index(t), t)
        return

    if cmd == "clear":
        before = len(tasks)
        tasks[:] = [t for t in tasks if not t.done]
        save_tasks(tasks)
        print(f"Cleared {before - len(tasks)} completed task(s).")
        return

    if cmd == "stats":
        total = len(tasks)
        done_n = sum(1 for t in tasks if t.done)
        overdue_n = sum(1 for t in tasks if is_overdue(t))
        print(f"Total: {total} | Done: {done_n} | Remaining: {total - done_n} | Overdue: {overdue_n}")
        # by tag
        from collections import Counter
        tag_c = Counter()
        pri_c = Counter()
        for t in tasks:
            for tag in t.tags:
                tag_c[tag] += 1
            if t.priority:
                pri_c[t.priority] += 1
        if pri_c:
            print("By priority: " + ", ".join(f"{k} {v}" for k, v in sorted(pri_c.items())))
        if tag_c:
            print("By tag: " + ", ".join(f"#{k} {v}" for k, v in tag_c.most_common()))
        return

    if cmd == "undo":
        if not os.path.exists(BACKUP_FILE):
            print("No backup to undo.")
            return
        shutil.copyfile(BACKUP_FILE, TASKS_FILE)
        print("Undone - restored backup.")
        return

    print(f"Error: unknown command '{cmd}'.")
    print(HELP)


if __name__ == "__main__":
    main()
