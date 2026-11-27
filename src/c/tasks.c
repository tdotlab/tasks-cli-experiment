#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <errno.h>

#define TASKS_FILE "tasks.md"
#define BACKUP_FILE "tasks.md.bak"
#define MAX_INPUT 4096

typedef struct {
    int done;
    char priority[4]; // "P1", "P2", "P3" or ""
    char due[11];     // "YYYY-MM-DD" or ""
    char *text;       // malloc'd
} Task;

static Task *tasks = NULL;
static size_t tasks_len = 0;
static size_t tasks_cap = 0;

static struct termios orig_termios;
static int raw_enabled = 0;

/* ---------- helpers ---------- */
static char *xstrdup(const char *s) {
    if (!s) return NULL;
    size_t n = strlen(s) + 1;
    char *p = (char *)malloc(n);
    if (!p) return NULL;
    memcpy(p, s, n);
    return p;
}

static char *xstrndup(const char *s, size_t n) {
    char *p = (char *)malloc(n + 1);
    if (!p) return NULL;
    memcpy(p, s, n);
    p[n] = '\0';
    return p;
}

static void *xrealloc(void *ptr, size_t n) {
    void *p = realloc(ptr, n);
    if (!p && n != 0) {
        fprintf(stderr, "out of memory\n");
        exit(1);
    }
    return p;
}

static void ensure_cap(size_t need) {
    if (need <= tasks_cap) return;
    size_t ncap = tasks_cap ? tasks_cap * 2 : 16;
    while (ncap < need) ncap *= 2;
    tasks = (Task *)xrealloc(tasks, ncap * sizeof(Task));
    tasks_cap = ncap;
}

static void free_task(Task *t) {
    if (t->text) free(t->text);
    t->text = NULL;
}

static void free_all_tasks(void) {
    for (size_t i = 0; i < tasks_len; i++) free_task(&tasks[i]);
    free(tasks);
    tasks = NULL;
    tasks_len = 0;
    tasks_cap = 0;
}

static void trim_inplace(char *s) {
    if (!s) return;
    size_t len = strlen(s);
    size_t start = 0;
    while (start < len && isspace((unsigned char)s[start])) start++;
    size_t end = len;
    while (end > start && isspace((unsigned char)s[end - 1])) end--;
    if (start > 0) memmove(s, s + start, end - start);
    s[end - start] = '\0';
}

static void collapse_spaces(char *s) {
    if (!s) return;
    size_t r = 0, w = 0;
    int prev_space = 1;
    while (s[r]) {
        if (isspace((unsigned char)s[r])) {
            if (!prev_space) {
                s[w++] = ' ';
                prev_space = 1;
            }
        } else {
            s[w++] = s[r];
            prev_space = 0;
        }
        r++;
    }
    if (w > 0 && s[w - 1] == ' ') w--;
    s[w] = '\0';
}

static void today_str(char *buf, size_t n) {
    time_t now = time(NULL);
    struct tm tmv;
    localtime_r(&now, &tmv);
    strftime(buf, n, "%Y-%m-%d", &tmv);
}

static int is_overdue(Task *t) {
    if (t->due[0] == '\0') return 0;
    char today[16];
    today_str(today, sizeof(today));
    return strcmp(t->due, today) < 0;
}

static int is_today(Task *t) {
    if (t->due[0] == '\0') return 0;
    char today[16];
    today_str(today, sizeof(today));
    return strcmp(t->due, today) == 0;
}

/* ---------- parsing / formatting ---------- */
static int parse_line(const char *line, Task *out) {
    // "- [ ] ..." or "- [x] ..."
    if (strncmp(line, "- [", 3) != 0) return 0;
    if (line[3] != ' ' && line[3] != 'x') return 0;
    if (line[4] != ']') return 0;
    out->done = (line[3] == 'x');
    out->priority[0] = '\0';
    out->due[0] = '\0';
    const char *rest = line + 5;
    while (*rest && isspace((unsigned char)*rest)) rest++;
    // priority "(P1)"
    if (strncmp(rest, "(P1)", 4) == 0 || strncmp(rest, "(P2)", 4) == 0 || strncmp(rest, "(P3)", 4) == 0) {
        out->priority[0] = rest[1];
        out->priority[1] = rest[2];
        out->priority[2] = '\0';
        rest += 4;
        while (*rest && isspace((unsigned char)*rest)) rest++;
    }
    // due "due:YYYY-MM-DD"
    if (strncmp(rest, "due:", 4) == 0 && strlen(rest) >= 14) {
        // check shape YYYY-MM-DD
        const char *d = rest + 4;
        if (d[4] == '-' && d[7] == '-') {
            memcpy(out->due, d, 10);
            out->due[10] = '\0';
            rest += 14;
            while (*rest && isspace((unsigned char)*rest)) rest++;
        }
    }
    out->text = xstrdup(rest);
    trim_inplace(out->text);
    return 1;
}

