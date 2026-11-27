// tasks.js - Todo CLI v2 (straight JavaScript, Node.js, no dependencies)
// Same spec + same tasks.md as Python / C / C++ / Go / Zig / TypeScript v2.
// Run: node tasks.js  |  node tasks.js list  |  node tasks.js add "Buy milk #home"
// No build step. No TypeScript. No npm install.

const fs = require('fs');

const TASKS_FILE = 'tasks.md';
const BACKUP_FILE = 'tasks.md.bak';
const MAX_INPUT = 4096;

let tasks = [];

// ---------- helpers ----------
function trim(s) { return s.replace(/^\s+/, '').replace(/\s+$/, ''); }
function collapseSpaces(s) { return trim(s.replace(/\s+/g, ' ')); }

function todayStr() {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function isOverdue(t) { return t.due !== '' && t.due < todayStr(); }
function isToday(t) { return t.due !== '' && t.due === todayStr(); }

// ---------- parsing / formatting ----------
function parseLine(line) {
  if (!line.startsWith('- [')) return null;
  if (line.length < 5) return null;
  if (line[3] !== ' ' && line[3] !== 'x') return null;
  if (line[4] !== ']') return null;
  const t = { done: line[3] === 'x', priority: '', due: '', text: '' };
  let rest = trim(line.slice(5));
  if (rest.startsWith('(P1)') || rest.startsWith('(P2)') || rest.startsWith('(P3)')) {
    t.priority = rest.slice(1, 3);
    rest = trim(rest.slice(4));
  }
  if (rest.startsWith('due:') && rest.length >= 14) {
    const d = rest.slice(4, 14);
    if (d.length === 10 && d[4] === '-' && d[7] === '-') {
      t.due = d;
      rest = trim(rest.slice(14));
    }
  }
  t.text = trim(rest);
  return t;
}

function formatTask(t) {
  let s = '- [' + (t.done ? 'x' : ' ') + ']';
  if (t.priority) s += ' (' + t.priority + ')';
  if (t.due) s += ' due:' + t.due;
  s += ' ' + t.text;
  return s;
}

function loadTasks() {
  tasks = [];
  if (!fs.existsSync(TASKS_FILE)) return;
  const content = fs.readFileSync(TASKS_FILE, 'utf8');
  for (const rawLine of content.split('\n')) {
    const line = rawLine.replace(/\r$/, '');
    if (trim(line) === '') continue;
    const t = parseLine(line);
    if (t) tasks.push(t);
  }
}

function copyFile(src, dst) {
  try { fs.copyFileSync(src, dst); return true; } catch { return false; }
}

function saveTasks() {
  if (fs.existsSync(TASKS_FILE)) copyFile(TASKS_FILE, BACKUP_FILE);
  const out = tasks.map(formatTask).join('\n');
  fs.writeFileSync(TASKS_FILE, out ? out + '\n' : '');
}

function parseAddText(full) {
  const t = { done: false, priority: '', due: '', text: '' };
  let text = trim(full);
  if (text.startsWith('P1 ') || text.startsWith('P2 ') || text.startsWith('P3 ')) {
    t.priority = text.slice(0, 2);
    text = trim(text.slice(3));
  } else if (text.startsWith('(P1)') || text.startsWith('(P2)') || text.startsWith('(P3)')) {
    t.priority = text.slice(1, 3);
    text = trim(text.slice(4));
  }
  const pos = text.indexOf('due:');
  if (pos !== -1 && text.length >= pos + 14) {
    const cand = text.slice(pos + 4, pos + 14);
    if (cand.length === 10 && cand[4] === '-' && cand[7] === '-') {
      t.due = cand;
      const before = trim(text.slice(0, pos));
      const after = trim(text.slice(pos + 14));
      text = trim(before + ' ' + after);
    }
  }
  t.text = collapseSpaces(text);
  return t;
}

function parseTaskNumber(s, n) {
  const v = Number(trim(s));
  if (!Number.isInteger(v)) return -1;
  if (v < 1 || v > n) return -1;
  return v - 1;
}

function matchesMode(t, mode) {
  if (mode === 'todo') return !t.done;
  if (mode === 'done') return t.done;
  if (mode === 'overdue') return !t.done && isOverdue(t);
  if (mode === 'today') return !t.done && isToday(t);
  return true;
}

function matchesSearch(t, q) {
  if (!q) return true;
  return t.text.toLowerCase().includes(q.toLowerCase());
}

function filteredIndices(mode, search) {
  const out = [];
  for (let i = 0; i < tasks.length; i++) {
    if (!matchesMode(tasks[i], mode)) continue;
    if (!matchesSearch(tasks[i], search)) continue;
    out.push(i);
  }
  return out;
}

function countDone() { return tasks.filter(t => t.done).length; }
function countOverdue() { return tasks.filter(t => !t.done && isOverdue(t)).length; }

function hasTag(t, tag) {
  const want = tag.startsWith('#') ? tag.slice(1) : tag;
  for (const tok of t.text.split(/\s+/)) {
    if (tok.length > 1 && tok[0] === '#') {
      if (tok === tag || tok.slice(1) === want) return true;
    }
  }
  return false;
}

function hasProject(t, proj) {
  const want = proj.startsWith('+') ? proj.slice(1) : proj;
  for (const tok of t.text.split(/\s+/)) {
    if (tok.length > 1 && tok[0] === '+') {
      if (tok === proj || tok.slice(1) === want) return true;
    }
  }
  return false;
}

function printTask(idx, t) {
  const mark = t.done ? 'x' : ' ';
  let s = `${idx + 1}. [${mark}] `;
  if (t.priority) s += t.priority + ' ';
  if (t.due) s += t.due + ' ';
  s += t.text;
  console.log(s);
}

function cliList(args) {
  let tag = '', project = '', priority = '', search = '', mode = 'all';
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--tag' && i + 1 < args.length) { tag = args[++i]; continue; }
    if (a === '--project' && i + 1 < args.length) { project = args[++i]; continue; }
    if (a === '--priority' && i + 1 < args.length) { priority = args[++i]; continue; }
    if (a === '--search' && i + 1 < args.length) { search = args[++i]; continue; }
    if (a === '--overdue') mode = 'overdue';
    else if (a === '--today') mode = 'today';
    else if (a === '--done') mode = 'done';
    else if (a === '--todo') mode = 'todo';
  }
  let shown = 0;
  for (const idx of filteredIndices(mode, search)) {
    const t = tasks[idx];
    if (tag && !hasTag(t, tag)) continue;
    if (project && !hasProject(t, project)) continue;
    if (priority && t.priority !== priority) continue;
    printTask(idx, t);
    shown++;
  }
  if (shown === 0) console.log('No tasks.');
}

