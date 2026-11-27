// tasks.cs - Todo CLI v2 (C# / .NET 8, no dependencies)
// Same spec + same tasks.md as Python / C / C++ / Go / Zig / TypeScript / JavaScript v2.
// Run: dotnet run --project tasks.csproj  |  dotnet build  |  ./bin/Debug/net8.0/tasks
// Or:  dotnet run -- list  |  dotnet run -- add "Buy milk #home"

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

class Task
{
    public bool Done = false;
    public string Priority = ""; // "P1", "P2", "P3" or ""
    public string Due = "";       // "YYYY-MM-DD" or ""
    public string Text = "";
}

class Program
{
    const string TASKS_FILE = "tasks.md";
    const string BACKUP_FILE = "tasks.md.bak";
    const int MAX_INPUT = 4096;

    static List<Task> tasks = new List<Task>();
    static bool cancelRequested = false;

    // ---------- helpers ----------
    static string Trim(string s) => s.Trim();
    static string CollapseSpaces(string s)
    {
        var parts = s.Split(new[] { ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        return string.Join(" ", parts);
    }

    static string TodayStr() => DateTime.Now.ToString("yyyy-MM-dd");
    static bool IsOverdue(Task t) => t.Due != "" && string.CompareOrdinal(t.Due, TodayStr()) < 0;
    static bool IsToday(Task t) => t.Due != "" && t.Due == TodayStr();

    // ---------- parsing / formatting ----------
    static Task? ParseLine(string line)
    {
        if (!line.StartsWith("- [")) return null;
        if (line.Length < 5) return null;
        if (line[3] != ' ' && line[3] != 'x') return null;
        if (line[4] != ']') return null;
        var t = new Task { Done = line[3] == 'x' };
        string rest = Trim(line.Substring(5));
        if (rest.StartsWith("(P1)") || rest.StartsWith("(P2)") || rest.StartsWith("(P3)"))
        {
            t.Priority = rest.Substring(1, 2);
            rest = Trim(rest.Substring(4));
        }
        if (rest.StartsWith("due:") && rest.Length >= 14)
        {
            string d = rest.Substring(4, 10);
            if (d.Length == 10 && d[4] == '-' && d[7] == '-')
            {
                t.Due = d;
                rest = Trim(rest.Substring(14));
            }
        }
        t.Text = Trim(rest);
        return t;
    }

    static string FormatTask(Task t)
    {
        var sb = new StringBuilder();
        sb.Append("- [");
        sb.Append(t.Done ? "x" : " ");
        sb.Append("]");
        if (t.Priority != "") sb.Append(" (" + t.Priority + ")");
        if (t.Due != "") sb.Append(" due:" + t.Due);
        sb.Append(" " + t.Text);
        return sb.ToString();
    }

    static void LoadTasks()
    {
        tasks.Clear();
        if (!File.Exists(TASKS_FILE)) return;
        foreach (var raw in File.ReadAllLines(TASKS_FILE))
        {
            var line = raw.TrimEnd('\r');
            if (Trim(line) == "") continue;
            var t = ParseLine(line);
            if (t != null) tasks.Add(t);
        }
    }

    static bool CopyFile(string src, string dst)
    {
        try { File.Copy(src, dst, true); return true; } catch { return false; }
    }

    static void SaveTasks()
    {
        if (File.Exists(TASKS_FILE)) CopyFile(TASKS_FILE, BACKUP_FILE);
        File.WriteAllLines(TASKS_FILE, tasks.Select(FormatTask));
    }

    static Task ParseAddText(string full)
    {
        var t = new Task();
        string text = Trim(full);
        if (text.StartsWith("P1 ") || text.StartsWith("P2 ") || text.StartsWith("P3 "))
        {
            t.Priority = text.Substring(0, 2);
            text = Trim(text.Substring(3));
        }
        else if (text.StartsWith("(P1)") || text.StartsWith("(P2)") || text.StartsWith("(P3)"))
        {
            t.Priority = text.Substring(1, 2);
            text = Trim(text.Substring(4));
        }
        int pos = text.IndexOf("due:", StringComparison.Ordinal);
        if (pos >= 0 && text.Length >= pos + 14)
        {
            string cand = text.Substring(pos + 4, 10);
            if (cand.Length == 10 && cand[4] == '-' && cand[7] == '-')
            {
                t.Due = cand;
                string before = Trim(text.Substring(0, pos));
                string after = Trim(text.Substring(pos + 14));
                text = Trim(before + " " + after);
            }
        }
        t.Text = CollapseSpaces(text);
        return t;
    }

    static int ParseTaskNumber(string s, int n)
    {
        if (!int.TryParse(Trim(s), out int v)) return -1;
        if (v < 1 || v > n) return -1;
        return v - 1;
    }

    static bool MatchesMode(Task t, string mode)
    {
        if (mode == "todo") return !t.Done;
        if (mode == "done") return t.Done;
        if (mode == "overdue") return !t.Done && IsOverdue(t);
        if (mode == "today") return !t.Done && IsToday(t);
        return true;
    }

    static bool MatchesSearch(Task t, string q)
    {
        if (string.IsNullOrEmpty(q)) return true;
        return t.Text.ToLowerInvariant().Contains(q.ToLowerInvariant());
    }

    static List<int> FilteredIndices(string mode, string search)
    {
        var outList = new List<int>();
        for (int i = 0; i < tasks.Count; i++)
        {
            if (!MatchesMode(tasks[i], mode)) continue;
            if (!MatchesSearch(tasks[i], search)) continue;
            outList.Add(i);
        }
        return outList;
    }

    static int CountDone() => tasks.Count(t => t.Done);
    static int CountOverdue() => tasks.Count(t => !t.Done && IsOverdue(t));

    static bool HasTag(Task t, string tag)
    {
        string want = tag.StartsWith("#") ? tag.Substring(1) : tag;
        foreach (var tok in t.Text.Split(' ', StringSplitOptions.RemoveEmptyEntries))
        {
            if (tok.Length > 1 && tok[0] == '#')
            {
                if (tok == tag || tok.Substring(1) == want) return true;
            }
        }
        return false;
    }

    static bool HasProject(Task t, string proj)
    {
        string want = proj.StartsWith("+") ? proj.Substring(1) : proj;
        foreach (var tok in t.Text.Split(' ', StringSplitOptions.RemoveEmptyEntries))
        {
            if (tok.Length > 1 && tok[0] == '+')
            {
                if (tok == proj || tok.Substring(1) == want) return true;
            }
        }
        return false;
    }

    static void PrintTask(int idx, Task t)
    {
        char mark = t.Done ? 'x' : ' ';
        string s = $"{idx + 1}. [{mark}] ";
        if (t.Priority != "") s += t.Priority + " ";
        if (t.Due != "") s += t.Due + " ";
        s += t.Text;
        Console.WriteLine(s);
    }

    static void CliList(string[] args)
    {
        string tag = "", project = "", priority = "", search = "", mode = "all";
        for (int i = 0; i < args.Length; i++)
        {
            string a = args[i];
            if (a == "--tag" && i + 1 < args.Length) { tag = args[++i]; continue; }
            if (a == "--project" && i + 1 < args.Length) { project = args[++i]; continue; }
            if (a == "--priority" && i + 1 < args.Length) { priority = args[++i]; continue; }
            if (a == "--search" && i + 1 < args.Length) { search = args[++i]; continue; }
            if (a == "--overdue") mode = "overdue";
            else if (a == "--today") mode = "today";
            else if (a == "--done") mode = "done";
            else if (a == "--todo") mode = "todo";
        }
        int shown = 0;
        foreach (int idx in FilteredIndices(mode, search))
        {
            var t = tasks[idx];
            if (tag != "" && !HasTag(t, tag)) continue;
            if (project != "" && !HasProject(t, project)) continue;
            if (priority != "" && t.Priority != priority) continue;
            PrintTask(idx, t);
            shown++;
        }
        if (shown == 0) Console.WriteLine("No tasks.");
    }

    // [STRIPPED 77 bytes] TUI - AUDITED FIXES (same as C / C++ / JS / Python / Go / Zig / TS)
    // 1. Prompt has NO small char limit: reads keys one-by-one via
    //    Console.ReadKey(true) into a growing string, 4096 cap, horizontal
    //    scroll. No Console.ReadLine() with fixed width, no char[64]/[256]
    //    buffer, no width truncation.
    // 2. Exit is explicit: q, Q, Esc, Ctrl-C, Ctrl-D, Ctrl-Q all quit from
    //    main list, footer always shows "q / Esc / Ctrl-C to quit". In a
    //    prompt, Enter saves, Esc / Ctrl-C cancels back to list.
    //    Console.CancelKeyPress is handled so Ctrl-C does NOT kill the app.
    // [STRIPPED 75 bytes]

    static (int rows, int cols) GetTermSize()
    {
        int rows = 24, cols = 80;
        try { rows = Console.WindowHeight; cols = Console.WindowWidth; } catch {}
        if (rows <= 0) rows = 24;
        if (cols <= 0) cols = 80;
        return (rows, cols);
    }

    static void ClearLine(int row, int cols)
    {
        try
        {
            Console.SetCursorPosition(0, row);
            Console.Write(new string(' ', Math.Max(0, cols - 1)));
            Console.SetCursorPosition(0, row);
        }
        catch {}
    }

    // PromptInput: returns string (trimmed) or null if cancelled.
    // Dynamic string, no small limit, 4096 cap, horizontal scroll.
    static string? PromptInput(string label)
    {
        string text = "";
        int cursor = 0;
        int offset = 0;
        int labelLen = label.Length + 1; // label + space
        while (true)
        {
            var (rows, cols) = GetTermSize();
            int avail = cols - labelLen - 1;
            if (avail < 10) avail = 10;
            if (cursor < offset) offset = cursor;
            if (cursor >= offset + avail) offset = cursor - avail + 1;
            // Hint line
            ClearLine(rows - 2, cols);
            try { Console.SetCursorPosition(0, rows - 2); Console.Write("Enter=save  Esc / Ctrl-C=cancel"); } catch {}
            // Prompt line
            ClearLine(rows - 1, cols);
            try
            {
                Console.SetCursorPosition(0, rows - 1);
                Console.Write(label + " ");
                int end = Math.Min(offset + avail, text.Length);
                if (offset < text.Length) Console.Write(text.Substring(offset, end - offset));
                int cursorX = labelLen + (cursor - offset);
                if (cursorX >= cols) cursorX = cols - 1;
                if (cursorX < 0) cursorX = 0;
                Console.SetCursorPosition(cursorX, rows - 1);
            }
            catch {}
            var key = Console.ReadKey(true);
            // Enter saves
            if (key.Key == ConsoleKey.Enter) break;
            // Esc / Ctrl-C / Ctrl-D -> cancel
            if (key.Key == ConsoleKey.Escape) return null;
            if ((key.Modifiers & ConsoleModifiers.Control) != 0 && (key.Key == ConsoleKey.C || key.Key == ConsoleKey.D)) return null;
            if (key.KeyChar == 3 || key.KeyChar == 4) return null;
            if (key.Key == ConsoleKey.Backspace)
            {
                if (cursor > 0)
                {
                    text = text.Remove(cursor - 1, 1);
                    cursor--;
                }
                continue;
            }
            if (key.Key == ConsoleKey.Delete)
            {
                if (cursor < text.Length) text = text.Remove(cursor, 1);
                continue;
            }
            if (key.Key == ConsoleKey.LeftArrow) { if (cursor > 0) cursor--; continue; }
            if (key.Key == ConsoleKey.RightArrow) { if (cursor < text.Length) cursor++; continue; }
            if (key.Key == ConsoleKey.Home || (key.Key == ConsoleKey.A && (key.Modifiers & ConsoleModifiers.Control) != 0)) { cursor = 0; continue; }
            if (key.Key == ConsoleKey.End || (key.Key == ConsoleKey.E && (key.Modifiers & ConsoleModifiers.Control) != 0)) { cursor = text.Length; continue; }
            if (key.Key == ConsoleKey.U && (key.Modifiers & ConsoleModifiers.Control) != 0) { text = ""; cursor = 0; offset = 0; continue; } // Ctrl-U
            if (key.Key == ConsoleKey.K && (key.Modifiers & ConsoleModifiers.Control) != 0) { text = text.Substring(0, cursor); continue; } // Ctrl-K
            if (key.Key == ConsoleKey.W && (key.Modifiers & ConsoleModifiers.Control) != 0) // Ctrl-W
            {
                while (cursor > 0 && text[cursor - 1] == ' ') { text = text.Remove(cursor - 1, 1); cursor--; }
                while (cursor > 0 && text[cursor - 1] != ' ') { text = text.Remove(cursor - 1, 1); cursor--; }
                continue;
            }
            if (key.Key == ConsoleKey.UpArrow || key.Key == ConsoleKey.DownArrow) continue;
            // Printable: KeyChar >= 32, not a control combo
            if (key.KeyChar >= 32)
            {
                if (text.Length < MAX_INPUT)
                {
                    text = text.Insert(cursor, key.KeyChar.ToString());
                    cursor++;
                }
                continue;
            }
            // ignore other control keys
        }
        return Trim(text);
    }

    static void RunTui()
    {
        // Prevent Ctrl-C from killing the app - we handle it as quit/cancel.
        ConsoleCancelEventHandler handler = (sender, e) => { e.Cancel = true; cancelRequested = true; };
        Console.CancelKeyPress += handler;
        try
        {
            int selected = 0;
            string[] filters = new[] { "all", "todo", "done", "overdue", "today" };
            int filterIdx = 0;
            string search = "";
            string status = "Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter";
            while (true)
            {
                if (cancelRequested)
                {
                    cancelRequested = false;
                    break; // Ctrl-C from main list = quit
                }
                var (rows, cols) = GetTermSize();
                string filterMode = filters[filterIdx];
                var visible = FilteredIndices(filterMode, search);
                if (visible.Count == 0) selected = 0;
                else
                {
                    if (selected >= visible.Count) selected = visible.Count - 1;
                    if (selected < 0) selected = 0;
                }
                Console.Clear();
                int total = tasks.Count;
                int doneN = CountDone();
                int overdueN = CountOverdue();
                Console.WriteLine($"tasks - {total} total | {doneN} done | {overdueN} overdue | filter: {filterMode} | search: {search}");
                Console.WriteLine("#    []  P    Due         Text");
                Console.WriteLine(new string('-', Math.Min(80, Math.Max(0, cols))));
                int maxRows = Math.Max(5, rows - 5);
                for (int i = 0; i < visible.Count && i < maxRows; i++)
                {
                    int idx = visible[i];
                    var t = tasks[idx];
                    char mark = t.Done ? 'x' : ' ';
                    string line = (idx + 1).ToString().PadRight(4) + $" [{mark}] ";
                    if (t.Priority != "") line += $"({t.Priority}) ";
                    if (t.Due != "") line += $"due:{t.Due} ";
                    line += t.Text;
                    if (line.Length > cols) line = line.Substring(0, Math.Max(0, cols));
                    if (i == selected)
                    {
                        Console.BackgroundColor = ConsoleColor.Gray;
                        Console.ForegroundColor = ConsoleColor.Black;
                        Console.WriteLine(line.PadRight(Math.Max(0, cols - 1)));
                        Console.ResetColor();
                    }
                    else if (t.Done)
                    {
                        Console.ForegroundColor = ConsoleColor.DarkGray;
                        Console.WriteLine(line);
                        Console.ResetColor();
                    }
                    else
                    {
                        Console.WriteLine(line);
                    }
                }
                // status + footer - footer ALWAYS shows quit
                try
                {
                    Console.SetCursorPosition(0, rows - 2);
                    Console.Write(status.PadRight(Math.Max(0, cols - 1)).Substring(0, Math.Min(cols - 1, status.PadRight(cols - 1).Length)));
                }
                catch {}
                try
                {
                    Console.SetCursorPosition(0, rows - 1);
                    Console.Write("q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats");
                }
                catch {}
                var k = Console.ReadKey(true);
                // EXIT - checked FIRST, from main list view
                if (k.Key == ConsoleKey.Escape) break;
                if (k.KeyChar == 'q' || k.KeyChar == 'Q') break;
                if ((k.Modifiers & ConsoleModifiers.Control) != 0 && (k.Key == ConsoleKey.C || k.Key == ConsoleKey.D || k.Key == ConsoleKey.Q)) break;
                if (k.KeyChar == 3 || k.KeyChar == 4 || k.KeyChar == 17) break;
                if (cancelRequested) { cancelRequested = false; break; }

                if (k.KeyChar == 'j' || k.Key == ConsoleKey.DownArrow) { if (selected + 1 < visible.Count) selected++; continue; }
                if (k.KeyChar == 'k' || k.Key == ConsoleKey.UpArrow) { if (selected > 0) selected--; continue; }
                if (k.KeyChar == 'g') { selected = 0; continue; }
                if (k.KeyChar == 'G') { if (visible.Count > 0) selected = visible.Count - 1; continue; }
                if (k.Key == ConsoleKey.Spacebar)
                {
                    if (visible.Count > 0)
                    {
                        int idx = visible[selected];
                        tasks[idx].Done = !tasks[idx].Done;
                        SaveTasks();
                        status = tasks[idx].Done ? "Marked done" : "Marked todo";
                    }
                    continue;
                }
                if (k.KeyChar == 'a')
                {
                    var s = PromptInput("Add:");
                    if (!string.IsNullOrEmpty(s))
                    {
                        var nt = ParseAddText(s);
                        tasks.Add(nt);
                        SaveTasks();
                        selected = tasks.Count - 1;
                        status = "Added: " + nt.Text;
                    }
                    else status = "Add cancelled - press q or Esc to quit";
                    continue;
                }
                if (k.KeyChar == 'e')
                {
                    if (visible.Count > 0)
                    {
                        int idx = visible[selected];
                        var old = tasks[idx];
                        var s = PromptInput($"Edit [{old.Text}]:");
                        if (!string.IsNullOrEmpty(s))
                        {
                            var nt = ParseAddText(s);
                            if (nt.Priority == "") nt.Priority = old.Priority;
                            if (nt.Due == "") nt.Due = old.Due;
                            nt.Done = old.Done;
                            tasks[idx] = nt;
                            SaveTasks();
                            status = "Edited";
                        }
                    }
                    continue;
                }
                if (k.KeyChar == 'd')
                {
                    if (visible.Count > 0)
                    {
                        int idx = visible[selected];
                        string removed = tasks[idx].Text;
                        tasks.RemoveAt(idx);
                        SaveTasks();
                        status = "Deleted: " + removed;
                        if (selected >= visible.Count - 1 && selected > 0) selected--;
                    }
                    continue;
                }
                if (k.KeyChar == '/')
                {
                    var s = PromptInput("Search:");
                    if (s != null)
                    {
                        search = s;
                        selected = 0;
                        status = search != "" ? "Search: " + search : "Search cleared - press q or Esc to quit";
                    }
                    continue;
                }
                if (k.KeyChar == 'f')
                {
                    filterIdx = (filterIdx + 1) % filters.Length;
                    selected = 0;
                    status = "Filter: " + filters[filterIdx];
                    continue;
                }
                if (k.KeyChar == 'u')
                {
                    if (File.Exists(BACKUP_FILE))
                    {
                        CopyFile(BACKUP_FILE, TASKS_FILE);
                        LoadTasks();
                        status = "Undone";
                    }
                    else status = "No backup to undo";
                    continue;
                }
                if (k.KeyChar == 'c')
                {
                    int before = tasks.Count;
                    tasks = tasks.Where(t => !t.Done).ToList();
                    SaveTasks();
                    status = $"Cleared {before - tasks.Count} done";
                    selected = 0;
                    continue;
                }
                if (k.KeyChar == 's')
                {
                    int total2 = tasks.Count;
                    int doneN2 = CountDone();
                    int overdueN2 = CountOverdue();
                    status = $"Total {total2} - Done {doneN2} - Todo {total2 - doneN2} - Overdue {overdueN2}";
                    continue;
                }
                if (k.KeyChar == '?')
                {
                    status = "Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats";
                    continue;
                }
            }
        }
        finally
        {
            Console.CancelKeyPress -= handler;
            Console.ResetColor();
            Console.WriteLine();
        }
    }

    static void PrintHelp()
    {
        Console.WriteLine("Usage:");
        Console.WriteLine("  tasks tui                    Interactive TUI (default, no args = tui)");
        Console.WriteLine("  tasks add [--priority P1] [--due YYYY-MM-DD] <text>");
        Console.WriteLine("  tasks list [--tag X] [--project Y] [--priority P1] [--search Q] [--overdue|--today|--done|--todo]");
        Console.WriteLine("  tasks done <n>");
        Console.WriteLine("  tasks undone <n>");
        Console.WriteLine("  tasks rm <n>");
        Console.WriteLine("  tasks edit <n> <new text>");
        Console.WriteLine("  tasks search <query>");
        Console.WriteLine("  tasks clear");
        Console.WriteLine("  tasks stats");
        Console.WriteLine("  tasks undo");
        Console.WriteLine("  tasks help");
        Console.WriteLine();
        Console.WriteLine("Format: tasks.md lines are - [ ] (P1) due:2026-11-30 Buy milk #home +groceries");
        Console.WriteLine("Tags start with #, projects with +. Priority P1/P2/P3, due YYYY-MM-DD.");
        Console.WriteLine("TUI keys: j/k or arrows move, Space toggle, a add, e edit, d delete,");
        Console.WriteLine("  / search, f filter, u undo, c clear done, s stats, q / Esc / Ctrl-C to quit");
        Console.WriteLine("  In a prompt: Enter saves, Esc / Ctrl-C cancels");
    }

    static int Main(string[] args)
    {
        LoadTasks();

        if (args.Length == 0 || args[0] == "tui")
        {
            RunTui();
            Console.WriteLine("Exited TUI - back to shell. Use: dotnet run -- list");
            return 0;
        }

        string cmd = args[0];

        if (cmd == "help" || cmd == "--help" || cmd == "-h")
        {
            PrintHelp();
            return 0;
        }

        if (cmd == "add")
        {
            string priority = "", due = "";
            var parts = new List<string>();
            for (int i = 1; i < args.Length; i++)
            {
                if (args[i] == "--priority" && i + 1 < args.Length) { priority = args[++i]; continue; }
                if (args[i] == "--due" && i + 1 < args.Length) { due = args[++i]; continue; }
                parts.Add(args[i]);
            }
            string buf = string.Join(" ", parts);
            if (Trim(buf) == "") { Console.WriteLine("Usage: tasks add <text>"); return 0; }
            var t = ParseAddText(buf);
            if (priority != "") t.Priority = priority;
            if (due != "") t.Due = due;
            tasks.Add(t);
            SaveTasks();
            Console.WriteLine("Added: " + t.Text);
            return 0;
        }

        if (cmd == "list")
        {
            CliList(args.Skip(1).ToArray());
            return 0;
        }

        if (cmd == "done")
        {
            if (args.Length < 2) { Console.WriteLine("Usage: tasks done <n>"); return 0; }
            int idx = ParseTaskNumber(args[1], tasks.Count);
            if (idx == -1) { Console.WriteLine("Invalid task number"); return 0; }
            tasks[idx].Done = true;
            SaveTasks();
            Console.WriteLine("Done: " + tasks[idx].Text);
            return 0;
        }

        if (cmd == "undone")
        {
            if (args.Length < 2) { Console.WriteLine("Usage: tasks undone <n>"); return 0; }
            int idx = ParseTaskNumber(args[1], tasks.Count);
            if (idx == -1) { Console.WriteLine("Invalid task number"); return 0; }
            tasks[idx].Done = false;
            SaveTasks();
            Console.WriteLine("Todo: " + tasks[idx].Text);
            return 0;
        }

        if (cmd == "rm")
        {
            if (args.Length < 2) { Console.WriteLine("Usage: tasks rm <n>"); return 0; }
            int idx = ParseTaskNumber(args[1], tasks.Count);
            if (idx == -1) { Console.WriteLine("Invalid task number"); return 0; }
            string removed = tasks[idx].Text;
            tasks.RemoveAt(idx);
            SaveTasks();
            Console.WriteLine("Deleted: " + removed);
            return 0;
        }

        if (cmd == "edit")
        {
            if (args.Length < 3) { Console.WriteLine("Usage: tasks edit <n> <new text>"); return 0; }
            int idx = ParseTaskNumber(args[1], tasks.Count);
            if (idx == -1) { Console.WriteLine("Invalid task number"); return 0; }
            var nt = ParseAddText(string.Join(" ", args.Skip(2)));
            var old = tasks[idx];
            if (nt.Priority == "") nt.Priority = old.Priority;
            if (nt.Due == "") nt.Due = old.Due;
            nt.Done = old.Done;
            tasks[idx] = nt;
            SaveTasks();
            Console.WriteLine($"Edited {idx + 1}: {nt.Text}");
            return 0;
        }

        if (cmd == "search")
        {
            if (args.Length < 2) { Console.WriteLine("Usage: tasks search <query>"); return 0; }
            string q = string.Join(" ", args.Skip(1));
            bool found = false;
            for (int i = 0; i < tasks.Count; i++)
            {
                if (MatchesSearch(tasks[i], q)) { PrintTask(i, tasks[i]); found = true; }
            }
            if (!found) Console.WriteLine("No matches.");
            return 0;
        }

        if (cmd == "clear")
        {
            int before = tasks.Count;
            tasks = tasks.Where(t => !t.Done).ToList();
            SaveTasks();
            Console.WriteLine($"Cleared {before - tasks.Count} done tasks");
            return 0;
        }

        if (cmd == "stats")
        {
            int total = tasks.Count;
            int doneN = CountDone();
            int overdueN = CountOverdue();
            int todayN = tasks.Count(t => !t.Done && IsToday(t));
            Console.WriteLine($"Total: {total}\nDone: {doneN}\nTodo: {total - doneN}\nOverdue: {overdueN}\nDue today: {todayN}");
            int c1 = tasks.Count(t => t.Priority == "P1");
            int c2 = tasks.Count(t => t.Priority == "P2");
            int c3 = tasks.Count(t => t.Priority == "P3");
            if (c1 > 0 || c2 > 0 || c3 > 0)
            {
                Console.WriteLine("By priority:");
                if (c1 > 0) Console.WriteLine($"  P1: {c1}");
                if (c2 > 0) Console.WriteLine($"  P2: {c2}");
                if (c3 > 0) Console.WriteLine($"  P3: {c3}");
            }
            var tagCounts = new Dictionary<string, int>();
            foreach (var t in tasks)
            {
                foreach (var tok in t.Text.Split(' ', StringSplitOptions.RemoveEmptyEntries))
                {
                    if (tok.Length > 1 && tok[0] == '#')
                    {
                        tagCounts[tok] = tagCounts.TryGetValue(tok, out int v) ? v + 1 : 1;
                    }
                }
            }
            if (tagCounts.Count > 0)
            {
                Console.WriteLine("By tag:");
                foreach (var kv in tagCounts.OrderBy(kv => kv.Key)) Console.WriteLine($"  {kv.Key}: {kv.Value}");
            }
            return 0;
        }

        if (cmd == "undo")
        {
            if (!File.Exists(BACKUP_FILE)) { Console.WriteLine("No backup to undo"); return 0; }
            CopyFile(BACKUP_FILE, TASKS_FILE);
            Console.WriteLine("Undone - restored from backup");
            return 0;
        }

        Console.WriteLine("Unknown command: " + cmd);
        PrintHelp();
        return 0;
    }
}
