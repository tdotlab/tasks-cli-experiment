// Tasks.java - Todo CLI v2 (Java, stdlib only, no dependencies)
// Same spec + same tasks.md as Python / C / C++ / Go / Zig / TypeScript / JavaScript / C# / Rust v2.
// Compile: javac Tasks.java
// Run: java Tasks  |  java Tasks list  |  java Tasks add "Buy milk #home"
// Or: java Tasks tui

import java.io.*;
import java.nio.file.*;
import java.time.LocalDate;
import java.util.*;
import java.util.concurrent.*;

public class Tasks {
    static final String TASKS_FILE = "tasks.md";
    static final String BACKUP_FILE = "tasks.md.bak";
    static final int MAX_INPUT = 4096;

    static class Task {
        boolean done = false;
        String priority = ""; // "P1", "P2", "P3" or ""
        String due = "";      // "YYYY-MM-DD" or ""
        String text = "";
        Task() {}
        Task(Task o) { done = o.done; priority = o.priority; due = o.due; text = o.text; }
    }

    static List<Task> tasks = new ArrayList<>();

    // ---------- helpers ----------
    static String trim(String s) { return s.trim(); }
    static String collapseSpaces(String s) {
        return String.join(" ", s.trim().split("\\s+")).trim();
    }
    static String todayStr() {
        try { return LocalDate.now().toString(); } catch (Exception e) { return "1970-01-01"; }
    }
    static boolean isOverdue(Task t) { return !t.due.isEmpty() && t.due.compareTo(todayStr()) < 0; }
    static boolean isToday(Task t) { return !t.due.isEmpty() && t.due.equals(todayStr()); }

    // ---------- parsing / formatting ----------
    static Task parseLine(String line) {
        if (!line.startsWith("- [")) return null;
        if (line.length() < 5) return null;
        char mark = line.charAt(3);
        if (mark != ' ' && mark != 'x') return null;
        if (line.charAt(4) != ']') return null;
        Task t = new Task();
        t.done = mark == 'x';
        String rest = trim(line.substring(5));
        if (rest.startsWith("(P1)") || rest.startsWith("(P2)") || rest.startsWith("(P3)")) {
            t.priority = rest.substring(1, 3);
            rest = trim(rest.substring(4));
        }
        if (rest.startsWith("due:") && rest.length() >= 14) {
            String d = rest.substring(4, 14);
            if (d.length() == 10 && d.charAt(4) == '-' && d.charAt(7) == '-') {
                t.due = d;
                rest = trim(rest.substring(14));
            }
        }
        t.text = trim(rest);
        return t;
    }

    static String formatTask(Task t) {
        StringBuilder sb = new StringBuilder();
        sb.append("- [").append(t.done ? "x" : " ").append("]");
        if (!t.priority.isEmpty()) sb.append(" (").append(t.priority).append(")");
        if (!t.due.isEmpty()) sb.append(" due:").append(t.due);
        sb.append(" ").append(t.text);
        return sb.toString();
    }

    static void loadTasks() {
        tasks.clear();
        Path p = Paths.get(TASKS_FILE);
        if (!Files.exists(p)) return;
        try {
            for (String raw : Files.readAllLines(p)) {
                String line = raw.replaceAll("\\r$", "");
                if (trim(line).isEmpty()) continue;
                Task t = parseLine(line);
                if (t != null) tasks.add(t);
            }
        } catch (Exception e) {}
    }

    static boolean copyFile(String src, String dst) {
        try { Files.copy(Paths.get(src), Paths.get(dst), StandardCopyOption.REPLACE_EXISTING); return true; }
        catch (Exception e) { return false; }
    }

    static void saveTasks() {
        if (Files.exists(Paths.get(TASKS_FILE))) copyFile(TASKS_FILE, BACKUP_FILE);
        try {
            List<String> out = new ArrayList<>();
            for (Task t : tasks) out.add(formatTask(t));
            Files.write(Paths.get(TASKS_FILE), out);
        } catch (Exception e) {}
    }

