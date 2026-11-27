// tasks.rs - Todo CLI v2 (Rust, stdlib only)
// Same spec + same tasks.md as all other languages.
// Build: rustc -O tasks.rs -o tasks
// Run: ./tasks  |  ./tasks list  |  ./tasks add "Buy milk #home"
// FIX 2026-11-27: Raw mode via direct tcgetattr/tcsetattr FFI.
// No subprocess for terminal config. Previous version used a piped
// subprocess for terminal setup, which pipes stdio away from the tty,
// so raw mode never engaged and `q` needed Enter.
// Now: tcgetattr saves exact termios, tcsetattr restores it on exit.

use std::env;
use std::fs;
use std::io::{self, Read, Write};
use std::os::unix::io::AsRawFd;
use std::time::{SystemTime, UNIX_EPOCH};

const TASKS_FILE: &str = "tasks.md";
const BACKUP_FILE: &str = "tasks.md.bak";
const MAX_INPUT: usize = 4096;

// Linux termios (x86_64 / aarch64, glibc)
#[repr(C)]
#[derive(Clone, Copy)]
struct Termios {
    c_iflag: u32,
    c_oflag: u32,
    c_cflag: u32,
    c_lflag: u32,
    c_line: u8,
    c_cc: [u8; 32],
    c_ispeed: u32,
    c_ospeed: u32,
}

extern "C" {
    fn tcgetattr(fd: i32, termios_p: *mut Termios) -> i32;
    fn tcsetattr(fd: i32, action: i32, termios_p: *const Termios) -> i32;
}

const TCSAFLUSH: i32 = 2;
const BRKINT: u32 = 0x2;
const ICRNL: u32 = 0x100;
const INPCK: u32 = 0x10;
const ISTRIP: u32 = 0x20;
const IXON: u32 = 0x400;
const OPOST: u32 = 0x1;
const CS8: u32 = 0x30;
const ECHO: u32 = 0x8;
const ICANON: u32 = 0x2;
const IEXTEN: u32 = 0x8000;
const ISIG: u32 = 0x1;
const VMIN: usize = 6;
const VTIME: usize = 5;

static mut ORIG_TERMIOS: Option<Termios> = None;
static mut TERMIOS_SAVED: bool = false;

fn save_termios() {
    unsafe {
        let mut t = std::mem::zeroed::<Termios>();
        if tcgetattr(io::stdin().as_raw_fd(), &mut t) == 0 {
            ORIG_TERMIOS = Some(t);
            TERMIOS_SAVED = true;
        }
    }
}