static void format_task(Task *t, char *buf, size_t n) {
    char mark = t->done ? 'x' : ' ';
    if (t->priority[0] && t->due[0]) {
        snprintf(buf, n, "- [%c] (%s) due:%s %s", mark, t->priority, t->due, t->text);
    } else if (t->priority[0]) {
        snprintf(buf, n, "- [%c] (%s) %s", mark, t->priority, t->text);
    } else if (t->due[0]) {
        snprintf(buf, n, "- [%c] due:%s %s", mark, t->due, t->text);
    } else {
        snprintf(buf, n, "- [%c] %s", mark, t->text);
    }
}

static void load_tasks(void) {
    free_all_tasks();
    FILE *f = fopen(TASKS_FILE, "r");
    if (!f) return;
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    while ((len = getline(&line, &cap, f)) != -1) {
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) line[--len] = '\0';
        if (len == 0) continue;
        // skip blank
        int blank = 1;
        for (ssize_t i = 0; i < len; i++) if (!isspace((unsigned char)line[i])) { blank = 0; break; }
        if (blank) continue;
        Task t;
        memset(&t, 0, sizeof(t));
        if (parse_line(line, &t)) {
            ensure_cap(tasks_len + 1);
            tasks[tasks_len++] = t;
        }
    }
    free(line);
    fclose(f);
}

static int copy_file(const char *src, const char *dst) {
    FILE *in = fopen(src, "rb");
    if (!in) return -1;
    FILE *out = fopen(dst, "wb");
    if (!out) { fclose(in); return -1; }
    char buf[8192];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), in)) > 0) fwrite(buf, 1, n, out);
    fclose(in);
    fclose(out);
    return 0;
}

static void save_tasks(void) {
    FILE *test = fopen(TASKS_FILE, "r");
    if (test) {
        fclose(test);
        copy_file(TASKS_FILE, BACKUP_FILE);
    }
    FILE *f = fopen(TASKS_FILE, "w");
    if (!f) return;
    char buf[8192];
    for (size_t i = 0; i < tasks_len; i++) {
        format_task(&tasks[i], buf, sizeof(buf));
        fprintf(f, "%s\n", buf);
    }
    fclose(f);
}

static Task parse_add_text(const char *full) {
    Task t;
    memset(&t, 0, sizeof(t));
    t.done = 0;
    t.priority[0] = '\0';
    t.due[0] = '\0';
    char *text = xstrdup(full);
    trim_inplace(text);
    // P1 prefix
    if ((strncmp(text, "P1 ", 3) == 0 || strncmp(text, "P2 ", 3) == 0 || strncmp(text, "P3 ", 3) == 0)) {
        t.priority[0] = text[0];
        t.priority[1] = text[1];
        t.priority[2] = '\0';
        memmove(text, text + 3, strlen(text + 3) + 1);
        trim_inplace(text);
    } else if (strncmp(text, "(P1)", 4) == 0 || strncmp(text, "(P2)", 4) == 0 || strncmp(text, "(P3)", 4) == 0) {
        t.priority[0] = text[1];
        t.priority[1] = text[2];
        t.priority[2] = '\0';
        memmove(text, text + 4, strlen(text + 4) + 1);
        trim_inplace(text);
    }
    // due: inside
    char *duepos = strstr(text, "due:");
    if (duepos) {
        // check shape after due:
        if (strlen(duepos) >= 14 && duepos[8] == '-' && duepos[11] == '-') {
            memcpy(t.due, duepos + 4, 10);
            t.due[10] = '\0';
            // remove "due:YYYY-MM-DD" from text, replace with space
            size_t before = (size_t)(duepos - text);
            size_t after_off = before + 14;
            size_t after_len = strlen(text + after_off);
            memmove(text + before + 1, text + after_off, after_len + 1);
            text[before] = ' ';
            trim_inplace(text);
        }
    }
    collapse_spaces(text);
    t.text = text;
    return t;
}

static int parse_task_number(const char *s, size_t n) {
    char *end = NULL;
    long v = strtol(s, &end, 10);
    if (end == s || *end != '\0') return -1;
    if (v < 1 || (size_t)v > n) return -1;
    return (int)(v - 1);
}

static int matches_mode(Task *t, const char *mode) {
    if (strcmp(mode, "todo") == 0) return !t->done;
    if (strcmp(mode, "done") == 0) return t->done;
    if (strcmp(mode, "overdue") == 0) return !t->done && is_overdue(t);
    if (strcmp(mode, "today") == 0) return !t->done && is_today(t);
    return 1;
}

static int contains_ci(const char *hay, const char *needle) {
    if (!*needle) return 1;
    size_t hn = strlen(hay);
    size_t nn = strlen(needle);
    if (nn > hn) return 0;
    for (size_t i = 0; i + nn <= hn; i++) {
        size_t j;
        for (j = 0; j < nn; j++) {
            if (tolower((unsigned char)hay[i + j]) != tolower((unsigned char)needle[j])) break;
        }
        if (j == nn) return 1;
    }
    return 0;
}

static int matches_search(Task *t, const char *q) {
    if (!q || q[0] == '\0') return 1;
    return contains_ci(t->text, q);
}