    static Task parseAddText(String full) {
        Task t = new Task();
        String text = trim(full);
        if (text.startsWith("P1 ") || text.startsWith("P2 ") || text.startsWith("P3 ")) {
            t.priority = text.substring(0, 2);
            text = trim(text.substring(3));
        } else if (text.startsWith("(P1)") || text.startsWith("(P2)") || text.startsWith("(P3)")) {
            t.priority = text.substring(1, 3);
            text = trim(text.substring(4));
        }
        int pos = text.indexOf("due:");
        if (pos >= 0 && text.length() >= pos + 14) {
            String cand = text.substring(pos + 4, pos + 14);
            if (cand.length() == 10 && cand.charAt(4) == '-' && cand.charAt(7) == '-') {
                t.due = cand;
                String before = trim(text.substring(0, pos));
                String after = trim(text.substring(pos + 14));
                text = trim((before + " " + after).trim());
            }
        }
        t.text = collapseSpaces(text);
        return t;
    }

    static int parseTaskNumber(String s, int n) {
        try {
            int v = Integer.parseInt(trim(s));
            if (v < 1 || v > n) return -1;
            return v - 1;
        } catch (Exception e) { return -1; }
    }

    static boolean matchesMode(Task t, String mode) {
        switch (mode) {
            case "todo": return !t.done;
            case "done": return t.done;
            case "overdue": return !t.done && isOverdue(t);
            case "today": return !t.done && isToday(t);
            default: return true;
        }
    }

    static boolean matchesSearch(Task t, String q) {
        if (q == null || q.isEmpty()) return true;
        return t.text.toLowerCase().contains(q.toLowerCase());
    }

    static List<Integer> filteredIndices(String mode, String search) {
        List<Integer> out = new ArrayList<>();
        for (int i = 0; i < tasks.size(); i++) {
            if (!matchesMode(tasks.get(i), mode)) continue;
            if (!matchesSearch(tasks.get(i), search)) continue;
            out.add(i);
        }
        return out;
    }

    static int countDone() {
        int c = 0; for (Task t : tasks) if (t.done) c++; return c;
    }
    static int countOverdue() {
        int c = 0; for (Task t : tasks) if (!t.done && isOverdue(t)) c++; return c;
    }

    static boolean hasTag(Task t, String tag) {
        String want = tag.startsWith("#") ? tag.substring(1) : tag;
        for (String tok : t.text.split("\\s+")) {
            if (tok.length() > 1 && tok.charAt(0) == '#') {
                if (tok.equals(tag) || tok.substring(1).equals(want)) return true;
            }
        }
        return false;
    }

    static boolean hasProject(Task t, String proj) {
        String want = proj.startsWith("+") ? proj.substring(1) : proj;
        for (String tok : t.text.split("\\s+")) {
            if (tok.length() > 1 && tok.charAt(0) == '+') {
                if (tok.equals(proj) || tok.substring(1).equals(want)) return true;
            }
        }
        return false;
    }

    static void printTask(int idx, Task t) {
        char mark = t.done ? 'x' : ' ';
        StringBuilder s = new StringBuilder();
        s.append(idx + 1).append(". [").append(mark).append("] ");
        if (!t.priority.isEmpty()) s.append(t.priority).append(" ");
        if (!t.due.isEmpty()) s.append(t.due).append(" ");
        s.append(t.text);
        System.out.println(s);
    }

    static void cliList(String[] args) {
        String tag = "", project = "", priority = "", search = "", mode = "all";
        for (int i = 0; i < args.length; i++) {
            String a = args[i];
            if (a.equals("--tag") && i + 1 < args.length) { tag = args[++i]; continue; }
            if (a.equals("--project") && i + 1 < args.length) { project = args[++i]; continue; }
            if (a.equals("--priority") && i + 1 < args.length) { priority = args[++i]; continue; }
            if (a.equals("--search") && i + 1 < args.length) { search = args[++i]; continue; }
            if (a.equals("--overdue")) mode = "overdue";
            else if (a.equals("--today")) mode = "today";
            else if (a.equals("--done")) mode = "done";
            else if (a.equals("--todo")) mode = "todo";
        }
        int shown = 0;
        for (int idx : filteredIndices(mode, search)) {
            Task t = tasks.get(idx);
            if (!tag.isEmpty() && !hasTag(t, tag)) continue;
            if (!project.isEmpty() && !hasProject(t, project)) continue;
            if (!priority.isEmpty() && !t.priority.equals(priority)) continue;
            printTask(idx, t);
            shown++;
        }
        if (shown == 0) System.out.println("No tasks.");
    }

