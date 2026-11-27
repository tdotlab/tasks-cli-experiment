#include <algorithm>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

const std::string TASKS_FILE = "tasks.md";

const std::string HELP =
    "Usage: tasks <command> [args]\n"
    "\n"
    "Commands:\n"
    "  add \"Buy milk\"   Add a task\n"
    "  list             Show all tasks\n"
    "  done 2           Mark task 2 complete\n"
    "  rm 2             Delete task 2\n"
    "  clear            Remove completed tasks\n"
    "  stats            Show totals\n";

struct Task {
    bool done = false;
    std::string text;
};

std::vector<Task> load_tasks() {
    std::vector<Task> tasks;
    std::ifstream in(TASKS_FILE);
    if (!in) {
        return tasks;
    }
    std::string line;
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        if (line.rfind("- [ ] ", 0) == 0) {
            tasks.push_back({false, line.substr(6)});
        } else if (line.rfind("- [x] ", 0) == 0) {
            tasks.push_back({true, line.substr(6)});
        }
    }
    return tasks;
}

void save_tasks(const std::vector<Task> &tasks) {
    std::ofstream out(TASKS_FILE);
    if (!out) {
        std::cerr << "Error: could not open " << TASKS_FILE << " for writing.\n";
        return;
    }
    for (const auto &task : tasks) {
        out << (task.done ? "- [x] " : "- [ ] ") << task.text << "\n";
    }
}

int parse_task_number(const std::string &s, int count) {
    try {
        size_t pos = 0;
        int n = std::stoi(s, &pos);
        if (pos != s.size()) {
            return -1;
        }
        if (n < 1 || n > count) {
            return -1;
        }
        return n - 1;
    } catch (...) {
        return -1;
    }
}

int main(int argc, char *argv[]) {
    std::vector<Task> tasks = load_tasks();

    if (argc < 2 ||
        std::string(argv[1]) == "help" ||
        std::string(argv[1]) == "-h" ||
        std::string(argv[1]) == "--help") {
        std::cout << HELP;
        return 0;
    }

    std::string command = argv[1];

    if (command == "add") {
        if (argc < 3) {
            std::cout << "Error: task text is required.\n";
            return 0;
        }
        std::string text;
        for (int i = 2; i < argc; i++) {
            if (i > 2) text += " ";
            text += argv[i];
        }
        bool only_spaces = true;
        for (char c : text) {
            if (c != ' ' && c != '\t') {
                only_spaces = false;
                break;
            }
        }
        if (only_spaces) {
            std::cout << "Error: task text is required.\n";
            return 0;
        }
        tasks.push_back({false, text});
        save_tasks(tasks);
        std::cout << "Added: " << text << "\n";
        return 0;
    }

    if (command == "list") {
        if (tasks.empty()) {
            std::cout << "No tasks yet.\n";
            return 0;
        }
        for (size_t i = 0; i < tasks.size(); i++) {
            std::cout << (i + 1) << ". [" << (tasks[i].done ? 'x' : ' ') << "] " << tasks[i].text << "\n";
        }
        return 0;
    }

    if (command == "done") {
        if (argc < 3) {
            std::cout << "Error: invalid task number.\n";
            return 0;
        }
        int idx = parse_task_number(argv[2], (int)tasks.size());
        if (idx == -1) {
            std::cout << "Error: invalid task number.\n";
            return 0;
        }
        tasks[idx].done = true;
        save_tasks(tasks);
        std::cout << "Done: " << tasks[idx].text << "\n";
        return 0;
    }

    if (command == "rm") {
        if (argc < 3) {
            std::cout << "Error: invalid task number.\n";
            return 0;
        }
        int idx = parse_task_number(argv[2], (int)tasks.size());
        if (idx == -1) {
            std::cout << "Error: invalid task number.\n";
            return 0;
        }
        std::string removed = tasks[idx].text;
        tasks.erase(tasks.begin() + idx);
        save_tasks(tasks);
        std::cout << "Removed: " << removed << "\n";
        return 0;
    }

    if (command == "clear") {
        int before = (int)tasks.size();
        tasks.erase(
            std::remove_if(tasks.begin(), tasks.end(),
                           [](const Task &t) { return t.done; }),
            tasks.end());
        int cleared = before - (int)tasks.size();
        save_tasks(tasks);
        std::cout << "Cleared " << cleared << " completed task(s).\n";
        return 0;
    }

    if (command == "stats") {
        int total = (int)tasks.size();
        int done = 0;
        for (const auto &t : tasks) {
            if (t.done) done++;
        }
        int remaining = total - done;
        std::cout << "Total: " << total << " | Done: " << done << " | Remaining: " << remaining << "\n";
        return 0;
    }

    std::cout << "Error: unknown command '" << command << "'.\n";
    std::cout << HELP;
    return 0;
}
