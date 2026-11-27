const std = @import("std");

const alloc = std.heap.page_allocator;
const TASKS_FILE = "tasks.md";
const BACKUP_FILE = "tasks.md.bak";

const Task = struct {
    done: bool,
    priority: []const u8,
    due: []const u8,
    text: []const u8,
};

fn dup(s: []const u8) []const u8 {
    return alloc.dupe(u8, s) catch "";
}

fn todayStr() []const u8 {
    const ts = std.time.timestamp();
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(ts) };
    const day = epoch.getEpochDay();
    const ymd = day.calculateYearMonthDay();
    return std.fmt.allocPrint(alloc, "{d:0>4}-{d:0>2}-{d:0>2}", .{ ymd.year, ymd.month, ymd.day }) catch "";
}

fn isOverdue(t: Task) bool {
    if (t.due.len == 0) return false;
    return std.mem.order(u8, t.due, todayStr()) == .lt;
}

fn isToday(t: Task) bool {
    if (t.due.len == 0) return false;
    return std.mem.eql(u8, t.due, todayStr());
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn parseLine(line: []const u8) ?Task {
    if (!std.mem.startsWith(u8, line, "- [")) return null;
    if (line.len < 5) return null;
    const done = line[3] == 'x';
    var rest = trim(line[5..]);
    var priority: []const u8 = "";
    if (std.mem.startsWith(u8, rest, "(P1)") or std.mem.startsWith(u8, rest, "(P2)") or std.mem.startsWith(u8, rest, "(P3)")) {
        priority = rest[1..3];
        rest = trim(rest[4..]);
    }
    var due: []const u8 = "";
    if (std.mem.startsWith(u8, rest, "due:")) {
        if (rest.len >= 14) {
            due = rest[4..14];
            rest = trim(rest[14..]);
        }
    }
    return Task{ .done = done, .priority = priority, .due = due, .text = dup(rest) };
}

fn formatTask(t: Task) []const u8 {
    const mark: []const u8 = if (t.done) "x" else " ";
    if (t.priority.len > 0 and t.due.len > 0) {
        return std.fmt.allocPrint(alloc, "- [{s}] ({s}) due:{s} {s}", .{ mark, t.priority, t.due, t.text }) catch "";
    } else if (t.priority.len > 0) {
        return std.fmt.allocPrint(alloc, "- [{s}] ({s}) {s}", .{ mark, t.priority, t.text }) catch "";
    } else if (t.due.len > 0) {
        return std.fmt.allocPrint(alloc, "- [{s}] due:{s} {s}", .{ mark, t.due, t.text }) catch "";
    } else {
        return std.fmt.allocPrint(alloc, "- [{s}] {s}", .{ mark, t.text }) catch "";
    }
}

fn loadTasks() []Task {
    const data = std.fs.cwd().readFileAlloc(alloc, TASKS_FILE, 1024 * 1024) catch return &[_]Task{};
    var out = std.ArrayList(Task).init(alloc);
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        const l = trim(line);
        if (l.len == 0) continue;
        if (parseLine(l)) |t| {
            out.append(t) catch continue;
        }
    }
    return out.items;
}

fn saveTasks(tasks: []Task) void {
    if (std.fs.cwd().statFile(TASKS_FILE) catch null) |_| {
        const old = std.fs.cwd().readFileAlloc(alloc, TASKS_FILE, 1024 * 1024) catch "";
        std.fs.cwd().writeFile(.{ .sub_path = BACKUP_FILE, .data = old }) catch {};
    }
    var buf = std.ArrayList(u8).init(alloc);
    for (tasks) |t| {
        const line = formatTask(t);
        buf.appendSlice(line) catch {};
        buf.appendSlice("\n") catch {};
    }
    std.fs.cwd().writeFile(.{ .sub_path = TASKS_FILE, .data = buf.items }) catch {};
}