    // [STRIPPED 77 bytes] TUI - AUDITED FIXES (same as C / C++ / JS / C# / Rust / Python / Go / Zig / TS)
    // 1. Prompt has NO small char limit: reads bytes one-by-one in raw mode into
    //    a growing StringBuilder, 4096 cap, horizontal scroll. No fixed
    //    char[64]/[256] buffer, no Scanner.nextLine() with width truncation.
    // 2. Exit is explicit: q, Q, Esc, Ctrl-C, Ctrl-D, Ctrl-Q all quit from
    //    main list, footer always shows "q / Esc / Ctrl-C to quit". In a
    //    prompt, Enter saves, Esc / Ctrl-C cancels back to list.
    //    Raw mode is via `stty` (stdlib only, no JLine): original settings
    //    saved with `stty -g` and restored on exit, so terminal is not left broken.
    // [STRIPPED 75 bytes]

    static int[] getTermSize() {
        // `stty size` prints "rows cols"
        try {
            Process p = new ProcessBuilder("sh", "-c", "stty size < /dev/tty").start();
            String out = new String(p.getInputStream().readAllBytes()).trim();
            p.waitFor();
            String[] parts = out.split("\\s+");
            if (parts.length == 2) {
                int r = Integer.parseInt(parts[0]);
                int c = Integer.parseInt(parts[1]);
                if (r > 0 && c > 0) return new int[]{r, c};
            }
        } catch (Exception e) {}
        try {
            String lr = System.getenv("LINES");
            String lc = System.getenv("COLUMNS");
            if (lr != null && lc != null) {
                int r = Integer.parseInt(lr);
                int c = Integer.parseInt(lc);
                if (r > 0 && c > 0) return new int[]{r, c};
            }
        } catch (Exception e) {}
        return new int[]{24, 80};
    }

    static String sttyGet() {
        try {
            Process p = new ProcessBuilder("sh", "-c", "stty -g < /dev/tty").start();
            String out = new String(p.getInputStream().readAllBytes()).trim();
            p.waitFor();
            return out;
        } catch (Exception e) { return ""; }
    }

    static void sttySet(String args) {
        try {
            Process p = new ProcessBuilder("sh", "-c", "stty " + args + " < /dev/tty").start();
            p.waitFor();
        } catch (Exception e) {}
    }

    static String enableRaw() {
        String orig = sttyGet();
        sttySet("raw -echo -isig");
        return orig;
    }

    static void disableRaw(String orig) {
        if (orig != null && !orig.isEmpty()) sttySet(orig);
        else sttySet("sane");
        System.out.println();
    }

    // Byte reader: background thread pushes stdin bytes into a queue,
    // so readByteTimeout() can wait 30ms for Esc sequences.
    static class ByteReader {
        BlockingQueue<Integer> q = new LinkedBlockingQueue<>();
        ByteReader() {
            Thread th = new Thread(() -> {
                try {
                    InputStream in = System.in;
                    int b;
                    while ((b = in.read()) != -1) {
                        q.put(b);
                    }
                } catch (Exception e) {}
            });
            th.setDaemon(true);
            th.start();
        }
        Integer readByte() {
            try { return q.take(); } catch (Exception e) { return null; }
        }
        Integer readByteTimeout(long ms) {
            try { return q.poll(ms, TimeUnit.MILLISECONDS); } catch (Exception e) { return null; }
        }
    }

