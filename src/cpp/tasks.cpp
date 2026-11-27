// tasks.cpp - Todo CLI v2 (C++, stdlib only)
// Same spec + same tasks.md as all other languages.
// Build: g++ -std=c++17 -O2 -o tasks tasks.cpp
// Run: ./tasks  |  ./tasks list  |  ./tasks add "Buy milk #home"
// Audit fix: prompt is dynamic std::string, key-by-key, 4096 cap only.
// No fixed-size prompt buffer anywhere.

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <iostream>
#include <string>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#include <vector>

static const std::string TASKS_FILE = "tasks.md";
static const std::string BACKUP_FILE = "tasks.md.bak";
static const int MAX_INPUT = 4096;

struct Task {
    bool done = false;
    std::string priority;
    std::string due;
    std::string text;
};

static std::vector<Task> tasks;

static std::string trimStr(const std::string &s) {
    size_t a = 0;
    while (a < s.size() && std::isspace((unsigned char)s[a])) a++;
    size_t b = s.size();
    while (b > a && std::isspace((unsigned char)s[b - 1])) b--;
    return s.substr(a, b - a);
}

static std::string collapseSpaces(const std::string &s) {
    std::string out;
    bool inSpace = false;
    for (char c : s) {
        if (std::isspace((unsigned char)c)) {
            if (!inSpace && !out.empty()) out += ' ';
            inSpace = true;
        } else {
            out += c;
            inSpace = false;
        }
    }
    return trimStr(out);
}

static std::string todayStr() {
    std::time_t now = std::time(nullptr);
    std::tm tmv{};
    localtime_r(&now, &tmv);
    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y-%m-%d", &tmv);
    return std::string(buf);
}

static bool isOverdue(const Task &t) { return !t.due.empty() && t.due < todayStr(); }
static bool isToday(const Task &t) { return !t.due.empty() && t.due == todayStr(); }

static bool parseLine(const std::string &line, Task &out) {
    if (line.rfind("- [", 0) != 0) return false;
    if (line.size() < 5) return false;
    char mark = line[3];
    if (mark != ' ' && mark != 'x') return false;
    if (line[4] != ']') return false;
    out = Task();
    out.done = (mark == 'x');
    std::string rest = trimStr(line.substr(5));
    if (rest.rfind("(P1)", 0) == 0 || rest.rfind("(P2)", 0) == 0 || rest.rfind("(P3)", 0) == 0) {
        out.priority = rest.substr(1, 2);
        rest = trimStr(rest.substr(4));
    }
    if (rest.rfind("due:", 0) == 0 && rest.size() >= 14) {
        std::string d = rest.substr(4, 10);
        if (d.size() == 10 && d[4] == '-' && d[7] == '-') {
            out.due = d;
            rest = trimStr(rest.substr(14));
        }
    }
    out.text = trimStr(rest);
    return true;
}

static std::string formatTask(const Task &t) {
    std::string s = "- [";
    s += (t.done ? "x" : " ");
    s += "]";
    if (!t.priority.empty()) s += " (" + t.priority + ")";
    if (!t.due.empty()) s += " due:" + t.due;
    s += " " + t.text;
    return s;
}

static void loadTasks() {
    tasks.clear();
    std::ifstream in(TASKS_FILE);
    if (!in) return;
    std::string line;
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (trimStr(line).empty()) continue;
        Task t;
        if (parseLine(line, t)) tasks.push_back(t);
    }
}

static bool copyFile(const std::string &src, const std::string &dst) {
    std::ifstream in(src, std::ios::binary);
    if (!in) return false;
    std::ofstream out(dst, std::ios::binary);
    if (!out) return false;
    out << in.rdbuf();
    return true;
}

static void saveTasks() {
    std::ifstream check(TASKS_FILE);
    if (check) { check.close(); copyFile(TASKS_FILE, BACKUP_FILE); }
    std::ofstream out(TASKS_FILE);
    for (auto &t : tasks) out << formatTask(t) << "\n";
}