// [STRIPPED 77 bytes] TUI - AUDITED FIXES (same as C / C++ / Python / Go / Zig / TS)
// 1. Prompt has NO small char limit: reads bytes one-by-one in raw mode into
//    a growing JS string, 4096 cap, horizontal scroll. No readline with a
//    fixed width, no char[64]/[256] buffer, no width truncation.
// 2. Exit is explicit: q, Q, Esc, Ctrl-C, Ctrl-D, Ctrl-Q all quit from
//    main list, footer always shows "q / Esc / Ctrl-C to quit". In a
//    prompt, Enter saves, Esc / Ctrl-C cancels back to list.
// [STRIPPED 75 bytes]

function getTermSize() {
  return {
    rows: process.stdout.rows || 24,
    cols: process.stdout.columns || 80,
  };
}

// --- Byte-level key reader (raw mode) ---
let byteQueue = [];
let byteWaiters = [];
let stdinAttached = false;

function ensureStdin() {
  if (stdinAttached) return;
  stdinAttached = true;
  process.stdin.on('data', (chunk) => {
    for (const b of chunk) {
      byteQueue.push(b);
    }
    while (byteWaiters.length > 0 && byteQueue.length > 0) {
      const resolve = byteWaiters.shift();
      const b = byteQueue.shift();
      resolve(b);
    }
  });
}

function readByte() {
  ensureStdin();
  return new Promise((resolve) => {
    if (byteQueue.length > 0) {
      resolve(byteQueue.shift());
      return;
    }
    byteWaiters.push(resolve);
  });
}

function readByteTimeout(ms) {
  ensureStdin();
  return new Promise((resolve) => {
    if (byteQueue.length > 0) {
      resolve(byteQueue.shift());
      return;
    }
    const timer = setTimeout(() => {
      const idx = byteWaiters.indexOf(onByte);
      if (idx !== -1) byteWaiters.splice(idx, 1);
      resolve(null);
    }, ms);
    const onByte = (b) => {
      clearTimeout(timer);
      resolve(b);
    };
    byteWaiters.push(onByte);
  });
}

