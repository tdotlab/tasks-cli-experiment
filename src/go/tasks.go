package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

const TASKS_FILE = "tasks.md"
const BACKUP_FILE = "tasks.md.bak"

const HELP = "Usage:\n  tasks tui                    Interactive TUI (default, no args = tui)\n  tasks add [--priority P1] [--due YYYY-MM-DD] <text>\n  tasks list [--tag X] [--project Y] [--priority P1] [--search Q] [--overdue|--today|--done|--todo]\n  tasks done <n>\n  tasks undone <n>\n  tasks rm <n>\n  tasks edit <n> <new text>\n  tasks search <query>\n  tasks clear\n  tasks stats\n  tasks undo\n  tasks help\n\nFormat: tasks.md lines are - [ ] (P1) due:2026-11-30 Buy milk #home +groceries\nTags start with #, projects with +. Priority P1/P2/P3, due YYYY-MM-DD.\nTUI keys: j/k or arrows move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear done, s stats, q quit\n"

type Task struct {
	Done     bool
	Priority string
	Due      string
	Text     string
}

func (t Task) Tags() []string {
	var out []string
	for _, tok := range strings.Fields(t.Text) {
		if strings.HasPrefix(tok, "#") && len(tok) > 1 {
			out = append(out, tok)
		}
	}
	return out
}

func (t Task) Projects() []string {
	var out []string
	for _, tok := range strings.Fields(t.Text) {
		if strings.HasPrefix(tok, "+") && len(tok) > 1 {
			out = append(out, tok)
		}
	}
	return out
}

func todayStr() string {
	return time.Now().Format("2006-01-02")
}

func isOverdue(t Task) bool {
	if t.Due == "" {
		return false
	}
	return t.Due < todayStr()
}

func isToday(t Task) bool {
	if t.Due == "" {
		return false
	}
	return t.Due == todayStr()
}

var lineRe = regexp.MustCompile(`^- \[( |x)\]\s*(.*)$`)
var priParenRe = regexp.MustCompile(`^\((P1|P2|P3)\)\s*`)
var duePrefixRe = regexp.MustCompile(`^due:(\d{4}-\d{2}-\d{2})\s*`)
var dueAnyRe = regexp.MustCompile(`\bdue:(\d{4}-\d{2}-\d{2})\b`)

func parseLine(line string) *Task {
	m := lineRe.FindStringSubmatch(line)
	if m == nil {
		return nil
	}
	done := m[1] == "x"
	rest := strings.TrimSpace(m[2])
	priority := ""
	if pm := priParenRe.FindStringSubmatch(rest); pm != nil {
		priority = pm[1]
		rest = strings.TrimSpace(priParenRe.ReplaceAllString(rest, ""))
	}
	due := ""
	if dm := duePrefixRe.FindStringSubmatch(rest); dm != nil {
		due = dm[1]
		rest = strings.TrimSpace(duePrefixRe.ReplaceAllString(rest, ""))
	}
	return &Task{Done: done, Priority: priority, Due: due, Text: rest}
}

func formatTask(t Task) string {
	mark := " "
	if t.Done {
		mark = "x"
	}
	parts := []string{"- [" + mark + "]"}
	if t.Priority != "" {
		parts = append(parts, "("+t.Priority+")")
	}
	if t.Due != "" {
		parts = append(parts, "due:"+t.Due)
	}
	parts = append(parts, t.Text)
	return strings.Join(parts, " ")
}

func loadTasks() []Task {
	tasks := []Task{}
	data, err := os.ReadFile(TASKS_FILE)
	if err != nil {
		return tasks
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimRight(line, "\r")
		if strings.TrimSpace(line) == "" {
			continue
		}
		if t := parseLine(line); t != nil {
			tasks = append(tasks, *t)
		}
	}
	return tasks
}

func copyFile(src, dst string) {
	data, err := os.ReadFile(src)
	if err != nil {
		return
	}
	_ = os.WriteFile(dst, data, 0644)
}