static Task parseAddText(const std::string &full) {
    Task t;
    std::string text = trimStr(full);
    if (text.rfind("P1 ", 0) == 0 || text.rfind("P2 ", 0) == 0 || text.rfind("P3 ", 0) == 0) {
        t.priority = text.substr(0, 2);
        text = trimStr(text.substr(3));
    } else if (text.rfind("(P1)", 0) == 0 || text.rfind("(P2)", 0) == 0 || text.rfind("(P3)", 0) == 0) {
        t.priority = text.substr(1, 2);
        text = trimStr(text.substr(4));
    }
    size_t pos = text.find("due:");
    if (pos != std::string::npos && text.size() >= pos + 14) {
        std::string cand = text.substr(pos + 4, 10);
        if (cand.size() == 10 && cand[4] == '-' && cand[7] == '-') {
            t.due = cand;
            std::string before = trimStr(text.substr(0, pos));
            std::string after = trimStr(text.substr(pos + 14));
            text = trimStr(before + " " + after);
        }
    }
    t.text = collapseSpaces(text);
    return t;
}

static bool parseTaskNumber(const std::string &s, int n, int &out) {
    std::string t = trimStr(s);
    if (t.empty()) return false;
    for (char c : t) if (!std::isdigit((unsigned char)c)) return false;
    try { out = std::stoi(t) - 1; } catch (...) { return false; }
    if (out < 0 || out >= n) return false;
    return true;
}

static bool matchesMode(const Task &t, const std::string &mode) {
    if (mode == "todo") return !t.done;
    if (mode == "done") return t.done;
    if (mode == "overdue") return !t.done && isOverdue(t);
    if (mode == "today") return !t.done && isToday(t);
    return true;
}

static bool matchesSearch(const Task &t, const std::string &q) {
    if (q.empty()) return true;
    std::string a = t.text, b = q;
    for (auto &c : a) c = std::tolower((unsigned char)c);
    for (auto &c : b) c = std::tolower((unsigned char)c);
    return a.find(b) != std::string::npos;
}

static std::vector<int> filteredIndices(const std::string &mode, const std::string &search) {
    std::vector<int> out;
    for (int i = 0; i < (int)tasks.size(); i++) {
        if (!matchesMode(tasks[i], mode)) continue;
        if (!matchesSearch(tasks[i], search)) continue;
        out.push_back(i);
    }
    return out;
}

static int countDone() {
    int c = 0;
    for (auto &t : tasks) if (t.done) c++;
    return c;
}

static int countOverdue() {
    int c = 0;
    for (auto &t : tasks) if (!t.done && isOverdue(t)) c++;
    return c;
}

static bool hasTag(const Task &t, const std::string &tag) {
    std::string want = (!tag.empty() && tag[0] == '#') ? tag.substr(1) : tag;
    std::string cur;
    for (size_t i = 0; i <= t.text.size(); i++) {
        char c = (i < t.text.size()) ? t.text[i] : ' ';
        if (std::isspace((unsigned char)c)) {
            if (cur.size() > 1 && cur[0] == '#') {
                if (cur == tag || cur.substr(1) == want) return true;
            }
            cur.clear();
        } else cur += c;
    }
    return false;
}

static bool hasProject(const Task &t, const std::string &proj) {
    std::string want = (!proj.empty() && proj[0] == '+') ? proj.substr(1) : proj;
    std::string cur;
    for (size_t i = 0; i <= t.text.size(); i++) {
        char c = (i < t.text.size()) ? t.text[i] : ' ';
        if (std::isspace((unsigned char)c)) {
            if (cur.size() > 1 && cur[0] == '+') {
                if (cur == proj || cur.substr(1) == want) return true;
            }
            cur.clear();
        } else cur += c;
    }
    return false;
}

static void printTask(int idx, const Task &t) {
    std::cout << (idx + 1) << ". [" << (t.done ? "x" : " ") << "] ";
    if (!t.priority.empty()) std::cout << t.priority << " ";
    if (!t.due.empty()) std::cout << t.due << " ";
    std::cout << t.text << "\n";
}

