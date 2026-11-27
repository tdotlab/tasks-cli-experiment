#!/usr/bin/env ruby
# tasks.rb - Todo CLI v2 (Ruby, stdlib only)
# Same spec + same tasks.md as all other languages.
# Run: ruby tasks.rb  |  ruby tasks.rb list  |  ruby tasks.rb add "Buy milk #home"
# FIX 2026-11-27: Terminal handling via io/console STDIN.raw block.
# No shell-out to configure the terminal. STDIN.raw saves the exact
# termios struct with tcgetattr and restores it byte-for-byte on
# block exit (even on exception), so BRKINT / ISTRIP / ECHONL and
# every other flag come back exactly as they were. Previous version
# configured the terminal via a subprocess, which left flags changed.

require "io/console"
require "date"
require "fileutils"

TASKS_FILE = "tasks.md"
BACKUP_FILE = "tasks.md.bak"
MAX_INPUT = 4096

Task = Struct.new(:done, :priority, :due, :text) do
  def initialize(done = false, priority = "", due = "", text = "")
    super(done, priority, due, text)
  end
end

$tasks = []

def trim_s(s)
  s.to_s.strip
end

def collapse_spaces(s)
  s.to_s.split.join(" ")
end

def today_str
  Date.today.iso8601
end

def overdue?(t)
  !t.due.empty? && t.due < today_str
end

def today_task?(t)
  !t.due.empty? && t.due == today_str
end

def parse_line(line)
  return nil unless line.start_with?("- [")
  return nil if line.length < 5
  mark = line[3]
  return nil unless mark == " " || mark == "x"
  return nil unless line[4] == "]"
  t = Task.new(mark == "x")
  rest = trim_s(line[5..] || "")
  if rest.start_with?("(P1)") || rest.start_with?("(P2)") || rest.start_with?("(P3)")
    t.priority = rest[1, 2]
    rest = trim_s(rest[4..] || "")
  end
  if rest.start_with?("due:") && rest.length >= 14
    d = rest[4, 10]
    if d.length == 10 && d[4] == "-" && d[7] == "-"
      t.due = d
      rest = trim_s(rest[14..] || "")
    end
  end
  t.text = trim_s(rest)
  t
end

def format_task(t)
  s = "- [" + (t.done ? "x" : " ") + "]"
  s += " (#{t.priority})" unless t.priority.empty?
  s += " due:#{t.due}" unless t.due.empty?
  s + " #{t.text}"
end

def load_tasks
  $tasks.clear
  return unless File.exist?(TASKS_FILE)
  File.foreach(TASKS_FILE, encoding: "UTF-8") do |raw|
    line = raw.chomp.sub(/\r\z/, "")
    next if trim_s(line).empty?
    t = parse_line(line)
    $tasks << t if t
  end
end

def save_tasks
  FileUtils.cp(TASKS_FILE, BACKUP_FILE) if File.exist?(TASKS_FILE)
  File.open(TASKS_FILE, "w:UTF-8") do |f|
    $tasks.each { |t| f.puts format_task(t) }
  end
end

def parse_add_text(full)
  t = Task.new
  text = trim_s(full)
  if text.start_with?("P1 ", "P2 ", "P3 ")
    t.priority = text[0, 2]
    text = trim_s(text[3..] || "")
  elsif text.start_with?("(P1)", "(P2)", "(P3)")
    t.priority = text[1, 2]
    text = trim_s(text[4..] || "")
  end
  pos = text.index("due:")
  if pos && text.length >= pos + 14
    cand = text[pos + 4, 10]
    if cand && cand.length == 10 && cand[4] == "-" && cand[7] == "-"
      t.due = cand
      before = trim_s(text[0...pos] || "")
      after = trim_s(text[pos + 14..] || "")
      text = trim_s("#{before} #{after}")
    end
  end
  t.text = collapse_spaces(text)
  t
end

def parse_task_number(s, n)
  v = Integer(trim_s(s), exception: false)
  return nil if v.nil?
  return nil if v < 1 || v > n
  v - 1
end

def matches_mode(t, mode)
  case mode
  when "todo" then !t.done
  when "done" then t.done
  when "overdue" then !t.done && overdue?(t)
  when "today" then !t.done && today_task?(t)
  else true
  end