fn parseAddText(full: []const u8) Task {
    var text = trim(full);
    var priority: []const u8 = "";
    var due: []const u8 = "";
    // P1 prefix
    if (text.len >= 3 and (std.mem.startsWith(u8, text, "P1 ") or std.mem.startsWith(u8, text, "P2 ") or std.mem.startsWith(u8, text, "P3 "))) {
        priority = text[0..2];
        text = trim(text[3..]);
    } else if (std.mem.startsWith(u8, text, "(P1)") or std.mem.startsWith(u8, text, "(P2)") or std.mem.startsWith(u8, text, "(P3)")) {
        priority = text[1..3];
        text = trim(text[4..]);
    }
    // due: in text
    if (std.mem.indexOf(u8, text, "due:")) |idx| {
        if (text.len >= idx + 14) {
            const cand = text[idx + 4 .. idx + 14];
            // simple check: looks like YYYY-MM-DD
            if (cand[4] == '-' and cand[7] == '-') {
                due = cand;
                var tmp = std.ArrayList(u8).init(alloc);
                tmp.appendSlice(trim(text[0..idx])) catch {};
                tmp.appendSlice(" ") catch {};
                tmp.appendSlice(trim(text[idx + 14 ..])) catch {};
                text = trim(tmp.items);
            }
        }
    }
    // collapse spaces
    var collapsed = std.ArrayList(u8).init(alloc);
    var prev_space = true;
    for (text) |c| {
        if (c == ' ' or c == '\t') {
            if (!prev_space) {
                collapsed.append(' ') catch {};
                prev_space = true;
            }
        } else {
            collapsed.append(c) catch {};
            prev_space = false;
        }
    }
    text = trim(collapsed.items);
    return Task{ .done = false, .priority = priority, .due = due, .text = dup(text) };
}

fn parseTaskNumber(s: []const u8, n: usize) ?usize {
    const v = std.fmt.parseInt(usize, trim(s), 10) catch return null;
    if (v < 1 or v > n) return null;
    return v - 1;
}

fn matchesMode(t: Task, mode: []const u8) bool {
    if (std.mem.eql(u8, mode, "todo")) return !t.done;
    if (std.mem.eql(u8, mode, "done")) return t.done;
    if (std.mem.eql(u8, mode, "overdue")) return !t.done and isOverdue(t);
    if (std.mem.eql(u8, mode, "today")) return !t.done and isToday(t);
    return true;
}

fn matchesSearch(t: Task, q: []const u8) bool {
    if (q.len == 0) return true;
    // case-insensitive contains
    const lower_text = std.ascii.allocLowerString(alloc, t.text) catch t.text;
    const lower_q = std.ascii.allocLowerString(alloc, q) catch q;
    return std.mem.indexOf(u8, lower_text, lower_q) != null;
}

fn filteredIndices(tasks: []Task, mode: []const u8, search: []const u8) []usize {
    var out = std.ArrayList(usize).init(alloc);
    for (tasks, 0..) |t, i| {
        if (!matchesMode(t, mode)) continue;
        if (!matchesSearch(t, search)) continue;
        out.append(i) catch continue;
    }
    return out.items;
}

fn countDone(tasks: []Task) usize {
    var n: usize = 0;
    for (tasks) |t| {
        if (t.done) n += 1;
    }
    return n;
}

fn countOverdue(tasks: []Task) usize {
    var n: usize = 0;
    for (tasks) |t| {
        if (!t.done and isOverdue(t)) n += 1;
    }
    return n;
}

fn hasTag(t: Task, tag: []const u8) bool {
    const want = std.mem.trimLeft(u8, tag, "#");
    var it = std.mem.splitScalar(u8, t.text, ' ');
    while (it.next()) |tok| {
        if (tok.len > 1 and tok[0] == '#') {
            if (std.mem.eql(u8, tok, tag) or std.mem.eql(u8, tok[1..], want)) return true;
        }
    }
    return false;
}

fn hasProject(t: Task, proj: []const u8) bool {
    const want = std.mem.trimLeft(u8, proj, "+");
    var it = std.mem.splitScalar(u8, t.text, ' ');
    while (it.next()) |tok| {
        if (tok.len > 1 and tok[0] == '+') {
            if (std.mem.eql(u8, tok, proj) or std.mem.eql(u8, tok[1..], want)) return true;
        }
    }
    return false;
}