// Decode one UTF-8 char starting with first byte b (already consumed).
// Returns a JS string (1 char, may be surrogate pair).
async function decodeUtf8Char(firstByte) {
  if (firstByte < 0x80) return String.fromCharCode(firstByte);
  let need = 0;
  if (firstByte >= 0xC2 && firstByte <= 0xDF) need = 1;
  else if (firstByte >= 0xE0 && firstByte <= 0xEF) need = 2;
  else if (firstByte >= 0xF0 && firstByte <= 0xF4) need = 3;
  else return ''; // invalid lead, drop
  const bytes = [firstByte];
  for (let i = 0; i < need; i++) {
    const nb = await readByteTimeout(30);
    if (nb === null) break;
    bytes.push(nb);
  }
  try { return Buffer.from(bytes).toString('utf8'); } catch { return ''; }
}

// readKey returns: 'ESC', 'UP', 'DOWN', 'LEFT', 'RIGHT', 'HOME', 'END', 'DEL',
// '\r' for Enter, single-char string for printable / Ctrl keys (e.g. '\x03').
async function readKey() {
  const b = await readByte();
  if (b !== 27) {
    if (b >= 0x80) return await decodeUtf8Char(b);
    return String.fromCharCode(b);
  }
  // Esc - could be Esc alone or arrow sequence. Wait 30ms.
  const b2 = await readByteTimeout(30);
  if (b2 === null) return 'ESC';
  if (b2 !== 91 && b2 !== 79) return 'ESC'; // not '[' or 'O'
  const b3 = await readByteTimeout(30);
  if (b3 === null) return 'ESC';
  if (b3 === 65) return 'UP';
  if (b3 === 66) return 'DOWN';
  if (b3 === 67) return 'RIGHT';
  if (b3 === 68) return 'LEFT';
  if (b3 === 72) return 'HOME';
  if (b3 === 70) return 'END';
  if (b3 === 51) {
    await readByteTimeout(30); // consume ~
    return 'DEL';
  }
  return 'ESC';
}

// promptInput: returns string (trimmed) or null if cancelled.
// Dynamic string, no small limit, 4096 cap, horizontal scroll.
async function promptInput(label) {
  let text = '';
  let cursor = 0; // in JS string index (UTF-16 units, fine for most input)
  let offset = 0;
  const labelLen = label.length + 1; // label + space
  while (true) {
    const { rows, cols } = getTermSize();
    let avail = cols - labelLen - 1;
    if (avail < 10) avail = 10;
    if (cursor < offset) offset = cursor;
    if (cursor >= offset + avail) offset = cursor - avail + 1;
    process.stdout.write(`\x1b[${rows - 1};1H\x1b[2KEnter=save  Esc / Ctrl-C=cancel`);
    process.stdout.write(`\x1b[${rows};1H\x1b[2K`);
    process.stdout.write(label + ' ');
    const end = Math.min(offset + avail, text.length);
    if (offset < text.length) process.stdout.write(text.slice(offset, end));
    let cursorX = labelLen + (cursor - offset) + 1;
    if (cursorX > cols) cursorX = cols;
    process.stdout.write(`\x1b[${rows};${cursorX}H`);
    const k = await readKey();
    if (k === '\r' || k === '\n') break;
    if (k === 'ESC' || k === '\x03' || k === '\x04') { // Esc / Ctrl-C / Ctrl-D -> cancel
      return null;
    }
    if (k === '\x7f' || k === '\x08') { // Backspace
      if (cursor > 0) {
        text = text.slice(0, cursor - 1) + text.slice(cursor);
        cursor--;
      }
      continue;
    }
    if (k === 'DEL') {
      if (cursor < text.length) text = text.slice(0, cursor) + text.slice(cursor + 1);
      continue;
    }
    if (k === 'LEFT') { if (cursor > 0) cursor--; continue; }
    if (k === 'RIGHT') { if (cursor < text.length) cursor++; continue; }
    if (k === 'HOME' || k === '\x01') { cursor = 0; continue; } // Home / Ctrl-A
    if (k === 'END' || k === '\x05') { cursor = text.length; continue; } // End / Ctrl-E
    if (k === '\x15') { text = ''; cursor = 0; offset = 0; continue; } // Ctrl-U
    if (k === '\x0b') { text = text.slice(0, cursor); continue; } // Ctrl-K
    if (k === '\x17') { // Ctrl-W delete word
      while (cursor > 0 && text[cursor - 1] === ' ') { text = text.slice(0, cursor - 1) + text.slice(cursor); cursor--; }
      while (cursor > 0 && text[cursor - 1] !== ' ') { text = text.slice(0, cursor - 1) + text.slice(cursor); cursor--; }
      continue;
    }
    if (k === 'UP' || k === 'DOWN') continue;
    // Printable: single char, not a control char, not a special token
    if (typeof k === 'string' && k.length >= 1 && k !== 'ESC') {
      const code = k.charCodeAt(0);
      if (code >= 32 || code >= 128) {
        if (text.length < MAX_INPUT) {
          text = text.slice(0, cursor) + k + text.slice(cursor);
          cursor += k.length;
        }
      }
      continue;
    }
  }
  return trim(text);
}