    enum KeyKind { CHAR, ESC, UP, DOWN, LEFT, RIGHT, HOME, END, DEL, ENTER, BACKSPACE, CTRL_C, CTRL_D, CTRL_Q, CTRL_A, CTRL_E, CTRL_U, CTRL_K, CTRL_W, OTHER }
    static class Key {
        KeyKind kind;
        char ch;
        Key(KeyKind k) { kind = k; }
        Key(char c) { kind = KeyKind.CHAR; ch = c; }
    }

    static char decodeUtf8Char(int first, ByteReader r) {
        if (first < 0x80) return (char) first;
        int need;
        if (first >= 0xC2 && first <= 0xDF) need = 1;
        else if (first >= 0xE0 && first <= 0xEF) need = 2;
        else if (first >= 0xF0 && first <= 0xF4) need = 3;
        else return '\uFFFD';
        byte[] bytes = new byte[need + 1];
        bytes[0] = (byte) first;
        for (int i = 0; i < need; i++) {
            Integer b = r.readByteTimeout(30);
            if (b == null) break;
            bytes[i + 1] = b.byteValue();
        }
        try { return new String(bytes, "UTF-8").charAt(0); }
        catch (Exception e) { return '\uFFFD'; }
    }

    static Key readKey(ByteReader r) {
        Integer bb = r.readByte();
        if (bb == null) return new Key(KeyKind.OTHER);
        int b = bb;
        if (b == 13 || b == 10) return new Key(KeyKind.ENTER);
        if (b == 3) return new Key(KeyKind.CTRL_C);
        if (b == 4) return new Key(KeyKind.CTRL_D);
        if (b == 17) return new Key(KeyKind.CTRL_Q);
        if (b == 1) return new Key(KeyKind.CTRL_A);
        if (b == 5) return new Key(KeyKind.CTRL_E);
        if (b == 21) return new Key(KeyKind.CTRL_U);
        if (b == 11) return new Key(KeyKind.CTRL_K);
        if (b == 23) return new Key(KeyKind.CTRL_W);
        if (b == 127 || b == 8) return new Key(KeyKind.BACKSPACE);
        if (b == 27) {
            Integer b2 = r.readByteTimeout(30);
            if (b2 == null) return new Key(KeyKind.ESC);
            if (b2 != '[' && b2 != 'O') return new Key(KeyKind.ESC);
            Integer b3 = r.readByteTimeout(30);
            if (b3 == null) return new Key(KeyKind.ESC);
            if (b3 == 'A') return new Key(KeyKind.UP);
            if (b3 == 'B') return new Key(KeyKind.DOWN);
            if (b3 == 'C') return new Key(KeyKind.RIGHT);
            if (b3 == 'D') return new Key(KeyKind.LEFT);
            if (b3 == 'H') return new Key(KeyKind.HOME);
            if (b3 == 'F') return new Key(KeyKind.END);
            if (b3 == '3') { r.readByteTimeout(30); return new Key(KeyKind.DEL); }
            return new Key(KeyKind.ESC);
        }
        if (b >= 0x80) {
            char c = decodeUtf8Char(b, r);
            return new Key(c);
        }
        if (b >= 32) return new Key((char) b);
        return new Key(KeyKind.OTHER);
    }

