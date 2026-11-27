const std = @import("std");

const TASKS_FILE = "tasks.md";

const HELP =
    \\Usage: tasks <command> [args]
    \\
    \\Commands:
    \\  add "Buy milk"   Add a task
    \\  list             Show all tasks
    \\  done 2           Mark task 2 complete
    \\  rm 2             Delete task 2
    \\  clear            Remove completed tasks
    \\  stats            Show totals
    \\
;

const Task = struct {
    done: bool,
    text: []const u8,
};

fn loadTasks(allocator: std.mem.Allocator) !std.ArrayList(Task) {
    var tasks = std.ArrayList(Task).init(allocator);
    const contents = std.fs.cwd().readFileAlloc(allocator, TASKS_FILE, 1 << 20) catch |err| switch (err) {
        error.FileNotFound => return tasks,
        else => return err,
    };
    defer allocator.free(contents);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimRight(u8, raw, "\r");
        if (std.mem.startsWith(u8, line, "- [ ] ")) {
            const text = try allocator.dupe(u8, line[6..]);
            try tasks.append(.{ .done = false, .text = text });
        } else if (std.mem.startsWith(u8, line, "- [x] ")) {
            const text = try allocator.dupe(u8, line[6..]);
            try tasks.append(.{ .done = true, .text = text });
        }
    }
    return tasks;
}

fn saveTasks(tasks: []Task) !void {
    var file = try std.fs.cwd().createFile(TASKS_FILE, .{});
    defer file.close();
    var writer = file.writer();
    for (tasks) |t| {
        const prefix: []const u8 = if (t.done) "- [x] " else "- [ ] ";
        try writer.print("{s}{s}\n", .{ prefix, t.text });
    }
}

fn parseTaskNumber(s: []const u8, count: usize) ?usize {
    const n = std.fmt.parseInt(usize, s, 10) catch return null;
    if (n < 1 or n > count) return null;
    return n - 1;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    var tasks = try loadTasks(allocator);

    if (args.len < 2 or std.mem.eql(u8, args[1], "help") or std.mem.eql(u8, args[1], "-h") or std.mem.eql(u8, args[1], "--help")) {
        std.debug.print("{s}", .{HELP});
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "add")) {
        if (args.len < 3) {
            std.debug.print("Error: task text is required.\n", .{});
            return;
        }
        const text = try std.mem.join(allocator, " ", args[2..]);
        if (std.mem.trim(u8, text, " \t").len == 0) {
            std.debug.print("Error: task text is required.\n", .{});
            return;
        }
        const owned = try allocator.dupe(u8, text);
        try tasks.append(.{ .done = false, .text = owned });
        try saveTasks(tasks.items);
        std.debug.print("Added: {s}\n", .{text});
        return;
    }

    if (std.mem.eql(u8, command, "list")) {
        if (tasks.items.len == 0) {
            std.debug.print("No tasks yet.\n", .{});
            return;
        }
        for (tasks.items, 0..) |t, i| {
            const mark: u8 = if (t.done) 'x' else ' ';
            std.debug.print("{d}. [{c}] {s}\n", .{ i + 1, mark, t.text });
        }
        return;
    }

    if (std.mem.eql(u8, command, "done")) {
        if (args.len < 3) {
            std.debug.print("Error: invalid task number.\n", .{});
            return;
        }
        const idx = parseTaskNumber(args[2], tasks.items.len) orelse {
            std.debug.print("Error: invalid task number.\n", .{});
            return;
        };
        tasks.items[idx].done = true;
        try saveTasks(tasks.items);
        std.debug.print("Done: {s}\n", .{tasks.items[idx].text});
        return;
    }

    if (std.mem.eql(u8, command, "rm")) {
        if (args.len < 3) {
            std.debug.print("Error: invalid task number.\n", .{});
            return;
        }
        const idx = parseTaskNumber(args[2], tasks.items.len) orelse {
            std.debug.print("Error: invalid task number.\n", .{});
            return;
        };
        const removed = tasks.items[idx];
        _ = tasks.orderedRemove(idx);
        try saveTasks(tasks.items);
        std.debug.print("Removed: {s}\n", .{removed.text});
        return;
    }

    if (std.mem.eql(u8, command, "clear")) {
        const before = tasks.items.len;
        var kept = std.ArrayList(Task).init(allocator);
        for (tasks.items) |t| {
            if (!t.done) try kept.append(t);
        }
        const cleared = before - kept.items.len;
        tasks.clearRetainingCapacity();
        try tasks.appendSlice(kept.items);
        try saveTasks(tasks.items);
        std.debug.print("Cleared {d} completed task(s).\n", .{cleared});
        return;
    }

    if (std.mem.eql(u8, command, "stats")) {
        const total = tasks.items.len;
        var done: usize = 0;
        for (tasks.items) |t| {
            if (t.done) done += 1;
        }
        const remaining = total - done;
        std.debug.print("Total: {d} | Done: {d} | Remaining: {d}\n", .{ total, done, remaining });
        return;
    }

    std.debug.print("Error: unknown command '{s}'.\n", .{command});
    std.debug.print("{s}", .{HELP});
}
