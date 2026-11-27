// tasks.zig - Todo CLI v2 (Zig, stdlib only)
// Same spec + same tasks.md as all other languages.
// Build (0.13 / 0.14): zig build-exe tasks.zig -O ReleaseSafe -o tasks
// Run: ./tasks  |  ./tasks list  |  ./tasks add "Buy milk #home"
// FIX 2026-11-27: Date conversion uses the 0.13 / 0.14 epoch API:
//   EpochSeconds -> getEpochDay -> calculateYearDay -> calculateMonthDay
// The old single-step conversion no longer exists in 0.13 / 0.14.
// TUI raw mode via posix.tcgetattr / tcsetattr, original termios
// saved and restored on exit.

const std = @import("std");
const Allocator = std.mem.Allocator;
const posix = std.posix;

const TASKS_FILE = "tasks.md";
const BACKUP_FILE = "tasks.md.bak";
const MAX_INPUT: usize = 4096;

const Task = struct {
    done: bool = false,
    priority: []u8 = &[_]u8{},
    due: []u8 = &[_]u8{},
    text: []u8 = &[_]u8{},
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var alloc: Allocator = undefined;
var tasks: std.ArrayList(Task) = undefined;

fn trimS(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn dupTrim(s: []const u8) ![]u8 {
    return alloc.dupe(u8, trimS(s));
}

fn collapseSpaces(s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();
    var in_space = true;
    for (s) |c| {
        if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
            if (!in_space and out.items.len > 0) try out.append(' ');
            in_space = true;
        } else {
            try out.append(c);
            in_space = false;
        }
    }
    return alloc.dupe(u8, trimS(out.items));
}

fn todayString() ![]u8 {
    const secs = std.time.timestamp();
    const secs_u: u64 = if (secs < 0) 0 else @intCast(secs);
    const es = std.time.epoch.EpochSeconds{ .secs = secs_u };
    // 0.13 / 0.14 API: EpochDay -> YearDay -> MonthDay (two steps)
    const year_day = es.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const month: u32 = @intFromEnum(month_day.month);
    const day: u32 = month_day.day_index + 1;
    return std.fmt.allocPrint(alloc, "{d:0>4}-{d:0>2}-{d:0>2}", .{ year_day.year, month, day });
}

fn isOverdue(t: Task) !bool {
    if (t.due.len == 0) return false;
    const today = try todayString();
    defer alloc.free(today);
    return std.mem.order(u8, t.due, today) == .lt;
}

fn isToday(t: Task) !bool {
    if (t.due.len == 0) return false;
    const today = try todayString();
    defer alloc.free(today);
    return std.mem.eql(u8, t.due, today);
}

fn parseLine(line: []const u8) !?Task {
    if (!std.mem.startsWith(u8, line, "- [")) return null;
    if (line.len < 5) return null;
    const mark = line[3];
    if (mark != ' ' and mark != 'x') return null;
    if (line[4] != ']') return null;
    var t = Task{ .done = mark == 'x' };
    var rest = trimS(line[5..]);
    if (std.mem.startsWith(u8, rest, "(P1)") or std.mem.startsWith(u8, rest, "(P2)") or std.mem.startsWith(u8, rest, "(P3)")) {
        t.priority = try alloc.dupe(u8, rest[1..3]);
        rest = trimS(rest[4..]);
    }
    if (std.mem.startsWith(u8, rest, "due:") and rest.len >= 14) {
        const d = rest[4..14];
        if (d.len == 10 and d[4] == '-' and d[7] == '-') {
            t.due = try alloc.dupe(u8, d);
            rest = trimS(rest[14..]);
        }
    }
    t.text = try alloc.dupe(u8, trimS(rest));
    return t;
}

fn formatTask(t: Task) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();
    try out.appendSlice("- [");
    try out.append(if (t.done) 'x' else ' ');
    try out.append(']');
    if (t.priority.len > 0) {
        try out.appendSlice(" (");
        try out.appendSlice(t.priority);
        try out.append(')');
    }
    if (t.due.len > 0) {
        try out.appendSlice(" due:");
        try out.appendSlice(t.due);
    }
    try out.append(' ');
    try out.appendSlice(t.text);
    return alloc.dupe(u8, out.items);
}

