#!/usr/bin/env ruby
# tasks.rb - Todo CLI v2 (Ruby, stdlib only, no gems)
# Same spec + same tasks.md as Python / C / C++ / Go / Zig / TypeScript / JavaScript / C# / Rust / Java v2.
# Run: ruby tasks.rb  |  ruby tasks.rb list  |  ruby tasks.rb add "Buy milk #home"
# Or: chmod +x tasks.rb && ./tasks.rb

require 'io/console'
require 'date'
require 'fileutils'

TASKS_FILE = 'tasks.md'
BACKUP_FILE = 'tasks.md.bak'
MAX_INPUT = 4096

# Task as a simple struct: done, priority, due, text
Task = Struct.new(:done, :priority, :due, :text) do
  def initialize(done = false, priority = '', due = '', text = '')
    super(done, priority, due, text)
  end
end

$tasks = []

# ---------- helpers ----------
def trim(s) = s.strip
def collapse_spaces(s) = s.split.join(' ')
def today_str = Date.today.strftime('%Y-%m-%d')
def overdue?(t) = !t.due.empty? && t.due < today_str
def today_due?(t) = !t.due.empty? && t.due == today_str

# ---------- parsing / formatting ----------
def parse_line(line)
  return nil unless line.start_with?('- [')
  return nil if line.length < 5
  mark = line[3]
  return nil unless mark == ' ' || mark == 'x'
  return nil unless line[4] == ']'
  t = Task.new(mark == 'x', '', '', '')
  rest = trim(line[5..] || '')
  if rest.start_with?('(P1)') || rest.start_with?('(P2)') || rest.start_with?('(P3)')
    t.priority = rest[1, 2]
    rest = trim(rest[4..] || '')
  end
  if rest.start_with?('due:') && rest.length >= 14
    d = rest[4, 10]
    if d.length == 10 && d[4] == '-' && d[7] == '-'
      t.due = d
      rest = trim(rest[14..] || '')
    end
  end
  t.text = trim(rest)
  t
end

def format_task(t)
  s = "- [#{t.done ? 'x' : ' '}]"
  s += " (#{t.priority})" unless t.priority.empty?
  s += " due:#{t.due}" unless t.due.empty?
  s += " #{t.text}"
  s
end

def load_tasks
  $tasks.clear
  return unless File.exist?(TASKS_FILE)
  File.foreach(TASKS_FILE) do |raw|
    line = raw.chomp.sub(/\r$/, '')
    next if trim(line).empty?
    t = parse_line(line)
    $tasks << t if t
  end
end

def copy_file(src, dst)
  FileUtils.cp(src, dst)
  true
rescue StandardError
  false
end

def save_tasks
  copy_file(TASKS_FILE, BACKUP_FILE) if File.exist?(TASKS_FILE)
  File.write(TASKS_FILE, $tasks.map { |t| format_task(t) }.join("\n") + ($tasks.empty? ? '' : "\n"))
end

def parse_add_text(full)
  t = Task.new(false, '', '', '')
  text = trim(full)
  if text.start_with?('P1 ', 'P2 ', 'P3 ')
    t.priority = text[0, 2]
    text = trim(text[3..] || '')
  elsif text.start_with?('(P1)', '(P2)', '(P3)')
    t.priority = text[1, 2]
    text = trim(text[4..] || '')
  end
  pos = text.index('due:')
  if pos && text.length >= pos + 14
    cand = text[pos + 4, 10]
    if cand && cand.length == 10 && cand[4] == '-' && cand[7] == '-'
      t.due = cand
      before = trim(text[0...pos] || '')
      after = trim(text[(pos + 14)..] || '')
      text = trim("#{before} #{after}")
    end
  end
  t.text = collapse_spaces(text)
  t
end

def parse_task_number(s, n)
  v = Integer(trim(s), exception: false)
  return nil if v.nil? || v < 1 || v > n
  v - 1
end

def matches_mode?(t, mode)
  case mode
  when 'todo' then !t.done
  when 'done' then t.done
  when 'overdue' then !t.done && overdue?(t)
  when 'today' then !t.done && today_due?(t)
  else true
  end
end

def matches_search?(t, q)
  return true if q.nil? || q.empty?
  t.text.downcase.include?(q.downcase)
end

def filtered_indices(mode, search)
  out = []
  $tasks.each_with_index do |t, i|
    next unless matches_mode?(t, mode)
    next unless matches_search?(t, search)
    out << i
  end
  out