static void cliList(const std::vector<std::string> &args) {
    std::string tag, project, priority, search, mode = "all";
    for (size_t i = 0; i < args.size(); i++) {
        std::string a = args[i];
        if (a == "--tag" && i + 1 < args.size()) tag = args[++i];
        else if (a == "--project" && i + 1 < args.size()) project = args[++i];
        else if (a == "--priority" && i + 1 < args.size()) priority = args[++i];
        else if (a == "--search" && i + 1 < args.size()) search = args[++i];
        else if (a == "--overdue") mode = "overdue";
        else if (a == "--today") mode = "today";
        else if (a == "--done") mode = "done";
        else if (a == "--todo") mode = "todo";
    }
    int shown = 0;
    for (int idx : filteredIndices(mode, search)) {
        Task &t = tasks[idx];
        if (!tag.empty() && !hasTag(t, tag)) continue;
        if (!project.empty() && !hasProject(t, project)) continue;
        if (!priority.empty() && t.priority != priority) continue;
        printTask(idx, t);
        shown++;
    }
    if (shown == 0) std::cout << "No tasks.\n";
}

// --- TUI ---
// AUDITED FIXES:
// 1. Prompt: reads bytes one-by-one via read() into growing std::string,
//    4096 cap only, horizontal scroll. No fixed-size prompt buffer.
// 2. Exit: q / Q / Esc / Ctrl-C / Ctrl-D / Ctrl-Q quit from main list.
//    Footer always shows it. In prompt, Enter saves, Esc / Ctrl-C cancels.
//    Original termios saved and restored on exit.

static termios origTermios{};
static bool termiosSaved = false;

static void getTermSize(int &rows, int &cols) {
    struct winsize ws{};
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_row > 0 && ws.ws_col > 0) {
        rows = ws.ws_row; cols = ws.ws_col; return;
    }
    const char *lr = getenv("LINES");
    const char *lc = getenv("COLUMNS");
    rows = lr ? atoi(lr) : 24;
    cols = lc ? atoi(lc) : 80;
    if (rows <= 0) rows = 24;
    if (cols <= 0) cols = 80;
}

static void setRaw(bool on, int vmin, int vtime) {
    if (on) {
        termios raw = origTermios;
        raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
        raw.c_oflag &= ~(OPOST);
        raw.c_cflag |= CS8;
        raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
        raw.c_cc[VMIN] = (cc_t)vmin;
        raw.c_cc[VTIME] = (cc_t)vtime;
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
    } else {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &origTermios);
    }
}

static int readByte() {
    unsigned char c = 0;
    ssize_t n = read(STDIN_FILENO, &c, 1);
    if (n <= 0) return -1;
    return c;
}

static int readByteTimeout() {
    setRaw(true, 0, 1);
    int b = readByte();
    setRaw(true, 1, 0);
    return b;
}

enum KeyKind { K_CHAR, K_ENTER, K_ESC, K_UP, K_DOWN, K_LEFT, K_RIGHT, K_HOME, K_END, K_DEL, K_BACKSPACE, K_CTRL_C, K_CTRL_D, K_CTRL_Q, K_CTRL_A, K_CTRL_E, K_CTRL_U, K_CTRL_K, K_CTRL_W, K_OTHER };
struct Key { KeyKind kind; std::string ch; };

static std::string decodeUtf8(int first) {
    if (first < 0x80) return std::string(1, (char)first);
    int need = 0;
    if (first >= 0xC2 && first <= 0xDF) need = 1;
    else if (first >= 0xE0 && first <= 0xEF) need = 2;
    else if (first >= 0xF0 && first <= 0xF4) need = 3;
    else return "\xEF\xBF\xBD";
    std::string s;
    s += (char)first;
    for (int i = 0; i < need; i++) {
        int b = readByteTimeout();
        if (b < 0) break;
        s += (char)b;
    }
    return s;
}

static Key readKey() {
    int b = readByte();
    if (b < 0) return {K_OTHER, ""};
    if (b == 13 || b == 10) return {K_ENTER, ""};
    if (b == 3) return {K_CTRL_C, ""};
    if (b == 4) return {K_CTRL_D, ""};
    if (b == 17) return {K_CTRL_Q, ""};
    if (b == 1) return {K_CTRL_A, ""};
    if (b == 5) return {K_CTRL_E, ""};
    if (b == 21) return {K_CTRL_U, ""};
    if (b == 11) return {K_CTRL_K, ""};
    if (b == 23) return {K_CTRL_W, ""};
    if (b == 127 || b == 8) return {K_BACKSPACE, ""};
    if (b == 27) {
        int b2 = readByteTimeout();
        if (b2 < 0) return {K_ESC, ""};
        if (b2 != '[' && b2 != 'O') return {K_ESC, ""};
        int b3 = readByteTimeout();
        if (b3 < 0) return {K_ESC, ""};
        if (b3 == 'A') return {K_UP, ""};
        if (b3 == 'B') return {K_DOWN, ""};
        if (b3 == 'C') return {K_RIGHT, ""};
        if (b3 == 'D') return {K_LEFT, ""};
        if (b3 == 'H') return {K_HOME, ""};
        if (b3 == 'F') return {K_END, ""};
        if (b3 == '3') { readByteTimeout(); return {K_DEL, ""}; }
        return {K_ESC, ""};
    }
    if (b >= 0x80) return {K_CHAR, decodeUtf8(b)};
    if (b >= 32) return {K_CHAR, std::string(1, (char)b)};
    return {K_OTHER, ""};
}