fn loadTasks() !void {
    tasks.clearRetainingCapacity();
    const data = std.fs.cwd().readFileAlloc(alloc, TASKS_FILE, 10 * 1024 * 1024) catch return;
    defer alloc.free(data);
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |raw| {
        const line = trimS(raw);
        if (line.len == 0) continue;
        const clean = if (std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line;
        if (try parseLine(clean)) |t| try tasks.append(t);
    }
}

fn saveTasks() !void {
    if (std.fs.cwd().access(TASKS_FILE, .{})) {
        std.fs.cwd().copyFile(TASKS_FILE, std.fs.cwd(), BACKUP_FILE, .{}) catch {};
    } else |_| {}
    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();
    for (tasks.items) |t| {
        const s = try formatTask(t);
        defer alloc.free(s);
        try out.appendSlice(s);
        try out.append('\n');
    }
    try std.fs.cwd().writeFile(.{ .sub_path = TASKS_FILE, .data = out.items });
}

fn parseAddText(full: []const u8) !Task {
    var t = Task{};
    var text = trimS(full);
    if (std.mem.startsWith(u8, text, "P1 ") or std.mem.startsWith(u8, text, "P2 ") or std.mem.startsWith(u8, text, "P3 ")) {
        t.priority = try alloc.dupe(u8, text[0..2]);
        text = trimS(text[3..]);
    } else if (std.mem.startsWith(u8, text, "(P1)") or std.mem.startsWith(u8, text, "(P2)") or std.mem.startsWith(u8, text, "(P3)")) {
        t.priority = try alloc.dupe(u8, text[1..3]);
        text = trimS(text[4..]);
    }
    if (std.mem.indexOf(u8, text, "due:")) |pos| {
        if (text.len >= pos + 14) {
            const cand = text[pos + 4 .. pos + 14];
            if (cand.len == 10 and cand[4] == '-' and cand[7] == '-') {
                t.due = try alloc.dupe(u8, cand);
                const before = trimS(text[0..pos]);
                const after = trimS(text[pos + 14 ..]);
                const joined = try std.fmt.allocPrint(alloc, "{s} {s}", .{ before, after });
                defer alloc.free(joined);
                text = trimS(joined);
                // copy because joined is freed below; re-dupe via collapse
                const cs = try collapseSpaces(text);
                t.text = cs;
                return t;
            }
        }
    }
    t.text = try collapseSpaces(text);
    return t;
}

fn parseTaskNumber(s: []const u8, n: usize) ?usize {
    const t = trimS(s);
    if (t.len == 0) return null;
    for (t) |c| if (c < '0' or c > '9') return null;
    const v = std.fmt.parseInt(usize, t, 10) catch return null;
    if (v < 1 or v > n) return null;
    return v - 1;
}

fn matchesMode(t: Task, mode: []const u8) !bool {
    if (std.mem.eql(u8, mode, "todo")) return !t.done;
    if (std.mem.eql(u8, mode, "done")) return t.done;
    if (std.mem.eql(u8, mode, "overdue")) return !t.done and try isOverdue(t);
    if (std.mem.eql(u8, mode, "today")) return !t.done and try isToday(t);
    return true;
}

fn matchesSearch(t: Task, q: []const u8) !bool {
    if (q.len == 0) return true;
    const a = try std.ascii.allocLowerString(alloc, t.text);
    defer alloc.free(a);
    const b = try std.ascii.allocLowerString(alloc, q);
    defer alloc.free(b);
    return std.mem.indexOf(u8, a, b) != null;
}

fn filteredIndices(mode: []const u8, search: []const u8) !std.ArrayList(usize) {
    var out = std.ArrayList(usize).init(alloc);
    for (tasks.items, 0..) |t, i| {
        if (!(try matchesMode(t, mode))) continue;
        if (!(try matchesSearch(t, search))) continue;
        try out.append(i);
    }
    return out;
}

fn countDone() usize {
    var c: usize = 0;
    for (tasks.items) |t| if (t.done) c += 1;
    return c;
}

fn countOverdue() !usize {
    var c: usize = 0;
    for (tasks.items) |t| if (!t.done and try isOverdue(t)) c += 1;
    return c;
}

fn hasTag(t: Task, tag: []const u8) bool {
    const want = if (std.mem.startsWith(u8, tag, "#")) tag[1..] else tag;
    var it = std.mem.tokenizeAny(u8, t.text, " \t");
    while (it.next()) |tok| {
        if (tok.len > 1 and tok[0] == '#') {
            if (std.mem.eql(u8, tok, tag) or std.mem.eql(u8, tok[1..], want)) return true;
        }
    }
    return false;
}

fn hasProject(t: Task, proj: []const u8) bool {
    const want = if (std.mem.startsWith(u8, proj, "+")) proj[1..] else proj;
    var it = std.mem.tokenizeAny(u8, t.text, " \t");
    while (it.next()) |tok| {
        if (tok.len > 1 and tok[0] == '+') {
            if (std.mem.eql(u8, tok, proj) or std.mem.eql(u8, tok[1..], want)) return true;
        }
    }
    return false;
}

fn printTask(writer: anytype, idx: usize, t: Task) !void {
    try writer.print("{d}. [{c}] ", .{ idx + 1, if (t.done) @as(u8, 'x') else @as(u8, ' ') });
    if (t.priority.len > 0) try writer.print("{s} ", .{t.priority});
    if (t.due.len > 0) try writer.print("{s} ", .{t.due});
    try writer.print("{s}\n", .{t.text});
}

fn cliList(args: [][]const u8) !void {
    const stdout = std.io.getStdOut().writer();
    var tag: []const u8 = "";
    var project: []const u8 = "";
    var priority: []const u8 = "";
    var search: []const u8 = "";
    var mode: []const u8 = "all";
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--tag") and i + 1 < args.len) { tag = args[i + 1]; i += 1; continue; }
        if (std.mem.eql(u8, a, "--project") and i + 1 < args.len) { project = args[i + 1]; i += 1; continue; }
        if (std.mem.eql(u8, a, "--priority") and i + 1 < args.len) { priority = args[i + 1]; i += 1; continue; }
        if (std.mem.eql(u8, a, "--search") and i + 1 < args.len) { search = args[i + 1]; i += 1; continue; }
        if (std.mem.eql(u8, a, "--overdue")) mode = "overdue";
        if (std.mem.eql(u8, a, "--today")) mode = "today";
        if (std.mem.eql(u8, a, "--done")) mode = "done";
        if (std.mem.eql(u8, a, "--todo")) mode = "todo";
    }
    var shown: usize = 0;
    var vis = try filteredIndices(mode, search);
    defer vis.deinit();
    for (vis.items) |idx| {
        const t = tasks.items[idx];
        if (tag.len > 0 and !hasTag(t, tag)) continue;
        if (project.len > 0 and !hasProject(t, project)) continue;
        if (priority.len > 0 and !std.mem.eql(u8, t.priority, priority)) continue;
        try printTask(stdout, idx, t);
        shown += 1;
    }
    if (shown == 0) try stdout.print("No tasks.\n", .{});
}

