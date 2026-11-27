// tasks.rs - Todo CLI v2 (Rust, std only, no crates)
// Same spec + same tasks.md as Python / C / C++ / Go / Zig / TypeScript / JavaScript / C# v2.
// Build: rustc -O -o tasks tasks.rs
//    or: cargo init (then copy this to src/main.rs) && cargo build --release
// Run: ./tasks  |  ./tasks list  |  ./tasks add "Buy milk #home"

use std::env;
use std::fs;
use std::io::{self, Read, Write};
use std::process::Command;
use std::sync::mpsc::{channel, Receiver, RecvTimeoutError};
use std::thread;
use std::time::Duration;

const TASKS_FILE: &str = "tasks.md";
const BACKUP_FILE: &str = "tasks.md.bak";
const MAX_INPUT: usize = 4096;

#[derive(Clone, Debug)]
struct Task {
    done: bool,
    priority: String, // "P1", "P2", "P3" or ""
    due: String,      // "YYYY-MM-DD" or ""
    text: String,
}

static mut TASKS: Vec<Task> = Vec::new();

// SAFETY: single-threaded CLI, TUI runs on main thread only.
// We use a global for simplicity, matching the C/C++ versions.
fn tasks() -> &'static mut Vec<Task> {
    unsafe { &mut *(&raw mut TASKS) }
}

// ---------- helpers ----------
fn trim(s: &str) -> &str {
    s.trim()
}

