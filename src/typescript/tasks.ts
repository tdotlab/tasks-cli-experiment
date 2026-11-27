import * as fs from "fs";

const TASKS_FILE = "tasks.md";

const HELP = `Usage: tasks <command> [args]

Commands:
  add "Buy milk"   Add a task
  list             Show all tasks
  done 2           Mark task 2 complete
  rm 2             Delete task 2
  clear            Remove completed tasks
  stats            Show totals
`;

interface Task {
  done: boolean;
  text: string;
}

function loadTasks(): Task[] {
  if (!fs.existsSync(TASKS_FILE)) {
    return [];
  }
  const content = fs.readFileSync(TASKS_FILE, "utf-8");
  const tasks: Task[] = [];
  for (const rawLine of content.split("\n")) {
    const line = rawLine.replace(/\r$/, "");
    if (line.startsWith("- [ ] ")) {
      tasks.push({ done: false, text: line.slice(6) });
    } else if (line.startsWith("- [x] ")) {
      tasks.push({ done: true, text: line.slice(6) });
    }
  }
  return tasks;
}

function saveTasks(tasks: Task[]): void {
  const body = tasks.map((t) => `${t.done ? "- [x] " : "- [ ] "}${t.text}`).join("\n");
  fs.writeFileSync(TASKS_FILE, body ? body + "\n" : "");
}

function parseTaskNumber(s: string, count: number): number | null {
  if (!/^\d+$/.test(s)) {
    return null;
  }
  const n = parseInt(s, 10);
  if (n < 1 || n > count) {
    return null;
  }
  return n - 1;
}

function main(): void {
  const args = process.argv.slice(2);
  const tasks = loadTasks();

  if (args.length === 0 || args[0] === "help" || args[0] === "-h" || args[0] === "--help") {
    console.log(HELP);
    return;
  }

  const command = args[0];

  if (command === "add") {
    if (args.length < 2) {
      console.log("Error: task text is required.");
      return;
    }
    const text = args.slice(1).join(" ");
    if (!text.trim()) {
      console.log("Error: task text is required.");
      return;
    }
    tasks.push({ done: false, text });
    saveTasks(tasks);
    console.log(`Added: ${text}`);
    return;
  }

  if (command === "list") {
    if (tasks.length === 0) {
      console.log("No tasks yet.");
      return;
    }
    tasks.forEach((task, i) => {
      console.log(`${i + 1}. [${task.done ? "x" : " "}] ${task.text}`);
    });
    return;
  }

  if (command === "done") {
    if (args.length < 2) {
      console.log("Error: invalid task number.");
      return;
    }
    const idx = parseTaskNumber(args[1], tasks.length);
    if (idx === null) {
      console.log("Error: invalid task number.");
      return;
    }
    tasks[idx].done = true;
    saveTasks(tasks);
    console.log(`Done: ${tasks[idx].text}`);
    return;
  }

  if (command === "rm") {
    if (args.length < 2) {
      console.log("Error: invalid task number.");
      return;
    }
    const idx = parseTaskNumber(args[1], tasks.length);
    if (idx === null) {
      console.log("Error: invalid task number.");
      return;
    }
    const [removed] = tasks.splice(idx, 1);
    saveTasks(tasks);
    console.log(`Removed: ${removed.text}`);
    return;
  }

  if (command === "clear") {
    const before = tasks.length;
    const kept = tasks.filter((t) => !t.done);
    const cleared = before - kept.length;
    tasks.length = 0;
    tasks.push(...kept);
    saveTasks(tasks);
    console.log(`Cleared ${cleared} completed task(s).`);
    return;
  }

  if (command === "stats") {
    const total = tasks.length;
    const done = tasks.filter((t) => t.done).length;
    const remaining = total - done;
    console.log(`Total: ${total} | Done: ${done} | Remaining: ${remaining}`);
    return;
  }

  console.log(`Error: unknown command '${command}'.`);
  console.log(HELP);
}

main();