fn set_raw(vmin: u8, vtime: u8) {
    unsafe {
        if let Some(orig) = ORIG_TERMIOS {
            let mut raw = orig;
            raw.c_iflag &= !(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
            raw.c_oflag &= !OPOST;
            raw.c_cflag |= CS8;
            raw.c_lflag &= !(ECHO | ICANON | IEXTEN | ISIG);
            raw.c_cc[VMIN] = vmin;
            raw.c_cc[VTIME] = vtime;
            tcsetattr(io::stdin().as_raw_fd(), TCSAFLUSH, &raw);
        }
    }
}

fn restore_termios() {
    unsafe {
        if TERMIOS_SAVED {
            if let Some(orig) = ORIG_TERMIOS {
                tcsetattr(io::stdin().as_raw_fd(), TCSAFLUSH, &orig);
            }
        }
    }
}

#[derive(Clone, Debug)]
struct Task {
    done: bool,
    priority: String,
    due: String,
    text: String,
}

fn trim_s(s: &str) -> String { s.trim().to_string() }
fn collapse_spaces(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn today_str() -> String {
    let secs = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    let days = (secs / 86400) as i64;
    let z = days + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };
    format!("{:04}-{:02}-{:02}", year, m, d)
}

fn is_overdue(t: &Task) -> bool { !t.due.is_empty() && t.due < today_str() }
fn is_today(t: &Task) -> bool { !t.due.is_empty() && t.due == today_str() }

fn parse_line(line: &str) -> Option<Task> {
    if !line.starts_with("- [") { return None; }
    if line.len() < 5 { return None; }
    let mark = line.chars().nth(3)?;
    if mark != ' ' && mark != 'x' { return None; }
    if line.chars().nth(4)? != ']' { return None; }
    let mut t = Task { done: mark == 'x', priority: String::new(), due: String::new(), text: String::new() };
    let mut rest = trim_s(&line[5..]);
    if rest.starts_with("(P1)") || rest.starts_with("(P2)") || rest.starts_with("(P3)") {
        t.priority = rest[1..3].to_string();
        rest = trim_s(&rest[4..]);
    }
    if rest.starts_with("due:") && rest.len() >= 14 {
        let d = &rest[4..14];
        if d.len() == 10 && d.as_bytes()[4] == b'-' && d.as_bytes()[7] == b'-' {
            t.due = d.to_string();
            rest = trim_s(&rest[14..]);
        }
    }
    t.text = trim_s(&rest);
    Some(t)
}

fn format_task(t: &Task) -> String {
    let mut s = format!("- [{}]", if t.done { "x" } else { " " });
    if !t.priority.is_empty() { s += &format!(" ({})", t.priority); }
    if !t.due.is_empty() { s += &format!(" due:{}", t.due); }
    s += &format!(" {}", t.text);
    s
}

fn load_tasks() -> Vec<Task> {
    let mut out = Vec::new();
    if let Ok(content) = fs::read_to_string(TASKS_FILE) {
        for line in content.lines() {
            let line = line.strip_suffix('\r').unwrap_or(line);
            if trim_s(line).is_empty() { continue; }
            if let Some(t) = parse_line(line) { out.push(t); }
        }
    }
    out
}

fn save_tasks(tasks: &[Task]) {
    if fs::metadata(TASKS_FILE).is_ok() {
        let _ = fs::copy(TASKS_FILE, BACKUP_FILE);
    }
    let mut s = String::new();
    for t in tasks { s += &format_task(t); s += "\n"; }
    let _ = fs::write(TASKS_FILE, s);
}

fn parse_add_text(full: &str) -> Task {
    let mut t = Task { done: false, priority: String::new(), due: String::new(), text: String::new() };
    let mut text = trim_s(full);
    if text.starts_with("P1 ") || text.starts_with("P2 ") || text.starts_with("P3 ") {
        t.priority = text[..2].to_string();
        text = trim_s(&text[3..]);
    } else if text.starts_with("(P1)") || text.starts_with("(P2)") || text.starts_with("(P3)") {
        t.priority = text[1..3].to_string();
        text = trim_s(&text[4..]);
    }
    if let Some(pos) = text.find("due:") {
        if text.len() >= pos + 14 {
            let cand = &text[pos + 4..pos + 14];
            if cand.len() == 10 && cand.as_bytes()[4] == b'-' && cand.as_bytes()[7] == b'-' {
                t.due = cand.to_string();
                let before = trim_s(&text[..pos]);
                let after = trim_s(&text[pos + 14..]);
                text = trim_s(&format!("{} {}", before, after));
            }
        }
    }
    t.text = collapse_spaces(&text);
    t
}

fn parse_task_number(s: &str, n: usize) -> Option<usize> {
    let v: usize = trim_s(s).parse().ok()?;
    if v < 1 || v > n { return None; }
    Some(v - 1)
}

fn matches_mode(t: &Task, mode: &str) -> bool {
    match mode {
        "todo" => !t.done,
        "done" => t.done,
        "overdue" => !t.done && is_overdue(t),
        "today" => !t.done && is_today(t),
        _ => true,
    }
}
fn matches_search(t: &Task, q: &str) -> bool {
    if q.is_empty() { return true; }
    t.text.to_lowercase().contains(&q.to_lowercase())
}
fn filtered_indices(tasks: &[Task], mode: &str, search: &str) -> Vec<usize> {
    tasks.iter().enumerate().filter(|(_, t)| matches_mode(t, mode) && matches_search(t, search)).map(|(i, _)| i).collect()
}
fn count_done(tasks: &[Task]) -> usize { tasks.iter().filter(|t| t.done).count() }
fn count_overdue(tasks: &[Task]) -> usize { tasks.iter().filter(|t| !t.done && is_overdue(t)).count() }

fn has_tag(t: &Task, tag: &str) -> bool {
    let want = tag.strip_prefix('#').unwrap_or(tag);
    for tok in t.text.split_whitespace() {
        if tok.len() > 1 && tok.starts_with('#') {
            if tok == tag || &tok[1..] == want { return true; }
        }
    }
    false
}
fn has_project(t: &Task, proj: &str) -> bool {
    let want = proj.strip_prefix('+').unwrap_or(proj);
    for tok in t.text.split_whitespace() {
        if tok.len() > 1 && tok.starts_with('+') {
            if tok == proj || &tok[1..] == want { return true; }
        }
    }
    false
}
fn print_task(idx: usize, t: &Task) {
    let mut s = format!("{}. [{}] ", idx + 1, if t.done { "x" } else { " " });
    if !t.priority.is_empty() { s += &format!("{} ", t.priority); }
    if !t.due.is_empty() { s += &format!("{} ", t.due); }
    s += &t.text;
    println!("{}", s);
}

fn cli_list(tasks: &[Task], args: &[String]) {
    let mut tag = String::new();
    let mut project = String::new();
    let mut priority = String::new();
    let mut search = String::new();
    let mut mode = "all".to_string();
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if a == "--tag" && i + 1 < args.len() { tag = args[i + 1].clone(); i += 2; continue; }
        if a == "--project" && i + 1 < args.len() { project = args[i + 1].clone(); i += 2; continue; }
        if a == "--priority" && i + 1 < args.len() { priority = args[i + 1].clone(); i += 2; continue; }
        if a == "--search" && i + 1 < args.len() { search = args[i + 1].clone(); i += 2; continue; }
        if a == "--overdue" { mode = "overdue".to_string(); }
        else if a == "--today" { mode = "today".to_string(); }
        else if a == "--done" { mode = "done".to_string(); }
        else if a == "--todo" { mode = "todo".to_string(); }
        i += 1;
    }
    let mut shown = 0;
    for idx in filtered_indices(tasks, &mode, &search) {
        let t = &tasks[idx];
        if !tag.is_empty() && !has_tag(t, &tag) { continue; }
        if !project.is_empty() && !has_project(t, &project) { continue; }
        if !priority.is_empty() && t.priority != priority { continue; }
        print_task(idx, t);
        shown += 1;
    }
    if shown == 0 { println!("No tasks."); }
}

