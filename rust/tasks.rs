use std::env;
use std::fs;

const TASKS_FILE: &str = "tasks.md";

const HELP: &str = "Usage: tasks <command> [args]\n\nCommands:\n  add \"Buy milk\"   Add a task\n  list             Show all tasks\n  done 2           Mark task 2 complete\n  rm 2             Delete task 2\n  clear            Remove completed tasks\n  stats            Show totals\n";

#[derive(Debug, Clone)]
struct Task {
    done: bool,
    text: String,
}

fn load_tasks() -> Vec<Task> {
    let mut tasks = Vec::new();
    let Ok(contents) = fs::read_to_string(TASKS_FILE) else {
        return tasks;
    };
    for line in contents.lines() {
        let line = line.strip_suffix('\r').unwrap_or(line);
        if let Some(text) = line.strip_prefix("- [ ] ") {
            tasks.push(Task {
                done: false,
                text: text.to_string(),
            });
        } else if let Some(text) = line.strip_prefix("- [x] ") {
            tasks.push(Task {
                done: true,
                text: text.to_string(),
            });
        }
    }
    tasks
}

fn save_tasks(tasks: &[Task]) {
    let mut out = String::new();
    for task in tasks {
        let prefix = if task.done { "- [x] " } else { "- [ ] " };
        out.push_str(prefix);
        out.push_str(&task.text);
        out.push('\n');
    }
    if let Err(e) = fs::write(TASKS_FILE, out) {
        eprintln!("Error: could not write {TASKS_FILE}: {e}");
    }
}

fn parse_task_number(s: &str, count: usize) -> Option<usize> {
    let n: usize = s.parse().ok()?;
    if n < 1 || n > count {
        return None;
    }
    Some(n - 1)
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let mut tasks = load_tasks();

    if args.len() < 2 || args[1] == "help" || args[1] == "-h" || args[1] == "--help" {
        print!("{HELP}");
        return;
    }

    let command = args[1].as_str();

    if command == "add" {
        if args.len() < 3 {
            println!("Error: task text is required.");
            return;
        }
        let text = args[2..].join(" ");
        if text.trim().is_empty() {
            println!("Error: task text is required.");
            return;
        }
        tasks.push(Task {
            done: false,
            text: text.clone(),
        });
        save_tasks(&tasks);
        println!("Added: {text}");
        return;
    }

    if command == "list" {
        if tasks.is_empty() {
            println!("No tasks yet.");
            return;
        }
        for (i, task) in tasks.iter().enumerate() {
            let mark = if task.done { 'x' } else { ' ' };
            println!("{}. [{mark}] {}", i + 1, task.text);
        }
        return;
    }

    if command == "done" {
        if args.len() < 3 {
            println!("Error: invalid task number.");
            return;
        }
        let Some(idx) = parse_task_number(&args[2], tasks.len()) else {
            println!("Error: invalid task number.");
            return;
        };
        tasks[idx].done = true;
        save_tasks(&tasks);
        println!("Done: {}", tasks[idx].text);
        return;
    }

    if command == "rm" {
        if args.len() < 3 {
            println!("Error: invalid task number.");
            return;
        }
        let Some(idx) = parse_task_number(&args[2], tasks.len()) else {
            println!("Error: invalid task number.");
            return;
        };
        let removed = tasks.remove(idx);
        save_tasks(&tasks);
        println!("Removed: {}", removed.text);
        return;
    }

    if command == "clear" {
        let before = tasks.len();
        tasks.retain(|t| !t.done);
        let cleared = before - tasks.len();
        save_tasks(&tasks);
        println!("Cleared {cleared} completed task(s).");
        return;
    }

    if command == "stats" {
        let total = tasks.len();
        let done = tasks.iter().filter(|t| t.done).count();
        let remaining = total - done;
        println!("Total: {total} | Done: {done} | Remaining: {remaining}");
        return;
    }

    println!("Error: unknown command '{command}'.");
    print!("{HELP}");
}