static size_t filtered_indices(Task *unused, const char *mode, const char *search, int *out, size_t max_out) {
    (void)unused;
    size_t n = 0;
    for (size_t i = 0; i < tasks_len; i++) {
        if (!matches_mode(&tasks[i], mode)) continue;
        if (!matches_search(&tasks[i], search)) continue;
        if (n < max_out) out[n] = (int)i;
        n++;
    }
    return n;
}

static int count_done(void) {
    int n = 0;
    for (size_t i = 0; i < tasks_len; i++) if (tasks[i].done) n++;
    return n;
}

static int count_overdue(void) {
    int n = 0;
    for (size_t i = 0; i < tasks_len; i++) if (!tasks[i].done && is_overdue(&tasks[i])) n++;
    return n;
}

static int has_tag(Task *t, const char *tag) {
    const char *want = tag;
    if (want[0] == '#') want++;
    // tokenise by spaces
    char *copy = xstrdup(t->text);
    char *save = NULL;
    char *tok = strtok_r(copy, " ", &save);
    int found = 0;
    while (tok) {
        if (tok[0] == '#' && tok[1] != '\0') {
            if (strcmp(tok, tag) == 0 || strcmp(tok + 1, want) == 0) { found = 1; break; }
        }
        tok = strtok_r(NULL, " ", &save);
    }
    free(copy);
    return found;
}

static int has_project(Task *t, const char *proj) {
    const char *want = proj;
    if (want[0] == '+') want++;
    char *copy = xstrdup(t->text);
    char *save = NULL;
    char *tok = strtok_r(copy, " ", &save);
    int found = 0;
    while (tok) {
        if (tok[0] == '+' && tok[1] != '\0') {
            if (strcmp(tok, proj) == 0 || strcmp(tok + 1, want) == 0) { found = 1; break; }
        }
        tok = strtok_r(NULL, " ", &save);
    }
    free(copy);
    return found;
}

static void print_task(int idx, Task *t) {
    char mark = t->done ? 'x' : ' ';
    if (t->priority[0] && t->due[0]) {
        printf("%d. [%c] %s %s %s\n", idx + 1, mark, t->priority, t->due, t->text);
    } else if (t->priority[0]) {
        printf("%d. [%c] %s %s\n", idx + 1, mark, t->priority, t->text);
    } else if (t->due[0]) {
        printf("%d. [%c] %s %s\n", idx + 1, mark, t->due, t->text);
    } else {
        printf("%d. [%c] %s\n", idx + 1, mark, t->text);
    }
}

static void cli_list(int argc, char **argv) {
    const char *tag = "";
    const char *project = "";
    const char *priority = "";
    const char *search = "";
    const char *mode = "all";
    for (int i = 0; i < argc; i++) {
        const char *a = argv[i];
        if (strcmp(a, "--tag") == 0 && i + 1 < argc) { tag = argv[++i]; continue; }
        if (strcmp(a, "--project") == 0 && i + 1 < argc) { project = argv[++i]; continue; }
        if (strcmp(a, "--priority") == 0 && i + 1 < argc) { priority = argv[++i]; continue; }
        if (strcmp(a, "--search") == 0 && i + 1 < argc) { search = argv[++i]; continue; }
        if (strcmp(a, "--overdue") == 0) mode = "overdue";
        else if (strcmp(a, "--today") == 0) mode = "today";
        else if (strcmp(a, "--done") == 0) mode = "done";
        else if (strcmp(a, "--todo") == 0) mode = "todo";
    }
    int *vis = (int *)malloc(sizeof(int) * (tasks_len + 1));
    size_t n = filtered_indices(NULL, mode, search, vis, tasks_len + 1);
    int shown = 0;
    for (size_t k = 0; k < n; k++) {
        int idx = vis[k];
        Task *t = &tasks[idx];
        if (tag[0] && !has_tag(t, tag)) continue;
        if (project[0] && !has_project(t, project)) continue;
        if (priority[0] && strcmp(t->priority, priority) != 0) continue;
        print_task(idx, t);
        shown++;
    }
    if (shown == 0) printf("No tasks.\n");
    free(vis);
}

/* [STRIPPED 77 bytes] TUI - AUDITED FIXES (same as Python/Go/Zig/TS)
 * 1. Prompt has NO small char limit: reads bytes one-by-one into a growing
 *    malloc'd buffer, 4096 cap, horizontal scroll. No getstr(), no fixed
 *    [64]/[256] buffer, no width truncation.
 * 2. Exit is explicit: q, Q, Esc, Ctrl-C, Ctrl-D, Ctrl-Q all quit from
 *    main list, footer always shows "q / Esc / Ctrl-C to quit". In a
 *    prompt, Enter saves, Esc / Ctrl-C cancels back to list.
 * [STRIPPED 75 bytes] */

static void get_term_size(int *rows, int *cols) {
    struct winsize ws;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0 && ws.ws_row > 0) {
        *rows = ws.ws_row;
        *cols = ws.ws_col;
    } else {
        *rows = 24;
        *cols = 80;
    }
}

static void enable_raw(void) {
    if (tcgetattr(STDIN_FILENO, &orig_termios) != 0) return;
    struct termios raw = orig_termios;
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.c_oflag &= ~(OPOST);
    raw.c_cflag |= CS8;
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
    raw_enabled = 1;
}

