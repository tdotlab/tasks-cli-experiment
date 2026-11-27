package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strings"
	"time"
)

const tasksFile = "tasks.md"
const backupFile = "tasks.md.bak"

type Task struct {
	Done     bool
	Priority string
	Due      string
	Text     string
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
var priRe = regexp.MustCompile(`^\((P1|P2|P3)\)\s*`)
var dueRe = regexp.MustCompile(`^due:(\d{4}-\d{2}-\d{2})\s*`)
var dueInTextRe = regexp.MustCompile(`\bdue:(\d{4}-\d{2}-\d{2})\b`)
var priPlainRe = regexp.MustCompile(`^(P1|P2|P3)\s+`)

func parseLine(line string) (Task, bool) {
	m := lineRe.FindStringSubmatch(line)
	if m == nil {
		return Task{}, false
	}
	done := m[1] == "x"
	rest := strings.TrimSpace(m[2])
	priority := ""
	if pm := priRe.FindStringSubmatch(rest); pm != nil {
		priority = pm[1]
		rest = strings.TrimSpace(priRe.ReplaceAllString(rest, ""))
	}
	due := ""
	if dm := dueRe.FindStringSubmatch(rest); dm != nil {
		due = dm[1]
		rest = strings.TrimSpace(dueRe.ReplaceAllString(rest, ""))
	}
	return Task{Done: done, Priority: priority, Due: due, Text: rest}, true
}

func formatTask(t Task) string {
	mark := " "
	if t.Done {
		mark = "x"
	}
	parts := []string{fmt.Sprintf("- [%s]", mark)}
	if t.Priority != "" {
		parts = append(parts, fmt.Sprintf("(%s)", t.Priority))
	}
	if t.Due != "" {
		parts = append(parts, fmt.Sprintf("due:%s", t.Due))
	}
	parts = append(parts, t.Text)
	return strings.Join(parts, " ")
}

func loadTasks() []Task {
	f, err := os.Open(tasksFile)
	if err != nil {
		return []Task{}
	}
	defer f.Close()
	var out []Task
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		line := strings.TrimRight(sc.Text(), "\r")
		if strings.TrimSpace(line) == "" {
			continue
		}
		if t, ok := parseLine(line); ok {
			out = append(out, t)
		}
	}
	if out == nil {
		out = []Task{}
	}
	return out
}

func saveTasks(tasks []Task) {
	if _, err := os.Stat(tasksFile); err == nil {
		_ = copyFile(tasksFile, backupFile)
	}
	var b strings.Builder
	for _, t := range tasks {
		b.WriteString(formatTask(t) + "\n")
	}
	_ = os.WriteFile(tasksFile, []byte(b.String()), 0644)
}

func copyFile(src, dst string) error {
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, data, 0644)
}

func parseAddText(full string) Task {
	text := strings.TrimSpace(full)
	priority := ""
	due := ""
	if m := priPlainRe.FindStringSubmatch(text); m != nil {
		priority = m[1]
		text = strings.TrimSpace(priPlainRe.ReplaceAllString(text, ""))
	} else if m := priRe.FindStringSubmatch(text); m != nil {
		priority = m[1]
		text = strings.TrimSpace(priRe.ReplaceAllString(text, ""))
	}
	if m := dueInTextRe.FindStringSubmatch(text); m != nil {
		due = m[1]
		text = strings.TrimSpace(dueInTextRe.ReplaceAllString(text, " "))
	}
	text = strings.Join(strings.Fields(text), " ")
	return Task{Done: false, Priority: priority, Due: due, Text: text}
}