end

def count_done = $tasks.count(&:done)
def count_overdue = $tasks.count { |t| !t.done && overdue?(t) }

def has_tag?(t, tag)
  want = tag.start_with?('#') ? tag[1..] : tag
  t.text.split.any? do |tok|
    tok.length > 1 && tok[0] == '#' && (tok == tag || tok[1..] == want)
  end
end

def has_project?(t, proj)
  want = proj.start_with?('+') ? proj[1..] : proj
  t.text.split.any? do |tok|
    tok.length > 1 && tok[0] == '+' && (tok == proj || tok[1..] == want)
  end
end

def print_task(idx, t)
  mark = t.done ? 'x' : ' '
  s = "#{idx + 1}. [#{mark}] "
  s += "#{t.priority} " unless t.priority.empty?
  s += "#{t.due} " unless t.due.empty?
  s += t.text
  puts s
end

def cli_list(args)
  tag = ''; project = ''; priority = ''; search = ''; mode = 'all'
  i = 0
  while i < args.length
    a = args[i]
    if a == '--tag' && i + 1 < args.length
      tag = args[i + 1]; i += 2; next
    elsif a == '--project' && i + 1 < args.length
      project = args[i + 1]; i += 2; next
    elsif a == '--priority' && i + 1 < args.length
      priority = args[i + 1]; i += 2; next
    elsif a == '--search' && i + 1 < args.length
      search = args[i + 1]; i += 2; next
    elsif a == '--overdue'
      mode = 'overdue'
    elsif a == '--today'
      mode = 'today'
    elsif a == '--done'
      mode = 'done'
    elsif a == '--todo'
      mode = 'todo'
    end
    i += 1
  end
  shown = 0
  filtered_indices(mode, search).each do |idx|
    t = $tasks[idx]
    next if !tag.empty? && !has_tag?(t, tag)
    next if !project.empty? && !has_project?(t, project)
    next if !priority.empty? && t.priority != priority
    print_task(idx, t)
    shown += 1
  end
  puts 'No tasks.' if shown == 0
end

# [STRIPPED 77 bytes] TUI - AUDITED FIXES (same as C / C++ / JS / C# / Rust / Java / Python / Go / Zig / TS)
# 1. Prompt has NO small char limit: reads keys one-by-one in raw mode via
#    STDIN.getch into a growing String, 4096 cap, horizontal scroll. No
#    fixed [64]/[256] buffer, no gets with width truncation.
# 2. Exit is explicit: q, Q, Esc, Ctrl-C, Ctrl-D, Ctrl-Q all quit from
#    main list, footer always shows "q / Esc / Ctrl-C to quit". In a
#    prompt, Enter saves, Esc / Ctrl-C cancels back to list.
#    Raw mode is via io/console (stdlib): STDIN.raw! / STDIN.cooked!
#    in ensure, so terminal is not left broken.
# [STRIPPED 75 bytes]

def get_term_size
  begin
    rows, cols = STDIN.winsize
    return [rows, cols] if rows > 0 && cols > 0
  rescue StandardError
  end
  r = (ENV['LINES'] || '24').to_i
  c = (ENV['COLUMNS'] || '80').to_i
  r = 24 if r <= 0
  c = 80 if c <= 0
  [r, c]
end

# read_key: returns [:char, ch] | [:esc] | [:up] etc.
# Uses IO.select with 30ms timeout to distinguish Esc alone from arrows.
def read_key
  c = STDIN.getch
  return [:other, nil] if c.nil?
  return [:enter, nil] if c == "\r" || c == "\n"
  return [:ctrl_c, nil] if c == "\x03"
  return [:ctrl_d, nil] if c == "\x04"
  return [:ctrl_q, nil] if c == "\x11"
  return [:ctrl_a, nil] if c == "\x01"
  return [:ctrl_e, nil] if c == "\x05"
  return [:ctrl_u, nil] if c == "\x15"
  return [:ctrl_k, nil] if c == "\x0B"
  return [:ctrl_w, nil] if c == "\x17"
  return [:backspace, nil] if c == "\x7F" || c == "\b"
  if c == "\e"
    # Wait 30ms for rest of sequence
    if IO.select([STDIN], nil, nil, 0.03).nil?
      return [:esc, nil]
    end
    b2 = STDIN.getch
    return [:esc, nil] if b2.nil? || (b2 != '[' && b2 != 'O')
    if IO.select([STDIN], nil, nil, 0.03).nil?
      return [:esc, nil]
    end
    b3 = STDIN.getch
    return [:esc, nil] if b3.nil?
    case b3
    when 'A' then return [:up, nil]
    when 'B' then return [:down, nil]
    when 'C' then return [:right, nil]
    when 'D' then return [:left, nil]
    when 'H' then return [:home, nil]
    when 'F' then return [:end, nil]
    when '3'
      # consume ~
      STDIN.getch if IO.select([STDIN], nil, nil, 0.03)
      return [:del, nil]
    else
      return [:esc, nil]
    end
  end
  # Printable (including UTF-8 multibyte - getch returns full char)
  if c.ord >= 32
    return [:char, c]
  end
  [:other, nil]