async function runTui() {
  // raw mode
  if (process.stdin.isTTY) process.stdin.setRawMode(true);
  process.stdin.resume();
  let selected = 0;
  const filters = ['all', 'todo', 'done', 'overdue', 'today'];
  let filterIdx = 0;
  let search = '';
  let status = 'Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter';
  try {
    while (true) {
      const { rows, cols } = getTermSize();
      const filterMode = filters[filterIdx];
      const visible = filteredIndices(filterMode, search);
      if (visible.length === 0) selected = 0;
      else {
        if (selected >= visible.length) selected = visible.length - 1;
        if (selected < 0) selected = 0;
      }
      let out = '\x1b[2J\x1b[H';
      const total = tasks.length;
      const doneN = countDone();
      const overdueN = countOverdue();
      out += `tasks - ${total} total | ${doneN} done | ${overdueN} overdue | filter: ${filterMode} | search: ${search}\n`;
      out += '#    []  P    Due         Text\n';
      out += '-'.repeat(Math.min(80, cols)) + '\n';
      const maxRows = Math.max(5, rows - 5);
      for (let i = 0; i < visible.length && i < maxRows; i++) {
        const idx = visible[i];
        const t = tasks[idx];
        const mark = t.done ? 'x' : ' ';
        let line = String(idx + 1).padEnd(4) + ` [${mark}] `;
        if (t.priority) line += `(${t.priority}) `;
        if (t.due) line += `due:${t.due} `;
        line += t.text;
        if (line.length > cols) line = line.slice(0, cols);
        if (i === selected) out += `\x1b[7m${line}\x1b[0m\n`;
        else if (t.done) out += `\x1b[2m${line}\x1b[0m\n`;
        else out += line + '\n';
      }
      out += `\x1b[${rows - 1};1H\x1b[2K${status}`;
      out += `\x1b[${rows};1H\x1b[2K`;
      out += 'q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats';
      out += `\x1b[${rows};1H`;
      process.stdout.write(out);
      const k = await readKey();
      // EXIT - checked FIRST, from main list view
      if (k === 'q' || k === 'Q' || k === 'ESC' || k === '\x03' || k === '\x04' || k === '\x11') break;
      if (k === 'j' || k === 'DOWN') { if (selected + 1 < visible.length) selected++; continue; }
      if (k === 'k' || k === 'UP') { if (selected > 0) selected--; continue; }
      if (k === 'g') { selected = 0; continue; }
      if (k === 'G') { if (visible.length) selected = visible.length - 1; continue; }
      if (k === ' ') {
        if (visible.length) {
          const idx = visible[selected];
          tasks[idx].done = !tasks[idx].done;
          saveTasks();
          status = tasks[idx].done ? 'Marked done' : 'Marked todo';
        }
        continue;
      }
      if (k === 'a') {
        const s = await promptInput('Add:');
        if (s) {
          const nt = parseAddText(s);
          tasks.push(nt);
          saveTasks();
          selected = tasks.length - 1;
          status = 'Added: ' + nt.text;
        } else {
          status = 'Add cancelled - press q or Esc to quit';
        }
        continue;
      }
      if (k === 'e') {
        if (visible.length) {
          const idx = visible[selected];
          const old = tasks[idx];
          const s = await promptInput(`Edit [${old.text}]:`);
          if (s) {
            const nt = parseAddText(s);
            if (!nt.priority) nt.priority = old.priority;
            if (!nt.due) nt.due = old.due;
            nt.done = old.done;
            tasks[idx] = nt;
            saveTasks();
            status = 'Edited';
          }
        }
        continue;
      }
      if (k === 'd') {
        if (visible.length) {
          const idx = visible[selected];
          const removed = tasks[idx].text;
          tasks.splice(idx, 1);
          saveTasks();
          status = 'Deleted: ' + removed;
          if (selected >= visible.length - 1 && selected > 0) selected--;
        }
        continue;
      }
      if (k === '/') {
        const s = await promptInput('Search:');
        if (s !== null) {
          search = s;
          selected = 0;
          status = search ? 'Search: ' + search : 'Search cleared - press q or Esc to quit';
        }
        continue;
      }
      if (k === 'f') {
        filterIdx = (filterIdx + 1) % filters.length;
        selected = 0;
        status = 'Filter: ' + filters[filterIdx];
        continue;
      }
      if (k === 'u') {
        if (fs.existsSync(BACKUP_FILE)) {
          copyFile(BACKUP_FILE, TASKS_FILE);
          loadTasks();
          status = 'Undone';
        } else {
          status = 'No backup to undo';
        }
        continue;
      }
      if (k === 'c') {
        const before = tasks.length;
        tasks = tasks.filter(t => !t.done);
        saveTasks();
        status = `Cleared ${before - tasks.length} done`;
        selected = 0;
        continue;
      }
      if (k === 's') {
        const total2 = tasks.length;
        const doneN2 = countDone();
        const overdueN2 = countOverdue();
        status = `Total ${total2} - Done ${doneN2} - Todo ${total2 - doneN2} - Overdue ${overdueN2}`;
        continue;
      }
      if (k === '?') {
        status = 'Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats';
        continue;
      }
    }
  } finally {
    if (process.stdin.isTTY) process.stdin.setRawMode(false);
    process.stdin.pause();
    process.stdout.write('\n');
  }
}