func parseTaskNumber(s string, n int) int {
	var v int
	_, err := fmt.Sscanf(s, "%d", &v)
	if err != nil || v < 1 || v > n {
		return -1
	}
	return v - 1
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

func tagsOf(t Task) []string {
	var out []string
	for _, tok := range strings.Fields(t.Text) {
		if strings.HasPrefix(tok, "#") && len(tok) > 1 {
			out = append(out, tok)
		}
	}
	return out
}

func projectsOf(t Task) []string {
	var out []string
	for _, tok := range strings.Fields(t.Text) {
		if strings.HasPrefix(tok, "+") && len(tok) > 1 {
			out = append(out, tok)
		}
	}
	return out
}

func hasTag(t Task, tag string) bool {
	want := strings.TrimPrefix(tag, "#")
	for _, tg := range tagsOf(t) {
		if tg == tag || tg == "#"+want {
			return true
		}
	}
	return false
}

func hasProject(t Task, proj string) bool {
	want := strings.TrimPrefix(proj, "+")
	for _, pr := range projectsOf(t) {
		if pr == proj || pr == "+"+want {
			return true
		}
	}
	return false
}

func printTask(idx int, t Task) {
	mark := " "
	if t.Done {
		mark = "x"
	}
	parts := []string{fmt.Sprintf("%d.", idx+1), fmt.Sprintf("[%s]", mark)}
	if t.Priority != "" {
		parts = append(parts, t.Priority)
	}
	if t.Due != "" {
		parts = append(parts, t.Due)
	}
	parts = append(parts, t.Text)
	fmt.Println(strings.Join(parts, " "))
}

func cliList(tasks []Task, args []string) {
	tag, project, priority, search := "", "", "", ""
	mode := "all"
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "--tag" && i+1 < len(args) {
			tag = args[i+1]
			i++
			continue
		}
		if a == "--project" && i+1 < len(args) {
			project = args[i+1]
			i++
			continue
		}
		if a == "--priority" && i+1 < len(args) {
			priority = args[i+1]
			i++
			continue
		}
		if a == "--search" && i+1 < len(args) {
			search = args[i+1]
			i++
			continue
		}
		if a == "--overdue" {
			mode = "overdue"
		} else if a == "--today" {
			mode = "today"
		} else if a == "--done" {
			mode = "done"
		} else if a == "--todo" {
			mode = "todo"
		}
	}
	shown := 0
	for _, idx := range filteredIndices(tasks, mode, search) {
		t := tasks[idx]
		if tag != "" && !hasTag(t, tag) {
			continue
		}
		if project != "" && !hasProject(t, project) {
			continue
		}
		if priority != "" && t.Priority != priority {
			continue
		}
		printTask(idx, t)
		shown++
	}
	if shown == 0 {
		fmt.Println("No tasks.")
	}
}

// ---------------------------------------------------------------------------
// TUI - AUDITED FIXES
// 1. Prompt has NO small char limit: reads bytes one-by-one into a growing
//    slice, 4096 cap, horizontal scroll. Old Go used bufio.Scanner / fixed
//    buffer for prompts which could truncate. Now dynamic.
// 2. Exit is explicit: q, Q, Esc, Ctrl-C, Ctrl-D, Ctrl-Q all quit from
//    main list, footer always shows "q / Esc / Ctrl-C to quit". In a
//    prompt, Enter saves, Esc / Ctrl-C cancels back to list.
// ---------------------------------------------------------------------------

func termSize() (int, int) {
	out, err := exec.Command("stty", "size").Output()
	if err != nil {
		return 24, 80
	}
	var rows, cols int
	_, err = fmt.Sscanf(strings.TrimSpace(string(out)), "%d %d", &rows, &cols)
	if err != nil || rows <= 0 || cols <= 0 {
		return 24, 80
	}
	return rows, cols
}

func enableRaw() func() {
	// Save state
	out, err := exec.Command("stty", "-F", "/dev/tty", "-g").Output()
	saved := ""
	if err == nil {
		saved = strings.TrimSpace(string(out))
	} else {
		// macOS fallback
		out2, err2 := exec.Command("stty", "-f", "/dev/tty", "-g").Output()
		if err2 == nil {
			saved = strings.TrimSpace(string(out2))
		}
	}
	// Raw: no echo, cbreak, min 1
	_ = exec.Command("stty", "-F", "/dev/tty", "-echo", "cbreak", "min", "1").Run()
	_ = exec.Command("stty", "-f", "/dev/tty", "-echo", "cbreak", "min", "1").Run()
	return func() {
		if saved != "" {
			_ = exec.Command("stty", "-F", "/dev/tty", saved).Run()
			_ = exec.Command("stty", "-f", "/dev/tty", saved).Run()
		} else {
			_ = exec.Command("stty", "-F", "/dev/tty", "sane").Run()
			_ = exec.Command("stty", "-f", "/dev/tty", "sane").Run()
		}
		// Move to new line so shell prompt is clean
		fmt.Print("\n")
	}
}