end

def matches_search(t, q)
  return true if q.nil? || q.empty?
  t.text.downcase.include?(q.downcase)
end

def filtered_indices(mode, search)
  out = []
  $tasks.each_with_index do |t, i|
    next unless matches_mode(t, mode)
    next unless matches_search(t, search)
    out << i
  end
  out
end

def count_done
  $tasks.count(&:done)
end

def count_overdue
  $tasks.count { |t| !t.done && overdue?(t) }
end

def has_tag(t, tag)
  want = tag.start_with?("#") ? tag[1..] : tag
  t.text.split.any? do |tok|
    tok.length > 1 && tok.start_with?("#") && (tok == tag || tok[1..] == want)
  end
end

def has_project(t, proj)
  want = proj.start_with?("+") ? proj[1..] : proj
  t.text.split.any? do |tok|
    tok.length > 1 && tok.start_with?("+") && (tok == proj || tok[1..] == want)
  end
end

def print_task(idx, t)
  s = "#{idx + 1}. [#{t.done ? 'x' : ' '}] "
  s += "#{t.priority} " unless t.priority.empty?
  s += "#{t.due} " unless t.due.empty?
  s += t.text
  puts s
end

def cli_list(args)
  tag = ""; project = ""; priority = ""; search = ""; mode = "all"
  i = 0
  while i < args.length
    a = args[i]
    if a == "--tag" && i + 1 < args.length
      tag = args[i + 1]; i += 2; next
    end
    if a == "--project" && i + 1 < args.length
      project = args[i + 1]; i += 2; next
    end
    if a == "--priority" && i + 1 < args.length
      priority = args[i + 1]; i += 2; next
    end
    if a == "--search" && i + 1 < args.length
      search = args[i + 1]; i += 2; next
    end
    mode = "overdue" if a == "--overdue"
    mode = "today" if a == "--today"
    mode = "done" if a == "--done"
    mode = "todo" if a == "--todo"
    i += 1
  end
  shown = 0
  filtered_indices(mode, search).each do |idx|
    t = $tasks[idx]
    next if !tag.empty? && !has_tag(t, tag)
    next if !project.empty? && !has_project(t, project)
    next if !priority.empty? && t.priority != priority
    print_task(idx, t)
    shown += 1
  end
  puts "No tasks." if shown == 0
end

# --- TUI ---
# All terminal I/O inside STDIN.raw { }.
# STDIN.getch reads one key without Enter. Escape sequences are
# read with a short non-blocking drain. Prompt is a growing array
# of characters, 4096 cap only, horizontal scroll. No fixed buffer.
# Exit: q / Q / Esc / Ctrl-C / Ctrl-D / Ctrl-Q quit from main list.
# Footer always shows it. In prompt, Enter saves, Esc / Ctrl-C cancels.

def read_key
  ch = STDIN.getch
  return nil if ch.nil?
  return :enter if ch == "\r" || ch == "\n"
  return :ctrl_c if ch == "\x03"
  return :ctrl_d if ch == "\x04"
  return :ctrl_q if ch == "\x11"
  return :ctrl_a if ch == "\x01"
  return :ctrl_e if ch == "\x05"
  return :ctrl_u if ch == "\x15"
  return :ctrl_k if ch == "\x0b"
  return :ctrl_w if ch == "\x17"
  return :backspace if ch == "\x7f" || ch == "\x08"
  if ch == "\x1b"
    # Try to read the rest of an escape sequence without blocking long.
    begin
      if IO.select([STDIN], nil, nil, 0.05)
        c2 = STDIN.getch
        return :esc if c2.nil? || (c2 != "[" && c2 != "O")
        c3 = STDIN.getch
        return :esc if c3.nil?
        return :up if c3 == "A"
        return :down if c3 == "B"
        return :right if c3 == "C"
        return :left if c3 == "D"
        return :home if c3 == "H"
        return :end if c3 == "F"
        if c3 == "3"
          STDIN.getch rescue nil
          return :del
        end
        return :esc
      else
        return :esc
      end
    rescue IOError, Errno::EAGAIN
      return :esc
    end
  end
  return [:char, ch] if ch.length == 1 && ch.ord >= 32
  return [:char, ch] if ch.length > 1
  :other