fn collapse_spaces(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn today_str() -> String {
    // Use system `date` so local timezone is correct without chrono.
    if let Ok(out) = Command::new("date").arg("+%Y-%m-%d").output() {
        let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if s.len() == 10 {
            return s;
        }
    }
    // Fallback: UTC from SystemTime (days since epoch -> civil date)
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let days = (secs / 86400) as i64;
    civil_from_days(days)
}

fn civil_from_days(z: i64) -> String {
    // Howard Hinnant's civil_from_days, shifted to 1970-01-01.
    let z = z + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!("{:04}-{:02}-{:02}", y, m, d)
}

fn is_overdue(t: &Task) -> bool {
    !t.due.is_empty() && t.due < today_str()
}
fn is_today(t: &Task) -> bool {
    !t.due.is_empty() && t.due == today_str()
}

// ---------- parsing / formatting ----------
fn parse_line(line: &str) -> Option<Task> {
    if !line.starts_with("- [") {
        return None;
    }
    if line.len() < 5 {
        return None;
    }
    let mark = line.chars().nth(3)?;
    if mark != ' ' && mark != 'x' {
        return None;
    }
    if line.chars().nth(4)? != ']' {
        return None;
    }
    let mut t = Task {
        done: mark == 'x',
        priority: String::new(),
        due: String::new(),
        text: String::new(),
    };
    let mut rest = trim(&line[5..]).to_string();
    if rest.starts_with("(P1)") || rest.starts_with("(P2)") || rest.starts_with("(P3)") {
        t.priority = rest[1..3].to_string();
        rest = trim(&rest[4..]).to_string();
    }
    if rest.starts_with("due:") && rest.len() >= 14 {
        let d = &rest[4..14];
        if d.len() == 10 && d.as_bytes()[4] == b'-' && d.as_bytes()[7] == b'-' {
            t.due = d.to_string();
            rest = trim(&rest[14..]).to_string();
        }
    }
    t.text = trim(&rest).to_string();
    Some(t)
}

fn format_task(t: &Task) -> String {
    let mut s = String::new();
    s.push_str("- [");
    s.push(if t.done { 'x' } else { ' ' });
    s.push(']');
    if !t.priority.is_empty() {
        s.push_str(&format!(" ({})", t.priority));
    }
    if !t.due.is_empty() {
        s.push_str(&format!(" due:{}", t.due));
    }
    s.push(' ');
    s.push_str(&t.text);
    s
}

fn load_tasks() {
    tasks().clear();
    let Ok(content) = fs::read_to_string(TASKS_FILE) else {
        return;
    };
    for raw in content.lines() {
        let line = raw.trim_end_matches('\r');
        if trim(line).is_empty() {
            continue;
        }
        if let Some(t) = parse_line(line) {
            tasks().push(t);
        }
    }
}

fn copy_file(src: &str, dst: &str) -> bool {
    fs::copy(src, dst).is_ok()
}

fn save_tasks() {
    if fs::metadata(TASKS_FILE).is_ok() {
        copy_file(TASKS_FILE, BACKUP_FILE);
    }
    let out = tasks()
        .iter()
        .map(|t| format_task(t))
        .collect::<Vec<_>>()
        .join("\n");
    let _ = fs::write(TASKS_FILE, if out.is_empty() { String::new() } else { out + "\n" });
}

fn parse_add_text(full: &str) -> Task {
    let mut t = Task {
        done: false,
        priority: String::new(),
        due: String::new(),
        text: String::new(),
    };
    let mut text = trim(full).to_string();
    if text.starts_with("P1 ") || text.starts_with("P2 ") || text.starts_with("P3 ") {
        t.priority = text[..2].to_string();
        text = trim(&text[3..]).to_string();
    } else if text.starts_with("(P1)") || text.starts_with("(P2)") || text.starts_with("(P3)") {
        t.priority = text[1..3].to_string();
        text = trim(&text[4..]).to_string();
    }
    if let Some(pos) = text.find("due:") {
        if text.len() >= pos + 14 {
            let cand = &text[pos + 4..pos + 14];
            if cand.len() == 10 && cand.as_bytes()[4] == b'-' && cand.as_bytes()[7] == b'-' {
                t.due = cand.to_string();
                let before = trim(&text[..pos]).to_string();
                let after = trim(&text[pos + 14..]).to_string();
                text = trim(&format!("{} {}", before, after)).to_string();
            }
        }
    }
    t.text = collapse_spaces(&text);
    t
}

fn parse_task_number(s: &str, n: usize) -> Option<usize> {
    let v: i64 = trim(s).parse().ok()?;
    if v < 1 || (v as usize) > n {
        return None;
    }
    Some((v - 1) as usize)
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
    if q.is_empty() {
        return true;
    }
    t.text.to_lowercase().contains(&q.to_lowercase())
}

fn filtered_indices(mode: &str, search: &str) -> Vec<usize> {
    let mut out = Vec::new();
    for (i, t) in tasks().iter().enumerate() {
        if !matches_mode(t, mode) {
            continue;
        }
        if !matches_search(t, search) {
            continue;
        }
        out.push(i);
    }
    out
}

fn count_done() -> usize {
    tasks().iter().filter(|t| t.done).count()
}
fn count_overdue() -> usize {
    tasks().iter().filter(|t| !t.done && is_overdue(t)).count()
}

fn has_tag(t: &Task, tag: &str) -> bool {
    let want = tag.strip_prefix('#').unwrap_or(tag);
    for tok in t.text.split_whitespace() {
        if tok.len() > 1 && tok.starts_with('#') {
            if tok == tag || &tok[1..] == want {
                return true;
            }
        }
    }
    false
}

fn has_project(t: &Task, proj: &str) -> bool {
    let want = proj.strip_prefix('+').unwrap_or(proj);
    for tok in t.text.split_whitespace() {
        if tok.len() > 1 && tok.starts_with('+') {
            if tok == proj || &tok[1..] == want {
                return true;
            }
        }
    }
    false
}

fn print_task(idx: usize, t: &Task) {
    let mark = if t.done { 'x' } else { ' ' };
    let mut s = format!("{}. [{}] ", idx + 1, mark);
    if !t.priority.is_empty() {
        s.push_str(&format!("{} ", t.priority));
    }
    if !t.due.is_empty() {
        s.push_str(&format!("{} ", t.due));
    }
    s.push_str(&t.text);
    println!("{}", s);
}

fn cli_list(args: &[String]) {
    let mut tag = String::new();
    let mut project = String::new();
    let mut priority = String::new();
    let mut search = String::new();
    let mut mode = "all".to_string();
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if a == "--tag" && i + 1 < args.len() {
            tag = args[i + 1].clone();
            i += 2;
            continue;
        }
        if a == "--project" && i + 1 < args.len() {
            project = args[i + 1].clone();
            i += 2;
            continue;
        }
        if a == "--priority" && i + 1 < args.len() {
            priority = args[i + 1].clone();
            i += 2;
            continue;
        }
        if a == "--search" && i + 1 < args.len() {
            search = args[i + 1].clone();
            i += 2;
            continue;
        }
        if a == "--overdue" {
            mode = "overdue".to_string();
        } else if a == "--today" {
            mode = "today".to_string();
        } else if a == "--done" {
            mode = "done".to_string();
        } else if a == "--todo" {
            mode = "todo".to_string();
        }
        i += 1;
    }
    let mut shown = 0;
    for idx in filtered_indices(&mode, &search) {
        let t = tasks()[idx].clone();
        if !tag.is_empty() && !has_tag(&t, &tag) {
            continue;
        }
        if !project.is_empty() && !has_project(&t, &project) {
            continue;
        }
        if !priority.is_empty() && t.priority != priority {
            continue;
        }
        print_task(idx, &t);
        shown += 1;
    }
    if shown == 0 {
        println!("No tasks.");
    }
}