fn printTask(idx: usize, t: Task) void {
    const mark: []const u8 = if (t.done) "x" else " ";
    if (t.priority.len > 0 and t.due.len > 0) {
        std.debug.print("{d}. [{s}] {s} {s} {s}\n", .{ idx + 1, mark, t.priority, t.due, t.text });
    } else if (t.priority.len > 0) {
        std.debug.print("{d}. [{s}] {s} {s}\n", .{ idx + 1, mark, t.priority, t.text });
    } else if (t.due.len > 0) {
        std.debug.print("{d}. [{s}] {s} {s}\n", .{ idx + 1, mark, t.due, t.text });
    } else {
        std.debug.print("{d}. [{s}] {s}\n", .{ idx + 1, mark, t.text });
    }
}

fn cliList(tasks: []Task, args: []const []const u8) void {
    var tag: []const u8 = "";
    var project: []const u8 = "";
    var priority: []const u8 = "";
    var search: []const u8 = "";
    var mode: []const u8 = "all";
    var i: usize = 0;
    while (i < args.len) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--tag") and i + 1 < args.len) {
            tag = args[i + 1];
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, a, "--project") and i + 1 < args.len) {
            project = args[i + 1];
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, a, "--priority") and i + 1 < args.len) {
            priority = args[i + 1];
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, a, "--search") and i + 1 < args.len) {
            search = args[i + 1];
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, a, "--overdue")) mode = "overdue";
        if (std.mem.eql(u8, a, "--today")) mode = "today";
        if (std.mem.eql(u8, a, "--done")) mode = "done";
        if (std.mem.eql(u8, a, "--todo")) mode = "todo";
        i += 1;
    }
    var shown: usize = 0;
    for (filteredIndices(tasks, mode, search)) |idx| {
        const t = tasks[idx];
        if (tag.len > 0 and !hasTag(t, tag)) continue;
        if (project.len > 0 and !hasProject(t, project)) continue;
        if (priority.len > 0 and !std.mem.eql(u8, t.priority, priority)) continue;
        printTask(idx, t);
        shown += 1;
    }
    if (shown == 0) {
        std.debug.print("No tasks.\n", .{});
    }
}

// ---------------------------------------------------------------------------
// TUI - AUDITED FIXES
// 1. Prompt has NO small char limit: reads bytes one-by-one into a growing
//    ArrayList(u8), 4096 cap, horizontal scroll. Old Zig used a fixed
//    [256]u8 buffer for prompts which truncated / returned StreamTooLong.
//    Now dynamic.
// 2. Exit is explicit: q, Q, Esc, Ctrl-C, Ctrl-D, Ctrl-Q all quit from
//    main list, footer always shows "q / Esc / Ctrl-C to quit". In a
//    prompt, Enter saves, Esc / Ctrl-C cancels back to list.
// ---------------------------------------------------------------------------

var orig_termios: std.posix.termios = undefined;
var raw_set: bool = false;

fn enableRaw() void {
    orig_termios = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch return;
    var raw = orig_termios;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    raw.oflag.OPOST = false;
    raw.cflag.CSIZE = .CS8;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, raw) catch {};
    raw_set = true;
}

fn disableRaw() void {
    if (raw_set) {
        std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, orig_termios) catch {};
    }
    std.debug.print("\n", .{});
}

fn readByte() ?u8 {
    var buf: [1]u8 = undefined;
    const n = std.io.getStdIn().read(&buf) catch return null;
    if (n == 0) return null;
    return buf[0];
}