// Helpers to work with UTF-8 chars as units in prompt
static std::vector<std::string> splitChars(const std::string &s) {
    std::vector<std::string> out;
    for (size_t i = 0; i < s.size();) {
        unsigned char c = (unsigned char)s[i];
        size_t len = 1;
        if (c >= 0xC2 && c <= 0xDF) len = 2;
        else if (c >= 0xE0 && c <= 0xEF) len = 3;
        else if (c >= 0xF0 && c <= 0xF4) len = 4;
        if (i + len > s.size()) len = 1;
        out.push_back(s.substr(i, len));
        i += len;
    }
    return out;
}
static std::string joinChars(const std::vector<std::string> &v) {
    std::string s;
    for (auto &c : v) s += c;
    return s;
}

static bool promptInput(const std::string &label, std::string &out) {
    std::vector<std::string> chars;
    int cursor = 0;
    int offset = 0;
    int labelLen = (int)label.size() + 1;
    while (true) {
        int rows, cols;
        getTermSize(rows, cols);
        int avail = cols - labelLen - 1;
        if (avail < 10) avail = 10;
        if (cursor < offset) offset = cursor;
        if (cursor >= offset + avail) offset = cursor - avail + 1;
        printf("\033[%d;1H\033[2KEnter=save  Esc / Ctrl-C=cancel", rows - 1);
        printf("\033[%d;1H\033[2K", rows);
        printf("%s ", label.c_str());
        for (int i = offset; i < (int)chars.size() && i < offset + avail; i++) printf("%s", chars[i].c_str());
        int cx = labelLen + (cursor - offset) + 1;
        if (cx > cols) cx = cols;
        printf("\033[%d;%dH", rows, cx);
        fflush(stdout);
        Key k = readKey();
        if (k.kind == K_ENTER) break;
        if (k.kind == K_ESC || k.kind == K_CTRL_C || k.kind == K_CTRL_D) return false;
        if (k.kind == K_BACKSPACE) {
            if (cursor > 0) { chars.erase(chars.begin() + cursor - 1); cursor--; }
        } else if (k.kind == K_DEL) {
            if (cursor < (int)chars.size()) chars.erase(chars.begin() + cursor);
        } else if (k.kind == K_LEFT) {
            if (cursor > 0) cursor--;
        } else if (k.kind == K_RIGHT) {
            if (cursor < (int)chars.size()) cursor++;
        } else if (k.kind == K_HOME || k.kind == K_CTRL_A) cursor = 0;
        else if (k.kind == K_END || k.kind == K_CTRL_E) cursor = (int)chars.size();
        else if (k.kind == K_CTRL_U) { chars.clear(); cursor = 0; offset = 0; }
        else if (k.kind == K_CTRL_K) { chars.resize(cursor); }
        else if (k.kind == K_CTRL_W) {
            while (cursor > 0 && chars[cursor - 1] == " ") { chars.erase(chars.begin() + cursor - 1); cursor--; }
            while (cursor > 0 && chars[cursor - 1] != " ") { chars.erase(chars.begin() + cursor - 1); cursor--; }
        } else if (k.kind == K_UP || k.kind == K_DOWN) {
        } else if (k.kind == K_CHAR) {
            if ((int)chars.size() < MAX_INPUT) {
                chars.insert(chars.begin() + cursor, k.ch);
                cursor++;
            }
        }
    }
    out = trimStr(joinChars(chars));
    return true;
}