end

# prompt_input: returns trimmed string or nil if cancelled.
# Dynamic String, no small limit, 4096 cap, horizontal scroll.
def prompt_input(label)
  text = +''
  cursor = 0 # char index
  offset = 0
  label_len = label.length + 1 # label + space
  loop do
    rows, cols = get_term_size
    avail = cols - label_len - 1
    avail = 10 if avail < 10
    offset = cursor if cursor < offset
    offset = cursor - avail + 1 if cursor >= offset + avail
    print "\e[#{rows - 1};1H\e[2KEnter=save  Esc / Ctrl-C=cancel"
    print "\e[#{rows};1H\e[2K"
    print "#{label} "
    chars = text.chars
    ending = [offset + avail, chars.length].min
    print chars[offset...ending].join if offset < chars.length
    cursor_x = label_len + (cursor - offset) + 1
    cursor_x = cols if cursor_x > cols
    print "\e[#{rows};#{cursor_x}H"
    $stdout.flush
    kind, ch = read_key
    case kind
    when :enter then break
    when :esc, :ctrl_c, :ctrl_d then return nil
    when :backspace
      if cursor > 0
        text = text.chars.tap { |a| a.delete_at(cursor - 1) }.join
        cursor -= 1
      end
    when :del
      if cursor < text.chars.length
        text = text.chars.tap { |a| a.delete_at(cursor) }.join
      end
    when :left then cursor -= 1 if cursor > 0
    when :right then cursor += 1 if cursor < text.chars.length
    when :home, :ctrl_a then cursor = 0
    when :end, :ctrl_e then cursor = text.chars.length
    when :ctrl_u then text = +''; cursor = 0; offset = 0
    when :ctrl_k then text = text.chars[0...cursor].join
    when :ctrl_w
      arr = text.chars
      while cursor > 0 && arr[cursor - 1] == ' '
        arr.delete_at(cursor - 1); cursor -= 1
      end
      while cursor > 0 && arr[cursor - 1] != ' '
        arr.delete_at(cursor - 1); cursor -= 1
      end
      text = arr.join
    when :up, :down then next
    when :char
      if text.chars.length < MAX_INPUT
        arr = text.chars
        arr.insert(cursor, ch)
        text = arr.join
        cursor += 1
      end
    end
  end
  trim(text)
end