    // promptInput: returns trimmed string or null if cancelled.
    // Dynamic StringBuilder, no small limit, 4096 cap, horizontal scroll.
    static String promptInput(ByteReader r, String label) {
        StringBuilder text = new StringBuilder();
        int cursor = 0; // char index
        int offset = 0;
        int labelLen = label.length() + 1; // label + space
        PrintStream out = System.out;
        while (true) {
            int[] sz = getTermSize();
            int rows = sz[0], cols = sz[1];
            int avail = cols - labelLen - 1;
            if (avail < 10) avail = 10;
            if (cursor < offset) offset = cursor;
            if (cursor >= offset + avail) offset = cursor - avail + 1;
            out.print("\u001b[" + (rows - 1) + ";1H\u001b[2KEnter=save  Esc / Ctrl-C=cancel");
            out.print("\u001b[" + rows + ";1H\u001b[2K");
            out.print(label + " ");
            String full = text.toString();
            int end = Math.min(offset + avail, full.length());
            if (offset < full.length()) out.print(full.substring(offset, end));
            int cursorX = labelLen + (cursor - offset) + 1;
            if (cursorX > cols) cursorX = cols;
            out.print("\u001b[" + rows + ";" + cursorX + "H");
            out.flush();
            Key k = readKey(r);
            if (k.kind == KeyKind.ENTER) break;
            if (k.kind == KeyKind.ESC || k.kind == KeyKind.CTRL_C || k.kind == KeyKind.CTRL_D) return null;
            if (k.kind == KeyKind.BACKSPACE) {
                if (cursor > 0) { text.deleteCharAt(cursor - 1); cursor--; }
                continue;
            }
            if (k.kind == KeyKind.DEL) {
                if (cursor < text.length()) text.deleteCharAt(cursor);
                continue;
            }
            if (k.kind == KeyKind.LEFT) { if (cursor > 0) cursor--; continue; }
            if (k.kind == KeyKind.RIGHT) { if (cursor < text.length()) cursor++; continue; }
            if (k.kind == KeyKind.HOME || k.kind == KeyKind.CTRL_A) { cursor = 0; continue; }
            if (k.kind == KeyKind.END || k.kind == KeyKind.CTRL_E) { cursor = text.length(); continue; }
            if (k.kind == KeyKind.CTRL_U) { text.setLength(0); cursor = 0; offset = 0; continue; }
            if (k.kind == KeyKind.CTRL_K) { text.setLength(cursor); continue; }
            if (k.kind == KeyKind.CTRL_W) {
                while (cursor > 0 && text.charAt(cursor - 1) == ' ') { text.deleteCharAt(cursor - 1); cursor--; }
                while (cursor > 0 && text.charAt(cursor - 1) != ' ') { text.deleteCharAt(cursor - 1); cursor--; }
                continue;
            }
            if (k.kind == KeyKind.UP || k.kind == KeyKind.DOWN) continue;
            if (k.kind == KeyKind.CHAR) {
                if (text.length() < MAX_INPUT) { text.insert(cursor, k.ch); cursor++; }
                continue;
            }
        }
        return trim(text.toString());
    }