// [STRIPPED 77 bytes] TUI - AUDITED FIXES (same as C / C++ / JS / C# / Python / Go / Zig / TS)
// 1. Prompt has NO small char limit: reads bytes one-by-one in raw mode into
//    a growing String, 4096 cap, horizontal scroll. No fixed [64]/[256]
//    buffer, no line-based read with width truncation.
// 2. Exit is explicit: q, Q, Esc, Ctrl-C, Ctrl-D, Ctrl-Q all quit from
//    main list, footer always shows "q / Esc / Ctrl-C to quit". In a
//    prompt, Enter saves, Esc / Ctrl-C cancels back to list.
//    Raw mode is via `stty` (std only, no crates): original settings saved
//    with `stty -g` and restored on exit, so the terminal is not left broken.
// [STRIPPED 75 bytes]

fn get_term_size() -> (usize, usize) {
    // `stty size` prints "rows cols"
    if let Ok(out) = Command::new("stty").arg("size").output() {
        let s = String::from_utf8_lossy(&out.stdout);
        let parts: Vec<&str> = s.split_whitespace().collect();
        if parts.len() == 2 {
            if let (Ok(r), Ok(c)) = (parts[0].parse::<usize>(), parts[1].parse::<usize>()) {
                if r > 0 && c > 0 {
                    return (r, c);
                }
            }
        }
    }
    if let (Ok(r), Ok(c)) = (env::var("LINES"), env::var("COLUMNS")) {
        if let (Ok(r), Ok(c)) = (r.parse::<usize>(), c.parse::<usize>()) {
            if r > 0 && c > 0 {
                return (r, c);
            }
        }
    }
    (24, 80)
}

fn stty_get() -> String {
    Command::new("stty")
        .arg("-g")
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default()
}

fn stty_set(args: &[&str]) {
    let _ = Command::new("stty").args(args).output();
}

fn enable_raw() -> String {
    let orig = stty_get();
    // raw, no echo, no signals (so Ctrl-C arrives as byte 3, not SIGINT)
    stty_set(&["raw", "-echo", "-isig"]);
    orig
}

fn disable_raw(orig: &str) {
    if !orig.is_empty() {
        stty_set(&[orig]);
    } else {
        stty_set(&["sane"]);
    }
    println!();
}

// Byte reader: background thread pushes stdin bytes into a channel,
// so read_byte_timeout() can wait 30ms for Esc sequences.
struct ByteReader {
    rx: Receiver<u8>,
}