static void runTui() {
    if (tcgetattr(STDIN_FILENO, &origTermios) == 0) termiosSaved = true;
    setRaw(true, 1, 0);
    int selected = 0;
    std::vector<std::string> filters = {"all", "todo", "done", "overdue", "today"};
    int filterIdx = 0;
    std::string search;
    std::string status = "Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter";
    while (true) {
        int rows, cols;
        getTermSize(rows, cols);
        std::string mode = filters[filterIdx];
        std::vector<int> visible = filteredIndices(mode, search);
        if (visible.empty()) selected = 0;
        else {
            if (selected >= (int)visible.size()) selected = (int)visible.size() - 1;
            if (selected < 0) selected = 0;
        }
        printf("\033[2J\033[H");
        printf("tasks - %d total | %d done | %d overdue | filter: %s | search: %s\n",
               (int)tasks.size(), countDone(), countOverdue(), mode.c_str(), search.c_str());
        printf("#    []  P    Due         Text\n");
        printf("%s\n", std::string(std::min(80, cols), '-').c_str());
        int maxRows = std::max(5, rows - 5);
        for (int i = 0; i < (int)visible.size() && i < maxRows; i++) {
            int idx = visible[i];
            Task &t = tasks[idx];
            std::string line = std::to_string(idx + 1);
            while (line.size() < 4) line += ' ';
            line += " ["; line += (t.done ? "x" : " "); line += "] ";
            if (!t.priority.empty()) line += "(" + t.priority + ") ";
            if (!t.due.empty()) line += "due:" + t.due + " ";
            line += t.text;
            if ((int)line.size() > cols) line = line.substr(0, std::max(0, cols));
            if (i == selected) printf("\033[7m%s\033[0m\n", line.c_str());
            else if (t.done) printf("\033[2m%s\033[0m\n", line.c_str());
            else printf("%s\n", line.c_str());
        }
        printf("\033[%d;1H\033[2K%s", rows - 1, status.c_str());
        printf("\033[%d;1H\033[2K", rows);
        printf("q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats");
        printf("\033[%d;1H", rows);
        fflush(stdout);
        Key k = readKey();
        if (k.kind == K_ESC || k.kind == K_CTRL_C || k.kind == K_CTRL_D || k.kind == K_CTRL_Q) break;
        if (k.kind == K_CHAR && (k.ch == "q" || k.ch == "Q")) break;
        if (k.kind == K_DOWN) { if (selected + 1 < (int)visible.size()) selected++; continue; }
        if (k.kind == K_UP) { if (selected > 0) selected--; continue; }
        if (k.kind != K_CHAR) continue;
        std::string ch = k.ch;
        if (ch == "j") { if (selected + 1 < (int)visible.size()) selected++; }
        else if (ch == "k") { if (selected > 0) selected--; }
        else if (ch == "g") selected = 0;
        else if (ch == "G") { if (!visible.empty()) selected = (int)visible.size() - 1; }
        else if (ch == " ") {
            if (!visible.empty()) {
                int idx = visible[selected];
                tasks[idx].done = !tasks[idx].done;
                saveTasks();
                status = tasks[idx].done ? "Marked done" : "Marked todo";
            }
        } else if (ch == "a") {
            std::string s;
            if (promptInput("Add:", s) && !s.empty()) {
                Task nt = parseAddText(s);
                tasks.push_back(nt);
                saveTasks();
                selected = (int)tasks.size() - 1;
                status = "Added: " + nt.text;
            } else status = "Add cancelled - press q or Esc to quit";
        } else if (ch == "e") {
            if (!visible.empty()) {
                int idx = visible[selected];
                Task old = tasks[idx];
                std::string s;
                if (promptInput("Edit [" + old.text + "]:", s) && !s.empty()) {
                    Task nt = parseAddText(s);
                    if (nt.priority.empty()) nt.priority = old.priority;
                    if (nt.due.empty()) nt.due = old.due;
                    nt.done = old.done;
                    tasks[idx] = nt;
                    saveTasks();
                    status = "Edited";
                }
            }
        } else if (ch == "d") {
            if (!visible.empty()) {
                int idx = visible[selected];
                std::string removed = tasks[idx].text;
                tasks.erase(tasks.begin() + idx);
                saveTasks();
                status = "Deleted: " + removed;
                if (selected >= (int)visible.size() - 1 && selected > 0) selected--;
            }
        } else if (ch == "/") {
            std::string s;
            if (promptInput("Search:", s)) {
                search = s;
                selected = 0;
                status = !search.empty() ? ("Search: " + search) : "Search cleared - press q or Esc to quit";
            }
        } else if (ch == "f") {
            filterIdx = (filterIdx + 1) % (int)filters.size();
            selected = 0;
            status = "Filter: " + filters[filterIdx];
        } else if (ch == "u") {
            std::ifstream bf(BACKUP_FILE);
            if (bf) { bf.close(); copyFile(BACKUP_FILE, TASKS_FILE); loadTasks(); status = "Undone"; }
            else status = "No backup to undo";
        } else if (ch == "c") {
            int before = (int)tasks.size();
            tasks.erase(std::remove_if(tasks.begin(), tasks.end(), [](const Task &t) { return t.done; }), tasks.end());
            saveTasks();
            status = "Cleared " + std::to_string(before - (int)tasks.size()) + " done";
            selected = 0;
        } else if (ch == "s") {
            int tot = (int)tasks.size(), dn = countDone(), ov = countOverdue();
            status = "Total " + std::to_string(tot) + " - Done " + std::to_string(dn) + " - Todo " + std::to_string(tot - dn) + " - Overdue " + std::to_string(ov);
        } else if (ch == "?") {
            status = "Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats";
        }
    }
    if (termiosSaved) setRaw(false, 1, 0);
    printf("\n");
}