    static void runTui() {
        String orig = enableRaw();
        ByteReader reader = new ByteReader();
        int selected = 0;
        String[] filters = {"all", "todo", "done", "overdue", "today"};
        int filterIdx = 0;
        String search = "";
        String status = "Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter";
        PrintStream out = System.out;
        try {
            while (true) {
                int[] sz = getTermSize();
                int rows = sz[0], cols = sz[1];
                String filterMode = filters[filterIdx];
                List<Integer> visible = filteredIndices(filterMode, search);
                if (visible.isEmpty()) selected = 0;
                else {
                    if (selected >= visible.size()) selected = visible.size() - 1;
                    if (selected < 0) selected = 0;
                }
                out.print("\u001b[2J\u001b[H");
                int total = tasks.size();
                int doneN = countDone();
                int overdueN = countOverdue();
                out.println("tasks - " + total + " total | " + doneN + " done | " + overdueN + " overdue | filter: " + filterMode + " | search: " + search);
                out.println("#    []  P    Due         Text");
                StringBuilder dash = new StringBuilder();
                for (int i = 0; i < Math.min(80, cols); i++) dash.append("-");
                out.println(dash);
                int maxRows = Math.max(5, rows - 5);
                for (int i = 0; i < visible.size() && i < maxRows; i++) {
                    int idx = visible.get(i);
                    Task t = tasks.get(idx);
                    char mark = t.done ? 'x' : ' ';
                    StringBuilder line = new StringBuilder();
                    line.append(String.format("%-4d", idx + 1)).append(" [").append(mark).append("] ");
                    if (!t.priority.isEmpty()) line.append("(").append(t.priority).append(") ");
                    if (!t.due.isEmpty()) line.append("due:").append(t.due).append(" ");
                    line.append(t.text);
                    String ls = line.toString();
                    if (ls.length() > cols) ls = ls.substring(0, Math.max(0, cols));
                    if (i == selected) out.println("\u001b[7m" + ls + "\u001b[0m");
                    else if (t.done) out.println("\u001b[2m" + ls + "\u001b[0m");
                    else out.println(ls);
                }
                out.print("\u001b[" + (rows - 1) + ";1H\u001b[2K" + status);
                out.print("\u001b[" + rows + ";1H\u001b[2K");
                out.print("q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats");
                out.print("\u001b[" + rows + ";1H");
                out.flush();
                Key k = readKey(reader);
                // EXIT - checked FIRST, from main list view
                if (k.kind == KeyKind.ESC || k.kind == KeyKind.CTRL_C || k.kind == KeyKind.CTRL_D || k.kind == KeyKind.CTRL_Q) break;
                if (k.kind == KeyKind.CHAR && (k.ch == 'q' || k.ch == 'Q')) break;

                if ((k.kind == KeyKind.CHAR && k.ch == 'j') || k.kind == KeyKind.DOWN) { if (selected + 1 < visible.size()) selected++; continue; }
                if ((k.kind == KeyKind.CHAR && k.ch == 'k') || k.kind == KeyKind.UP) { if (selected > 0) selected--; continue; }
                if (k.kind == KeyKind.CHAR && k.ch == 'g') { selected = 0; continue; }
                if (k.kind == KeyKind.CHAR && k.ch == 'G') { if (!visible.isEmpty()) selected = visible.size() - 1; continue; }
                if (k.kind == KeyKind.CHAR && k.ch == ' ') {
                    if (!visible.isEmpty()) {
                        int idx = visible.get(selected);
                        tasks.get(idx).done = !tasks.get(idx).done;
                        saveTasks();
                        status = tasks.get(idx).done ? "Marked done" : "Marked todo";
                    }
                    continue;
                }
                if (k.kind == KeyKind.CHAR && k.ch == 'a') {
                    String s = promptInput(reader, "Add:");
                    if (s != null && !s.isEmpty()) {
                        Task nt = parseAddText(s);
                        tasks.add(nt);
                        saveTasks();
                        selected = tasks.size() - 1;
                        status = "Added: " + nt.text;
                    } else status = "Add cancelled - press q or Esc to quit";
                    continue;
                }
                if (k.kind == KeyKind.CHAR && k.ch == 'e') {
                    if (!visible.isEmpty()) {
                        int idx = visible.get(selected);
                        Task old = tasks.get(idx);
                        String s = promptInput(reader, "Edit [" + old.text + "]:");
                        if (s != null && !s.isEmpty()) {
                            Task nt = parseAddText(s);
                            if (nt.priority.isEmpty()) nt.priority = old.priority;
                            if (nt.due.isEmpty()) nt.due = old.due;
                            nt.done = old.done;
                            tasks.set(idx, nt);
                            saveTasks();
                            status = "Edited";
                        }
                    }
                    continue;
                }
                if (k.kind == KeyKind.CHAR && k.ch == 'd') {
                    if (!visible.isEmpty()) {
                        int idx = visible.get(selected);
                        String removed = tasks.get(idx).text;
                        tasks.remove(idx);
                        saveTasks();
                        status = "Deleted: " + removed;
                        if (selected >= visible.size() - 1 && selected > 0) selected--;
                    }
                    continue;
                }
                if (k.kind == KeyKind.CHAR && k.ch == '/') {
                    String s = promptInput(reader, "Search:");
                    if (s != null) {
                        search = s;
                        selected = 0;
                        status = !search.isEmpty() ? "Search: " + search : "Search cleared - press q or Esc to quit";
                    }
                    continue;
                }
                if (k.kind == KeyKind.CHAR && k.ch == 'f') {
                    filterIdx = (filterIdx + 1) % filters.length;
                    selected = 0;
                    status = "Filter: " + filters[filterIdx];
                    continue;
                }
                if (k.kind == KeyKind.CHAR && k.ch == 'u') {
                    if (Files.exists(Paths.get(BACKUP_FILE))) {
                        copyFile(BACKUP_FILE, TASKS_FILE);
                        loadTasks();
                        status = "Undone";
                    } else status = "No backup to undo";
                    continue;
                }
                if (k.kind == KeyKind.CHAR && k.ch == 'c') {
                    int before = tasks.size();
                    tasks.removeIf(t -> t.done);
                    saveTasks();
                    status = "Cleared " + (before - tasks.size()) + " done";
                    selected = 0;
                    continue;
                }
                if (k.kind == KeyKind.CHAR && k.ch == 's') {
                    int total2 = tasks.size();
                    int doneN2 = countDone();
                    int overdueN2 = countOverdue();
                    status = "Total " + total2 + " - Done " + doneN2 + " - Todo " + (total2 - doneN2) + " - Overdue " + overdueN2;
                    continue;
                }
                if (k.kind == KeyKind.CHAR && k.ch == '?') {
                    status = "Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats";
                    continue;
                }
            }
        } finally {
            disableRaw(orig);
        }
    }