fn promptInput(label: []const u8, initial: []const u8) ?[]const u8 {
    // Dynamic, no small limit - ArrayList grows, 4096 cap only
    var text = std.ArrayList(u8).init(alloc);
    text.appendSlice(initial) catch {};
    var cursor: usize = text.items.len;
    var offset: usize = 0;
    const width: usize = 80;
    const label_str = std.fmt.allocPrint(alloc, "{s} ", .{label}) catch label;
    const avail: usize = if (width > label_str.len + 1) width - label_str.len - 1 else 10;
    while (true) {
        if (cursor < offset) offset = cursor;
        if (cursor >= offset + avail) offset = cursor - avail + 1;
        // Clear prompt area - hint + prompt
        std.debug.print("\x1b[23;1H\x1b[2KEnter=save  Esc / Ctrl-C=cancel", .{});
        std.debug.print("\x1b[24;1H\x1b[2K", .{});
        std.debug.print("{s}", .{label_str});
        const end = @min(offset + avail, text.items.len);
        if (offset < text.items.len) {
            std.debug.print("{s}", .{text.items[offset..end]});
        }
        const cursor_x = label_str.len + (cursor - offset) + 1;
        std.debug.print("\x1b[24;{d}H", .{cursor_x});
        const b = readByte() orelse continue;
        if (b == 13 or b == 10) {
            break;
        }
        if (b == 27) { // Esc - cancel
            return null;
        }
        if (b == 3 or b == 4) { // Ctrl-C / Ctrl-D - cancel
            return null;
        }
        if (b == 127 or b == 8) { // Backspace
            if (cursor > 0) {
                _ = text.orderedRemove(cursor - 1);
                cursor -= 1;
            }
            continue;
        }
        if (b == 21) { // Ctrl-U clear
            text.clearRetainingCapacity();
            cursor = 0;
            offset = 0;
            continue;
        }
        if (b == 11) { // Ctrl-K kill to end
            text.shrinkRetainingCapacity(cursor);
            continue;
        }
        if (b == 1) { // Ctrl-A start
            cursor = 0;
            continue;
        }
        if (b == 5) { // Ctrl-E end
            cursor = text.items.len;
            continue;
        }
        if (b == 23) { // Ctrl-W delete word
            while (cursor > 0 and text.items[cursor - 1] == ' ') {
                _ = text.orderedRemove(cursor - 1);
                cursor -= 1;
            }
            while (cursor > 0 and text.items[cursor - 1] != ' ') {
                _ = text.orderedRemove(cursor - 1);
                cursor -= 1;
            }
            continue;
        }
        if (b >= 32 and b <= 126) {
            if (text.items.len < 4096) {
                text.insert(cursor, b) catch {};
                cursor += 1;
            }
            continue;
        }
        // Ignore other bytes
    }
    return trim(text.items);
}