impl ByteReader {
    fn new() -> Self {
        let (tx, rx) = channel::<u8>();
        thread::spawn(move || {
            let stdin = io::stdin();
            let mut lock = stdin.lock();
            let mut buf = [0u8; 1];
            loop {
                match lock.read(&mut buf) {
                    Ok(0) => break, // EOF
                    Ok(_) => {
                        if tx.send(buf[0]).is_err() {
                            break;
                        }
                    }
                    Err(_) => break,
                }
            }
        });
        ByteReader { rx }
    }
    fn read_byte(&self) -> Option<u8> {
        self.rx.recv().ok()
    }
    fn read_byte_timeout(&self, ms: u64) -> Option<u8> {
        match self.rx.recv_timeout(Duration::from_millis(ms)) {
            Ok(b) => Some(b),
            Err(RecvTimeoutError::Timeout) => None,
            Err(_) => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
enum Key {
    Char(char),
    Esc,
    Up,
    Down,
    Left,
    Right,
    Home,
    End,
    Del,
    Enter,
    Backspace,
    CtrlC,
    CtrlD,
    CtrlQ,
    CtrlA,
    CtrlE,
    CtrlU,
    CtrlK,
    CtrlW,
    Other(u8),
}

fn decode_utf8_char(first: u8, reader: &ByteReader) -> char {
    if first < 0x80 {
        return first as char;
    }
    let need = if (0xC2..=0xDF).contains(&first) {
        1
    } else if (0xE0..=0xEF).contains(&first) {
        2
    } else if (0xF0..=0xF4).contains(&first) {
        3
    } else {
        return '\u{FFFD}';
    };
    let mut bytes = vec![first];
    for _ in 0..need {
        if let Some(b) = reader.read_byte_timeout(30) {
            bytes.push(b);
        } else {
            break;
        }
    }
    String::from_utf8_lossy(&bytes).chars().next().unwrap_or('\u{FFFD}')
}

fn read_key(reader: &ByteReader) -> Key {
    let Some(b) = reader.read_byte() else {
        return Key::Other(0);
    };
    if b == 13 || b == 10 {
        return Key::Enter;
    }
    if b == 3 {
        return Key::CtrlC;
    }
    if b == 4 {
        return Key::CtrlD;
    }
    if b == 17 {
        return Key::CtrlQ;
    }
    if b == 1 {
        return Key::CtrlA;
    }
    if b == 5 {
        return Key::CtrlE;
    }
    if b == 21 {
        return Key::CtrlU;
    }
    if b == 11 {
        return Key::CtrlK;
    }
    if b == 23 {
        return Key::CtrlW;
    }
    if b == 127 || b == 8 {
        return Key::Backspace;
    }
    if b == 27 {
        // Esc - could be Esc alone or arrow sequence. Wait 30ms.
        let Some(b2) = reader.read_byte_timeout(30) else {
            return Key::Esc;
        };
        if b2 != b'[' && b2 != b'O' {
            return Key::Esc;
        }
        let Some(b3) = reader.read_byte_timeout(30) else {
            return Key::Esc;
        };
        match b3 {
            b'A' => return Key::Up,
            b'B' => return Key::Down,
            b'C' => return Key::Right,
            b'D' => return Key::Left,
            b'H' => return Key::Home,
            b'F' => return Key::End,
            b'3' => {
                let _ = reader.read_byte_timeout(30); // consume ~
                return Key::Del;
            }
            _ => return Key::Esc,
        }
    }
    if b >= 0x80 {
        let c = decode_utf8_char(b, reader);
        return Key::Char(c);
    }
    if b >= 32 {
        return Key::Char(b as char);
    }
    Key::Other(b)
}

// prompt_input: returns Some(trimmed) or None if cancelled.
// Dynamic String, no small limit, 4096 cap, horizontal scroll.
fn prompt_input(reader: &ByteReader, label: &str) -> Option<String> {
    let mut text = String::new();
    let mut cursor: usize = 0; // char index
    let mut offset: usize = 0;
    let label_len = label.chars().count() + 1; // label + space
    loop {
        let (rows, cols) = get_term_size();
        let mut avail = cols.saturating_sub(label_len + 1);
        if avail < 10 {
            avail = 10;
        }
        if cursor < offset {
            offset = cursor;
        }
        if cursor >= offset + avail {
            offset = cursor - avail + 1;
        }
        print!("\x1b[{};1H\x1b[2KEnter=save  Esc / Ctrl-C=cancel", rows - 1);
        print!("\x1b[{};1H\x1b[2K", rows);
        print!("{} ", label);
        let chars: Vec<char> = text.chars().collect();
        let end = usize::min(offset + avail, chars.len());
        if offset < chars.len() {
            let slice: String = chars[offset..end].iter().collect();
            print!("{}", slice);
        }
        let mut cursor_x = label_len + (cursor - offset) + 1;
        if cursor_x > cols {
            cursor_x = cols;
        }
        print!("\x1b[{};{}H", rows, cursor_x);
        let _ = io::stdout().flush();
        match read_key(reader) {
            Key::Enter => break,
            Key::Esc | Key::CtrlC | Key::CtrlD => return None,
            Key::Backspace => {
                if cursor > 0 {
                    let mut v: Vec<char> = text.chars().collect();
                    v.remove(cursor - 1);
                    text = v.into_iter().collect();
                    cursor -= 1;
                }
            }
            Key::Del => {
                if cursor < text.chars().count() {
                    let mut v: Vec<char> = text.chars().collect();
                    v.remove(cursor);
                    text = v.into_iter().collect();
                }
            }
            Key::Left => {
                if cursor > 0 {
                    cursor -= 1;
                }
            }
            Key::Right => {
                if cursor < text.chars().count() {
                    cursor += 1;
                }
            }
            Key::Home | Key::CtrlA => cursor = 0,
            Key::End | Key::CtrlE => cursor = text.chars().count(),
            Key::CtrlU => {
                text.clear();
                cursor = 0;
                offset = 0;
            }
            Key::CtrlK => {
                let v: Vec<char> = text.chars().collect();
                text = v[..cursor].iter().collect();
            }
            Key::CtrlW => {
                let mut v: Vec<char> = text.chars().collect();
                while cursor > 0 && v[cursor - 1] == ' ' {
                    v.remove(cursor - 1);
                    cursor -= 1;
                }
                while cursor > 0 && v[cursor - 1] != ' ' {
                    v.remove(cursor - 1);
                    cursor -= 1;
                }
                text = v.into_iter().collect();
            }
            Key::Up | Key::Down => {}
            Key::Char(c) => {
                if text.chars().count() < MAX_INPUT {
                    let mut v: Vec<char> = text.chars().collect();
                    v.insert(cursor, c);
                    text = v.into_iter().collect();
                    cursor += 1;
                }
            }
            _ => {}
        }
    }
    Some(trim(&text).to_string())
}

fn run_tui() {
    let orig = enable_raw();
    let reader = ByteReader::new();
    let mut selected: usize = 0;
    let filters = ["all", "todo", "done", "overdue", "today"];
    let mut filter_idx: usize = 0;
    let mut search = String::new();
    let mut status = "Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter".to_string();
    loop {
        let (rows, cols) = get_term_size();
        let filter_mode = filters[filter_idx];
        let visible = filtered_indices(filter_mode, &search);
        if visible.is_empty() {
            selected = 0;
        } else {
            if selected >= visible.len() {
                selected = visible.len() - 1;
            }
        }
        print!("\x1b[2J\x1b[H");
        let total = tasks().len();
        let done_n = count_done();
        let overdue_n = count_overdue();
        println!(
            "tasks - {} total | {} done | {} overdue | filter: {} | search: {}",
            total, done_n, overdue_n, filter_mode, search
        );
        println!("#    []  P    Due         Text");
        println!("{}", "-".repeat(usize::min(80, cols)));
        let max_rows = if rows > 5 { rows - 5 } else { 5 };
        for (i, &idx) in visible.iter().enumerate().take(max_rows) {
            let t = tasks()[idx].clone();
            let mark = if t.done { 'x' } else { ' ' };
            let mut line = format!("{:<4} [{}] ", idx + 1, mark);
            if !t.priority.is_empty() {
                line.push_str(&format!("({}) ", t.priority));
            }
            if !t.due.is_empty() {
                line.push_str(&format!("due:{} ", t.due));
            }
            line.push_str(&t.text);
            if line.chars().count() > cols {
                line = line.chars().take(cols).collect();
            }
            if i == selected {
                println!("\x1b[7m{}\x1b[0m", line);
            } else if t.done {
                println!("\x1b[2m{}\x1b[0m", line);
            } else {
                println!("{}", line);
            }
        }
        print!("\x1b[{};1H\x1b[2K{}", rows - 1, status);
        print!("\x1b[{};1H\x1b[2K", rows);
        print!("q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats");
        print!("\x1b[{};1H", rows);
        let _ = io::stdout().flush();
        let k = read_key(&reader);
        // EXIT - checked FIRST, from main list view
        match k {
            Key::Esc | Key::CtrlC | Key::CtrlD | Key::CtrlQ => break,
            Key::Char('q') | Key::Char('Q') => break,
            _ => {}
        }
        match k {
            Key::Char('j') | Key::Down => {
                if selected + 1 < visible.len() {
                    selected += 1;
                }
            }
            Key::Char('k') | Key::Up => {
                if selected > 0 {
                    selected -= 1;
                }
            }
            Key::Char('g') => selected = 0,
            Key::Char('G') => {
                if !visible.is_empty() {
                    selected = visible.len() - 1;
                }
            }
            Key::Char(' ') => {
                if !visible.is_empty() {
                    let idx = visible[selected];
                    tasks()[idx].done = !tasks()[idx].done;
                    let done = tasks()[idx].done;
                    save_tasks();
                    status = if done { "Marked done".to_string() } else { "Marked todo".to_string() };
                }
            }
            Key::Char('a') => {
                if let Some(s) = prompt_input(&reader, "Add:") {
                    if !s.is_empty() {
                        let nt = parse_add_text(&s);
                        tasks().push(nt.clone());
                        save_tasks();
                        selected = tasks().len() - 1;
                        status = format!("Added: {}", nt.text);
                    } else {
                        status = "Add cancelled - press q or Esc to quit".to_string();
                    }
                } else {
                    status = "Add cancelled - press q or Esc to quit".to_string();
                }
            }
            Key::Char('e') => {
                if !visible.is_empty() {
                    let idx = visible[selected];
                    let old = tasks()[idx].clone();
                    let label = format!("Edit [{}]:", old.text);
                    if let Some(s) = prompt_input(&reader, &label) {
                        if !s.is_empty() {
                            let mut nt = parse_add_text(&s);
                            if nt.priority.is_empty() {
                                nt.priority = old.priority.clone();
                            }
                            if nt.due.is_empty() {
                                nt.due = old.due.clone();
                            }
                            nt.done = old.done;
                            tasks()[idx] = nt;
                            save_tasks();
                            status = "Edited".to_string();
                        }
                    }
                }
            }
            Key::Char('d') => {
                if !visible.is_empty() {
                    let idx = visible[selected];
                    let removed = tasks()[idx].text.clone();
                    tasks().remove(idx);
                    save_tasks();
                    status = format!("Deleted: {}", removed);
                    if selected >= visible.len().saturating_sub(1) && selected > 0 {
                        selected -= 1;
                    }
                }
            }
            Key::Char('/') => {
                if let Some(s) = prompt_input(&reader, "Search:") {
                    search = s.clone();
                    selected = 0;
                    status = if !search.is_empty() {
                        format!("Search: {}", search)
                    } else {
                        "Search cleared - press q or Esc to quit".to_string()
                    };
                }
            }
            Key::Char('f') => {
                filter_idx = (filter_idx + 1) % filters.len();
                selected = 0;
                status = format!("Filter: {}", filters[filter_idx]);
            }
            Key::Char('u') => {
                if fs::metadata(BACKUP_FILE).is_ok() {
                    copy_file(BACKUP_FILE, TASKS_FILE);
                    load_tasks();
                    status = "Undone".to_string();
                } else {
                    status = "No backup to undo".to_string();
                }
            }
            Key::Char('c') => {
                let before = tasks().len();
                tasks().retain(|t| !t.done);
                save_tasks();
                status = format!("Cleared {} done", before - tasks().len());
                selected = 0;
            }
            Key::Char('s') => {
                let total2 = tasks().len();
                let done_n2 = count_done();
                let overdue_n2 = count_overdue();
                status = format!(
                    "Total {} - Done {} - Todo {} - Overdue {}",
                    total2,
                    done_n2,
                    total2 - done_n2,
                    overdue_n2
                );
            }
            Key::Char('?') => {
                status = "Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats".to_string();
            }
            _ => {}
        }
    }
    disable_raw(&orig);
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
    load_tasks();
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 || args[1] == "tui" {
        run_tui();
        println!("Exited TUI - back to shell. Use: ./tasks list");
        return;
    }

    let cmd = args[1].as_str();

    if cmd == "help" || cmd == "--help" || cmd == "-h" {
        print_help();
        return;
    }

    if cmd == "add" {
        let mut priority = String::new();
        let mut due = String::new();
        let mut parts: Vec<String> = Vec::new();
        let mut i = 2;
        while i < args.len() {
            if args[i] == "--priority" && i + 1 < args.len() {
                priority = args[i + 1].clone();
                i += 2;
                continue;
            }
            if args[i] == "--due" && i + 1 < args.len() {
                due = args[i + 1].clone();
                i += 2;
                continue;
            }
            parts.push(args[i].clone());
            i += 1;
        }
        let buf = parts.join(" ");
        if trim(&buf).is_empty() {
            println!("Usage: tasks add <text>");
            return;
        }
        let mut t = parse_add_text(&buf);
        if !priority.is_empty() {
            t.priority = priority;
        }
        if !due.is_empty() {
            t.due = due;
        }
        let text = t.text.clone();
        tasks().push(t);
        save_tasks();
        println!("Added: {}", text);
        return;
    }

    if cmd == "list" {
        cli_list(&args[2..]);
        return;
    }

    if cmd == "done" {
        if args.len() < 3 {
            println!("Usage: tasks done <n>");
            return;
        }
        let Some(idx) = parse_task_number(&args[2], tasks().len()) else {
            println!("Invalid task number");
            return;
        };
        tasks()[idx].done = true;
        let text = tasks()[idx].text.clone();
        save_tasks();
        println!("Done: {}", text);
        return;
    }

    if cmd == "undone" {
        if args.len() < 3 {
            println!("Usage: tasks undone <n>");
            return;
        }
        let Some(idx) = parse_task_number(&args[2], tasks().len()) else {
            println!("Invalid task number");
            return;
        };
        tasks()[idx].done = false;
        let text = tasks()[idx].text.clone();
        save_tasks();
        println!("Todo: {}", text);
        return;
    }

    if cmd == "rm" {
        if args.len() < 3 {
            println!("Usage: tasks rm <n>");
            return;
        }
        let Some(idx) = parse_task_number(&args[2], tasks().len()) else {
            println!("Invalid task number");
            return;
        };
        let removed = tasks()[idx].text.clone();
        tasks().remove(idx);
        save_tasks();
        println!("Deleted: {}", removed);
        return;
    }

    if cmd == "edit" {
        if args.len() < 4 {
            println!("Usage: tasks edit <n> <new text>");
            return;
        }
        let Some(idx) = parse_task_number(&args[2], tasks().len()) else {
            println!("Invalid task number");
            return;
        };
        let mut nt = parse_add_text(&args[3..].join(" "));
        let old = tasks()[idx].clone();
        if nt.priority.is_empty() {
            nt.priority = old.priority;
        }
        if nt.due.is_empty() {
            nt.due = old.due;
        }
        nt.done = old.done;
        let text = nt.text.clone();
        tasks()[idx] = nt;
        save_tasks();
        println!("Edited {}: {}", idx + 1, text);
        return;
    }

    if cmd == "search" {
        if args.len() < 3 {
            println!("Usage: tasks search <query>");
            return;
        }
        let q = args[2..].join(" ");
        let mut found = false;
        for i in 0..tasks().len() {
            if matches_search(&tasks()[i].clone(), &q) {
                let t = tasks()[i].clone();
                print_task(i, &t);
                found = true;
            }
        }
        if !found {
            println!("No matches.");
        }
        return;
    }

    if cmd == "clear" {
        let before = tasks().len();
        tasks().retain(|t| !t.done);
        save_tasks();
        println!("Cleared {} done tasks", before - tasks().len());
        return;
    }

    if cmd == "stats" {
        let total = tasks().len();
        let done_n = count_done();
        let overdue_n = count_overdue();
        let today_n = tasks().iter().filter(|t| !t.done && is_today(t)).count();
        println!("Total: {}\nDone: {}\nTodo: {}\nOverdue: {}\nDue today: {}", total, done_n, total - done_n, overdue_n, today_n);
        let c1 = tasks().iter().filter(|t| t.priority == "P1").count();
        let c2 = tasks().iter().filter(|t| t.priority == "P2").count();
        let c3 = tasks().iter().filter(|t| t.priority == "P3").count();
        if c1 > 0 || c2 > 0 || c3 > 0 {
            println!("By priority:");
            if c1 > 0 {
                println!("  P1: {}", c1);
            }
            if c2 > 0 {
                println!("  P2: {}", c2);
            }
            if c3 > 0 {
                println!("  P3: {}", c3);
            }
        }
        let mut tag_counts: Vec<(String, usize)> = Vec::new();
        for t in tasks().iter() {
            for tok in t.text.split_whitespace() {
                if tok.len() > 1 && tok.starts_with('#') {
                    if let Some(entry) = tag_counts.iter_mut().find(|(k, _)| k == tok) {
                        entry.1 += 1;
                    } else {
                        tag_counts.push((tok.to_string(), 1));
                    }
                }
            }
        }
        if !tag_counts.is_empty() {
            tag_counts.sort();
            println!("By tag:");
            for (k, v) in tag_counts {
                println!("  {}: {}", k, v);
            }
        }
        return;
    }

    if cmd == "undo" {
        if fs::metadata(BACKUP_FILE).is_err() {
            println!("No backup to undo");
            return;
        }
        copy_file(BACKUP_FILE, TASKS_FILE);
        println!("Undone - restored from backup");
        return;
    }

    println!("Unknown command: {}", cmd);
    print_help();
}