static void disable_raw(void) {
    if (raw_enabled) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
        raw_enabled = 0;
    }
    printf("\n");
}

static int read_byte_blocking(void) {
    unsigned char c;
    while (1) {
        ssize_t n = read(STDIN_FILENO, &c, 1);
        if (n == 1) return (int)c;
        if (n == -1 && errno == EINTR) continue;
        if (n == 0) return -1;
        if (n == -1) return -1;
    }
}

static int read_byte_timeout(int timeout_ms) {
    fd_set set;
    FD_ZERO(&set);
    FD_SET(STDIN_FILENO, &set);
    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    int r = select(STDIN_FILENO + 1, &set, NULL, NULL, &tv);
    if (r <= 0) return -1;
    unsigned char c;
    ssize_t n = read(STDIN_FILENO, &c, 1);
    if (n == 1) return (int)c;
    return -1;
}

#define KEY_ESC 1000
#define KEY_UP 1001
#define KEY_DOWN 1002
#define KEY_RIGHT 1003
#define KEY_LEFT 1004
#define KEY_HOME 1005
#define KEY_END 1006
#define KEY_DEL 1007

static int read_key(void) {
    int c = read_byte_blocking();
    if (c < 0) return c;
    if (c != 27) return c;
    // Esc - could be Esc alone or arrow sequence. Wait 30ms for next byte.
    int c2 = read_byte_timeout(30);
    if (c2 < 0) return KEY_ESC; // Esc alone -> quit / cancel
    if (c2 != '[' && c2 != 'O') return KEY_ESC;
    int c3 = read_byte_timeout(30);
    if (c3 < 0) return KEY_ESC;
    if (c3 == 'A') return KEY_UP;
    if (c3 == 'B') return KEY_DOWN;
    if (c3 == 'C') return KEY_RIGHT;
    if (c3 == 'D') return KEY_LEFT;
    if (c3 == 'H') return KEY_HOME;
    if (c3 == 'F') return KEY_END;
    if (c3 == '3') {
        // Delete is Esc [ 3 ~ - consume ~
        read_byte_timeout(30);
        return KEY_DEL;
    }
    return KEY_ESC;
}

// prompt_input: returns malloc'd trimmed string, or NULL if cancelled.
// Dynamic buffer, no small limit, 4096 cap, horizontal scroll.
static char *prompt_input(const char *label) {
    int rows, cols;
    get_term_size(&rows, &cols);
    size_t cap = 128;
    size_t len = 0;
    char *text = (char *)malloc(cap);
    text[0] = '\0';
    size_t cursor = 0;
    size_t offset = 0;
    size_t label_len = strlen(label) + 1; // label + space
    while (1) {
        get_term_size(&rows, &cols);
        int avail = (int)cols - (int)label_len - 1;
        if (avail < 10) avail = 10;
        if (cursor < offset) offset = cursor;
        if (cursor >= offset + (size_t)avail) offset = cursor - (size_t)avail + 1;
        // Hint line above prompt
        printf("\x1b[%d;1H\x1b[2KEnter=save  Esc / Ctrl-C=cancel", rows - 1);
        printf("\x1b[%d;1H\x1b[2K", rows);
        printf("%s ", label);
        // visible slice
        size_t end = offset + (size_t)avail;
        if (end > len) end = len;
        if (offset < len) {
            fwrite(text + offset, 1, end - offset, stdout);
        }
        size_t cursor_x = label_len + (cursor - offset) + 1;
        if (cursor_x > (size_t)cols) cursor_x = (size_t)cols;
        printf("\x1b[%d;%zuH", rows, cursor_x);
        fflush(stdout);
        int k = read_key();
        if (k == '\r' || k == '\n') {
            break;
        }
        if (k == KEY_ESC || k == 3 || k == 4) { // Esc / Ctrl-C / Ctrl-D -> cancel
            free(text);
            return NULL;
        }
        if (k == 127 || k == 8) { // Backspace
            if (cursor > 0) {
                // handle UTF-8: if previous byte is continuation, delete whole char - simplified: delete 1 byte, but also delete UTF-8 lead if needed
                // For simplicity, delete 1 byte; UTF-8 multi-byte will be deleted byte-by-byte, which still works
                memmove(text + cursor - 1, text + cursor, len - cursor + 1);
                len--;
                cursor--;
            }
            continue;
        }
        if (k == KEY_DEL) {
            if (cursor < len) {
                memmove(text + cursor, text + cursor + 1, len - cursor);
                len--;
            }
            continue;
        }
        if (k == KEY_LEFT) {
            if (cursor > 0) cursor--;
            continue;
        }
        if (k == KEY_RIGHT) {
            if (cursor < len) cursor++;
            continue;
        }
        if (k == KEY_HOME || k == 1) { // Home / Ctrl-A
            cursor = 0;
            continue;
        }
        if (k == KEY_END || k == 5) { // End / Ctrl-E
            cursor = len;
            continue;
        }
        if (k == 21) { // Ctrl-U clear
            len = 0;
            cursor = 0;
            offset = 0;
            text[0] = '\0';
            continue;
        }
        if (k == 11) { // Ctrl-K kill to end
            len = cursor;
            text[len] = '\0';
            continue;
        }
        if (k == 23) { // Ctrl-W delete word
            while (cursor > 0 && text[cursor - 1] == ' ') {
                memmove(text + cursor - 1, text + cursor, len - cursor + 1);
                len--; cursor--;
            }
            while (cursor > 0 && text[cursor - 1] != ' ') {
                memmove(text + cursor - 1, text + cursor, len - cursor + 1);
                len--; cursor--;
            }
            continue;
        }
        if (k == KEY_UP || k == KEY_DOWN) {
            continue;
        }
        // Printable: 32-126 + UTF-8 bytes >= 128
        if ((k >= 32 && k <= 126) || k >= 128) {
            if (len < MAX_INPUT) {
                if (len + 1 >= cap) {
                    cap *= 2;
                    if (cap > MAX_INPUT + 1) cap = MAX_INPUT + 1;
                    text = (char *)xrealloc(text, cap);
                }
                memmove(text + cursor + 1, text + cursor, len - cursor + 1);
                text[cursor] = (char)k;
                len++;
                cursor++;
            }
            continue;
        }
        // ignore other control keys
    }
    // trim
    trim_inplace(text);
    // collapse not needed here - parse_add_text does it, but trim is enough
    char *out = xstrdup(text);
    free(text);
    return out;
}

