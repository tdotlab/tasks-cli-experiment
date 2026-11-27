import * as fs from "fs";
import * as readline from "readline";

const TASKS_FILE = "tasks.md";
const BACKUP_FILE = "tasks.md.bak";

interface Task {
  done: boolean;
  priority: string;
  due: string;
  text: string;
}

function todayStr(): string {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function isOverdue(t: Task): boolean {
  if (!t.due) return false;
  return t.due < todayStr();
}

function isToday(t: Task): boolean {
  if (!t.due) return false;
  return t.due === todayStr();
}

function parseLine(line: string): Task | null {
  const m = line.match(/^- \[( |x)\]\s*(.*)$/);
  if (!m) return null;
  const done = m[1] === "x";
  let rest = m[2].trim();
  let priority = "";
  const pm = rest.match(/^\((P1|P2|P3)\)\s*/);
  if (pm) {
    priority = pm[1];
    rest = rest.replace(/^\((P1|P2|P3)\)\s*/, "").trim();
  }
  let due = "";
  const dm = rest.match(/^due:(\d{4}-\d{2}-\d{2})\s*/);
  if (dm) {
    due = dm[1];
    rest = rest.replace(/^due:(\d{4}-\d{2}-\d{2})\s*/, "").trim();
  }
  return { done, priority, due, text: rest };
}

function formatTask(t: Task): string {
  const mark = t.done ? "x" : " ";
  const parts: string[] = [`- [${mark}]`];
  if (t.priority) parts.push(`(${t.priority})`);
  if (t.due) parts.push(`due:${t.due}`);
  parts.push(t.text);
  return parts.join(" ");
}

function loadTasks(): Task[] {
  if (!fs.existsSync(TASKS_FILE)) return [];
  const data = fs.readFileSync(TASKS_FILE, "utf-8");
  const out: Task[] = [];
  for (const line of data.split("\n")) {
    const l = line.replace(/\r$/, "");
    if (!l.trim()) continue;
    const t = parseLine(l);
    if (t) out.push(t);
  }
  return out;
}

function saveTasks(tasks: Task[]): void {
  if (fs.existsSync(TASKS_FILE)) {
    try {
      fs.copyFileSync(TASKS_FILE, BACKUP_FILE);
    } catch {}
  }
  const content = tasks.map(formatTask).join("\n") + (tasks.length ? "\n" : "");
  fs.writeFileSync(TASKS_FILE, content);
}

function parseAddText(full: string): Task {
  let text = full.trim();
  let priority = "";
  let due = "";
  const pm1 = text.match(/^(P1|P2|P3)\s+/);
  if (pm1) {
    priority = pm1[1];
    text = text.replace(/^(P1|P2|P3)\s+/, "").trim();
  } else {
    const pm2 = text.match(/^\((P1|P2|P3)\)\s*/);
    if (pm2) {
      priority = pm2[1];
      text = text.replace(/^\((P1|P2|P3)\)\s*/, "").trim();
    }
  }
  const dm = text.match(/\bdue:(\d{4}-\d{2}-\d{2})\b/);
  if (dm) {
    due = dm[1];
    text = text.replace(/\bdue:(\d{4}-\d{2}-\d{2})\b/, " ").trim();
  }
  text = text.split(/\s+/).join(" ");
  return { done: false, priority, due, text };
}

function parseTaskNumber(s: string, n: number): number {
  const v = parseInt(s, 10);
  if (isNaN(v) || v < 1 || v > n) return -1;
  return v - 1;
}

function matchesMode(t: Task, mode: string): boolean {
  if (mode === "todo") return !t.done;
  if (mode === "done") return t.done;
  if (mode === "overdue") return !t.done && isOverdue(t);
  if (mode === "today") return !t.done && isToday(t);
  return true;
}

function matchesSearch(t: Task, q: string): boolean {
  if (!q) return true;
  return t.text.toLowerCase().includes(q.toLowerCase());
}

function filteredIndices(tasks: Task[], mode: string, search: string): number[] {
  const out: number[] = [];
  tasks.forEach((t, i) => {
    if (!matchesMode(t, mode)) return;
    if (!matchesSearch(t, search)) return;
    out.push(i);
  });
  return out;
}

function countDone(tasks: Task[]): number {
  return tasks.filter((t) => t.done).length;
}

function countOverdue(tasks: Task[]): number {
  return tasks.filter((t) => !t.done && isOverdue(t)).length;
}

function tagsOf(t: Task): string[] {
  return t.text.split(" ").filter((tok) => tok.startsWith("#") && tok.length > 1);
}

function projectsOf(t: Task): string[] {
  return t.text.split(" ").filter((tok) => tok.startsWith("+") && tok.length > 1);
}

function hasTag(t: Task, tag: string): boolean {
  const want = tag.replace(/^#/, "");
  return tagsOf(t).some((tg) => tg === tag || tg === `#${want}`);
}

function hasProject(t: Task, proj: string): boolean {
  const want = proj.replace(/^\+/, "");
  return projectsOf(t).some((pr) => pr === proj || pr === `+${want}`);
}

function printTask(idx: number, t: Task): void {
  const mark = t.done ? "x" : " ";
  const parts: string[] = [`${idx + 1}.`, `[${mark}]`];
  if (t.priority) parts.push(t.priority);
  if (t.due) parts.push(t.due);
  parts.push(t.text);
  console.log(parts.join(" "));
}

function cliList(tasks: Task[], args: string[]): void {
  let tag = "";
  let project = "";
  let priority = "";
  let search = "";
  let mode = "all";
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--tag" && i + 1 < args.length) {
      tag = args[i + 1];
      i++;
      continue;
    }
    if (a === "--project" && i + 1 < args.length) {
      project = args[i + 1];
      i++;
      continue;
    }
    if (a === "--priority" && i + 1 < args.length) {
      priority = args[i + 1];
      i++;
      continue;
    }
    if (a === "--search" && i + 1 < args.length) {
      search = args[i + 1];
      i++;
      continue;
    }
    if (a === "--overdue") mode = "overdue";
    else if (a === "--today") mode = "today";
    else if (a === "--done") mode = "done";
    else if (a === "--todo") mode = "todo";
  }
  let shown = 0;
  for (const idx of filteredIndices(tasks, mode, search)) {
    const t = tasks[idx];
    if (tag && !hasTag(t, tag)) continue;
    if (project && !hasProject(t, project)) continue;
    if (priority && t.priority !== priority) continue;
    printTask(idx, t);
    shown++;
  }
  if (shown === 0) console.log("No tasks.");
}