    static void printHelp() {
        System.out.println("Usage:");
        System.out.println("  tasks tui                    Interactive TUI (default, no args = tui)");
        System.out.println("  tasks add [--priority P1] [--due YYYY-MM-DD] <text>");
        System.out.println("  tasks list [--tag X] [--project Y] [--priority P1] [--search Q] [--overdue|--today|--done|--todo]");
        System.out.println("  tasks done <n>");
        System.out.println("  tasks undone <n>");
        System.out.println("  tasks rm <n>");
        System.out.println("  tasks edit <n> <new text>");
        System.out.println("  tasks search <query>");
        System.out.println("  tasks clear");
        System.out.println("  tasks stats");
        System.out.println("  tasks undo");
        System.out.println("  tasks help");
        System.out.println();
        System.out.println("Format: tasks.md lines are - [ ] (P1) due:2026-11-30 Buy milk #home +groceries");
        System.out.println("Tags start with #, projects with +. Priority P1/P2/P3, due YYYY-MM-DD.");
        System.out.println("TUI keys: j/k or arrows move, Space toggle, a add, e edit, d delete,");
        System.out.println("  / search, f filter, u undo, c clear done, s stats, q / Esc / Ctrl-C to quit");
        System.out.println("  In a prompt: Enter saves, Esc / Ctrl-C cancels");
    }