end

def prompt_input(label)
  chars = []
  cursor = 0
  offset = 0
  label_len = label.length + 1
  loop do
    rows = IO.console.winsize[0] rescue 24
    cols = IO.console.winsize[1] rescue 80
    rows = 24 if rows.nil? || rows <= 0
    cols = 80 if cols.nil? || cols <= 0
    avail = cols - label_len - 1
    avail = 10 if avail < 10
    offset = cursor if cursor < offset
    offset = cursor - avail + 1 if cursor >= offset + avail
    print "\e[#{rows - 1};1H\e[2KEnter=save  Esc / Ctrl-C=cancel"
    print "\e[#{rows};1H\e[2K"
    print "#{label} #{chars[offset, avail].join}"
    cx = label_len + (cursor - offset) + 1
    cx = cols if cx > cols
    cx = 1 if cx < 1
    print "\e[#{rows};#{cx}H"
    $stdout.flush
    k = read_key
    case k
    when :enter then break
    when :esc, :ctrl_c, :ctrl_d then return nil
    when :backspace
      if cursor > 0
        chars.delete_at(cursor - 1); cursor -= 1
      end
    when :del
      chars.delete_at(cursor) if cursor < chars.length
    when :left then cursor -= 1 if cursor > 0
    when :right then cursor += 1 if cursor < chars.length
    when :home, :ctrl_a then cursor = 0
    when :end, :ctrl_e then cursor = chars.length
    when :ctrl_u then chars = []; cursor = 0; offset = 0
    when :ctrl_k then chars = chars[0, cursor]
    when :ctrl_w
      while cursor > 0 && chars[cursor - 1] == " "
        chars.delete_at(cursor - 1); cursor -= 1
      end
      while cursor > 0 && chars[cursor - 1] != " "
        chars.delete_at(cursor - 1); cursor -= 1
      end
    when :up, :down, :other, nil then next
    else
      if k.is_a?(Array) && k[0] == :char
        ch = k[1]
        if chars.length < MAX_INPUT
          chars.insert(cursor, ch); cursor += 1
        end
      end
    end
  end
  trim_s(chars.join)
end