// --- TUI ---
var orig_termios: posix.termios = undefined;
var termios_saved: bool = false;

fn setRaw(vmin: u8, vtime: u8) void {
    if (!termios_saved) return;
    var raw = orig_termios;
    raw.iflag.BRKINT = false;
    raw.iflag.ICRNL = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    raw.iflag.IXON = false;
    raw.oflag.OPOST = false;
    raw.cflag.CS8 = true;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.IEXTEN = false;
    raw.lflag.ISIG = false;
    raw.cc[@intFromEnum(posix.VMIN)] = vmin;
    raw.cc[@intFromEnum(posix.VTIME)] = vtime;
    posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, raw) catch {};
}

fn restoreTermios() void {
    if (termios_saved) posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, orig_termios) catch {};
}

const KeyKind = enum { char, enter, esc, up, down, left, right, home, end, del, backspace, ctrl_c, ctrl_d, ctrl_q, ctrl_a, ctrl_e, ctrl_u, ctrl_k, ctrl_w, other };
const Key = struct { kind: KeyKind, ch: u8 = 0, utf8: []const u8 = "" };

fn readByte() ?u8 {
    var buf: [1]u8 = undefined;
    const n = std.io.getStdIn().read(&buf) catch return null;
    if (n == 0) return null;
    return buf[0];
}