#[derive(Debug, Clone, PartialEq)]
enum Key { Char(char), Enter, Esc, Up, Down, Left, Right, Home, End, Del, Backspace, CtrlC, CtrlD, CtrlQ, CtrlA, CtrlE, CtrlU, CtrlK, CtrlW, Other }

fn read_byte() -> Option<u8> {
    let mut buf = [0u8; 1];
    let n = io::stdin().read(&mut buf).ok()?;
    if n == 0 { None } else { Some(buf[0]) }
}
fn read_byte_timeout() -> Option<u8> {
    set_raw(0, 1);
    let b = read_byte();
    set_raw(1, 0);
    b
}
fn read_key() -> Key {
    let b = match read_byte() { Some(b) => b, None => return Key::Other };
    match b {
        13 | 10 => return Key::Enter,
        3 => return Key::CtrlC,
        4 => return Key::CtrlD,
        17 => return Key::CtrlQ,
        1 => return Key::CtrlA,
        5 => return Key::CtrlE,
        21 => return Key::CtrlU,
        11 => return Key::CtrlK,
        23 => return Key::CtrlW,
        127 | 8 => return Key::Backspace,
        27 => {
            let b2 = match read_byte_timeout() { Some(b) => b, None => return Key::Esc };
            if b2 != b'[' && b2 != b'O' { return Key::Esc; }
            let b3 = match read_byte_timeout() { Some(b) => b, None => return Key::Esc };
            return match b3 {
                b'A' => Key::Up,
                b'B' => Key::Down,
                b'C' => Key::Right,
                b'D' => Key::Left,
                b'H' => Key::Home,
                b'F' => Key::End,
                b'3' => { let _ = read_byte_timeout(); Key::Del },
                _ => Key::Esc,
            };
        },
        0x80..=0xFF => {
            let need = if (0xC2..=0xDF).contains(&b) { 1 } else if (0xE0..=0xEF).contains(&b) { 2 } else if (0xF0..=0xF4).contains(&b) { 3 } else { 0 };
            let mut bytes = vec![b];
            for _ in 0..need { if let Some(nb) = read_byte_timeout() { bytes.push(nb); } }
            if let Ok(s) = std::str::from_utf8(&bytes) { if let Some(c) = s.chars().next() { return Key::Char(c); } }
            return Key::Other;
        },
        32..=126 => return Key::Char(b as char),
        _ => return Key::Other,
    }
}

