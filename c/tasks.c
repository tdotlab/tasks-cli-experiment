#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TASKS_FILE "tasks.md"
#define MAX_TEXT 512
#define MAX_TASKS 1024

const char *HELP =
    "Usage: tasks <command> [args]\n"
    "\n"
    "Commands:\n"
    "  add \"Buy milk\"   Add a task\n"
    "  list             Show all tasks\n"
    "  done 2           Mark task 2 complete\n"
    "  rm 2             Delete task 2\n"
    "  clear            Remove completed tasks\n"
    "  stats            Show totals\n";

typedef struct {
    int done;
    char text[MAX_TEXT];
} Task;

Task tasks[MAX_TASKS];
int task_count = 0;

void load_tasks(void) {
    FILE *f = fopen(TASKS_FILE, "r");
    if (!f) {
        task_count = 0;
        return;
    }

    char line[600];
    while (fgets(line, sizeof(line), f)) {
        if (task_count >= MAX_TASKS) {
            break;
        }
        line[strcspn(line, "\r\n")] = '\0';

        if (strncmp(line, "- [ ] ", 6) == 0) {
            tasks[task_count].done = 0;
            strncpy(tasks[task_count].text, line + 6, MAX_TEXT - 1);
            tasks[task_count].text[MAX_TEXT - 1] = '\0';
            task_count++;
        } else if (strncmp(line, "- [x] ", 6) == 0) {
            tasks[task_count].done = 1;
            strncpy(tasks[task_count].text, line + 6, MAX_TEXT - 1);
            tasks[task_count].text[MAX_TEXT - 1] = '\0';
            task_count++;
        }
    }

    fclose(f);
}

void save_tasks(void) {
    FILE *f = fopen(TASKS_FILE, "w");
    if (!f) {
        perror(TASKS_FILE);
        return;
    }

    for (int i = 0; i < task_count; i++) {
        const char *prefix = tasks[i].done ? "- [x] " : "- [ ] ";
        fprintf(f, "%s%s\n", prefix, tasks[i].text);
    }

    fclose(f);
}

int parse_task_number(const char *s, int count) {
    char *end = NULL;
    long n = strtol(s, &end, 10);
    if (end == s || *end != '\0') {
        return -1;
    }
    if (n < 1 || n > count) {
        return -1;
    }
    return (int)n - 1;
}

int main(int argc, char *argv[]) {
    load_tasks();

    if (argc < 2 ||
        strcmp(argv[1], "help") == 0 ||
        strcmp(argv[1], "-h") == 0 ||
        strcmp(argv[1], "--help") == 0) {
        printf("%s", HELP);
        return 0;
    }

    if (strcmp(argv[1], "add") == 0) {
        if (argc < 3) {
            printf("Error: task text is required.\n");
            return 0;
        }
        char text[MAX_TEXT];
        text[0] = '\0';
        for (int i = 2; i < argc; i++) {
            if (i > 2) {
                strncat(text, " ", MAX_TEXT - strlen(text) - 1);
            }
            strncat(text, argv[i], MAX_TEXT - strlen(text) - 1);
        }
        int only_spaces = 1;
        for (int i = 0; text[i] != '\0'; i++) {
            if (text[i] != ' ' && text[i] != '\t') {
                only_spaces = 0;
                break;
            }
        }
        if (only_spaces) {
            printf("Error: task text is required.\n");
            return 0;
        }
        if (task_count >= MAX_TASKS) {
            printf("Error: task list is full.\n");
            return 0;
        }
        tasks[task_count].done = 0;
        strncpy(tasks[task_count].text, text, MAX_TEXT - 1);
        tasks[task_count].text[MAX_TEXT - 1] = '\0';
        task_count++;
        save_tasks();
        printf("Added: %s\n", text);
        return 0;
    }

    if (strcmp(argv[1], "list") == 0) {
        if (task_count == 0) {
            printf("No tasks yet.\n");
            return 0;
        }
        for (int i = 0; i < task_count; i++) {
            printf("%d. [%c] %s\n", i + 1, tasks[i].done ? 'x' : ' ', tasks[i].text);
        }
        return 0;
    }

    if (strcmp(argv[1], "done") == 0) {
        if (argc < 3) {
            printf("Error: invalid task number.\n");
            return 0;
        }
        int idx = parse_task_number(argv[2], task_count);
        if (idx == -1) {
            printf("Error: invalid task number.\n");
            return 0;
        }
        tasks[idx].done = 1;
        save_tasks();
        printf("Done: %s\n", tasks[idx].text);
        return 0;
    }

    if (strcmp(argv[1], "rm") == 0) {
        if (argc < 3) {
            printf("Error: invalid task number.\n");
            return 0;
        }
        int idx = parse_task_number(argv[2], task_count);
        if (idx == -1) {
            printf("Error: invalid task number.\n");
            return 0;
        }
        char removed[MAX_TEXT];
        strncpy(removed, tasks[idx].text, MAX_TEXT - 1);
        removed[MAX_TEXT - 1] = '\0';
        for (int i = idx; i < task_count - 1; i++) {
            tasks[i] = tasks[i + 1];
        }
        task_count--;
        save_tasks();
        printf("Removed: %s\n", removed);
        return 0;
    }

    if (strcmp(argv[1], "clear") == 0) {
        int before = task_count;
        int write = 0;
        for (int i = 0; i < task_count; i++) {
            if (!tasks[i].done) {
                if (write != i) {
                    tasks[write] = tasks[i];
                }
                write++;
            }
        }
        int cleared = before - write;
        task_count = write;
        save_tasks();
        printf("Cleared %d completed task(s).\n", cleared);
        return 0;
    }

    if (strcmp(argv[1], "stats") == 0) {
        int total = task_count;
        int done = 0;
        for (int i = 0; i < task_count; i++) {
            if (tasks[i].done) {
                done++;
            }
        }
        int remaining = total - done;
        printf("Total: %d | Done: %d | Remaining: %d\n", total, done, remaining);
        return 0;
    }

    printf("Error: unknown command '%s'.\n", argv[1]);
    printf("%s", HELP);
    return 0;
}