fn runTUI(tasks: *std.ArrayList(Task)) void {
    enableRaw();
    defer disableRaw();
    var selected: usize = 0;
    var filter_mode: []const u8 = "all";
    var search: []const u8 = "";
    var status: []const u8 = "Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter";
    const filters = [_][]const u8{ "all", "todo", "done", "overdue", "today" };
    while (true) {
        const visible = filteredIndices(tasks.items, filter_mode, search);
        if (visible.len == 0) {
            selected = 0;
        } else {
            if (selected >= visible.len) selected = visible.len - 1;
        }
        std.debug.print("\x1b[2J\x1b[H", .{});
        const total = tasks.items.len;
        const done_n = countDone(tasks.items);
        const overdue_n = countOverdue(tasks.items);
        std.debug.print("tasks - {d} total | {d} done | {d} overdue | filter: {s} | search: {s}\n", .{ total, done_n, overdue_n, filter_mode, search });
        std.debug.print("{s:<4} {s:<3} {s:<4} {s:<11} Text\n", .{ "#", "[]", "P", "Due" });
        std.debug.print("--------------------------------------------------------------------------------\n", .{});
        const max_rows: usize = 18;
        var i: usize = 0;
        while (i < visible.len and i < max_rows) : (i += 1) {
            const idx = visible[i];
            const t = tasks.items[idx];
            const mark: []const u8 = if (t.done) "x" else " ";
            const line = if (t.priority.len > 0 and t.due.len > 0)
                std.fmt.allocPrint(alloc, "{d:<4} [{s}] ({s}) due:{s} {s}", .{ idx + 1, mark, t.priority, t.due, t.text }) catch ""
            else if (t.priority.len > 0)
                std.fmt.allocPrint(alloc, "{d:<4} [{s}] ({s}) {s}", .{ idx + 1, mark, t.priority, t.text }) catch ""
            else if (t.due.len > 0)
                std.fmt.allocPrint(alloc, "{d:<4} [{s}] due:{s} {s}", .{ idx + 1, mark, t.due, t.text }) catch ""
            else
                std.fmt.allocPrint(alloc, "{d:<4} [{s}] {s}", .{ idx + 1, mark, t.text }) catch "";
            if (i == selected) {
                std.debug.print("\x1b[7m{s}\x1b[0m\n", .{line});
            } else if (t.done) {
                std.debug.print("\x1b[2m{s}\x1b[0m\n", .{line});
            } else {
                std.debug.print("{s}\n", .{line});
            }
        }
        std.debug.print("\x1b[22;1H\x1b[2K{s}\n", .{status});
        std.debug.print("q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats", .{});
        const b = readByte() orelse continue;
        // EXIT - checked first
        if (b == 'q' or b == 'Q' or b == 27 or b == 3 or b == 4 or b == 17) {
            break;
        }
        if (b == 'j') {
            if (selected + 1 < visible.len) selected += 1;
            continue;
        }
        if (b == 'k') {
            if (selected > 0) selected -= 1;
            continue;
        }
        if (b == 'g') {
            selected = 0;
            continue;
        }
        if (b == 'G') {
            if (visible.len > 0) selected = visible.len - 1;
            continue;
        }
        if (b == ' ') {
            if (visible.len > 0) {
                const idx = visible[selected];
                tasks.items[idx].done = !tasks.items[idx].done;
                saveTasks(tasks.items);
                status = if (tasks.items[idx].done) "Marked done" else "Marked todo";
            }
            continue;
        }
        if (b == 'a') {
            if (promptInput("Add:", "")) |s| {
                if (s.len > 0) {
                    const nt = parseAddText(s);
                    tasks.append(nt) catch {};
                    saveTasks(tasks.items);
                    selected = tasks.items.len - 1;
                    status = std.fmt.allocPrint(alloc, "Added: {s}", .{nt.text}) catch "Added";
                } else {
                    status = "Add cancelled - press q or Esc to quit";
                }
            } else {
                status = "Add cancelled - press q or Esc to quit";
            }
            continue;
        }
        if (b == 'e') {
            if (visible.len > 0) {
                const idx = visible[selected];
                const old = tasks.items[idx];
                const label = std.fmt.allocPrint(alloc, "Edit [{s}]:", .{old.text}) catch "Edit:";
                if (promptInput(label, "")) |s| {
                    if (s.len > 0) {
                        var nt = parseAddText(s);
                        if (nt.priority.len == 0) nt.priority = old.priority;
                        if (nt.due.len == 0) nt.due = old.due;
                        nt.done = old.done;
                        tasks.items[idx] = nt;
                        saveTasks(tasks.items);
                        status = "Edited";
                    }
                }
            }
            continue;
        }
        if (b == 'd') {
            if (visible.len > 0) {
                const idx = visible[selected];
                const removed = tasks.items[idx].text;
                _ = tasks.orderedRemove(idx);
                saveTasks(tasks.items);
                status = std.fmt.allocPrint(alloc, "Deleted: {s}", .{removed}) catch "Deleted";
                if (selected >= visible.len and selected > 0) selected -= 1;
            }
            continue;
        }
        if (b == '/') {
            if (promptInput("Search:", "")) |s| {
                search = s;
                selected = 0;
                if (search.len > 0) {
                    status = std.fmt.allocPrint(alloc, "Search: {s}", .{search}) catch "Search";
                } else {
                    status = "Search cleared - press q or Esc to quit";
                }
            }
            continue;
        }
        if (b == 'f') {
            var cur: usize = 0;
            for (filters, 0..) |f, fi| {
                if (std.mem.eql(u8, f, filter_mode)) cur = fi;
            }
            filter_mode = filters[(cur + 1) % filters.len];
            selected = 0;
            status = std.fmt.allocPrint(alloc, "Filter: {s}", .{filter_mode}) catch "Filter";
            continue;
        }
        if (b == 'u') {
            if (std.fs.cwd().statFile(BACKUP_FILE) catch null) |_| {
                const old = std.fs.cwd().readFileAlloc(alloc, BACKUP_FILE, 1024 * 1024) catch "";
                std.fs.cwd().writeFile(.{ .sub_path = TASKS_FILE, .data = old }) catch {};
                const nt = loadTasks();
                tasks.clearRetainingCapacity();
                tasks.appendSlice(nt) catch {};
                status = "Undone";
            } else {
                status = "No backup to undo";
            }
            continue;
        }
        if (b == 'c') {
            var kept = std.ArrayList(Task).init(alloc);
            for (tasks.items) |t| {
                if (!t.done) kept.append(t) catch {};
            }
            const cleared = tasks.items.len - kept.items.len;
            tasks.clearRetainingCapacity();
            tasks.appendSlice(kept.items) catch {};
            saveTasks(tasks.items);
            status = std.fmt.allocPrint(alloc, "Cleared {d} done", .{cleared}) catch "Cleared";
            selected = 0;
            continue;
        }
        if (b == 's') {
            const total2 = tasks.items.len;
            const done_n2 = countDone(tasks.items);
            const overdue_n2 = countOverdue(tasks.items);
            status = std.fmt.allocPrint(alloc, "Total {d} - Done {d} - Todo {d} - Overdue {d}", .{ total2, done_n2, total2 - done_n2, overdue_n2 }) catch "Stats";
            continue;
        }
        if (b == '?') {
            status = "Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats";
            continue;
        }
    }
}