fn term_size() -> (u16, u16) {
    let rows = env::var("LINES").ok().and_then(|v| v.parse().ok()).unwrap_or(24);
    let cols = env::var("COLUMNS").ok().and_then(|v| v.parse().ok()).unwrap_or(80);
    (rows.max(5), cols.max(20))
}

fn prompt_input(label: &str) -> Option<String> {
    let mut chars: Vec<char> = Vec::new();
    let mut cursor: usize = 0;
    let mut offset: usize = 0;
    let label_len = label.chars().count() + 1;
    loop {
        let (rows, cols) = term_size();
        let cols_us = cols as usize;
        let mut avail = cols_us.saturating_sub(label_len + 1);
        if avail < 10 { avail = 10; }
        if cursor < offset { offset = cursor; }
        if cursor >= offset + avail { offset = cursor - avail + 1; }
        let mut out = io::stdout();
        let _ = write!(out, "\x1b[{};1H\x1b[2KEnter=save  Esc / Ctrl-C=cancel", rows - 1);
        let _ = write!(out, "\x1b[{};1H\x1b[2K", rows);
        let _ = write!(out, "{} ", label);
        for i in offset..chars.len().min(offset + avail) { let _ = write!(out, "{}", chars[i]); }
        let cx = label_len + (cursor - offset) + 1;
        let cx = cx.min(cols_us);
        let _ = write!(out, "\x1b[{};{}H", rows, cx);
        let _ = out.flush();
        match read_key() {
            Key::Enter => break,
            Key::Esc | Key::CtrlC | Key::CtrlD => return None,
            Key::Backspace => { if cursor > 0 { chars.remove(cursor - 1); cursor -= 1; } },
            Key::Del => { if cursor < chars.len() { chars.remove(cursor); } },
            Key::Left => { if cursor > 0 { cursor -= 1; } },
            Key::Right => { if cursor < chars.len() { cursor += 1; } },
            Key::Home | Key::CtrlA => cursor = 0,
            Key::End | Key::CtrlE => cursor = chars.len(),
            Key::CtrlU => { chars.clear(); cursor = 0; offset = 0; },
            Key::CtrlK => { chars.truncate(cursor); },
            Key::CtrlW => {
                while cursor > 0 && chars[cursor - 1] == ' ' { chars.remove(cursor - 1); cursor -= 1; }
                while cursor > 0 && chars[cursor - 1] != ' ' { chars.remove(cursor - 1); cursor -= 1; }
            },
            Key::Up | Key::Down => {},
            Key::Char(c) => {
                if chars.len() < MAX_INPUT {
                    chars.insert(cursor, c);
                    cursor += 1;
                }
            },
            _ => {},
        }
    }
    let s: String = chars.iter().collect();
    Some(trim_s(&s))
}