// ---------------------------------------------------------------------------
// TUI - AUDITED FIXES
// 1. Prompt has NO small char limit: builds string dynamically, 4096 cap,
//    horizontal scroll. Old TS used readline.question with a fixed
//    terminal width slice / or a 50-char buffer in some builds - now
//    key-by-key, no truncation.
// 2. Exit is explicit: q, Q, Esc, Ctrl-C, Ctrl-D, Ctrl-Q all quit from
//    main list, footer always shows "q / Esc / Ctrl-C to quit". In a
//    prompt, Enter saves, Esc / Ctrl-C cancels back to list.
// ---------------------------------------------------------------------------

// Key queue - single keypress handler for whole TUI
let keyQueue: string[] = [];
let keyWaiters: ((k: string) => void)[] = [];
let keyHandlerInstalled = false;

function installKeyHandler(): void {
  if (keyHandlerInstalled) return;
  keyHandlerInstalled = true;
  readline.emitKeypressEvents(process.stdin);
  if (process.stdin.isTTY) {
    try {
      (process.stdin as any).setRawMode(true);
    } catch {}
  }
  process.stdin.on("keypress", (_str: string, key: any) => {
    let k = "";
    if (!key) {
      k = _str;
    } else if (key.ctrl && key.name === "c") {
      k = "ctrl-c";
    } else if (key.ctrl && key.name === "d") {
      k = "ctrl-d";
    } else if (key.ctrl && key.name === "q") {
      k = "ctrl-q";
    } else if (key.ctrl && key.name === "u") {
      k = "ctrl-u";
    } else if (key.ctrl && key.name === "k") {
      k = "ctrl-k";
    } else if (key.ctrl && key.name === "a") {
      k = "ctrl-a";
    } else if (key.ctrl && key.name === "e") {
      k = "ctrl-e";
    } else if (key.ctrl && key.name === "w") {
      k = "ctrl-w";
    } else if (key.name === "escape") {
      k = "esc";
    } else if (key.name === "return") {
      k = "enter";
    } else if (key.name === "backspace") {
      k = "backspace";
    } else if (key.name === "delete") {
      k = "delete";
    } else if (key.name === "left") {
      k = "left";
    } else if (key.name === "right") {
      k = "right";
    } else if (key.name === "up") {
      k = "up";
    } else if (key.name === "down") {
      k = "down";
    } else if (key.name === "home") {
      k = "home";
    } else if (key.name === "end") {
      k = "end";
    } else if (_str && _str.length === 1) {
      k = _str;
    } else if (key.sequence) {
      k = key.sequence;
    }
    if (!k) return;
    if (keyWaiters.length > 0) {
      const w = keyWaiters.shift()!;
      w(k);
    } else {
      keyQueue.push(k);
    }
  });
  process.stdin.resume();
}