fn readByteTimeout() ?u8 {
    setRaw(0, 1);
    const b = readByte();
    setRaw(1, 0);
    return b;
}

fn readKey() Key {
    const b = readByte() orelse return .{ .kind = .other };
    switch (b) {
        13, 10 => return .{ .kind = .enter },
        3 => return .{ .kind = .ctrl_c },
        4 => return .{ .kind = .ctrl_d },
        17 => return .{ .kind = .ctrl_q },
        1 => return .{ .kind = .ctrl_a },
        5 => return .{ .kind = .ctrl_e },
        21 => return .{ .kind = .ctrl_u },
        11 => return .{ .kind = .ctrl_k },
        23 => return .{ .kind = .ctrl_w },
        127, 8 => return .{ .kind = .backspace },
        27 => {
            const b2 = readByteTimeout() orelse return .{ .kind = .esc };
            if (b2 != '[' and b2 != 'O') return .{ .kind = .esc };
            const b3 = readByteTimeout() orelse return .{ .kind = .esc };
            return switch (b3) {
                'A' => .{ .kind = .up },
                'B' => .{ .kind = .down },
                'C' => .{ .kind = .right },
                'D' => .{ .kind = .left },
                'H' => .{ .kind = .home },
                'F' => .{ .kind = .end },
                '3' => blk: {
                    _ = readByteTimeout();
                    break :blk .{ .kind = .del };
                },
                else => .{ .kind = .esc },
            };
        },
        0x80...0xFF => {
            // UTF-8: read continuation bytes
            var buf: [4]u8 = undefined;
            buf[0] = b;
            var need: usize = 0;
            if (b >= 0xC2 and b <= 0xDF) need = 1 else if (b >= 0xE0 and b <= 0xEF) need = 2 else if (b >= 0xF0 and b <= 0xF4) need = 3 else return .{ .kind = .other };
            for (0..need) |i| {
                const nb = readByteTimeout() orelse break;
                buf[i + 1] = nb;
            }
            const s = alloc.dupe(u8, buf[0 .. need + 1]) catch return .{ .kind = .other };
            return .{ .kind = .char, .ch = b, .utf8 = s };
        },
        32...126 => return .{ .kind = .char, .ch = b, .utf8 = &[_]u8{b} },
        else => return .{ .kind = .other },
    }
}

fn termSize() struct { rows: u16, cols: u16 } {
    var ws: posix.winsize = undefined;
    if (posix.ioctl(posix.STDOUT_FILENO, posix.T.IOCGWINSZ, @intFromPtr(&ws)) == 0 and ws.row > 0 and ws.col > 0) {
        return .{ .rows = ws.row, .cols = ws.col };
    }
    return .{ .rows = 24, .cols = 80 };
}