static void printHelp() {
    std::cout << "Usage:\n";
    std::cout << "  tasks tui                    Interactive TUI (default, no args = tui)\n";
    std::cout << "  tasks add [--priority P1] [--due YYYY-MM-DD] <text>\n";
    std::cout << "  tasks list [--tag X] [--project Y] [--priority P1] [--search Q] [--overdue|--today|--done|--todo]\n";
    std::cout << "  tasks done <n>\n";
    std::cout << "  tasks undone <n>\n";
    std::cout << "  tasks rm <n>\n";
    std::cout << "  tasks edit <n> <new text>\n";
    std::cout << "  tasks search <query>\n";
    std::cout << "  tasks clear\n";
    std::cout << "  tasks stats\n";
    std::cout << "  tasks undo\n";
    std::cout << "  tasks help\n";
    std::cout << "\n";
    std::cout << "Format: tasks.md lines are - [ ] (P1) due:2026-11-30 Buy milk #home +groceries\n";
    std::cout << "Tags start with #, projects with +. Priority P1/P2/P3, due YYYY-MM-DD.\n";
    std::cout << "TUI keys: j/k or arrows move, Space toggle, a add, e edit, d delete,\n";
    std::cout << "  / search, f filter, u undo, c clear done, s stats, q / Esc / Ctrl-C to quit\n";
    std::cout << "  In a prompt: Enter saves, Esc / Ctrl-C cancels\n";
}