static void run_tui(void) {
    enable_raw();
    // atexit not needed, we disable at end of this function
    int selected = 0;
    const char *filters[] = {"all", "todo", "done", "overdue", "today"};
    int filter_idx = 0;
    char search[MAX_INPUT + 1] = "";
    char status[1024] = "Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter";
    while (1) {
        int rows, cols;
        get_term_size(&rows, &cols);
        const char *filter_mode = filters[filter_idx];
        int *vis = (int *)malloc(sizeof(int) * (tasks_len + 1));
        size_t vis_n = filtered_indices(NULL, filter_mode, search, vis, tasks_len + 1);
        if (vis_n == 0) selected = 0;
        else {
            if (selected >= (int)vis_n) selected = (int)vis_n - 1;
            if (selected < 0) selected = 0;
        }
        printf("\x1b[2J\x1b[H");
        int total = (int)tasks_len;
        int done_n = count_done();
        int overdue_n = count_overdue();
        printf("tasks - %d total | %d done | %d overdue | filter: %s | search: %s\n", total, done_n, overdue_n, filter_mode, search);
        printf("%-4s %-3s %-4s %-11s Text\n", "#", "[]", "P", "Due");
        for (int i = 0; i < 80 && i < cols; i++) putchar('-');
        putchar('\n');
        int max_rows = rows - 5;
        if (max_rows < 5) max_rows = 5;
        for (size_t i = 0; i < vis_n && (int)i < max_rows; i++) {
            int idx = vis[i];
            Task *t = &tasks[idx];
            char mark = t->done ? 'x' : ' ';
            char line[4096];
            if (t->priority[0] && t->due[0]) {
                snprintf(line, sizeof(line), "%-4d [%c] (%s) due:%s %s", idx + 1, mark, t->priority, t->due, t->text);
            } else if (t->priority[0]) {
                snprintf(line, sizeof(line), "%-4d [%c] (%s) %s", idx + 1, mark, t->priority, t->text);
            } else if (t->due[0]) {
                snprintf(line, sizeof(line), "%-4d [%c] due:%s %s", idx + 1, mark, t->due, t->text);
            } else {
                snprintf(line, sizeof(line), "%-4d [%c] %s", idx + 1, mark, t->text);
            }
            // truncate to cols
            if ((int)strlen(line) > cols) line[cols] = '\0';
            if ((int)i == selected) {
                printf("\x1b[7m%s\x1b[0m\n", line);
            } else if (t->done) {
                printf("\x1b[2m%s\x1b[0m\n", line);
            } else {
                printf("%s\n", line);
            }
        }
        // status + footer - footer ALWAYS shows quit
        printf("\x1b[%d;1H\x1b[2K", rows - 1);
        printf("%s", status);
        // truncate status display is handled by terminal, but ensure it fits
        printf("\x1b[%d;1H\x1b[2K", rows);
        printf("q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats");
        // move cursor to footer line start (prompt will overwrite)
        printf("\x1b[%d;1H", rows);
        fflush(stdout);
        int k = read_key();
        // EXIT - checked FIRST, from main list view
        if (k == 'q' || k == 'Q' || k == KEY_ESC || k == 3 || k == 4 || k == 17) {
            free(vis);
            break;
        }
        if (k == 'j' || k == KEY_DOWN) {
            if (selected + 1 < (int)vis_n) selected++;
            free(vis);
            continue;
        }
        if (k == 'k' || k == KEY_UP) {
            if (selected > 0) selected--;
            free(vis);
            continue;
        }
        if (k == 'g') {
            selected = 0;
            free(vis);
            continue;
        }
        if (k == 'G') {
            if (vis_n > 0) selected = (int)vis_n - 1;
            free(vis);
            continue;
        }
        if (k == ' ') {
            if (vis_n > 0) {
                int idx = vis[selected];
                tasks[idx].done = !tasks[idx].done;
                save_tasks();
                snprintf(status, sizeof(status), "%s", tasks[idx].done ? "Marked done" : "Marked todo");
            }
            free(vis);
            continue;
        }
        if (k == 'a') {
            free(vis);
            char *s = prompt_input("Add:");
            if (s && s[0] != '\0') {
                Task nt = parse_add_text(s);
                ensure_cap(tasks_len + 1);
                tasks[tasks_len++] = nt;
                save_tasks();
                selected = (int)tasks_len - 1;
                snprintf(status, sizeof(status), "Added: %s", nt.text);
            } else {
                snprintf(status, sizeof(status), "Add cancelled - press q or Esc to quit");
            }
            free(s);
            continue;
        }
        if (k == 'e') {
            if (vis_n > 0) {
                int idx = vis[selected];
                Task old = tasks[idx];
                char label[4096];
                snprintf(label, sizeof(label), "Edit [%s]:", old.text);
                free(vis);
                char *s = prompt_input(label);
                if (s && s[0] != '\0') {
                    Task nt = parse_add_text(s);
                    if (nt.priority[0] == '\0') strcpy(nt.priority, old.priority);
                    if (nt.due[0] == '\0') strcpy(nt.due, old.due);
                    nt.done = old.done;
                    free_task(&tasks[idx]);
                    tasks[idx] = nt;
                    save_tasks();
                    snprintf(status, sizeof(status), "Edited");
                }
                free(s);
            } else {
                free(vis);
            }
            continue;
        }
        if (k == 'd') {
            if (vis_n > 0) {
                int idx = vis[selected];
                char *removed = xstrdup(tasks[idx].text);
                free_task(&tasks[idx]);
                memmove(&tasks[idx], &tasks[idx + 1], (tasks_len - idx - 1) * sizeof(Task));
                tasks_len--;
                save_tasks();
                snprintf(status, sizeof(status), "Deleted: %s", removed);
                free(removed);
                if (selected >= (int)vis_n - 1 && selected > 0) selected--;
            }
            free(vis);
            continue;
        }
        if (k == '/') {
            free(vis);
            char *s = prompt_input("Search:");
            if (s) {
                strncpy(search, s, MAX_INPUT);
                search[MAX_INPUT] = '\0';
                selected = 0;
                if (search[0]) snprintf(status, sizeof(status), "Search: %s", search);
                else snprintf(status, sizeof(status), "Search cleared - press q or Esc to quit");
                free(s);
            }
            continue;
        }
        if (k == 'f') {
            filter_idx = (filter_idx + 1) % 5;
            selected = 0;
            snprintf(status, sizeof(status), "Filter: %s", filters[filter_idx]);
            free(vis);
            continue;
        }
        if (k == 'u') {
            FILE *bf = fopen(BACKUP_FILE, "r");
            if (bf) {
                fclose(bf);
                copy_file(BACKUP_FILE, TASKS_FILE);
                load_tasks();
                snprintf(status, sizeof(status), "Undone");
            } else {
                snprintf(status, sizeof(status), "No backup to undo");
            }
            free(vis);
            continue;
        }
        if (k == 'c') {
            int before = (int)tasks_len;
            size_t w = 0;
            for (size_t i = 0; i < tasks_len; i++) {
                if (!tasks[i].done) {
                    if (w != i) tasks[w] = tasks[i];
                    w++;
                } else {
                    free_task(&tasks[i]);
                }
            }
            tasks_len = w;
            save_tasks();
            snprintf(status, sizeof(status), "Cleared %d done", before - (int)tasks_len);
            selected = 0;
            free(vis);
            continue;
        }
        if (k == 's') {
            int total2 = (int)tasks_len;
            int done_n2 = count_done();
            int overdue_n2 = count_overdue();
            snprintf(status, sizeof(status), "Total %d - Done %d - Todo %d - Overdue %d", total2, done_n2, total2 - done_n2, overdue_n2);
            free(vis);
            continue;
        }
        if (k == '?') {
            snprintf(status, sizeof(status), "Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats");
            free(vis);
            continue;
        }
        free(vis);
    }
    disable_raw();
}