def run_tui
  selected = 0
  filters = %w[all todo done overdue today]
  filter_idx = 0
  search = ''
  status = 'Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter'
  STDIN.raw!
  begin
    loop do
      rows, cols = get_term_size
      filter_mode = filters[filter_idx]
      visible = filtered_indices(filter_mode, search)
      selected = 0 if visible.empty?
      if !visible.empty?
        selected = visible.length - 1 if selected >= visible.length
        selected = 0 if selected < 0
      end
      print "\e[2J\e[H"
      total = $tasks.length
      done_n = count_done
      overdue_n = count_overdue
      puts "tasks - #{total} total | #{done_n} done | #{overdue_n} overdue | filter: #{filter_mode} | search: #{search}"
      puts '#    []  P    Due         Text'
      puts '-' * [80, cols].min
      max_rows = [5, rows - 5].max
      visible.first(max_rows).each_with_index do |idx, i|
        t = $tasks[idx]
        mark = t.done ? 'x' : ' '
        line = format('%-4d', idx + 1) + " [#{mark}] "
        line += "(#{t.priority}) " unless t.priority.empty?
        line += "due:#{t.due} " unless t.due.empty?
        line += t.text
        line = line.chars.first(cols).join if line.length > cols
        if i == selected
          puts "\e[7m#{line}\e[0m"
        elsif t.done
          puts "\e[2m#{line}\e[0m"
        else
          puts line
        end
      end
      print "\e[#{rows - 1};1H\e[2K#{status}"
      print "\e[#{rows};1H\e[2K"
      print 'q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats'
      print "\e[#{rows};1H"
      $stdout.flush
      kind, ch = read_key
      # EXIT - checked FIRST, from main list view
      break if kind == :esc || kind == :ctrl_c || kind == :ctrl_d || kind == :ctrl_q
      break if kind == :char && (ch == 'q' || ch == 'Q')

      case kind
      when :down then selected += 1 if selected + 1 < visible.length
      when :up then selected -= 1 if selected > 0
      when :char
        case ch
        when 'j' then selected += 1 if selected + 1 < visible.length
        when 'k' then selected -= 1 if selected > 0
        when 'g' then selected = 0
        when 'G' then selected = visible.length - 1 unless visible.empty?
        when ' '
          unless visible.empty?
            idx = visible[selected]
            $tasks[idx].done = !$tasks[idx].done
            save_tasks
            status = $tasks[idx].done ? 'Marked done' : 'Marked todo'
          end
        when 'a'
          s = prompt_input('Add:')
          if s && !s.empty?
            nt = parse_add_text(s)
            $tasks << nt
            save_tasks
            selected = $tasks.length - 1
            status = "Added: #{nt.text}"
          else
            status = 'Add cancelled - press q or Esc to quit'
          end
        when 'e'
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
              status = 'Edited'
            end
          end
        when 'd'
          unless visible.empty?
            idx = visible[selected]
            removed = $tasks[idx].text
            $tasks.delete_at(idx)
            save_tasks
            status = "Deleted: #{removed}"
            selected -= 1 if selected >= visible.length - 1 && selected > 0
          end
        when '/'
          s = prompt_input('Search:')
          unless s.nil?
            search = s
            selected = 0
            status = search.empty? ? 'Search cleared - press q or Esc to quit' : "Search: #{search}"
          end
        when 'f'
          filter_idx = (filter_idx + 1) % filters.length
          selected = 0
          status = "Filter: #{filters[filter_idx]}"
        when 'u'
          if File.exist?(BACKUP_FILE)
            copy_file(BACKUP_FILE, TASKS_FILE)
            load_tasks
            status = 'Undone'
          else
            status = 'No backup to undo'
          end
        when 'c'
          before = $tasks.length
          $tasks.reject!(&:done)
          save_tasks
          status = "Cleared #{before - $tasks.length} done"
          selected = 0
        when 's'
          total2 = $tasks.length
          done_n2 = count_done
          overdue_n2 = count_overdue
          status = "Total #{total2} - Done #{done_n2} - Todo #{total2 - done_n2} - Overdue #{overdue_n2}"
        when '?'
          status = 'Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats'
        end
      end
    end
  ensure
    begin
      STDIN.cooked!
    rescue StandardError
    end
    puts
  end
end

def print_help
  puts 'Usage:'
  puts '  tasks tui                    Interactive TUI (default, no args = tui)'
  puts '  tasks add [--priority P1] [--due YYYY-MM-DD] <text>'
  puts '  tasks list [--tag X] [--project Y] [--priority P1] [--search Q] [--overdue|--today|--done|--todo]'
  puts '  tasks done <n>'
  puts '  tasks undone <n>'
  puts '  tasks rm <n>'
  puts '  tasks edit <n> <new text>'
  puts '  tasks search <query>'
  puts '  tasks clear'
  puts '  tasks stats'
  puts '  tasks undo'
  puts '  tasks help'
  puts
  puts 'Format: tasks.md lines are - [ ] (P1) due:2026-11-30 Buy milk #home +groceries'
  puts 'Tags start with #, projects with +. Priority P1/P2/P3, due YYYY-MM-DD.'
  puts 'TUI keys: j/k or arrows move, Space toggle, a add, e edit, d delete,'
  puts '  / search, f filter, u undo, c clear done, s stats, q / Esc / Ctrl-C to quit'
  puts '  In a prompt: Enter saves, Esc / Ctrl-C cancels'
end

load_tasks

if ARGV.empty? || ARGV[0] == 'tui'
  run_tui
  puts 'Exited TUI - back to shell. Use: ruby tasks.rb list'
  exit 0
end

cmd = ARGV[0]

case cmd
when 'help', '--help', '-h'
  print_help