fn run_tui(tasks: &mut Vec<Task>) {
    save_termios();
    set_raw(1, 0);
    let mut selected: usize = 0;
    let filters = vec!["all", "todo", "done", "overdue", "today"];
    let mut filter_idx: usize = 0;
    let mut search = String::new();
    let mut status = "Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter".to_string();
    loop {
        let (rows, cols) = term_size();
        let mode = filters[filter_idx];
        let visible = filtered_indices(tasks, mode, &search);
        if visible.is_empty() { selected = 0; } else {
            if selected >= visible.len() { selected = visible.len() - 1; }
        }
        let mut out = io::stdout();
        let _ = write!(out, "\x1b[2J\x1b[H");
        let _ = write!(out, "tasks - {} total | {} done | {} overdue | filter: {} | search: {}\n", tasks.len(), count_done(tasks), count_overdue(tasks), mode, search);
        let _ = write!(out, "#    []  P    Due         Text\n");
        let _ = write!(out, "{}\n", "-".repeat(cols.min(80) as usize));
        let max_rows = ((rows as i32) - 5).max(5) as usize;
        for (i, &idx) in visible.iter().take(max_rows).enumerate() {
            let t = &tasks[idx];
            let mut line = format!("{:<4} [{}] ", idx + 1, if t.done { "x" } else { " " });
            if !t.priority.is_empty() { line += &format!("({}) ", t.priority); }
            if !t.due.is_empty() { line += &format!("due:{} ", t.due); }
            line += &t.text;
            if line.len() > cols as usize { line.truncate(cols as usize); }
            if i == selected { let _ = write!(out, "\x1b[7m{}\x1b[0m\n", line); }
            else if t.done { let _ = write!(out, "\x1b[2m{}\x1b[0m\n", line); }
            else { let _ = write!(out, "{}\n", line); }
        }
        let _ = write!(out, "\x1b[{};1H\x1b[2K{}", rows - 1, status);
        let _ = write!(out, "\x1b[{};1H\x1b[2K", rows);
        let _ = write!(out, "q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats");
        let _ = write!(out, "\x1b[{};1H", rows);
        let _ = out.flush();
        match read_key() {
            Key::Esc | Key::CtrlC | Key::CtrlD | Key::CtrlQ => break,
            Key::Char('q') | Key::Char('Q') => break,
            Key::Down => { if selected + 1 < visible.len() { selected += 1; } },
            Key::Up => { if selected > 0 { selected -= 1; } },
            Key::Char('j') => { if selected + 1 < visible.len() { selected += 1; } },
            Key::Char('k') => { if selected > 0 { selected -= 1; } },
            Key::Char('g') => selected = 0,
            Key::Char('G') => { if !visible.is_empty() { selected = visible.len() - 1; } },
            Key::Char(' ') => {
                if !visible.is_empty() {
                    let idx = visible[selected];
                    tasks[idx].done = !tasks[idx].done;
                    save_tasks(tasks);
                    status = if tasks[idx].done { "Marked done".to_string() } else { "Marked todo".to_string() };
                }
            },
            Key::Char('a') => {
                if let Some(s) = prompt_input("Add:") {
                    if !s.is_empty() {
                        let nt = parse_add_text(&s);
                        tasks.push(nt.clone());
                        save_tasks(tasks);
                        selected = tasks.len() - 1;
                        status = format!("Added: {}", nt.text);
                    } else { status = "Add cancelled - press q or Esc to quit".to_string(); }
                } else { status = "Add cancelled - press q or Esc to quit".to_string(); }
            },
            Key::Char('e') => {
                if !visible.is_empty() {
                    let idx = visible[selected];
                    let old = tasks[idx].clone();
                    if let Some(s) = prompt_input(&format!("Edit [{}]:", old.text)) {
                        if !s.is_empty() {
                            let mut nt = parse_add_text(&s);
                            if nt.priority.is_empty() { nt.priority = old.priority.clone(); }
                            if nt.due.is_empty() { nt.due = old.due.clone(); }
                            nt.done = old.done;
                            tasks[idx] = nt;
                            save_tasks(tasks);
                            status = "Edited".to_string();
                        }
                    }
                }
            },
            Key::Char('d') => {
                if !visible.is_empty() {
                    let idx = visible[selected];
                    let removed = tasks[idx].text.clone();
                    tasks.remove(idx);
                    save_tasks(tasks);
                    status = format!("Deleted: {}", removed);
                    if selected >= visible.len().saturating_sub(1) && selected > 0 { selected -= 1; }
                }
            },
            Key::Char('/') => {
                if let Some(s) = prompt_input("Search:") {
                    search = s.clone();
                    selected = 0;
                    status = if !search.is_empty() { format!("Search: {}", search) } else { "Search cleared - press q or Esc to quit".to_string() };
                }
            },
            Key::Char('f') => {
                filter_idx = (filter_idx + 1) % filters.len();
                selected = 0;
                status = format!("Filter: {}", filters[filter_idx]);
            },
            Key::Char('u') => {
                if fs::metadata(BACKUP_FILE).is_ok() {
                    let _ = fs::copy(BACKUP_FILE, TASKS_FILE);
                    *tasks = load_tasks();
                    status = "Undone".to_string();
                } else { status = "No backup to undo".to_string(); }
            },
            Key::Char('c') => {
                let before = tasks.len();
                tasks.retain(|t| !t.done);
                save_tasks(tasks);
                status = format!("Cleared {} done", before - tasks.len());
                selected = 0;
            },
            Key::Char('s') => {
                let tot = tasks.len(); let dn = count_done(tasks); let ov = count_overdue(tasks);
                status = format!("Total {} - Done {} - Todo {} - Overdue {}", tot, dn, tot - dn, ov);
            },
            Key::Char('?') => {
                status = "Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats".to_string();
            },
            _ => {},
        }
    }
    restore_termios();
    println!();
}