pub fn main() !void {
    var args = std.process.argsAlloc(alloc) catch return;
    defer alloc.free(args);
    const rest = if (args.len > 1) args[1..] else &[_][]const u8{};
    var tasks_list = std.ArrayList(Task).init(alloc);
    tasks_list.appendSlice(loadTasks()) catch {};
    var tasks = tasks_list;

    if (rest.len == 0 or std.mem.eql(u8, rest[0], "tui")) {
        runTUI(&tasks);
        std.debug.print("Exited TUI - back to shell. Use: zig run tasks.zig -- list\n", .{});
        return;
    }

    const cmd = rest[0];
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        std.debug.print(
            \\Usage:
            \\  tasks tui                    Interactive TUI (default, no args = tui)
            \\  tasks add [--priority P1] [--due YYYY-MM-DD] <text>
            \\  tasks list [--tag X] [--project Y] [--priority P1] [--search Q] [--overdue|--today|--done|--todo]
            \\  tasks done <n>
            \\  tasks undone <n>
            \\  tasks rm <n>
            \\  tasks edit <n> <new text>
            \\  tasks search <query>
            \\  tasks clear
            \\  tasks stats
            \\  tasks undo
            \\  tasks help
            \\
            \\Format: tasks.md lines are - [ ] (P1) due:2026-11-30 Buy milk #home +groceries
            \\Tags start with #, projects with +. Priority P1/P2/P3, due YYYY-MM-DD.
            \\TUI keys: j/k move, Space toggle, a add, e edit, d delete,
            \\  / search, f filter, u undo, c clear done, s stats, q / Esc / Ctrl-C to quit
            \\  In a prompt: Enter saves, Esc / Ctrl-C cancels
            \\
        , .{});
        return;
    }
    if (std.mem.eql(u8, cmd, "add")) {
        var priority: []const u8 = "";
        var due: []const u8 = "";
        var parts = std.ArrayList([]const u8).init(alloc);
        var i: usize = 1;
        while (i < rest.len) : (i += 1) {
            if (std.mem.eql(u8, rest[i], "--priority") and i + 1 < rest.len) {
                priority = rest[i + 1];
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, rest[i], "--due") and i + 1 < rest.len) {
                due = rest[i + 1];
                i += 1;
                continue;
            }
            parts.append(rest[i]) catch {};
        }
        const full = std.mem.join(alloc, " ", parts.items) catch "";
        if (trim(full).len == 0) {
            std.debug.print("Usage: tasks add <text>\n", .{});
            return;
        }
        var t = parseAddText(full);
        if (priority.len > 0) t.priority = priority;
        if (due.len > 0) t.due = due;
        tasks.append(t) catch {};
        saveTasks(tasks.items);
        std.debug.print("Added: {s}\n", .{t.text});
        return;
    }
    if (std.mem.eql(u8, cmd, "list")) {
        cliList(tasks.items, rest[1..]);
        return;
    }
    if (std.mem.eql(u8, cmd, "done")) {
        if (rest.len < 2) {
            std.debug.print("Usage: tasks done <n>\n", .{});
            return;
        }
        const idx = parseTaskNumber(rest[1], tasks.items.len) orelse {
            std.debug.print("Invalid task number\n", .{});
            return;
        };
        tasks.items[idx].done = true;
        saveTasks(tasks.items);
        std.debug.print("Done: {s}\n", .{tasks.items[idx].text});
        return;
    }
    if (std.mem.eql(u8, cmd, "undone")) {
        if (rest.len < 2) {
            std.debug.print("Usage: tasks undone <n>\n", .{});
            return;
        }
        const idx = parseTaskNumber(rest[1], tasks.items.len) orelse {
            std.debug.print("Invalid task number\n", .{});
            return;
        };
        tasks.items[idx].done = false;
        saveTasks(tasks.items);
        std.debug.print("Todo: {s}\n", .{tasks.items[idx].text});
        return;
    }
    if (std.mem.eql(u8, cmd, "rm")) {
        if (rest.len < 2) {
            std.debug.print("Usage: tasks rm <n>\n", .{});
            return;
        }
        const idx = parseTaskNumber(rest[1], tasks.items.len) orelse {
            std.debug.print("Invalid task number\n", .{});
            return;
        };
        const removed = tasks.items[idx].text;
        _ = tasks.orderedRemove(idx);
        saveTasks(tasks.items);
        std.debug.print("Deleted: {s}\n", .{removed});
        return;
    }
    if (std.mem.eql(u8, cmd, "edit")) {
        if (rest.len < 3) {
            std.debug.print("Usage: tasks edit <n> <new text>\n", .{});
            return;
        }
        const idx = parseTaskNumber(rest[1], tasks.items.len) orelse {
            std.debug.print("Invalid task number\n", .{});
            return;
        };
        const full = std.mem.join(alloc, " ", rest[2..]) catch "";
        var nt = parseAddText(full);
        const old = tasks.items[idx];
        if (nt.priority.len == 0) nt.priority = old.priority;
        if (nt.due.len == 0) nt.due = old.due;
        nt.done = old.done;
        tasks.items[idx] = nt;
        saveTasks(tasks.items);
        std.debug.print("Edited {d}: {s}\n", .{ idx + 1, nt.text });
        return;
    }
    if (std.mem.eql(u8, cmd, "search")) {
        if (rest.len < 2) {
            std.debug.print("Usage: tasks search <query>\n", .{});
            return;
        }
        const q = std.mem.join(alloc, " ", rest[1..]) catch "";
        var found = false;
        for (tasks.items, 0..) |t, idx| {
            if (matchesSearch(t, q)) {
                printTask(idx, t);
                found = true;
            }
        }
        if (!found) std.debug.print("No matches.\n", .{});
        return;
    }
    if (std.mem.eql(u8, cmd, "clear")) {
        var kept = std.ArrayList(Task).init(alloc);
        for (tasks.items) |t| {
            if (!t.done) kept.append(t) catch {};
        }
        const before = tasks.items.len;
        tasks.clearRetainingCapacity();
        tasks.appendSlice(kept.items) catch {};
        saveTasks(tasks.items);
        std.debug.print("Cleared {d} done tasks\n", .{before - tasks.items.len});
        return;
    }
    if (std.mem.eql(u8, cmd, "stats")) {
        const total = tasks.items.len;
        const done_n = countDone(tasks.items);
        const overdue_n = countOverdue(tasks.items);
        var today_n: usize = 0;
        for (tasks.items) |t| {
            if (!t.done and isToday(t)) today_n += 1;
        }
        std.debug.print("Total: {d}\nDone: {d}\nTodo: {d}\nOverdue: {d}\nDue today: {d}\n", .{ total, done_n, total - done_n, overdue_n, today_n });
        return;
    }
    if (std.mem.eql(u8, cmd, "undo")) {
        if (std.fs.cwd().statFile(BACKUP_FILE) catch null) |_| {
            const old = std.fs.cwd().readFileAlloc(alloc, BACKUP_FILE, 1024 * 1024) catch "";
            std.fs.cwd().writeFile(.{ .sub_path = TASKS_FILE, .data = old }) catch {};
            std.debug.print("Undone - restored from backup\n", .{});
        } else {
            std.debug.print("No backup to undo\n", .{});
        }
        return;
    }
    std.debug.print("Unknown command: {s}\n", .{cmd});
}