def run_tui
  # STDIN.raw is the ONLY terminal configuration. It saves the exact
  # termios and restores it on exit, so no flag is left changed.
  STDIN.raw do
    selected = 0
    filters = ["all", "todo", "done", "overdue", "today"]
    filter_idx = 0
    search = ""
    status = "Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter"
    loop do
      rows = IO.console.winsize[0] rescue 24
      cols = IO.console.winsize[1] rescue 80
      rows = 24 if rows.nil? || rows <= 0
      cols = 80 if cols.nil? || cols <= 0
      mode = filters[filter_idx]
      visible = filtered_indices(mode, search)
      selected = 0 if visible.empty?
      if !visible.empty?
        selected = visible.length - 1 if selected >= visible.length
        selected = 0 if selected < 0
      end
      print "\e[2J\e[H"
      print "tasks - #{$tasks.length} total | #{count_done} done | #{count_overdue} overdue | filter: #{mode} | search: #{search}\n"
      print "#    []  P    Due         Text\n"
      print "#{'-' * [80, cols].min}\n"
      max_rows = [5, rows - 5].max
      visible.first(max_rows).each_with_index do |idx, i|
        t = $tasks[idx]
        line = format("%-4d [%s] ", idx + 1, t.done ? "x" : " ")
        line += "(#{t.priority}) " unless t.priority.empty?
        line += "due:#{t.due} " unless t.due.empty?
        line += t.text
        line = line[0, cols] if line.length > cols
        if i == selected
          print "\e[7m#{line}\e[0m\n"
        elsif t.done
          print "\e[2m#{line}\e[0m\n"
        else
          print "#{line}\n"
        end
      end
      print "\e[#{rows - 1};1H\e[2K#{status}"
      print "\e[#{rows};1H\e[2K"
      print "q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats"
      print "\e[#{rows};1H"
      $stdout.flush
      k = read_key
      break if [:esc, :ctrl_c, :ctrl_d, :ctrl_q].include?(k)
      if k.is_a?(Array) && k[0] == :char
        ch = k[1]
        break if ch == "q" || ch == "Q"
        case ch
        when "j" then selected += 1 if selected + 1 < visible.length
        when "k" then selected -= 1 if selected > 0
        when "g" then selected = 0
        when "G" then selected = visible.length - 1 unless visible.empty?
        when " "
          unless visible.empty?
            idx = visible[selected]
            $tasks[idx].done = !$tasks[idx].done
            save_tasks
            status = $tasks[idx].done ? "Marked done" : "Marked todo"
          end
        when "a"
          s = prompt_input("Add:")
          if s && !s.empty?
            nt = parse_add_text(s)
            $tasks << nt
            save_tasks
            selected = $tasks.length - 1
            status = "Added: #{nt.text}"
          else
            status = "Add cancelled - press q or Esc to quit"
          end
        when "e"
          unless visible.empty?
            idx = visible[selected]
            old = $tasks[idx]
            s = prompt_input("Edit [#{old.text}]:")
            if s && !s.empty?
              nt = parse_add_text(s)
              nt.priority = old.priority if nt.priority.empty?
              nt.due = old.due if nt.due.empty?
              nt.done = old.done
              $tasks[idx] = nt
              save_tasks
              status = "Edited"
            end
          end
        when "d"
          unless visible.empty?
            idx = visible[selected]
            removed = $tasks[idx].text
            $tasks.delete_at(idx)
            save_tasks
            status = "Deleted: #{removed}"
            selected -= 1 if selected >= visible.length - 1 && selected > 0
          end
        when "/"
          s = prompt_input("Search:")
          unless s.nil?
            search = s
            selected = 0
            status = search.empty? ? "Search cleared - press q or Esc to quit" : "Search: #{search}"
          end
        when "f"
          filter_idx = (filter_idx + 1) % filters.length
          selected = 0
          status = "Filter: #{filters[filter_idx]}"
        when "u"
          if File.exist?(BACKUP_FILE)
            FileUtils.cp(BACKUP_FILE, TASKS_FILE)
            load_tasks
            status = "Undone"
          else
            status = "No backup to undo"
          end
        when "c"
          before = $tasks.length
          $tasks.reject!(&:done)
          save_tasks
          status = "Cleared #{before - $tasks.length} done"
          selected = 0
        when "s"
          tot = $tasks.length; dn = count_done; ov = count_overdue
          status = "Total #{tot} - Done #{dn} - Todo #{tot - dn} - Overdue #{ov}"
        when "?"
          status = "Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats"
        end
      elsif k == :down
        selected += 1 if selected + 1 < visible.length
      elsif k == :up
        selected -= 1 if selected > 0
      end
    end
  end
  puts
end

def print_help
  puts "Usage:"
  puts "  tasks tui                    Interactive TUI (default, no args = tui)"
  puts "  tasks add [--priority P1] [--due YYYY-MM-DD] <text>"
  puts "  tasks list [--tag X] [--project Y] [--priority P1] [--search Q] [--overdue|--today|--done|--todo]"
  puts "  tasks done <n>"
  puts "  tasks undone <n>"
  puts "  tasks rm <n>"
  puts "  tasks edit <n> <new text>"
  puts "  tasks search <query>"
  puts "  tasks clear"
  puts "  tasks stats"
  puts "  tasks undo"
  puts "  tasks help"
  puts
  puts "Format: tasks.md lines are - [ ] (P1) due:2026-11-30 Buy milk #home +groceries"
  puts "Tags start with #, projects with +. Priority P1/P2/P3, due YYYY-MM-DD."
  puts "TUI keys: j/k or arrows move, Space toggle, a add, e edit, d delete,"
  puts "  / search, f filter, u undo, c clear done, s stats, q / Esc / Ctrl-C to quit"
  puts "  In a prompt: Enter saves, Esc / Ctrl-C cancels"
end

load_tasks
args = ARGV.dup
if args.empty? || args[0] == "tui"
  run_tui
  puts "Exited TUI - back to shell. Use: ruby tasks.rb list"
  exit
end
cmd = args[0]
case cmd
when "help", "--help", "-h"
  print_help