fn print_help() {
    println!("Usage:");
    println!("  tasks tui                    Interactive TUI (default, no args = tui)");
    println!("  tasks add [--priority P1] [--due YYYY-MM-DD] <text>");
    println!("  tasks list [--tag X] [--project Y] [--priority P1] [--search Q] [--overdue|--today|--done|--todo]");
    println!("  tasks done <n>");
    println!("  tasks undone <n>");
    println!("  tasks rm <n>");
    println!("  tasks edit <n> <new text>");
    println!("  tasks search <query>");
    println!("  tasks clear");
    println!("  tasks stats");
    println!("  tasks undo");
    println!("  tasks help");
    println!();
    println!("Format: tasks.md lines are - [ ] (P1) due:2026-11-30 Buy milk #home +groceries");
    println!("Tags start with #, projects with +. Priority P1/P2/P3, due YYYY-MM-DD.");
    println!("TUI keys: j/k or arrows move, Space toggle, a add, e edit, d delete,");
    println!("  / search, f filter, u undo, c clear done, s stats, q / Esc / Ctrl-C to quit");
    println!("  In a prompt: Enter saves, Esc / Ctrl-C cancels");
}

fn main() {
    let mut tasks = load_tasks();
    let args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() || args[0] == "tui" {
        run_tui(&mut tasks);
        println!("Exited TUI - back to shell. Use: ./tasks list");
        return;
    }
    let cmd = args[0].clone();
    match cmd.as_str() {
        "help" | "--help" | "-h" => print_help(),
        "add" => {
            let mut priority = String::new();
            let mut due = String::new();
            let mut parts: Vec<String> = Vec::new();
            let mut i = 1;
            while i < args.len() {
                if args[i] == "--priority" && i + 1 < args.len() { priority = args[i + 1].clone(); i += 2; continue; }
                if args[i] == "--due" && i + 1 < args.len() { due = args[i + 1].clone(); i += 2; continue; }
                parts.push(args[i].clone()); i += 1;
            }
            let buf = parts.join(" ");
            if trim_s(&buf).is_empty() { println!("Usage: tasks add <text>"); return; }
            let mut t = parse_add_text(&buf);
            if !priority.is_empty() { t.priority = priority; }
            if !due.is_empty() { t.due = due; }
            tasks.push(t.clone());
            save_tasks(&tasks);
            println!("Added: {}", t.text);
        },
        "list" => cli_list(&tasks, &args[1..]),
        "done" => {
            if args.len() < 2 { println!("Usage: tasks done <n>"); return; }
            match parse_task_number(&args[1], tasks.len()) {
                Some(idx) => { tasks[idx].done = true; save_tasks(&tasks); println!("Done: {}", tasks[idx].text); },
                None => println!("Invalid task number"),
            }
        },
        "undone" => {
            if args.len() < 2 { println!("Usage: tasks undone <n>"); return; }
            match parse_task_number(&args[1], tasks.len()) {
                Some(idx) => { tasks[idx].done = false; save_tasks(&tasks); println!("Todo: {}", tasks[idx].text); },
                None => println!("Invalid task number"),
            }
        },
        "rm" => {
            if args.len() < 2 { println!("Usage: tasks rm <n>"); return; }
            match parse_task_number(&args[1], tasks.len()) {
                Some(idx) => { let removed = tasks[idx].text.clone(); tasks.remove(idx); save_tasks(&tasks); println!("Deleted: {}", removed); },
                None => println!("Invalid task number"),
            }
        },
        "edit" => {
            if args.len() < 3 { println!("Usage: tasks edit <n> <new text>"); return; }
            match parse_task_number(&args[1], tasks.len()) {
                Some(idx) => {
                    let mut nt = parse_add_text(&args[2..].join(" "));
                    let old = tasks[idx].clone();
                    if nt.priority.is_empty() { nt.priority = old.priority; }
                    if nt.due.is_empty() { nt.due = old.due; }
                    nt.done = old.done;
                    tasks[idx] = nt.clone();
                    save_tasks(&tasks);
                    println!("Edited {}: {}", idx + 1, nt.text);
                },
                None => println!("Invalid task number"),
            }
        },
        "search" => {
            if args.len() < 2 { println!("Usage: tasks search <query>"); return; }
            let q = args[1..].join(" ");
            let mut found = false;
            for (i, t) in tasks.iter().enumerate() {
                if matches_search(t, &q) { print_task(i, t); found = true; }
            }
            if !found { println!("No matches."); }
        },
        "clear" => {
            let before = tasks.len();
            tasks.retain(|t| !t.done);
            save_tasks(&tasks);
            println!("Cleared {} done tasks", before - tasks.len());
        },
        "stats" => {
            let total = tasks.len(); let done_n = count_done(&tasks); let over_n = count_overdue(&tasks);
            let today_n = tasks.iter().filter(|t| !t.done && is_today(t)).count();
            println!("Total: {}\nDone: {}\nTodo: {}\nOverdue: {}\nDue today: {}", total, done_n, total - done_n, over_n, today_n);
            let c1 = tasks.iter().filter(|t| t.priority == "P1").count();
            let c2 = tasks.iter().filter(|t| t.priority == "P2").count();
            let c3 = tasks.iter().filter(|t| t.priority == "P3").count();
            if c1 > 0 || c2 > 0 || c3 > 0 {
                println!("By priority:");
                if c1 > 0 { println!("  P1: {}", c1); }
                if c2 > 0 { println!("  P2: {}", c2); }
                if c3 > 0 { println!("  P3: {}", c3); }
            }
            let mut tag_counts: Vec<(String, usize)> = Vec::new();
            for t in &tasks {
                for tok in t.text.split_whitespace() {
                    if tok.len() > 1 && tok.starts_with('#') {
                        if let Some(e) = tag_counts.iter_mut().find(|(k, _)| *k == tok) { e.1 += 1; } else { tag_counts.push((tok.to_string(), 1)); }
                    }
                }
            }
            if !tag_counts.is_empty() {
                println!("By tag:");
                tag_counts.sort();
                for (k, v) in tag_counts { println!("  {}: {}", k, v); }
            }
        },
        "undo" => {
            if fs::metadata(BACKUP_FILE).is_err() { println!("No backup to undo"); return; }
            let _ = fs::copy(BACKUP_FILE, TASKS_FILE);
            println!("Undone - restored from backup");
        },
        _ => { println!("Unknown command: {}", cmd); print_help(); },
    }
}