function printHelp() {
  console.log('Usage:');
  console.log('  node tasks.js tui                    Interactive TUI (default, no args = tui)');
  console.log('  node tasks.js add [--priority P1] [--due YYYY-MM-DD] <text>');
  console.log('  node tasks.js list [--tag X] [--project Y] [--priority P1] [--search Q] [--overdue|--today|--done|--todo]');
  console.log('  node tasks.js done <n>');
  console.log('  node tasks.js undone <n>');
  console.log('  node tasks.js rm <n>');
  console.log('  node tasks.js edit <n> <new text>');
  console.log('  node tasks.js search <query>');
  console.log('  node tasks.js clear');
  console.log('  node tasks.js stats');
  console.log('  node tasks.js undo');
  console.log('  node tasks.js help');
  console.log('');
  console.log('Format: tasks.md lines are - [ ] (P1) due:2026-11-30 Buy milk #home +groceries');
  console.log('Tags start with #, projects with +. Priority P1/P2/P3, due YYYY-MM-DD.');
  console.log('TUI keys: j/k or arrows move, Space toggle, a add, e edit, d delete,');
  console.log('  / search, f filter, u undo, c clear done, s stats, q / Esc / Ctrl-C to quit');
  console.log('  In a prompt: Enter saves, Esc / Ctrl-C cancels');
}