when "add"
  priority = ""; due = ""; parts = []
  i = 1
  while i < args.length
    if args[i] == "--priority" && i + 1 < args.length
      priority = args[i + 1]; i += 2; next
    end
    if args[i] == "--due" && i + 1 < args.length
      due = args[i + 1]; i += 2; next
    end
    parts << args[i]; i += 1
  end
  buf = parts.join(" ")
  if trim_s(buf).empty?
    puts "Usage: tasks add <text>"; exit
  end
  t = parse_add_text(buf)
  t.priority = priority unless priority.empty?
  t.due = due unless due.empty?
  $tasks << t; save_tasks
  puts "Added: #{t.text}"
when "list"
  cli_list(args[1..] || [])
when "done"
  if args.length < 2
    puts "Usage: tasks done <n>"; exit
  end
  idx = parse_task_number(args[1], $tasks.length)
  if idx.nil?
    puts "Invalid task number"; exit
  end
  $tasks[idx].done = true; save_tasks
  puts "Done: #{$tasks[idx].text}"
when "undone"
  if args.length < 2
    puts "Usage: tasks undone <n>"; exit
  end
  idx = parse_task_number(args[1], $tasks.length)
  if idx.nil?
    puts "Invalid task number"; exit
  end
  $tasks[idx].done = false; save_tasks
  puts "Todo: #{$tasks[idx].text}"
when "rm"
  if args.length < 2
    puts "Usage: tasks rm <n>"; exit
  end
  idx = parse_task_number(args[1], $tasks.length)
  if idx.nil?
    puts "Invalid task number"; exit
  end
  removed = $tasks[idx].text
  $tasks.delete_at(idx); save_tasks
  puts "Deleted: #{removed}"
when "edit"
  if args.length < 3
    puts "Usage: tasks edit <n> <new text>"; exit
  end
  idx = parse_task_number(args[1], $tasks.length)
  if idx.nil?
    puts "Invalid task number"; exit
  end
  nt = parse_add_text(args[2..].join(" "))
  old = $tasks[idx]
  nt.priority = old.priority if nt.priority.empty?
  nt.due = old.due if nt.due.empty?
  nt.done = old.done
  $tasks[idx] = nt; save_tasks
  puts "Edited #{idx + 1}: #{nt.text}"
when "search"
  if args.length < 2
    puts "Usage: tasks search <query>"; exit
  end
  q = args[1..].join(" ")
  found = false
  $tasks.each_with_index do |t, i|
    if matches_search(t, q)
      print_task(i, t); found = true
    end
  end
  puts "No matches." unless found
when "clear"
  before = $tasks.length
  $tasks.reject!(&:done)
  save_tasks
  puts "Cleared #{before - $tasks.length} done tasks"
when "stats"
  total = $tasks.length; done_n = count_done; over_n = count_overdue
  today_n = $tasks.count { |t| !t.done && today_task?(t) }
  puts "Total: #{total}\nDone: #{done_n}\nTodo: #{total - done_n}\nOverdue: #{over_n}\nDue today: #{today_n}"
  c1 = $tasks.count { |t| t.priority == "P1" }
  c2 = $tasks.count { |t| t.priority == "P2" }
  c3 = $tasks.count { |t| t.priority == "P3" }
  if c1 > 0 || c2 > 0 || c3 > 0
    puts "By priority:"
    puts "  P1: #{c1}" if c1 > 0
    puts "  P2: #{c2}" if c2 > 0
    puts "  P3: #{c3}" if c3 > 0
  end
  tag_counts = Hash.new(0)
  $tasks.each do |t|
    t.text.split.each { |tok| tag_counts[tok] += 1 if tok.length > 1 && tok.start_with?("#") }
  end
  unless tag_counts.empty?
    puts "By tag:"
    tag_counts.sort.each { |k, v| puts "  #{k}: #{v}" }
  end
when "undo"
  unless File.exist?(BACKUP_FILE)
    puts "No backup to undo"; exit
  end
  FileUtils.cp(BACKUP_FILE, TASKS_FILE)
  puts "Undone - restored from backup"
else
  puts "Unknown command: #{cmd}"
  print_help
end
