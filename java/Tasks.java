import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class Tasks {
    static final String TASKS_FILE = "tasks.md";

    static final String HELP = "Usage: tasks <command> [args]\n\n"
        + "Commands:\n"
        + "  add \"Buy milk\"   Add a task\n"
        + "  list             Show all tasks\n"
        + "  done 2           Mark task 2 complete\n"
        + "  rm 2             Delete task 2\n"
        + "  clear            Remove completed tasks\n"
        + "  stats            Show totals\n";

    static class Task {
        boolean done;
        String text;

        Task(boolean done, String text) {
            this.done = done;
            this.text = text;
        }
    }

    static List<Task> loadTasks() {
        List<Task> tasks = new ArrayList<>();
        Path path = Path.of(TASKS_FILE);
        if (!Files.exists(path)) {
            return tasks;
        }
        try {
            for (String line : Files.readAllLines(path)) {
                line = line.replaceAll("\\r$", "");
                if (line.startsWith("- [ ] ")) {
                    tasks.add(new Task(false, line.substring(6)));
                } else if (line.startsWith("- [x] ")) {
                    tasks.add(new Task(true, line.substring(6)));
                }
            }
        } catch (IOException e) {
            System.err.println("Error: could not read " + TASKS_FILE + ": " + e.getMessage());
        }
        return tasks;
    }

    static void saveTasks(List<Task> tasks) {
        List<String> lines = new ArrayList<>();
        for (Task t : tasks) {
            lines.add((t.done ? "- [x] " : "- [ ] ") + t.text);
        }
        try {
            Files.write(Path.of(TASKS_FILE), lines);
        } catch (IOException e) {
            System.err.println("Error: could not write " + TASKS_FILE + ": " + e.getMessage());
        }
    }

    static Integer parseTaskNumber(String s, int count) {
        try {
            int n = Integer.parseInt(s);
            if (n < 1 || n > count) {
                return null;
            }
            return n - 1;
        } catch (NumberFormatException e) {
            return null;
        }
    }

    public static void main(String[] args) {
        List<Task> tasks = loadTasks();

        if (args.length == 0 || args[0].equals("help") || args[0].equals("-h") || args[0].equals("--help")) {
            System.out.print(HELP);
            return;
        }

        String command = args[0];

        if (command.equals("add")) {
            if (args.length < 2) {
                System.out.println("Error: task text is required.");
                return;
            }
            String text = String.join(" ", Arrays.copyOfRange(args, 1, args.length));
            if (text.trim().isEmpty()) {
                System.out.println("Error: task text is required.");
                return;
            }
            tasks.add(new Task(false, text));
            saveTasks(tasks);
            System.out.println("Added: " + text);
            return;
        }

        if (command.equals("list")) {
            if (tasks.isEmpty()) {
                System.out.println("No tasks yet.");
                return;
            }
            for (int i = 0; i < tasks.size(); i++) {
                Task t = tasks.get(i);
                System.out.println((i + 1) + ". [" + (t.done ? "x" : " ") + "] " + t.text);
            }
            return;
        }

        if (command.equals("done")) {
            if (args.length < 2) {
                System.out.println("Error: invalid task number.");
                return;
            }
            Integer idx = parseTaskNumber(args[1], tasks.size());
            if (idx == null) {
                System.out.println("Error: invalid task number.");
                return;
            }
            tasks.get(idx).done = true;
            saveTasks(tasks);
            System.out.println("Done: " + tasks.get(idx).text);
            return;
        }

        if (command.equals("rm")) {
            if (args.length < 2) {
                System.out.println("Error: invalid task number.");
                return;
            }
            Integer idx = parseTaskNumber(args[1], tasks.size());
            if (idx == null) {
                System.out.println("Error: invalid task number.");
                return;
            }
            Task removed = tasks.remove((int) idx);
            saveTasks(tasks);
            System.out.println("Removed: " + removed.text);
            return;
        }

        if (command.equals("clear")) {
            int before = tasks.size();
            tasks.removeIf(t -> t.done);
            int cleared = before - tasks.size();
            saveTasks(tasks);
            System.out.println("Cleared " + cleared + " completed task(s).");
            return;
        }

        if (command.equals("stats")) {
            int total = tasks.size();
            int done = 0;
            for (Task t : tasks) {
                if (t.done) done++;
            }
            int remaining = total - done;
            System.out.println("Total: " + total + " | Done: " + done + " | Remaining: " + remaining);
            return;
        }

        System.out.println("Error: unknown command '" + command + "'.");
        System.out.print(HELP);
    }
}