func readKey() (string, bool) {
	buf := make([]byte, 1)
	n, err := os.Stdin.Read(buf)
	if err != nil || n == 0 {
		return "", false
	}
	b := buf[0]
	// Esc sequence - arrows
	if b == 27 {
		// Peek if more bytes available - try non-blocking read via checking
		// In raw cbreak min 1, next Read will block, so we need to try with timeout.
		// Simpler: if user pressed Esc alone, next read would block.
		// We handle Esc-alone as quit by returning "esc" immediately.
		// Arrow keys arrive as Esc [ A/B/C/D in quick succession, but on
		// Debian dev box with stty cbreak, they arrive together. We attempt
		// a second read with a short trick: set stdin to non-blocking via stty?
		// For simplicity, treat single Esc as quit, and arrows are handled
		// via j/k as well. Arrow support: try to read 2 more bytes if available
		// by using a goroutine with timeout.
		type res struct {
			b byte
			ok bool
		}
		ch1 := make(chan res, 1)
		go func() {
			bb := make([]byte, 1)
			nn, ee := os.Stdin.Read(bb)
			if ee != nil || nn == 0 {
				ch1 <- res{0, false}
				return
			}
			ch1 <- res{bb[0], true}
		}()
		// Wait 30ms for next byte
		select {
		case r := <-ch1:
			if !r.ok || r.b != '[' {
				return "esc", true
			}
			// Read third byte
			ch2 := make(chan res, 1)
			go func() {
				bb := make([]byte, 1)
				nn, ee := os.Stdin.Read(bb)
				if ee != nil || nn == 0 {
					ch2 <- res{0, false}
					return
				}
				ch2 <- res{bb[0], true}
			}()
			select {
			case r2 := <-ch2:
				if !r2.ok {
					return "esc", true
				}
				switch r2.b {
				case 'A':
					return "up", true
				case 'B':
					return "down", true
				case 'C':
					return "right", true
				case 'D':
					return "left", true
				default:
					return "esc", true
				}
			case <-time.After(30 * time.Millisecond):
				return "esc", true
			}
		case <-time.After(30 * time.Millisecond):
			return "esc", true
		}
	}
	if b == 3 { // Ctrl-C
		return "ctrl-c", true
	}
	if b == 4 { // Ctrl-D
		return "ctrl-d", true
	}
	if b == 17 { // Ctrl-Q
		return "ctrl-q", true
	}
	if b == 13 || b == 10 {
		return "enter", true
	}
	if b == 127 || b == 8 {
		return "backspace", true
	}
	if b >= 32 && b <= 126 {
		return string([]byte{b}), true
	}
	return "", true
}

// promptInput: dynamic, no small limit, horizontal scroll, Esc cancels
func promptInput(label, initial string) (string, bool) {
	_, w := termSize()
	if w < 20 {
		w = 80
	}
	// Build as rune slice for simplicity (ASCII tasks, but handle UTF-8 via runes)
	text := []rune(initial)
	cursor := len(text)
	offset := 0
	labelStr := label + " "
	for {
		_, w2 := termSize()
		if w2 > 10 {
			w = w2
		}
		avail := w - len([]rune(labelStr)) - 1
		if avail < 10 {
			avail = 10
		}
		if cursor < offset {
			offset = cursor
		}
		if cursor >= offset+avail {
			offset = cursor - avail + 1
		}
		if offset < 0 {
			offset = 0
		}
		// Clear prompt line + hint line
		fmt.Printf("\x1b[%d;1H\x1b[2KEnter=save  Esc / Ctrl-C=cancel", 24)
		// Use actual rows for hint: we render prompt at bottom row, hint above
		rows, _ := termSize()
		fmt.Printf("\x1b[%d;1H\x1b[2K", rows-1)
		fmt.Printf("Enter=save  Esc / Ctrl-C=cancel")
		fmt.Printf("\x1b[%d;1H\x1b[2K", rows)
		visible := ""
		if offset < len(text) {
			end := offset + avail
			if end > len(text) {
				end = len(text)
			}
			visible = string(text[offset:end])
		}
		fmt.Printf("%s%s", labelStr, visible)
		// Move cursor
		cursorX := len([]rune(labelStr)) + (cursor - offset) + 1
		if cursorX >= w {
			cursorX = w
		}
		fmt.Printf("\x1b[%d;%dH", rows, cursorX)
		// Read key
		key, ok := readKey()
		if !ok {
			continue
		}
		switch key {
		case "enter":
			fmt.Print("\x1b[?25l")
			return strings.TrimSpace(string(text)), true
		case "esc", "ctrl-c", "ctrl-d":
			return "", false
		case "backspace":
			if cursor > 0 {
				text = append(text[:cursor-1], text[cursor:]...)
				cursor--
			}
		case "left":
			if cursor > 0 {
				cursor--
			}
		case "right":
			if cursor < len(text) {
				cursor++
			}
		case "up", "down":
			// ignore in prompt
		default:
			if len(key) == 1 {
				r := []rune(key)[0]
				if r >= 32 && r <= 126 {
					if len(text) < 4096 {
						text = append(text[:cursor], append([]rune{r}, text[cursor:]...)...)
						cursor++
					}
				}
			} else if len(key) > 1 {
				// Multi-byte UTF-8 from Read of single byte is handled as separate
				// bytes above; for simplicity, insert runes
				for _, r := range key {
					if len(text) < 4096 {
						text = append(text[:cursor], append([]rune{r}, text[cursor:]...)...)
						cursor++
					}
				}
			}
		}
	}
}