func saveTasks(tasks []Task, backup bool) {
	if backup {
		if _, err := os.Stat(TASKS_FILE); err == nil {
			copyFile(TASKS_FILE, BACKUP_FILE)
		}
	}
	var b strings.Builder
	for _, t := range tasks {
		b.WriteString(formatTask(t) + "\n")
	}
	_ = os.WriteFile(TASKS_FILE, []byte(b.String()), 0644)
}

func parseAddText(full string) Task {
	priority := ""
	due := ""
	text := strings.TrimSpace(full)
	if strings.HasPrefix(text, "P1 ") || strings.HasPrefix(text, "P2 ") || strings.HasPrefix(text, "P3 ") {
		priority = text[:2]
		text = strings.TrimSpace(text[3:])
	} else if strings.HasPrefix(text, "(P1)") || strings.HasPrefix(text, "(P2)") || strings.HasPrefix(text, "(P3)") {
		priority = text[1:3]
		text = strings.TrimSpace(text[4:])
	}
	if m := dueAnyRe.FindStringSubmatch(text); m != nil {
		due = m[1]
		text = strings.TrimSpace(dueAnyRe.ReplaceAllString(text, " "))
	}
	text = strings.Join(strings.Fields(text), " ")
	return Task{Done: false, Priority: priority, Due: due, Text: text}
}

func parseTaskNumber(s string, n int) int {
	v, err := strconv.Atoi(s)
	if err != nil {
		return -1
	}
	if v < 1 || v > n {
		return -1
	}
	return v - 1
}