int main(int argc, char *argv[]) {
    loadTasks();
    std::vector<std::string> args;
    for (int i = 1; i < argc; i++) args.push_back(argv[i]);
    if (args.empty() || args[0] == "tui") {
        runTui();
        std::cout << "Exited TUI - back to shell. Use: ./tasks list\n";
        return 0;
    }
    std::string cmd = args[0];
    if (cmd == "help" || cmd == "--help" || cmd == "-h") {
        printHelp();
    } else if (cmd == "add") {
        std::string priority, due, buf;
        for (size_t i = 1; i < args.size(); i++) {
            if (args[i] == "--priority" && i + 1 < args.size()) priority = args[++i];
            else if (args[i] == "--due" && i + 1 < args.size()) due = args[++i];
            else { if (!buf.empty()) buf += " "; buf += args[i]; }
        }
        if (trimStr(buf).empty()) { std::cout << "Usage: tasks add <text>\n"; return 0; }
        Task t = parseAddText(buf);
        if (!priority.empty()) t.priority = priority;
        if (!due.empty()) t.due = due;
        tasks.push_back(t); saveTasks();
        std::cout << "Added: " << t.text << "\n";
    } else if (cmd == "list") {
        std::vector<std::string> rest(args.begin() + 1, args.end());
        cliList(rest);
    } else if (cmd == "done") {
        if (args.size() < 2) { std::cout << "Usage: tasks done <n>\n"; return 0; }
        int idx = 0;
        if (!parseTaskNumber(args[1], (int)tasks.size(), idx)) { std::cout << "Invalid task number\n"; return 0; }
        tasks[idx].done = true; saveTasks();
        std::cout << "Done: " << tasks[idx].text << "\n";
    } else if (cmd == "undone") {
        if (args.size() < 2) { std::cout << "Usage: tasks undone <n>\n"; return 0; }
        int idx = 0;
        if (!parseTaskNumber(args[1], (int)tasks.size(), idx)) { std::cout << "Invalid task number\n"; return 0; }
        tasks[idx].done = false; saveTasks();
        std::cout << "Todo: " << tasks[idx].text << "\n";
    } else if (cmd == "rm") {
        if (args.size() < 2) { std::cout << "Usage: tasks rm <n>\n"; return 0; }
        int idx = 0;
        if (!parseTaskNumber(args[1], (int)tasks.size(), idx)) { std::cout << "Invalid task number\n"; return 0; }
        std::string removed = tasks[idx].text;
        tasks.erase(tasks.begin() + idx); saveTasks();
        std::cout << "Deleted: " << removed << "\n";
    } else if (cmd == "edit") {
        if (args.size() < 3) { std::cout << "Usage: tasks edit <n> <new text>\n"; return 0; }
        int idx = 0;
        if (!parseTaskNumber(args[1], (int)tasks.size(), idx)) { std::cout << "Invalid task number\n"; return 0; }
        std::string joined;
        for (size_t i = 2; i < args.size(); i++) { if (!joined.empty()) joined += " "; joined += args[i]; }
        Task nt = parseAddText(joined);
        Task old = tasks[idx];
        if (nt.priority.empty()) nt.priority = old.priority;
        if (nt.due.empty()) nt.due = old.due;
        nt.done = old.done;
        tasks[idx] = nt; saveTasks();
        std::cout << "Edited " << (idx + 1) << ": " << nt.text << "\n";
    } else if (cmd == "search") {
        if (args.size() < 2) { std::cout << "Usage: tasks search <query>\n"; return 0; }
        std::string q;
        for (size_t i = 1; i < args.size(); i++) { if (!q.empty()) q += " "; q += args[i]; }
        bool found = false;
        for (int i = 0; i < (int)tasks.size(); i++) {
            if (matchesSearch(tasks[i], q)) { printTask(i, tasks[i]); found = true; }
        }
        if (!found) std::cout << "No matches.\n";
    } else if (cmd == "clear") {
        int before = (int)tasks.size();
        tasks.erase(std::remove_if(tasks.begin(), tasks.end(), [](const Task &t) { return t.done; }), tasks.end());
        saveTasks();
        std::cout << "Cleared " << (before - (int)tasks.size()) << " done tasks\n";
    } else if (cmd == "stats") {
        int total = (int)tasks.size(), doneN = countDone(), overN = countOverdue();
        int todayN = 0;
        for (auto &t : tasks) if (!t.done && isToday(t)) todayN++;
        std::cout << "Total: " << total << "\nDone: " << doneN << "\nTodo: " << (total - doneN) << "\nOverdue: " << overN << "\nDue today: " << todayN << "\n";
        int c1 = 0, c2 = 0, c3 = 0;
        for (auto &t : tasks) { if (t.priority == "P1") c1++; if (t.priority == "P2") c2++; if (t.priority == "P3") c3++; }
        if (c1 || c2 || c3) {
            std::cout << "By priority:\n";
            if (c1) std::cout << "  P1: " << c1 << "\n";
            if (c2) std::cout << "  P2: " << c2 << "\n";
            if (c3) std::cout << "  P3: " << c3 << "\n";
        }
    } else if (cmd == "undo") {
        std::ifstream bf(BACKUP_FILE);
        if (!bf) { std::cout << "No backup to undo\n"; return 0; }
        bf.close();
        copyFile(BACKUP_FILE, TASKS_FILE);
        std::cout << "Undone - restored from backup\n";
    } else {
        std::cout << "Unknown command: " << cmd << "\n";
        printHelp();
    }
    return 0;
}