static void print_help(void) {
    printf("Usage:\n");
    printf("  tasks tui                    Interactive TUI (default, no args = tui)\n");
    printf("  tasks add [--priority P1] [--due YYYY-MM-DD] <text>\n");
    printf("  tasks list [--tag X] [--project Y] [--priority P1] [--search Q] [--overdue|--today|--done|--todo]\n");
    printf("  tasks done <n>\n");
    printf("  tasks undone <n>\n");
    printf("  tasks rm <n>\n");
    printf("  tasks edit <n> <new text>\n");
    printf("  tasks search <query>\n");
    printf("  tasks clear\n");
    printf("  tasks stats\n");
    printf("  tasks undo\n");
    printf("  tasks help\n");
    printf("\n");
    printf("Format: tasks.md lines are - [ ] (P1) due:2026-11-30 Buy milk #home +groceries\n");
    printf("Tags start with #, projects with +. Priority P1/P2/P3, due YYYY-MM-DD.\n");
    printf("TUI keys: j/k or arrows move, Space toggle, a add, e edit, d delete,\n");
    printf("  / search, f filter, u undo, c clear done, s stats, q / Esc / Ctrl-C to quit\n");
    printf("  In a prompt: Enter saves, Esc / Ctrl-C cancels\n");
}

int main(int argc, char **argv) {
    load_tasks();

    if (argc < 2 || strcmp(argv[1], "tui") == 0) {
        run_tui();
        printf("Exited TUI - back to shell. Use: ./tasks list\n");
        free_all_tasks();
        return 0;
    }

    const char *cmd = argv[1];

    if (strcmp(cmd, "help") == 0 || strcmp(cmd, "--help") == 0 || strcmp(cmd, "-h") == 0) {
        print_help();
        free_all_tasks();
        return 0;
    }

    if (strcmp(cmd, "add") == 0) {
        const char *priority = "";
        const char *due = "";
        // build full text from remaining args, skipping flags
        size_t bufcap = 256;
        size_t buflen = 0;
        char *buf = (char *)malloc(bufcap);
        buf[0] = '\0';
        for (int i = 2; i < argc; i++) {
            if (strcmp(argv[i], "--priority") == 0 && i + 1 < argc) {
                priority = argv[++i];
                continue;
            }
            if (strcmp(argv[i], "--due") == 0 && i + 1 < argc) {
                due = argv[++i];
                continue;
            }
            size_t alen = strlen(argv[i]);
            if (buflen + alen + 2 > bufcap) {
                bufcap = (buflen + alen + 2) * 2;
                buf = (char *)xrealloc(buf, bufcap);
            }
            if (buflen > 0) { strcat(buf, " "); buflen++; }
            strcat(buf, argv[i]);
            buflen += alen;
        }
        if (buflen == 0) {
            printf("Usage: tasks add <text>\n");
            free(buf);
            free_all_tasks();
            return 0;
        }
        Task t = parse_add_text(buf);
        if (priority[0]) strcpy(t.priority, priority);
        if (due[0]) strcpy(t.due, due);
        ensure_cap(tasks_len + 1);
        tasks[tasks_len++] = t;
        save_tasks();
        printf("Added: %s\n", t.text);
        free(buf);
        free_all_tasks();
        return 0;
    }

    if (strcmp(cmd, "list") == 0) {
        cli_list(argc - 2, argv + 2);
        free_all_tasks();
        return 0;
    }

    if (strcmp(cmd, "done") == 0) {
        if (argc < 3) { printf("Usage: tasks done <n>\n"); free_all_tasks(); return 0; }
        int idx = parse_task_number(argv[2], tasks_len);
        if (idx == -1) { printf("Invalid task number\n"); free_all_tasks(); return 0; }
        tasks[idx].done = 1;
        save_tasks();
        printf("Done: %s\n", tasks[idx].text);
        free_all_tasks();
        return 0;
    }

    if (strcmp(cmd, "undone") == 0) {
        if (argc < 3) { printf("Usage: tasks undone <n>\n"); free_all_tasks(); return 0; }
        int idx = parse_task_number(argv[2], tasks_len);
        if (idx == -1) { printf("Invalid task number\n"); free_all_tasks(); return 0; }
        tasks[idx].done = 0;
        save_tasks();
        printf("Todo: %s\n", tasks[idx].text);
        free_all_tasks();
        return 0;
    }

    if (strcmp(cmd, "rm") == 0) {
        if (argc < 3) { printf("Usage: tasks rm <n>\n"); free_all_tasks(); return 0; }
        int idx = parse_task_number(argv[2], tasks_len);
        if (idx == -1) { printf("Invalid task number\n"); free_all_tasks(); return 0; }
        char *removed = xstrdup(tasks[idx].text);
        free_task(&tasks[idx]);
        memmove(&tasks[idx], &tasks[idx + 1], (tasks_len - idx - 1) * sizeof(Task));
        tasks_len--;
        save_tasks();
        printf("Deleted: %s\n", removed);
        free(removed);
        free_all_tasks();
        return 0;
    }

    if (strcmp(cmd, "edit") == 0) {
        if (argc < 4) { printf("Usage: tasks edit <n> <new text>\n"); free_all_tasks(); return 0; }
        int idx = parse_task_number(argv[2], tasks_len);
        if (idx == -1) { printf("Invalid task number\n"); free_all_tasks(); return 0; }
        // join argv[3..]
        size_t bufcap = 256;
        size_t buflen = 0;
        char *buf = (char *)malloc(bufcap);
        buf[0] = '\0';
        for (int i = 3; i < argc; i++) {
            size_t alen = strlen(argv[i]);
            if (buflen + alen + 2 > bufcap) {
                bufcap = (buflen + alen + 2) * 2;
                buf = (char *)xrealloc(buf, bufcap);
            }
            if (buflen > 0) { strcat(buf, " "); buflen++; }
            strcat(buf, argv[i]);
            buflen += alen;
        }
        Task nt = parse_add_text(buf);
        Task old = tasks[idx];
        if (nt.priority[0] == '\0') strcpy(nt.priority, old.priority);
        if (nt.due[0] == '\0') strcpy(nt.due, old.due);
        nt.done = old.done;
        free_task(&tasks[idx]);
        tasks[idx] = nt;
        save_tasks();
        printf("Edited %d: %s\n", idx + 1, nt.text);
        free(buf);
        free_all_tasks();
        return 0;
    }

    if (strcmp(cmd, "search") == 0) {
        if (argc < 3) { printf("Usage: tasks search <query>\n"); free_all_tasks(); return 0; }
        // join query
        size_t bufcap = 256;
        size_t buflen = 0;
        char *q = (char *)malloc(bufcap);
        q[0] = '\0';
        for (int i = 2; i < argc; i++) {
            size_t alen = strlen(argv[i]);
            if (buflen + alen + 2 > bufcap) {
                bufcap = (buflen + alen + 2) * 2;
                q = (char *)xrealloc(q, bufcap);
            }
            if (buflen > 0) { strcat(q, " "); buflen++; }
            strcat(q, argv[i]);
            buflen += alen;
        }
        int found = 0;
        for (size_t i = 0; i < tasks_len; i++) {
            if (matches_search(&tasks[i], q)) {
                print_task((int)i, &tasks[i]);
                found = 1;
            }
        }
        if (!found) printf("No matches.\n");
        free(q);
        free_all_tasks();
        return 0;
    }

    if (strcmp(cmd, "clear") == 0) {
        int before = (int)tasks_len;
        size_t w = 0;
        for (size_t i = 0; i < tasks_len; i++) {
            if (!tasks[i].done) {
                if (w != i) tasks[w] = tasks[i];
                w++;
            } else {
                free_task(&tasks[i]);
            }
        }
        tasks_len = w;
        save_tasks();
        printf("Cleared %d done tasks\n", before - (int)tasks_len);
        free_all_tasks();
        return 0;
    }

    if (strcmp(cmd, "stats") == 0) {
        int total = (int)tasks_len;
        int done_n = count_done();
        int overdue_n = count_overdue();
        int today_n = 0;
        for (size_t i = 0; i < tasks_len; i++) if (!tasks[i].done && is_today(&tasks[i])) today_n++;
        printf("Total: %d\nDone: %d\nTodo: %d\nOverdue: %d\nDue today: %d\n", total, done_n, total - done_n, overdue_n, today_n);
        // by priority
        int c1 = 0, c2 = 0, c3 = 0;
        for (size_t i = 0; i < tasks_len; i++) {
            if (strcmp(tasks[i].priority, "P1") == 0) c1++;
            else if (strcmp(tasks[i].priority, "P2") == 0) c2++;
            else if (strcmp(tasks[i].priority, "P3") == 0) c3++;
        }
        if (c1 || c2 || c3) {
            printf("By priority:\n");
            if (c1) printf("  P1: %d\n", c1);
            if (c2) printf("  P2: %d\n", c2);
            if (c3) printf("  P3: %d\n", c3);
        }
        // by tag - simple: collect unique tags, count
        // Use a small dynamic list
        char **tags = NULL;
        int *tag_counts = NULL;
        size_t tags_len = 0, tags_cap = 0;
        for (size_t i = 0; i < tasks_len; i++) {
            char *copy = xstrdup(tasks[i].text);
            char *save = NULL;
            char *tok = strtok_r(copy, " ", &save);
            while (tok) {
                if (tok[0] == '#' && tok[1] != '\0') {
                    int found = -1;
                    for (size_t k = 0; k < tags_len; k++) if (strcmp(tags[k], tok) == 0) { found = (int)k; break; }
                    if (found == -1) {
                        if (tags_len >= tags_cap) {
                            tags_cap = tags_cap ? tags_cap * 2 : 8;
                            tags = (char **)xrealloc(tags, tags_cap * sizeof(char *));
                            tag_counts = (int *)xrealloc(tag_counts, tags_cap * sizeof(int));
                        }
                        tags[tags_len] = xstrdup(tok);
                        tag_counts[tags_len] = 1;
                        tags_len++;
                    } else {
                        tag_counts[found]++;
                    }
                }
                tok = strtok_r(NULL, " ", &save);
            }
            free(copy);
        }
        if (tags_len > 0) {
            printf("By tag:\n");
            for (size_t i = 0; i < tags_len; i++) {
                printf("  %s: %d\n", tags[i], tag_counts[i]);
                free(tags[i]);
            }
        }
        free(tags);
        free(tag_counts);
        free_all_tasks();
        return 0;
    }

    if (strcmp(cmd, "undo") == 0) {
        FILE *bf = fopen(BACKUP_FILE, "r");
        if (!bf) {
            printf("No backup to undo\n");
            free_all_tasks();
            return 0;
        }
        fclose(bf);
        copy_file(BACKUP_FILE, TASKS_FILE);
        printf("Undone - restored from backup\n");
        free_all_tasks();
        return 0;
    }

    printf("Unknown command: %s\n", cmd);
    print_help();
    free_all_tasks();
    return 0;
}