when 'add'
  priority = ''; due = ''; parts = []
  i = 1
  while i < ARGV.length
    if ARGV[i] == '--priority' && i + 1 < ARGV.length
      priority = ARGV[i + 1]; i += 2; next
    elsif ARGV[i] == '--due' && i + 1 < ARGV.length
      due = ARGV[i + 1]; i += 2; next
    end
    parts << ARGV[i]
    i += 1
  end
  buf = parts.join(' ')
  if trim(buf).empty?
    puts 'Usage: tasks add <text>'
    exit 0
  end
  t = parse_add_text(buf)
  t.priority = priority unless priority.empty?
  t.due = due unless due.empty?
  $tasks << t
  save_tasks
  puts "Added: #{t.text}"
when 'list'
  cli_list(ARGV[1..] || [])
when 'done'
  if ARGV.length < 2
    puts 'Usage: tasks done <n>'
    exit 0
  end
  idx = parse_task_number(ARGV[1], $tasks.length)
  if idx.nil?
    puts 'Invalid task number'
    exit 0
  end
  $tasks[idx].done = true
  save_tasks
  puts "Done: #{$tasks[idx].text}"
when 'undone'
  if ARGV.length < 2
    puts 'Usage: tasks undone <n>'
    exit 0
  end
  idx = parse_task_number(ARGV[1], $tasks.length)
  if idx.nil?
    puts 'Invalid task number'
    exit 0
  end
  $tasks[idx].done = false
  save_tasks
  puts "Todo: #{$tasks[idx].text}"
when 'rm'
  if ARGV.length < 2
    puts 'Usage: tasks rm <n>'
    exit 0
  end
  idx = parse_task_number(ARGV[1], $tasks.length)
  if idx.nil?
    puts 'Invalid task number'
    exit 0
  end
  removed = $tasks[idx].text
  $tasks.delete_at(idx)
  save_tasks
  puts "Deleted: #{removed}"
when 'edit'
  if ARGV.length < 3
    puts 'Usage: tasks edit <n> <new text>'
    exit 0
  end
  idx = parse_task_number(ARGV[1], $tasks.length)
  if idx.nil?
    puts 'Invalid task number'
    exit 0
  end
  nt = parse_add_text(ARGV[2..].join(' '))
  old = $tasks[idx]
  nt.priority = old.priority if nt.priority.empty?
  nt.due = old.due if nt.due.empty?
  nt.done = old.done
  $tasks[idx] = nt
  save_tasks
  puts "Edited #{idx + 1}: #{nt.text}"
when 'search'
  if ARGV.length < 2
    puts 'Usage: tasks search <query>'
    exit 0
  end
  q = ARGV[1..].join(' ')
  found = false
  $tasks.each_with_index do |t, i|
    if matches_search?(t, q)
      print_task(i, t)
      found = true
    end
  end
  puts 'No matches.' unless found
when 'clear'
  before = $tasks.length
  $tasks.reject!(&:done)
  save_tasks
  puts "Cleared #{before - $tasks.length} done tasks"
when 'stats'
  total = $tasks.length
  done_n = count_done
  overdue_n = count_overdue
  today_n = $tasks.count { |t| !t.done && today_due?(t) }
  puts "Total: #{total}\nDone: #{done_n}\nTodo: #{total - done_n}\nOverdue: #{overdue_n}\nDue today: #{today_n}"
  c1 = $tasks.count { |t| t.priority == 'P1' }
  c2 = $tasks.count { |t| t.priority == 'P2' }
  c3 = $tasks.count { |t| t.priority == 'P3' }
  if c1 > 0 || c2 > 0 || c3 > 0
    puts 'By priority:'
    puts "  P1: #{c1}" if c1 > 0
    puts "  P2: #{c2}" if c2 > 0
    puts "  P3: #{c3}" if c3 > 0
  end
  tag_counts = Hash.new(0)
  $tasks.each do |t|
    t.text.split.each do |tok|
      tag_counts[tok] += 1 if tok.length > 1 && tok[0] == '#'
    end
  end
  unless tag_counts.empty?
    puts 'By tag:'
    tag_counts.sort.each { |k, v| puts "  #{k}: #{v}" }
  end
when 'undo'
  if !File.exist?(BACKUP_FILE)
    puts 'No backup to undo'
    exit 0
  end
  copy_file(BACKUP_FILE, TASKS_FILE)
  puts 'Undone - restored from backup'
else
  puts "Unknown command: #{cmd}"
  print_help
end