fn promptInput(label: []const u8) !?[]u8 {
    const stdout = std.io.getStdOut().writer();
    var chars = std.ArrayList([]const u8).init(alloc);
    defer {
        for (chars.items) |c| alloc.free(c);
        chars.deinit();
    }
    var cursor: usize = 0;
    var offset: usize = 0;
    const label_len: usize = label.len + 1;
    while (true) {
        const sz = termSize();
        const rows = sz.rows;
        const cols: usize = sz.cols;
        var avail: usize = if (cols > label_len + 1) cols - label_len - 1 else 10;
        if (avail < 10) avail = 10;
        if (cursor < offset) offset = cursor;
        if (cursor >= offset + avail) offset = cursor - avail + 1;
        try stdout.print("\x1b[{d};1H\x1b[2KEnter=save  Esc / Ctrl-C=cancel", .{rows - 1});
        try stdout.print("\x1b[{d};1H\x1b[2K", .{rows});
        try stdout.print("{s} ", .{label});
        for (chars.items[offset..@min(chars.items.len, offset + avail)]) |c| try stdout.print("{s}", .{c});
        var cx: usize = label_len + (cursor - offset) + 1;
        if (cx > cols) cx = cols;
        if (cx < 1) cx = 1;
        try stdout.print("\x1b[{d};{d}H", .{ rows, cx });
        const k = readKey();
        switch (k.kind) {
            .enter => break,
            .esc, .ctrl_c, .ctrl_d => return null,
            .backspace => {
                if (cursor > 0) {
                    alloc.free(chars.items[cursor - 1]);
                    _ = chars.orderedRemove(cursor - 1);
                    cursor -= 1;
                }
            },
            .del => {
                if (cursor < chars.items.len) {
                    alloc.free(chars.items[cursor]);
                    _ = chars.orderedRemove(cursor);
                }
            },
            .left => if (cursor > 0) {
                cursor -= 1;
            },
            .right => if (cursor < chars.items.len) {
                cursor += 1;
            },
            .home, .ctrl_a => cursor = 0,
            .end, .ctrl_e => cursor = chars.items.len,
            .ctrl_u => {
                for (chars.items) |c| alloc.free(c);
                chars.clearRetainingCapacity();
                cursor = 0;
                offset = 0;
            },
            .ctrl_k => {
                for (chars.items[cursor..]) |c| alloc.free(c);
                try chars.resize(cursor);
            },
            .ctrl_w => {
                while (cursor > 0 and std.mem.eql(u8, chars.items[cursor - 1], " ")) {
                    alloc.free(chars.items[cursor - 1]);
                    _ = chars.orderedRemove(cursor - 1);
                    cursor -= 1;
                }
                while (cursor > 0 and !std.mem.eql(u8, chars.items[cursor - 1], " ")) {
                    alloc.free(chars.items[cursor - 1]);
                    _ = chars.orderedRemove(cursor - 1);
                    cursor -= 1;
                }
            },
            .up, .down => {},
            .char => {
                if (chars.items.len < MAX_INPUT) {
                    const s = try alloc.dupe(u8, k.utf8);
                    try chars.insert(cursor, s);
                    cursor += 1;
                }
            },
            else => {},
        }
    }
    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();
    for (chars.items) |c| try out.appendSlice(c);
    return try alloc.dupe(u8, trimS(out.items));
}