async function main() {
  loadTasks();
  const argv = process.argv.slice(2);

  if (argv.length === 0 || argv[0] === 'tui') {
    await runTui();
    console.log('Exited TUI - back to shell. Use: node tasks.js list');
    return;
  }

  const cmd = argv[0];

  if (cmd === 'help' || cmd === '--help' || cmd === '-h') {
    printHelp();
    return;
  }

  if (cmd === 'add') {
    let priority = '', due = '';
    const parts = [];
    for (let i = 1; i < argv.length; i++) {
      if (argv[i] === '--priority' && i + 1 < argv.length) { priority = argv[++i]; continue; }
      if (argv[i] === '--due' && i + 1 < argv.length) { due = argv[++i]; continue; }
      parts.push(argv[i]);
    }
    const buf = parts.join(' ');
    if (trim(buf) === '') { console.log('Usage: node tasks.js add <text>'); return; }
    const t = parseAddText(buf);
    if (priority) t.priority = priority;
    if (due) t.due = due;
    tasks.push(t);
    saveTasks();
    console.log('Added: ' + t.text);
    return;
  }

  if (cmd === 'list') {
    cliList(argv.slice(1));
    return;
  }

  if (cmd === 'done') {
    if (argv.length < 2) { console.log('Usage: node tasks.js done <n>'); return; }
    const idx = parseTaskNumber(argv[1], tasks.length);
    if (idx === -1) { console.log('Invalid task number'); return; }
    tasks[idx].done = true;
    saveTasks();
    console.log('Done: ' + tasks[idx].text);
    return;
  }

  if (cmd === 'undone') {
    if (argv.length < 2) { console.log('Usage: node tasks.js undone <n>'); return; }
    const idx = parseTaskNumber(argv[1], tasks.length);
    if (idx === -1) { console.log('Invalid task number'); return; }
    tasks[idx].done = false;
    saveTasks();
    console.log('Todo: ' + tasks[idx].text);
    return;
  }

  if (cmd === 'rm') {
    if (argv.length < 2) { console.log('Usage: node tasks.js rm <n>'); return; }
    const idx = parseTaskNumber(argv[1], tasks.length);
    if (idx === -1) { console.log('Invalid task number'); return; }
    const removed = tasks[idx].text;
    tasks.splice(idx, 1);
    saveTasks();
    console.log('Deleted: ' + removed);
    return;
  }

  if (cmd === 'edit') {
    if (argv.length < 3) { console.log('Usage: node tasks.js edit <n> <new text>'); return; }
    const idx = parseTaskNumber(argv[1], tasks.length);
    if (idx === -1) { console.log('Invalid task number'); return; }
    const nt = parseAddText(argv.slice(2).join(' '));
    const old = tasks[idx];
    if (!nt.priority) nt.priority = old.priority;
    if (!nt.due) nt.due = old.due;
    nt.done = old.done;
    tasks[idx] = nt;
    saveTasks();
    console.log(`Edited ${idx + 1}: ${nt.text}`);
    return;
  }

  if (cmd === 'search') {
    if (argv.length < 2) { console.log('Usage: node tasks.js search <query>'); return; }
    const q = argv.slice(1).join(' ');
    let found = false;
    for (let i = 0; i < tasks.length; i++) {
      if (matchesSearch(tasks[i], q)) { printTask(i, tasks[i]); found = true; }
    }
    if (!found) console.log('No matches.');
    return;
  }

  if (cmd === 'clear') {
    const before = tasks.length;
    tasks = tasks.filter(t => !t.done);
    saveTasks();
    console.log(`Cleared ${before - tasks.length} done tasks`);
    return;
  }

  if (cmd === 'stats') {
    const total = tasks.length;
    const doneN = countDone();
    const overdueN = countOverdue();
    const todayN = tasks.filter(t => !t.done && isToday(t)).length;
    console.log(`Total: ${total}\nDone: ${doneN}\nTodo: ${total - doneN}\nOverdue: ${overdueN}\nDue today: ${todayN}`);
    const c1 = tasks.filter(t => t.priority === 'P1').length;
    const c2 = tasks.filter(t => t.priority === 'P2').length;
    const c3 = tasks.filter(t => t.priority === 'P3').length;
    if (c1 || c2 || c3) {
      console.log('By priority:');
      if (c1) console.log(`  P1: ${c1}`);
      if (c2) console.log(`  P2: ${c2}`);
      if (c3) console.log(`  P3: ${c3}`);
    }
    const tagCounts = new Map();
    for (const t of tasks) {
      for (const tok of t.text.split(/\s+/)) {
        if (tok.length > 1 && tok[0] === '#') tagCounts.set(tok, (tagCounts.get(tok) || 0) + 1);
      }
    }
    if (tagCounts.size > 0) {
      console.log('By tag:');
      for (const [k, v] of [...tagCounts.entries()].sort()) console.log(`  ${k}: ${v}`);
    }
    return;
  }

  if (cmd === 'undo') {
    if (!fs.existsSync(BACKUP_FILE)) { console.log('No backup to undo'); return; }
    copyFile(BACKUP_FILE, TASKS_FILE);
    console.log('Undone - restored from backup');
    return;
  }

  console.log('Unknown command: ' + cmd);
  printHelp();
}

main().catch((e) => {
  if (process.stdin.isTTY) { try { process.stdin.setRawMode(false); } catch {} }
  console.error(e);
  process.exit(1);
});