func useColor() bool {
	if os.Getenv("NO_COLOR") != "" {
		return false
	}
	if os.Getenv("TERM") == "dumb" {
		return false
	}
	fi, err := os.Stdout.Stat()
	if err != nil {
		return false
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}

func col(code, s string, enabled bool) string {
	if !enabled {
		return s
	}
	return "\x1b[" + code + "m" + s + "\x1b[0m"
}

func priorityStr(t Task, enabled bool) string {
	switch t.Priority {
	case "P1":
		return col("1;31", "P1", enabled)
	case "P2":
		return col("1;33", "P2", enabled)
	case "P3":
		return col("1;36", "P3", enabled)
	}
	return ""
}

func dueStr(t Task, enabled bool) string {
	if t.Due == "" {
		return ""
	}
	if isOverdue(t) && !t.Done {
		return col("1;31", t.Due, enabled)
	}
	if isToday(t) && !t.Done {
		return col("1;32", t.Due, enabled)
	}
	return t.Due
}

func textColored(t Task, enabled bool) string {
	if !enabled {
		return t.Text
	}
	var out []string
	for _, tok := range strings.Fields(t.Text) {
		if strings.HasPrefix(tok, "#") {
			out = append(out, col("35", tok, true))
		} else if strings.HasPrefix(tok, "+") {
			out = append(out, col("34", tok, true))
		} else {
			out = append(out, tok)
		}
	}
	return strings.Join(out, " ")
}

func printTask(idx int, t Task, enabled bool) {
	mark := " "
	if t.Done {
		mark = "x"
	}
	parts := []string{fmt.Sprintf("%d.", idx+1), "[" + mark + "]"}
	if t.Priority != "" {
		parts = append(parts, priorityStr(t, enabled))
	}
	if t.Due != "" {
		parts = append(parts, dueStr(t, enabled))
	}
	parts = append(parts, textColored(t, enabled))
	fmt.Println(strings.Join(parts, " "))
}

func matchesMode(t Task, mode string) bool {
	switch mode {
	case "todo":
		return !t.Done
	case "done":
		return t.Done
	case "overdue":
		return !t.Done && isOverdue(t)
	case "today":
		return !t.Done && isToday(t)
	default:
		return true
	}
}

func matchesSearch(t Task, q string) bool {
	if q == "" {
		return true
	}
	return strings.Contains(strings.ToLower(t.Text), strings.ToLower(q))
}

func filteredIndices(tasks []Task, mode, search string) []int {
	var out []int
	for i, t := range tasks {
		if !matchesMode(t, mode) {
			continue
		}
		if !matchesSearch(t, search) {
			continue
		}
		out = append(out, i)
	}
	return out
}

func countDone(tasks []Task) int {
	n := 0
	for _, t := range tasks {
		if t.Done {
			n++
		}
	}
	return n
}

func countOverdue(tasks []Task) int {
	n := 0
	for _, t := range tasks {
		if !t.Done && isOverdue(t) {
			n++
		}
	}
	return n
}

func indexOf(s []string, v string) int {
	for i, x := range s {
		if x == v {
			return i
		}
	}
	return 0
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func cliList(tasks []Task, args []string) {
	tag := ""
	project := ""
	priority := ""
	search := ""
	mode := "all"
	i := 0
	for i < len(args) {
		a := args[i]
		if a == "--tag" && i+1 < len(args) {
			tag = args[i+1]
			i += 2
			continue
		}
		if a == "--project" && i+1 < len(args) {
			project = args[i+1]
			i += 2
			continue
		}
		if a == "--priority" && i+1 < len(args) {
			priority = args[i+1]
			i += 2
			continue
		}
		if a == "--search" && i+1 < len(args) {
			search = args[i+1]
			i += 2
			continue
		}
		if a == "--overdue" {
			mode = "overdue"
			i++
			continue
		}
		if a == "--today" {
			mode = "today"
			i++
			continue
		}
		if a == "--done" {
			mode = "done"
			i++
			continue
		}
		if a == "--todo" {
			mode = "todo"
			i++
			continue
		}
		i++
	}
	enabled := useColor()
	var shown []int
	for _, idx := range filteredIndices(tasks, mode, search) {
		t := tasks[idx]
		if tag != "" {
			found := false
			for _, tg := range t.Tags() {
				if tg == tag || tg == "#"+strings.TrimPrefix(tag, "#") {
					found = true
				}
			}
			if !found {
				continue
			}
		}
		if project != "" {
			found := false
			for _, pr := range t.Projects() {
				if pr == project || pr == "+"+strings.TrimPrefix(project, "+") {
					found = true
				}
			}
			if !found {
				continue
			}
		}
		if priority != "" && t.Priority != priority {
			continue
		}
		shown = append(shown, idx)
	}
	if len(shown) == 0 {
		fmt.Println("No tasks.")
		return
	}
	for _, idx := range shown {
		printTask(idx, tasks[idx], enabled)
	}
}

func getSttyState() string {
	out, err := exec.Command("stty", "-F", "/dev/tty", "-g").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func setRaw() {
	_ = exec.Command("stty", "-F", "/dev/tty", "cbreak", "min", "1", "-echo").Run()
}

func restoreStty(saved string) {
	if saved != "" {
		_ = exec.Command("stty", "-F", "/dev/tty", saved).Run()
	}
}

func termSize() (int, int) {
	out, err := exec.Command("stty", "-F", "/dev/tty", "size").Output()
	if err != nil {
		return 24, 80
	}
	parts := strings.Fields(string(out))
	if len(parts) == 2 {
		r, e1 := strconv.Atoi(parts[0])
		c, e2 := strconv.Atoi(parts[1])
		if e1 == nil && e2 == nil && r > 0 && c > 0 {
			return r, c
		}
	}
	return 24, 80
}

func runTUI(tasks []Task) {
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		fmt.Println("TUI needs a terminal (/dev/tty). Use: tasks list")
		return
	}
	defer tty.Close()
	saved := getSttyState()
	defer restoreStty(saved)
	setRaw()
	fmt.Print("\x1b[?25l")
	defer fmt.Print("\x1b[?25h\x1b[0m\n")

	selected := 0
	filterMode := "all"
	search := ""
	status := "Welcome - j/k move, Space toggle, a add, e edit, d delete, / search, f filter, q quit"
	filters := []string{"all", "todo", "done", "overdue", "today"}

	prompt := func(label string) string {
		restoreStty(saved)
		fmt.Print("\x1b[?25h")
		fmt.Printf("\n%s ", label)
		reader := bufio.NewReader(tty)
		line, _ := reader.ReadString('\n')
		setRaw()
		fmt.Print("\x1b[?25l")
		return strings.TrimSpace(line)
	}

	for {
		rows, cols := termSize()
		visible := filteredIndices(tasks, filterMode, search)
		if len(visible) == 0 {
			selected = 0
		} else {
			if selected >= len(visible) {
				selected = len(visible) - 1
			}
			if selected < 0 {
				selected = 0
			}
		}
		fmt.Print("\x1b[2J\x1b[H")
		total := len(tasks)
		doneN := countDone(tasks)
		overdueN := countOverdue(tasks)
		fmt.Printf("tasks - %d total | %d done | %d overdue | filter: %s | search: %s\n", total, doneN, overdueN, filterMode, search)
		fmt.Printf("%-4s %-3s %-4s %-11s %s\n", "#", "[]", "P", "Due", "Text")
		fmt.Printf("%s\n", strings.Repeat("-", minInt(cols, 80)))
		maxRows := rows - 5
		if maxRows < 5 {
			maxRows = 10
		}
		for i, idx := range visible {
			if i >= maxRows {
				break
			}
			t := tasks[idx]
			isSel := i == selected
			prefix := "  "
			if isSel {
				prefix = "> "
			}
			mark := " "
			if t.Done {
				mark = "x"
			}
			var colored []string
			for _, tok := range strings.Fields(t.Text) {
				if strings.HasPrefix(tok, "#") {
					colored = append(colored, "\x1b[35m"+tok+"\x1b[0m")
				} else if strings.HasPrefix(tok, "+") {
					colored = append(colored, "\x1b[34m"+tok+"\x1b[0m")
				} else {
					colored = append(colored, tok)
				}
			}
			txt := strings.Join(colored, " ")
			pri := "   "
			if t.Priority == "P1" {
				pri = "\x1b[1;31mP1 \x1b[0m"
			} else if t.Priority == "P2" {
				pri = "\x1b[1;33mP2 \x1b[0m"
			} else if t.Priority == "P3" {
				pri = "\x1b[1;36mP3 \x1b[0m"
			}
			due := "           "
			if t.Due != "" {
				if isOverdue(t) && !t.Done {
					due = "\x1b[1;31m" + t.Due + " \x1b[0m"
				} else if isToday(t) && !t.Done {
					due = "\x1b[1;32m" + t.Due + " \x1b[0m"
				} else {
					due = t.Due + " "
				}
			}
			line := fmt.Sprintf("%s%-4d [%-1s] %s %-11s %s", prefix, idx+1, mark, pri, strings.TrimSpace(due), txt)
			if isSel {
				fmt.Printf("\x1b[7m%s\x1b[0m\n", line)
			} else {
				if t.Done {
					fmt.Printf("\x1b[2m%s\x1b[0m\n", line)
				} else {
					fmt.Printf("%s\n", line)
				}
			}
		}
		fmt.Printf("\n%s\n", status)
		fmt.Printf("j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear done - s stats - q quit\n")

		buf := make([]byte, 3)
		n, err := tty.Read(buf)
		if err != nil {
			break
		}
		if n == 1 {
			key := buf[0]
			if key == 'q' || key == 3 || key == 27 {
				break
			} else if key == 'j' {
				if selected < len(visible)-1 {
					selected++
				}
			} else if key == 'k' {
				if selected > 0 {
					selected--
				}
			} else if key == 'g' {
				selected = 0
			} else if key == 'G' {
				if len(visible) > 0 {
					selected = len(visible) - 1
				}
			} else if key == ' ' {
				if len(visible) > 0 {
					idx := visible[selected]
					tasks[idx].Done = !tasks[idx].Done
					saveTasks(tasks, true)
					if tasks[idx].Done {
						status = "Marked done"
					} else {
						status = "Marked todo"
					}
				}
			} else if key == 'a' {
				s := prompt("Add:")
				if s != "" {
					nt := parseAddText(s)
					tasks = append(tasks, nt)
					saveTasks(tasks, true)
					selected = len(tasks) - 1
					status = fmt.Sprintf("Added: %s", nt.Text)
				} else {
					status = "Add cancelled"
				}
			} else if key == 'e' {
				if len(visible) > 0 {
					idx := visible[selected]
					old := tasks[idx]
					s := prompt(fmt.Sprintf("Edit [%s]:", old.Text))
					if s != "" {
						nt := parseAddText(s)
						if nt.Priority == "" {
							nt.Priority = old.Priority
						}
						if nt.Due == "" {
							nt.Due = old.Due
						}
						nt.Done = old.Done
						tasks[idx] = nt
						saveTasks(tasks, true)
						status = "Edited"
					}
				}
			} else if key == 'd' {
				if len(visible) > 0 {
					idx := visible[selected]
					removed := tasks[idx].Text
					tasks = append(tasks[:idx], tasks[idx+1:]...)
					saveTasks(tasks, true)
					status = fmt.Sprintf("Deleted: %s", removed)
					if selected >= len(visible)-1 && selected > 0 {
						selected--
					}
				}
			} else if key == '/' {
				s := prompt("Search:")
				search = s
				selected = 0
				if search == "" {
					status = "Search cleared"
				} else {
					status = fmt.Sprintf("Search: %s", search)
				}
			} else if key == 'f' {
				cur := indexOf(filters, filterMode)
				filterMode = filters[(cur+1)%len(filters)]
				selected = 0
				status = fmt.Sprintf("Filter: %s", filterMode)
			} else if key == 'u' {
				if _, err := os.Stat(BACKUP_FILE); err == nil {
					copyFile(BACKUP_FILE, TASKS_FILE)
					tasks = loadTasks()
					status = "Undone"
				} else {
					status = "No backup to undo"
				}
			} else if key == 'c' {
				before := len(tasks)
				var kept []Task
				for _, t := range tasks {
					if !t.Done {
						kept = append(kept, t)
					}
				}
				if kept == nil {
					kept = []Task{}
				}
				tasks = kept
				saveTasks(tasks, true)
				status = fmt.Sprintf("Cleared %d done", before-len(tasks))
				selected = 0
			} else if key == 's' {
				todoN := total - doneN
				status = fmt.Sprintf("Total %d - Done %d - Todo %d - Overdue %d", total, doneN, todoN, overdueN)
			}
		} else if n == 3 && buf[0] == 27 && buf[1] == 91 {
			if buf[2] == 65 {
				if selected > 0 {
					selected--
				}
			} else if buf[2] == 66 {
				if selected < len(visible)-1 {
					selected++
				}
			}
		}
	}
}

func main() {
	args := os.Args[1:]
	tasks := loadTasks()

	if len(args) == 0 || args[0] == "tui" {
		runTUI(tasks)
		return
	}

	cmd := args[0]

	if cmd == "help" || cmd == "--help" || cmd == "-h" {
		fmt.Print(HELP)
		return
	}

	if cmd == "add" {
		rest := args[1:]
		priority := ""
		due := ""
		var textParts []string
		i := 0
		for i < len(rest) {
			if rest[i] == "--priority" && i+1 < len(rest) {
				priority = rest[i+1]
				i += 2
				continue
			}
			if rest[i] == "--due" && i+1 < len(rest) {
				due = rest[i+1]
				i += 2
				continue
			}
			textParts = append(textParts, rest[i])
			i++
		}
		full := strings.Join(textParts, " ")
		if strings.TrimSpace(full) == "" {
			fmt.Println("Usage: tasks add <text>")
			return
		}
		t := parseAddText(full)
		if priority != "" {
			t.Priority = priority
		}
		if due != "" {
			t.Due = due
		}
		tasks = append(tasks, t)
		saveTasks(tasks, true)
		fmt.Printf("Added: %s\n", t.Text)
		return
	}

	if cmd == "list" {
		cliList(tasks, args[1:])
		return
	}

	if cmd == "done" {
		if len(args) < 2 {
			fmt.Println("Usage: tasks done <n>")
			return
		}
		idx := parseTaskNumber(args[1], len(tasks))
		if idx == -1 {
			fmt.Println("Invalid task number")
			return
		}
		tasks[idx].Done = true
		saveTasks(tasks, true)
		fmt.Printf("Done: %s\n", tasks[idx].Text)
		return
	}

	if cmd == "undone" {
		if len(args) < 2 {
			fmt.Println("Usage: tasks undone <n>")
			return
		}
		idx := parseTaskNumber(args[1], len(tasks))
		if idx == -1 {
			fmt.Println("Invalid task number")
			return
		}
		tasks[idx].Done = false
		saveTasks(tasks, true)
		fmt.Printf("Todo: %s\n", tasks[idx].Text)
		return
	}

	if cmd == "rm" {
		if len(args) < 2 {
			fmt.Println("Usage: tasks rm <n>")
			return
		}
		idx := parseTaskNumber(args[1], len(tasks))
		if idx == -1 {
			fmt.Println("Invalid task number")
			return
		}
		removed := tasks[idx].Text
		tasks = append(tasks[:idx], tasks[idx+1:]...)
		saveTasks(tasks, true)
		fmt.Printf("Deleted: %s\n", removed)
		return
	}

	if cmd == "edit" {
		if len(args) < 3 {
			fmt.Println("Usage: tasks edit <n> <new text>")
			return
		}
		idx := parseTaskNumber(args[1], len(tasks))
		if idx == -1 {
			fmt.Println("Invalid task number")
			return
		}
		nt := parseAddText(strings.Join(args[2:], " "))
		old := tasks[idx]
		if nt.Priority == "" {
			nt.Priority = old.Priority
		}
		if nt.Due == "" {
			nt.Due = old.Due
		}
		nt.Done = old.Done
		tasks[idx] = nt
		saveTasks(tasks, true)
		fmt.Printf("Edited %d: %s\n", idx+1, nt.Text)
		return
	}

	if cmd == "search" {
		if len(args) < 2 {
			fmt.Println("Usage: tasks search <query>")
			return
		}
		q := strings.Join(args[1:], " ")
		enabled := useColor()
		found := false
		for i, t := range tasks {
			if matchesSearch(t, q) {
				printTask(i, t, enabled)
				found = true
			}
		}
		if !found {
			fmt.Println("No matches.")
		}
		return
	}

	if cmd == "clear" {
		before := len(tasks)
		var kept []Task
		for _, t := range tasks {
			if !t.Done {
				kept = append(kept, t)
			}
		}
		if kept == nil {
			kept = []Task{}
		}
		tasks = kept
		saveTasks(tasks, true)
		fmt.Printf("Cleared %d done tasks\n", before-len(tasks))
		return
	}

	if cmd == "stats" {
		total := len(tasks)
		doneN := countDone(tasks)
		overdueN := countOverdue(tasks)
		todayN := 0
		for _, t := range tasks {
			if !t.Done && isToday(t) {
				todayN++
			}
		}
		fmt.Printf("Total: %d\nDone: %d\nTodo: %d\nOverdue: %d\nDue today: %d\n", total, doneN, total-doneN, overdueN, todayN)
		priCount := map[string]int{}
		tagCount := map[string]int{}
		for _, t := range tasks {
			if t.Priority != "" {
				priCount[t.Priority]++
			}
			for _, tg := range t.Tags() {
				tagCount[tg]++
			}
		}
		if len(priCount) > 0 {
			fmt.Println("By priority:")
			keys := []string{}
			for k := range priCount {
				keys = append(keys, k)
			}
			sort.Strings(keys)
			for _, k := range keys {
				fmt.Printf("  %s: %d\n", k, priCount[k])
			}
		}
		if len(tagCount) > 0 {
			fmt.Println("By tag:")
			keys := []string{}
			for k := range tagCount {
				keys = append(keys, k)
			}
			sort.Strings(keys)
			for _, k := range keys {
				fmt.Printf("  %s: %d\n", k, tagCount[k])
			}
		}
		return
	}

	if cmd == "undo" {
		if _, err := os.Stat(BACKUP_FILE); err != nil {
			fmt.Println("No backup to undo")
			return
		}
		copyFile(BACKUP_FILE, TASKS_FILE)
		fmt.Println("Undone - restored from backup")
		return
	}

	fmt.Printf("Unknown command: %s\n", cmd)
	fmt.Print(HELP)
}