fn runTui() !void {
    orig_termios = posix.tcgetattr(posix.STDIN_FILENO) catch return;
    termios_saved = true;
    setRaw(1, 0);
    defer restoreTermios();
    const stdout = std.io.getStdOut().writer();
    var selected: usize = 0;
    const filters = [_][]const u8{ "all", "todo", "done", "overdue", "today" };
    var filter_idx: usize = 0;
    var search: []u8 = try alloc.dupe(u8, "");
    defer alloc.free(search);
    var status: []u8 = try alloc.dupe(u8, "Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter");
    defer alloc.free(status);
    while (true) {
        const sz = termSize();
        const rows = sz.rows;
        const cols: usize = sz.cols;
        const mode = filters[filter_idx];
        var vis = try filteredIndices(mode, search);
        defer vis.deinit();
        if (vis.items.len == 0) selected = 0 else {
            if (selected >= vis.items.len) selected = vis.items.len - 1;
        }
        try stdout.print("\x1b[2J\x1b[H", .{});
        try stdout.print("tasks - {d} total | {d} done | {d} overdue | filter: {s} | search: {s}\n", .{ tasks.items.len, countDone(), try countOverdue(), mode, search });
        try stdout.print("#    []  P    Due         Text\n", .{});
        try stdout.print("{s}\n", .{"-" ** 80});
        const max_rows: usize = if (rows > 5) rows - 5 else 5;
        for (vis.items[0..@min(vis.items.len, max_rows)], 0..) |idx, i| {
            const t = tasks.items[idx];
            var line = std.ArrayList(u8).init(alloc);
            defer line.deinit();
            try line.writer().print("{d:<4} [{c}] ", .{ idx + 1, if (t.done) @as(u8, 'x') else @as(u8, ' ') });
            if (t.priority.len > 0) try line.writer().print("({s}) ", .{t.priority});
            if (t.due.len > 0) try line.writer().print("due:{s} ", .{t.due});
            try line.appendSlice(t.text);
            const l = if (line.items.len > cols) line.items[0..cols] else line.items;
            if (i == selected) try stdout.print("\x1b[7m{s}\x1b[0m\n", .{l}) else if (t.done) try stdout.print("\x1b[2m{s}\x1b[0m\n", .{l}) else try stdout.print("{s}\n", .{l});
        }
        try stdout.print("\x1b[{d};1H\x1b[2K{s}", .{ rows - 1, status });
        try stdout.print("\x1b[{d};1H\x1b[2K", .{rows});
        try stdout.print("q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats", .{});
        try stdout.print("\x1b[{d};1H", .{rows});
        const k = readKey();
        if (k.kind == .esc or k.kind == .ctrl_c or k.kind == .ctrl_d or k.kind == .ctrl_q) break;
        if (k.kind == .char and (k.ch == 'q' or k.ch == 'Q')) break;
        if (k.kind == .down) {
            if (selected + 1 < vis.items.len) selected += 1;
            continue;
        }
        if (k.kind == .up) {
            if (selected > 0) selected -= 1;
            continue;
        }
        if (k.kind != .char) continue;
        const ch = k.ch;
        if (ch == 'j') {
            if (selected + 1 < vis.items.len) selected += 1;
        } else if (ch == 'k') {
            if (selected > 0) selected -= 1;
        } else if (ch == 'g') {
            selected = 0;
        } else if (ch == 'G') {
            if (vis.items.len > 0) selected = vis.items.len - 1;
        } else if (ch == ' ') {
            if (vis.items.len > 0) {
                const idx = vis.items[selected];
                tasks.items[idx].done = !tasks.items[idx].done;
                try saveTasks();
                alloc.free(status);
                status = try alloc.dupe(u8, if (tasks.items[idx].done) "Marked done" else "Marked todo");
            }
        } else if (ch == 'a') {
            const s = (try promptInput("Add:")) orelse {
                alloc.free(status);
                status = try alloc.dupe(u8, "Add cancelled - press q or Esc to quit");
                continue;
            };
            defer alloc.free(s);
            if (s.len > 0) {
                const nt = try parseAddText(s);
                try tasks.append(nt);
                try saveTasks();
                selected = tasks.items.len - 1;
                alloc.free(status);
                status = try std.fmt.allocPrint(alloc, "Added: {s}", .{nt.text});
            } else {
                alloc.free(status);
                status = try alloc.dupe(u8, "Add cancelled - press q or Esc to quit");
            }
        } else if (ch == 'e') {
            if (vis.items.len > 0) {
                const idx = vis.items[selected];
                const old = tasks.items[idx];
                const prompt = try std.fmt.allocPrint(alloc, "Edit [{s}]:", .{old.text});
                defer alloc.free(prompt);
                const s = (try promptInput(prompt)) orelse continue;
                defer alloc.free(s);
                if (s.len > 0) {
                    var nt = try parseAddText(s);
                    if (nt.priority.len == 0) nt.priority = old.priority;
                    if (nt.due.len == 0) nt.due = old.due;
                    nt.done = old.done;
                    tasks.items[idx] = nt;
                    try saveTasks();
                    alloc.free(status);
                    status = try alloc.dupe(u8, "Edited");
                }
            }
        } else if (ch == 'd') {
            if (vis.items.len > 0) {
                const idx = vis.items[selected];
                const removed = tasks.items[idx].text;
                _ = tasks.orderedRemove(idx);
                try saveTasks();
                alloc.free(status);
                status = try std.fmt.allocPrint(alloc, "Deleted: {s}", .{removed});
                if (selected >= vis.items.len and selected > 0) selected -= 1;
                if (selected > 0 and vis.items.len == 0) selected = 0;
            }
        } else if (ch == '/') {
            const s = (try promptInput("Search:")) orelse continue;
            alloc.free(search);
            search = s;
            selected = 0;
            alloc.free(status);
            if (search.len > 0) {
                status = try std.fmt.allocPrint(alloc, "Search: {s}", .{search});
            } else {
                status = try alloc.dupe(u8, "Search cleared - press q or Esc to quit");
            }
        } else if (ch == 'f') {
            filter_idx = (filter_idx + 1) % filters.len;
            selected = 0;
            alloc.free(status);
            status = try std.fmt.allocPrint(alloc, "Filter: {s}", .{filters[filter_idx]});
        } else if (ch == 'u') {
            if (std.fs.cwd().access(BACKUP_FILE, .{})) {
                std.fs.cwd().copyFile(BACKUP_FILE, std.fs.cwd(), TASKS_FILE, .{}) catch {};
                try loadTasks();
                alloc.free(status);
                status = try alloc.dupe(u8, "Undone");
            } else |_| {
                alloc.free(status);
                status = try alloc.dupe(u8, "No backup to undo");
            }
        } else if (ch == 'c') {
            const before = tasks.items.len;
            var i: usize = 0;
            while (i < tasks.items.len) {
                if (tasks.items[i].done) {
                    _ = tasks.orderedRemove(i);
                } else i += 1;
            }
            try saveTasks();
            alloc.free(status);
            status = try std.fmt.allocPrint(alloc, "Cleared {d} done", .{before - tasks.items.len});
            selected = 0;
        } else if (ch == 's') {
            const tot = tasks.items.len;
            const dn = countDone();
            const ov = try countOverdue();
            alloc.free(status);
            status = try std.fmt.allocPrint(alloc, "Total {d} - Done {d} - Todo {d} - Overdue {d}", .{ tot, dn, tot - dn, ov });
        } else if (ch == '?') {
            alloc.free(status);
            status = try alloc.dupe(u8, "Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats");
        }
    }
    try stdout.print("\n", .{});
}