function readKey(): Promise<string> {
  installKeyHandler();
  return new Promise((resolve) => {
    if (keyQueue.length > 0) {
      resolve(keyQueue.shift()!);
      return;
    }
    keyWaiters.push(resolve);
  });
}

function termSize(): { rows: number; cols: number } {
  const rows = process.stdout.rows || 24;
  const cols = process.stdout.columns || 80;
  return { rows, cols };
}

async function promptInput(label: string, initial: string): Promise<string | null> {
  // Dynamic string, no small limit, 4096 cap, horizontal scroll
  let text = initial.split("");
  let cursor = text.length;
  let offset = 0;
  const labelStr = label + " ";
  while (true) {
    const { rows, cols } = termSize();
    const w = cols;
    let avail = w - labelStr.length - 1;
    if (avail < 10) avail = 10;
    if (cursor < offset) offset = cursor;
    if (cursor >= offset + avail) offset = cursor - avail + 1;
    if (offset < 0) offset = 0;
    // Hint line + prompt line
    process.stdout.write(`\x1b[${rows - 1};1H\x1b[2KEnter=save  Esc / Ctrl-C=cancel`);
    process.stdout.write(`\x1b[${rows};1H\x1b[2K`);
    const visible = text.slice(offset, offset + avail).join("");
    process.stdout.write(`${labelStr}${visible}`);
    const cursorX = labelStr.length + (cursor - offset) + 1;
    process.stdout.write(`\x1b[${rows};${Math.min(cursorX, w)}H`);
    const k = await readKey();
    if (k === "enter") {
      return text.join("").trim();
    }
    if (k === "esc" || k === "ctrl-c" || k === "ctrl-d") {
      return null;
    }
    if (k === "backspace") {
      if (cursor > 0) {
        text.splice(cursor - 1, 1);
        cursor--;
      }
      continue;
    }
    if (k === "delete") {
      if (cursor < text.length) {
        text.splice(cursor, 1);
      }
      continue;
    }
    if (k === "left") {
      if (cursor > 0) cursor--;
      continue;
    }
    if (k === "right") {
      if (cursor < text.length) cursor++;
      continue;
    }
    if (k === "home" || k === "ctrl-a") {
      cursor = 0;
      continue;
    }
    if (k === "end" || k === "ctrl-e") {
      cursor = text.length;
      continue;
    }
    if (k === "ctrl-u") {
      text = [];
      cursor = 0;
      offset = 0;
      continue;
    }
    if (k === "ctrl-k") {
      text = text.slice(0, cursor);
      continue;
    }
    if (k === "ctrl-w") {
      while (cursor > 0 && text[cursor - 1] === " ") {
        text.splice(cursor - 1, 1);
        cursor--;
      }
      while (cursor > 0 && text[cursor - 1] !== " ") {
        text.splice(cursor - 1, 1);
        cursor--;
      }
      continue;
    }
    if (k === "up" || k === "down") {
      continue;
    }
    // Printable single char
    if (k.length === 1 && k >= " " && k <= "~") {
      if (text.length < 4096) {
        text.splice(cursor, 0, k);
        cursor++;
      }
      continue;
    }
    // Unicode printable (length > 1 but single grapheme)
    if (k.length >= 1 && k !== "enter" && !k.startsWith("ctrl") && k !== "esc") {
      // readline gives us the actual char in _str, which we stored as k
      // If it's printable and not a special name, insert it
      const isSpecial = ["up", "down", "left", "right", "home", "end", "backspace", "delete"].includes(k);
      if (!isSpecial && text.length < 4096) {
        // Only insert if it looks like a char, not a control sequence
        if (k.charCodeAt(0) >= 32) {
          text.splice(cursor, 0, k);
          cursor++;
        }
      }
      continue;
    }
  }
}