func runTUI(tasks []Task) {
	restore := enableRaw()
	defer restore()
	// Hide cursor? Keep visible for prompt, but hide in list - we show cursor via ANSI
	selected := 0
	filterMode := "all"
	search := ""
	status := "Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter"
	filters := []string{"all", "todo", "done", "overdue", "today"}

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
		// Clear + draw
		fmt.Print("\x1b[2J\x1b[H")
		total := len(tasks)
		doneN := countDone(tasks)
		overdueN := countOverdue(tasks)
		header := fmt.Sprintf("tasks - %d total | %d done | %d overdue | filter: %s | search: %s", total, doneN, overdueN, filterMode, search)
		if len(header) > cols {
			header = header[:cols]
		}
		fmt.Println(header)
		fmt.Println(fmt.Sprintf("%-4s %-3s %-4s %-11s Text", "#", "[]", "P", "Due"))
		fmt.Println(strings.Repeat("-", minInt(cols, 80)))
		maxRows := rows - 5
		if maxRows < 5 {
			maxRows = 5
		}
		for i := 0; i < len(visible) && i < maxRows; i++ {
			idx := visible[i]
			t := tasks[idx]
			mark := " "
			if t.Done {
				mark = "x"
			}
			pri := ""
			if t.Priority != "" {
				pri = fmt.Sprintf("(%s) ", t.Priority)
			}
			due := ""
			if t.Due != "" {
				due = fmt.Sprintf("due:%s ", t.Due)
			}
			line := fmt.Sprintf("%-4d [%s] %s%s%s", idx+1, mark, pri, due, t.Text)
			if len(line) > cols {
				line = line[:cols]
			}
			if i == selected {
				fmt.Printf("\x1b[7m%s\x1b[0m\n", line)
			} else if t.Done {
				fmt.Printf("\x1b[2m%s\x1b[0m\n", line)
			} else {
				fmt.Println(line)
			}
		}
		// Status + footer - footer ALWAYS shows quit
		fmt.Printf("\x1b[%d;1H\x1b[2K%s", rows-2, truncate(status, cols))
		fmt.Printf("\x1b[%d;1H\x1b[2K%s", rows-1, truncate("q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats", cols))
		fmt.Printf("\x1b[%d;1H", rows)
		key, ok := readKey()
		if !ok {
			continue
		}
		// EXIT - checked first
		if key == "q" || key == "Q" || key == "esc" || key == "ctrl-c" || key == "ctrl-d" || key == "ctrl-q" {
			break
		}
		switch key {
		case "j", "down":
			if selected < len(visible)-1 {
				selected++
			}
		case "k", "up":
			if selected > 0 {
				selected--
			}
		case "g":
			selected = 0
		case "G":
			if len(visible) > 0 {
				selected = len(visible) - 1
			}
		case " ":
			if len(visible) > 0 {
				idx := visible[selected]
				tasks[idx].Done = !tasks[idx].Done
				saveTasks(tasks)
				if tasks[idx].Done {
					status = "Marked done"
				} else {
					status = "Marked todo"
				}
			}
		case "a":
			s, ok2 := promptInput("Add:", "")
			if ok2 && s != "" {
				nt := parseAddText(s)
				tasks = append(tasks, nt)
				saveTasks(tasks)
				selected = len(tasks) - 1
				status = "Added: " + nt.Text
			} else {
				status = "Add cancelled - press q or Esc to quit"
			}
		case "e":
			if len(visible) > 0 {
				idx := visible[selected]
				old := tasks[idx]
				s, ok2 := promptInput(fmt.Sprintf("Edit [%s]:", old.Text), "")
				if ok2 && s != "" {
					nt := parseAddText(s)
					if nt.Priority == "" {
						nt.Priority = old.Priority
					}
					if nt.Due == "" {
						nt.Due = old.Due
					}
					nt.Done = old.Done
					tasks[idx] = nt
					saveTasks(tasks)
					status = "Edited"
				}
			}
		case "d":
			if len(visible) > 0 {
				idx := visible[selected]
				removed := tasks[idx].Text
				tasks = append(tasks[:idx], tasks[idx+1:]...)
				saveTasks(tasks)
				status = "Deleted: " + removed
				if selected >= len(visible)-1 && selected > 0 {
					selected--
				}
			}
		case "/":
			s, ok2 := promptInput("Search:", "")
			if ok2 {
				search = s
				selected = 0
				if search != "" {
					status = "Search: " + search
				} else {
					status = "Search cleared - press q or Esc to quit"
				}
			}
		case "f":
			cur := 0
			for i, ff := range filters {
				if ff == filterMode {
					cur = i
					break
				}
			}
			filterMode = filters[(cur+1)%len(filters)]
			selected = 0
			status = "Filter: " + filterMode
		case "u":
			if _, err := os.Stat(backupFile); err == nil {
				_ = copyFile(backupFile, tasksFile)
				tasks = loadTasks()
				status = "Undone"
			} else {
				status = "No backup to undo"
			}
		case "c":
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
			cleared := before - len(kept)
			tasks = kept
			saveTasks(tasks)
			status = fmt.Sprintf("Cleared %d done", cleared)
			selected = 0
		case "s":
			total := len(tasks)
			doneN := countDone(tasks)
			overdueN := countOverdue(tasks)
			status = fmt.Sprintf("Total %d - Done %d - Todo %d - Overdue %d", total, doneN, total-doneN, overdueN)
		case "?":
			status = "Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats"
		}
	}
}

