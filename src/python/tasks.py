#!/usr/bin/env python3
import os
import sys

TASKS_FILE = "tasks.md"

HELP = """Usage: tasks <command> [args]

Commands:
  add "Buy milk"   Add a task
  list             Show all tasks
  done 2           Mark task 2 complete
  rm 2             Delete task 2
  clear            Remove completed tasks
  stats            Show totals
"""

def load_tasks():
    tasks = []
    if not os.path.exists(TASKS_FILE):
        return tasks
    with open(TASKS_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("- [ ] "):
                tasks.append({"done": False, "text": line[6:]})
            elif line.startswith("- [x] "):
                tasks.append({"done": True, "text": line[6:]})
            else:
                continue
    return tasks

def save_tasks(tasks):
    with open(TASKS_FILE, "w", encoding="utf-8") as f:
        for task in tasks:
            prefix = "- [x] " if task["done"] else "- [ ] "
            f.write(f"{prefix}{task['text']}\n")

def parse_task_number(args, tasks):
    if len(args) < 2:
        return None
    try:
        n = int(args[1])
    except ValueError:
        return None
    if n < 1 or n > len(tasks):
        return None
    return n - 1

def main():
    args = sys.argv[1:]
    tasks = load_tasks()

    if not args or args[0] in ("help", "-h", "--help"):
        print(HELP)
        return

    command = args[0]

    if command == "add":
        text = " ".join(args[1:]).strip()
        if not text:
            print("Error: task text is required.")
            return
        tasks.append({"done": False, "text": text})
        save_tasks(tasks)
        print(f"Added: {text}")
        return

    if command == "list":
        if not tasks:
            print("No tasks yet.")
            return
        for i, task in enumerate(tasks, start=1):
            mark = "x" if task["done"] else " "
            print(f"{i}. [{mark}] {task['text']}")
        return

    if command == "done":
        idx = parse_task_number(args, tasks)
        if idx is None:
            print("Error: invalid task number.")
            return
        tasks[idx]["done"] = True
        save_tasks(tasks)
        print(f"Done: {tasks[idx]['text']}")
        return

    if command == "rm":
        idx = parse_task_number(args, tasks)
        if idx is None:
            print("Error: invalid task number.")
            return
        removed = tasks.pop(idx)
        save_tasks(tasks)
        print(f"Removed: {removed['text']}")
        return

    if command == "clear":
        before = len(tasks)
        tasks = [t for t in tasks if not t["done"]]
        cleared = before - len(tasks)
        save_tasks(tasks)
        print(f"Cleared {cleared} completed task(s).")
        return

    if command == "stats":
        total = len(tasks)
        done = sum(1 for t in tasks if t["done"])
        remaining = total - done
        print(f"Total: {total} | Done: {done} | Remaining: {remaining}")
        return

    print(f"Error: unknown command '{command}'.")
    print(HELP)

if __name__ == "__main__":
    main()