async function runTUI(tasks: Task[]): Promise<void> {
  installKeyHandler();
  let selected = 0;
  let filterMode = "all";
  let search = "";
  let status = "Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter";
  const filters = ["all", "todo", "done", "overdue", "today"];

  while (true) {
    const { rows, cols } = termSize();
    const visible = filteredIndices(tasks, filterMode, search);
    if (visible.length === 0) {
      selected = 0;
    } else {
      if (selected >= visible.length) selected = visible.length - 1;
      if (selected < 0) selected = 0;
    }
    process.stdout.write("\x1b[2J\x1b[H");
    const total = tasks.length;
    const doneN = countDone(tasks);
    const overdueN = countOverdue(tasks);
    let header = `tasks - ${total} total | ${doneN} done | ${overdueN} overdue | filter: ${filterMode} | search: ${search}`;
    if (header.length > cols) header = header.slice(0, cols);
    process.stdout.write(header + "\n");
    process.stdout.write(`${"#".padEnd(4)} ${"[]".padEnd(3)} ${"P".padEnd(4)} ${"Due".padEnd(11)} Text\n`);
    process.stdout.write("-".repeat(Math.min(cols, 80)) + "\n");
    const maxRows = Math.max(rows - 5, 5);
    for (let i = 0; i < Math.min(visible.length, maxRows); i++) {
      const idx = visible[i];
      const t = tasks[idx];
      const mark = t.done ? "x" : " ";
      const pri = t.priority ? `(${t.priority}) ` : "";
      const due = t.due ? `due:${t.due} ` : "";
      let line = `${String(idx + 1).padEnd(4)} [${mark}] ${pri}${due}${t.text}`;
      if (line.length > cols) line = line.slice(0, cols);
      if (i === selected) {
        process.stdout.write(`\x1b[7m${line}\x1b[0m\n`);
      } else if (t.done) {
        process.stdout.write(`\x1b[2m${line}\x1b[0m\n`);
      } else {
        process.stdout.write(line + "\n");
      }
    }
    process.stdout.write(`\x1b[${rows - 1};1H\x1b[2K${status.slice(0, cols)}\n`);
    process.stdout.write(`q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats`.slice(0, cols));
    const k = await readKey();
    // EXIT - checked first
    if (k === "q" || k === "Q" || k === "esc" || k === "ctrl-c" || k === "ctrl-d" || k === "ctrl-q") {
      break;
    }
    if (k === "j" || k === "down") {
      if (selected < visible.length - 1) selected++;
      continue;
    }
    if (k === "k" || k === "up") {
      if (selected > 0) selected--;
      continue;
    }
    if (k === "g") {
      selected = 0;
      continue;
    }
    if (k === "G") {
      if (visible.length > 0) selected = visible.length - 1;
      continue;
    }
    if (k === " ") {
      if (visible.length > 0) {
        const idx = visible[selected];
        tasks[idx].done = !tasks[idx].done;
        saveTasks(tasks);
        status = tasks[idx].done ? "Marked done" : "Marked todo";
      }
      continue;
    }
    if (k === "a") {
      const s = await promptInput("Add:", "");
      if (s && s.length > 0) {
        const nt = parseAddText(s);
        tasks.push(nt);
        saveTasks(tasks);
        selected = tasks.length - 1;
        status = `Added: ${nt.text}`;
      } else {
        status = "Add cancelled - press q or Esc to quit";
      }
      continue;
    }
    if (k === "e") {
      if (visible.length > 0) {
        const idx = visible[selected];
        const old = tasks[idx];
        const s = await promptInput(`Edit [${old.text}]:`, "");
        if (s && s.length > 0) {
          const nt = parseAddText(s);
          if (!nt.priority) nt.priority = old.priority;
          if (!nt.due) nt.due = old.due;
          nt.done = old.done;
          tasks[idx] = nt;
          saveTasks(tasks);
          status = "Edited";
        }
      }
      continue;
    }
    if (k === "d") {
      if (visible.length > 0) {
        const idx = visible[selected];
        const removed = tasks[idx].text;
        tasks.splice(idx, 1);
        saveTasks(tasks);
        status = `Deleted: ${removed}`;
        if (selected >= visible.length - 1 && selected > 0) selected--;
      }
      continue;
    }
    if (k === "/") {
      const s = await promptInput("Search:", "");
      if (s !== null) {
        search = s;
        selected = 0;
        status = search ? `Search: ${search}` : "Search cleared - press q or Esc to quit";
      }
      continue;
    }
    if (k === "f") {
      const cur = filters.indexOf(filterMode);
      filterMode = filters[(cur + 1) % filters.length];
      selected = 0;
      status = `Filter: ${filterMode}`;
      continue;
    }
    if (k === "u") {
      if (fs.existsSync(BACKUP_FILE)) {
        try {
          fs.copyFileSync(BACKUP_FILE, TASKS_FILE);
          const nt = loadTasks();
          tasks.length = 0;
          tasks.push(...nt);
          status = "Undone";
        } catch {
          status = "Undo failed";
        }
      } else {
        status = "No backup to undo";
      }
      continue;
    }
    if (k === "c") {
      const before = tasks.length;
      const kept = tasks.filter((t) => !t.done);
      const cleared = before - kept.length;
      tasks.length = 0;
      tasks.push(...kept);
      saveTasks(tasks);
      status = `Cleared ${cleared} done`;
      selected = 0;
      continue;
    }
    if (k === "s") {
      const total2 = tasks.length;
      const doneN2 = countDone(tasks);
      const overdueN2 = countOverdue(tasks);
      status = `Total ${total2} - Done ${doneN2} - Todo ${total2 - doneN2} - Overdue ${overdueN2}`;
      continue;
    }
    if (k === "?") {
      status = "Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats";
      continue;
    }
  }
  // Restore terminal
  try {
    (process.stdin as any).setRawMode(false);
  } catch {}
  process.stdin.pause();
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const tasks = loadTasks();

  if (args.length === 0 || args[0] === "tui") {
    await runTUI(tasks);
    console.log("Exited TUI - back to shell. Use: npx ts-node tasks.ts list");
    return;
  }

  const cmd = args[0];

  if (cmd === "help" || cmd === "--help" || cmd === "-h") {
    console.log(`Usage:
  tasks tui                    Interactive TUI (default, no args = tui)
  tasks add [--priority P1] [--due YYYY-MM-DD] <text>
  tasks list [--tag X] [--project Y] [--priority P1] [--search Q] [--overdue|--today|--done|--todo]
  tasks done <n>
  tasks undone <n>
  tasks rm <n>
  tasks edit <n> <new text>
  tasks search <query>
  tasks clear
  tasks stats
  tasks undo
  tasks help

Format: tasks.md lines are - [ ] (P1) due:2026-11-30 Buy milk #home +groceries
Tags start with #, projects with +. Priority P1/P2/P3, due YYYY-MM-DD.
TUI keys: j/k or arrows move, Space toggle, a add, e edit, d delete,
  / search, f filter, u undo, c clear done, s stats, q / Esc / Ctrl-C to quit
  In a prompt: Enter saves, Esc / Ctrl-C cancels`);
    return;
  }

  if (cmd === "add") {
    const rest = args.slice(1);
    let priority = "";
    let due = "";
    const parts: string[] = [];
    for (let i = 0; i < rest.length; i++) {
      if (rest[i] === "--priority" && i + 1 < rest.length) {
        priority = rest[i + 1];
        i++;
        continue;
      }
      if (rest[i] === "--due" && i + 1 < rest.length) {
        due = rest[i + 1];
        i++;
        continue;
      }
      parts.push(rest[i]);
    }
    const full = parts.join(" ");
    if (!full.trim()) {
      console.log("Usage: tasks add <text>");
      return;
    }
    const t = parseAddText(full);
    if (priority) t.priority = priority;
    if (due) t.due = due;
    tasks.push(t);
    saveTasks(tasks);
    console.log(`Added: ${t.text}`);
    return;
  }

  if (cmd === "list") {
    cliList(tasks, args.slice(1));
    return;
  }

  if (cmd === "done") {
    if (args.length < 2) {
      console.log("Usage: tasks done <n>");
      return;
    }
    const idx = parseTaskNumber(args[1], tasks.length);
    if (idx === -1) {
      console.log("Invalid task number");
      return;
    }
    tasks[idx].done = true;
    saveTasks(tasks);
    console.log(`Done: ${tasks[idx].text}`);
    return;
  }

  if (cmd === "undone") {
    if (args.length < 2) {
      console.log("Usage: tasks undone <n>");
      return;
    }
    const idx = parseTaskNumber(args[1], tasks.length);
    if (idx === -1) {
      console.log("Invalid task number");
      return;
    }
    tasks[idx].done = false;
    saveTasks(tasks);
    console.log(`Todo: ${tasks[idx].text}`);
    return;
  }

  if (cmd === "rm") {
    if (args.length < 2) {
      console.log("Usage: tasks rm <n>");
      return;
    }
    const idx = parseTaskNumber(args[1], tasks.length);
    if (idx === -1) {
      console.log("Invalid task number");
      return;
    }
    const removed = tasks[idx].text;
    tasks.splice(idx, 1);
    saveTasks(tasks);
    console.log(`Deleted: ${removed}`);
    return;
  }

  if (cmd === "edit") {
    if (args.length < 3) {
      console.log("Usage: tasks edit <n> <new text>");
      return;
    }
    const idx = parseTaskNumber(args[1], tasks.length);
    if (idx === -1) {
      console.log("Invalid task number");
      return;
    }
    const nt = parseAddText(args.slice(2).join(" "));
    const old = tasks[idx];
    if (!nt.priority) nt.priority = old.priority;
    if (!nt.due) nt.due = old.due;
    nt.done = old.done;
    tasks[idx] = nt;
    saveTasks(tasks);
    console.log(`Edited ${idx + 1}: ${nt.text}`);
    return;
  }

  if (cmd === "search") {
    if (args.length < 2) {
      console.log("Usage: tasks search <query>");
      return;
    }
    const q = args.slice(1).join(" ");
    let found = false;
    tasks.forEach((t, i) => {
      if (matchesSearch(t, q)) {
        printTask(i, t);
        found = true;
      }
    });
    if (!found) console.log("No matches.");
    return;
  }

  if (cmd === "clear") {
    const before = tasks.length;
    const kept = tasks.filter((t) => !t.done);
    tasks.length = 0;
    tasks.push(...kept);
    saveTasks(tasks);
    console.log(`Cleared ${before - tasks.length} done tasks`);
    return;
  }

  if (cmd === "stats") {
    const total = tasks.length;
    const doneN = countDone(tasks);
    const overdueN = countOverdue(tasks);
    const todayN = tasks.filter((t) => !t.done && isToday(t)).length;
    console.log(`Total: ${total}\nDone: ${doneN}\nTodo: ${total - doneN}\nOverdue: ${overdueN}\nDue today: ${todayN}`);
    const priCount: Record<string, number> = {};
    const tagCount: Record<string, number> = {};
    for (const t of tasks) {
      if (t.priority) priCount[t.priority] = (priCount[t.priority] || 0) + 1;
      for (const tg of tagsOf(t)) tagCount[tg] = (tagCount[tg] || 0) + 1;
    }
    if (Object.keys(priCount).length > 0) {
      console.log("By priority:");
      for (const k of Object.keys(priCount).sort()) console.log(`  ${k}: ${priCount[k]}`);
    }
    if (Object.keys(tagCount).length > 0) {
      console.log("By tag:");
      for (const k of Object.keys(tagCount).sort()) console.log(`  ${k}: ${tagCount[k]}`);
    }
    return;
  }

  if (cmd === "undo") {
    if (!fs.existsSync(BACKUP_FILE)) {
      console.log("No backup to undo");
      return;
    }
    fs.copyFileSync(BACKUP_FILE, TASKS_FILE);
    console.log("Undone - restored from backup");
    return;
  }

  console.log(`Unknown command: ${cmd}`);
  console.log("Run: npx ts-node tasks.ts help");
}

main().catch((e) => {
  console.error(e);
  try {
    (process.stdin as any).setRawMode(false);
  } catch {}
  process.exit(1);
});