fn printHelp(writer: anytype) !void {
    try writer.print(
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
        \\TUI keys: j/k or arrows move, Space toggle, a add, e edit, d delete,
        \\  / search, f filter, u undo, c clear done, s stats, q / Esc / Ctrl-C to quit
        \\  In a prompt: Enter saves, Esc / Ctrl-C cancels
        \\
    , .{});
}

pub fn main() !void {
    alloc = gpa.allocator();
    tasks = std.ArrayList(Task).init(alloc);
    defer {
        tasks.deinit();
        _ = gpa.deinit();
    }
    try loadTasks();
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    const stdout = std.io.getStdOut().writer();
    if (args.len < 2 or std.mem.eql(u8, args[1], "tui")) {
        try runTui();
        try stdout.print("Exited TUI - back to shell. Use: ./tasks list\n", .{});
        return;
    }
    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        try printHelp(stdout);
    } else if (std.mem.eql(u8, cmd, "add")) {
        var priority: []const u8 = "";
        var due: []const u8 = "";
        var parts = std.ArrayList([]const u8).init(alloc);
        defer parts.deinit();
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--priority") and i + 1 < args.len) { priority = args[i + 1]; i += 1; continue; }
            if (std.mem.eql(u8, args[i], "--due") and i + 1 < args.len) { due = args[i + 1]; i += 1; continue; }
            try parts.append(args[i]);
        }
        const buf = try std.mem.join(alloc, " ", parts.items);
        defer alloc.free(buf);
        if (trimS(buf).len == 0) { try stdout.print("Usage: tasks add <text>\n", .{}); return; }
        var t = try parseAddText(buf);
        if (priority.len > 0) t.priority = try alloc.dupe(u8, priority);
        if (due.len > 0) t.due = try alloc.dupe(u8, due);
        try tasks.append(t);
        try saveTasks();
        try stdout.print("Added: {s}\n", .{t.text});
    } else if (std.mem.eql(u8, cmd, "list")) {
        try cliList(args[2..]);
    } else if (std.mem.eql(u8, cmd, "done")) {
        if (args.len < 3) { try stdout.print("Usage: tasks done <n>\n", .{}); return; }
        const idx = parseTaskNumber(args[2], tasks.items.len) orelse {
            try stdout.print("Invalid task number\n", .{});
            return;
        };
        tasks.items[idx].done = true;
        try saveTasks();
        try stdout.print("Done: {s}\n", .{tasks.items[idx].text});
    } else if (std.mem.eql(u8, cmd, "undone")) {
        if (args.len < 3) { try stdout.print("Usage: tasks undone <n>\n", .{}); return; }
        const idx = parseTaskNumber(args[2], tasks.items.len) orelse {
            try stdout.print("Invalid task number\n", .{});
            return;
        };
        tasks.items[idx].done = false;
        try saveTasks();
        try stdout.print("Todo: {s}\n", .{tasks.items[idx].text});
    } else if (std.mem.eql(u8, cmd, "rm")) {
        if (args.len < 3) { try stdout.print("Usage: tasks rm <n>\n", .{}); return; }
        const idx = parseTaskNumber(args[2], tasks.items.len) orelse {
            try stdout.print("Invalid task number\n", .{});
            return;
        };
        const removed = tasks.items[idx].text;
        _ = tasks.orderedRemove(idx);
        try saveTasks();
        try stdout.print("Deleted: {s}\n", .{removed});
    } else if (std.mem.eql(u8, cmd, "edit")) {
        if (args.len < 4) { try stdout.print("Usage: tasks edit <n> <new text>\n", .{}); return; }
        const idx = parseTaskNumber(args[2], tasks.items.len) orelse {
            try stdout.print("Invalid task number\n", .{});
            return;
        };
        const joined = try std.mem.join(alloc, " ", args[3..]);
        defer alloc.free(joined);
        var nt = try parseAddText(joined);
        const old = tasks.items[idx];
        if (nt.priority.len == 0) nt.priority = old.priority;
        if (nt.due.len == 0) nt.due = old.due;
        nt.done = old.done;
        tasks.items[idx] = nt;
        try saveTasks();
        try stdout.print("Edited {d}: {s}\n", .{ idx + 1, nt.text });
    } else if (std.mem.eql(u8, cmd, "search")) {
        if (args.len < 3) { try stdout.print("Usage: tasks search <query>\n", .{}); return; }
        const q = try std.mem.join(alloc, " ", args[2..]);
        defer alloc.free(q);
        var found = false;
        for (tasks.items, 0..) |t, i| {
            if (try matchesSearch(t, q)) {
                try printTask(stdout, i, t);
                found = true;
            }
        }
        if (!found) try stdout.print("No matches.\n", .{});
    } else if (std.mem.eql(u8, cmd, "clear")) {
        const before = tasks.items.len;
        var i: usize = 0;
        while (i < tasks.items.len) {
            if (tasks.items[i].done) {
                _ = tasks.orderedRemove(i);
            } else i += 1;
        }
        try saveTasks();
        try stdout.print("Cleared {d} done tasks\n", .{before - tasks.items.len});
    } else if (std.mem.eql(u8, cmd, "stats")) {
        const total = tasks.items.len;
        const done_n = countDone();
        const over_n = try countOverdue();
        var today_n: usize = 0;
        for (tasks.items) |t| if (!t.done and try isToday(t)) today_n += 1;
        try stdout.print("Total: {d}\nDone: {d}\nTodo: {d}\nOverdue: {d}\nDue today: {d}\n", .{ total, done_n, total - done_n, over_n, today_n });
        var c1: usize = 0;
        var c2: usize = 0;
        var c3: usize = 0;
        for (tasks.items) |t| {
            if (std.mem.eql(u8, t.priority, "P1")) c1 += 1;
            if (std.mem.eql(u8, t.priority, "P2")) c2 += 1;
            if (std.mem.eql(u8, t.priority, "P3")) c3 += 1;
        }
        if (c1 > 0 or c2 > 0 or c3 > 0) {
            try stdout.print("By priority:\n", .{});
            if (c1 > 0) try stdout.print("  P1: {d}\n", .{c1});
            if (c2 > 0) try stdout.print("  P2: {d}\n", .{c2});
            if (c3 > 0) try stdout.print("  P3: {d}\n", .{c3});
        }
    } else if (std.mem.eql(u8, cmd, "undo")) {
        if (std.fs.cwd().access(BACKUP_FILE, .{})) {
            std.fs.cwd().copyFile(BACKUP_FILE, std.fs.cwd(), TASKS_FILE, .{}) catch {};
            try stdout.print("Undone - restored from backup\n", .{});
        } else |_| {
            try stdout.print("No backup to undo\n", .{});
        }
    } else {
        try stdout.print("Unknown command: {s}\n", .{cmd});
        try printHelp(stdout);
    }
}