func truncate(s string, n int) string {
	if n <= 0 {
		return ""
	}
	if len(s) > n {
		return s[:n]
	}
	return s
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func main() {
	args := os.Args[1:]
	tasks := loadTasks()

	if len(args) == 0 || args[0] == "tui" {
		runTUI(tasks)
		fmt.Println("Exited TUI - back to shell. Use: go run tasks.go list")
		return
	}

	cmd := args[0]
	switch cmd {
	case "help", "--help", "-h":
		fmt.Println(`Usage:
  tasks tui                    Interactive TUI (default, no args = tui)
  tasks add [--priority P1] [--due YYYY-MM-DD] <text>
  tasks list [--tag X] [--project Y] [--priority P1] [--search Q] [--overdue|--today|--done|--todo]
  tasks done <n>
  tasks undone <n>
  tasks rm <n>
  tasks edit <n> <new text>
  tasks search <query>
  tasks clear
  tasks stats
  tasks undo
  tasks help

Format: tasks.md lines are - [ ] (P1) due:2026-11-30 Buy milk #home +groceries
Tags start with #, projects with +. Priority P1/P2/P3, due YYYY-MM-DD.
TUI keys: j/k or arrows move, Space toggle, a add, e edit, d delete,
  / search, f filter, u undo, c clear done, s stats, q / Esc / Ctrl-C to quit
  In a prompt: Enter saves, Esc / Ctrl-C cancels`)
		return
	case "add":
		rest := args[1:]
		priority, due := "", ""
		var parts []string
		for i := 0; i < len(rest); i++ {
			if rest[i] == "--priority" && i+1 < len(rest) {
				priority = rest[i+1]
				i++
				continue
			}
			if rest[i] == "--due" && i+1 < len(rest) {
				due = rest[i+1]
				i++
				continue
			}
			parts = append(parts, rest[i])
		}
		full := strings.Join(parts, " ")
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
		saveTasks(tasks)
		fmt.Println("Added: " + t.Text)
		return
	case "list":
		cliList(tasks, args[1:])
		return
	case "done":
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
		saveTasks(tasks)
		fmt.Println("Done: " + tasks[idx].Text)
		return
	case "undone":
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
		saveTasks(tasks)
		fmt.Println("Todo: " + tasks[idx].Text)
		return
	case "rm":
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
		saveTasks(tasks)
		fmt.Println("Deleted: " + removed)
		return
	case "edit":
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
		saveTasks(tasks)
		fmt.Printf("Edited %d: %s\n", idx+1, nt.Text)
		return
	case "search":
		if len(args) < 2 {
			fmt.Println("Usage: tasks search <query>")
			return
		}
		q := strings.Join(args[1:], " ")
		found := false
		for i, t := range tasks {
			if matchesSearch(t, q) {
				printTask(i, t)
				found = true
			}
		}
		if !found {
			fmt.Println("No matches.")
		}
		return
	case "clear":
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
		saveTasks(tasks)
		fmt.Printf("Cleared %d done tasks\n", before-len(tasks))
		return
	case "stats":
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
			for _, tg := range tagsOf(t) {
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
	case "undo":
		if _, err := os.Stat(backupFile); err != nil {
			fmt.Println("No backup to undo")
			return
		}
		_ = copyFile(backupFile, tasksFile)
		fmt.Println("Undone - restored from backup")
		return
	default:
		fmt.Printf("Unknown command: %s\n", cmd)
		fmt.Println("Run: go run tasks.go help")
	}
}