    public static void main(String[] args) {
        loadTasks();

        if (args.length == 0 || args[0].equals("tui")) {
            runTui();
            System.out.println("Exited TUI - back to shell. Use: java Tasks list");
            return;
        }

        String cmd = args[0];

        if (cmd.equals("help") || cmd.equals("--help") || cmd.equals("-h")) { printHelp(); return; }

        if (cmd.equals("add")) {
            String priority = "", due = "";
            List<String> parts = new ArrayList<>();
            for (int i = 1; i < args.length; i++) {
                if (args[i].equals("--priority") && i + 1 < args.length) { priority = args[++i]; continue; }
                if (args[i].equals("--due") && i + 1 < args.length) { due = args[++i]; continue; }
                parts.add(args[i]);
            }
            String buf = String.join(" ", parts);
            if (trim(buf).isEmpty()) { System.out.println("Usage: tasks add <text>"); return; }
            Task t = parseAddText(buf);
            if (!priority.isEmpty()) t.priority = priority;
            if (!due.isEmpty()) t.due = due;
            tasks.add(t);
            saveTasks();
            System.out.println("Added: " + t.text);
            return;
        }

        if (cmd.equals("list")) {
            cliList(Arrays.copyOfRange(args, 1, args.length));
            return;
        }

        if (cmd.equals("done")) {
            if (args.length < 2) { System.out.println("Usage: tasks done <n>"); return; }
            int idx = parseTaskNumber(args[1], tasks.size());
            if (idx == -1) { System.out.println("Invalid task number"); return; }
            tasks.get(idx).done = true;
            saveTasks();
            System.out.println("Done: " + tasks.get(idx).text);
            return;
        }

        if (cmd.equals("undone")) {
            if (args.length < 2) { System.out.println("Usage: tasks undone <n>"); return; }
            int idx = parseTaskNumber(args[1], tasks.size());
            if (idx == -1) { System.out.println("Invalid task number"); return; }
            tasks.get(idx).done = false;
            saveTasks();
            System.out.println("Todo: " + tasks.get(idx).text);
            return;
        }

        if (cmd.equals("rm")) {
            if (args.length < 2) { System.out.println("Usage: tasks rm <n>"); return; }
            int idx = parseTaskNumber(args[1], tasks.size());
            if (idx == -1) { System.out.println("Invalid task number"); return; }
            String removed = tasks.get(idx).text;
            tasks.remove(idx);
            saveTasks();
            System.out.println("Deleted: " + removed);
            return;
        }

        if (cmd.equals("edit")) {
            if (args.length < 3) { System.out.println("Usage: tasks edit <n> <new text>"); return; }
            int idx = parseTaskNumber(args[1], tasks.size());
            if (idx == -1) { System.out.println("Invalid task number"); return; }
            Task nt = parseAddText(String.join(" ", Arrays.copyOfRange(args, 2, args.length)));
            Task old = tasks.get(idx);
            if (nt.priority.isEmpty()) nt.priority = old.priority;
            if (nt.due.isEmpty()) nt.due = old.due;
            nt.done = old.done;
            tasks.set(idx, nt);
            saveTasks();
            System.out.println("Edited " + (idx + 1) + ": " + nt.text);
            return;
        }

        if (cmd.equals("search")) {
            if (args.length < 2) { System.out.println("Usage: tasks search <query>"); return; }
            String q = String.join(" ", Arrays.copyOfRange(args, 1, args.length));
            boolean found = false;
            for (int i = 0; i < tasks.size(); i++) {
                if (matchesSearch(tasks.get(i), q)) { printTask(i, tasks.get(i)); found = true; }
            }
            if (!found) System.out.println("No matches.");
            return;
        }

        if (cmd.equals("clear")) {
            int before = tasks.size();
            tasks.removeIf(t -> t.done);
            saveTasks();
            System.out.println("Cleared " + (before - tasks.size()) + " done tasks");
            return;
        }

        if (cmd.equals("stats")) {
            int total = tasks.size();
            int doneN = countDone();
            int overdueN = countOverdue();
            int todayN = 0; for (Task t : tasks) if (!t.done && isToday(t)) todayN++;
            System.out.println("Total: " + total + "\nDone: " + doneN + "\nTodo: " + (total - doneN) + "\nOverdue: " + overdueN + "\nDue today: " + todayN);
            int c1 = 0, c2 = 0, c3 = 0;
            for (Task t : tasks) { if (t.priority.equals("P1")) c1++; if (t.priority.equals("P2")) c2++; if (t.priority.equals("P3")) c3++; }
            if (c1 > 0 || c2 > 0 || c3 > 0) {
                System.out.println("By priority:");
                if (c1 > 0) System.out.println("  P1: " + c1);
                if (c2 > 0) System.out.println("  P2: " + c2);
                if (c3 > 0) System.out.println("  P3: " + c3);
            }
            Map<String,Integer> tagCounts = new TreeMap<>();
            for (Task t : tasks) {
                for (String tok : t.text.split("\\s+")) {
                    if (tok.length() > 1 && tok.charAt(0) == '#') tagCounts.put(tok, tagCounts.getOrDefault(tok, 0) + 1);
                }
            }
            if (!tagCounts.isEmpty()) {
                System.out.println("By tag:");
                for (Map.Entry<String,Integer> e : tagCounts.entrySet()) System.out.println("  " + e.getKey() + ": " + e.getValue());
            }
            return;
        }

        if (cmd.equals("undo")) {
            if (!Files.exists(Paths.get(BACKUP_FILE))) { System.out.println("No backup to undo"); return; }
            copyFile(BACKUP_FILE, TASKS_FILE);
            System.out.println("Undone - restored from backup");
            return;
        }

        System.out.println("Unknown command: " + cmd);
        printHelp();
    }
}
