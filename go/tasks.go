package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

const tasksFile = "tasks.md"

const help = `Usage: tasks <command> [args]

Commands:
  add "Buy milk"   Add a task
  list             Show all tasks
  done 2           Mark task 2 complete
  rm 2             Delete task 2
  clear            Remove completed tasks
  stats            Show totals
`

type Task struct {
	Done bool
	Text string
}

func loadTasks() []Task {
	tasks := []Task{}
	data, err := os.ReadFile(tasksFile)
	if err != nil {
		return tasks
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSuffix(line, "\r")
		if strings.HasPrefix(line, "- [ ] ") {
			tasks = append(tasks, Task{Done: false, Text: line[6:]})
		} else if strings.HasPrefix(line, "- [x] ") {
			tasks = append(tasks, Task{Done: true, Text: line[6:]})
		}
	}
	return tasks
}

func saveTasks(tasks []Task) {
	var b strings.Builder
	for _, t := range tasks {
		prefix := "- [ ] "
		if t.Done {
			prefix = "- [x] "
		}
		b.WriteString(prefix)
		b.WriteString(t.Text)
		b.WriteString("\n")
	}
	if err := os.WriteFile(tasksFile, []byte(b.String()), 0644); err != nil {
		fmt.Fprintf(os.Stderr, "Error: could not write %s: %v\n", tasksFile, err)
	}
}

func parseTaskNumber(s string, count int) (int, bool) {
	n, err := strconv.Atoi(s)
	if err != nil || n < 1 || n > count {
		return 0, false
	}
	return n - 1, true
}

func main() {
	args := os.Args[1:]
	tasks := loadTasks()

	if len(args) == 0 || args[0] == "help" || args[0] == "-h" || args[0] == "--help" {
		fmt.Print(help)
		return
	}

	command := args[0]

	if command == "add" {
		if len(args) < 2 {
			fmt.Println("Error: task text is required.")
			return
		}
		text := strings.Join(args[1:], " ")
		if strings.TrimSpace(text) == "" {
			fmt.Println("Error: task text is required.")
			return
		}
		tasks = append(tasks, Task{Done: false, Text: text})
		saveTasks(tasks)
		fmt.Printf("Added: %s\n", text)
		return
	}

	if command == "list" {
		if len(tasks) == 0 {
			fmt.Println("No tasks yet.")
			return
		}
		for i, t := range tasks {
			mark := " "
			if t.Done {
				mark = "x"
			}
			fmt.Printf("%d. [%s] %s\n", i+1, mark, t.Text)
		}
		return
	}

	if command == "done" {
		if len(args) < 2 {
			fmt.Println("Error: invalid task number.")
			return
		}
		idx, ok := parseTaskNumber(args[1], len(tasks))
		if !ok {
			fmt.Println("Error: invalid task number.")
			return
		}
		tasks[idx].Done = true
		saveTasks(tasks)
		fmt.Printf("Done: %s\n", tasks[idx].Text)
		return
	}

	if command == "rm" {
		if len(args) < 2 {
			fmt.Println("Error: invalid task number.")
			return
		}
		idx, ok := parseTaskNumber(args[1], len(tasks))
		if !ok {
			fmt.Println("Error: invalid task number.")
			return
		}
		removed := tasks[idx]
		tasks = append(tasks[:idx], tasks[idx+1:]...)
		saveTasks(tasks)
		fmt.Printf("Removed: %s\n", removed.Text)
		return
	}

	if command == "clear" {
		before := len(tasks)
		kept := []Task{}
		for _, t := range tasks {
			if !t.Done {
				kept = append(kept, t)
			}
		}
		cleared := before - len(kept)
		tasks = kept
		saveTasks(tasks)
		fmt.Printf("Cleared %d completed task(s).\n", cleared)
		return
	}

	if command == "stats" {
		total := len(tasks)
		done := 0
		for _, t := range tasks {
			if t.Done {
				done++
			}
		}
		remaining := total - done
		fmt.Printf("Total: %d | Done: %d | Remaining: %d\n", total, done, remaining)
		return
	}

	fmt.Printf("Error: unknown command '%s'.\n", command)
	fmt.Print(help)
}
