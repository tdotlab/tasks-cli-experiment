TASKS_FILE = "tasks.md"

HELP = <<~HELP
  Usage: tasks <command> [args]

  Commands:
    add "Buy milk"   Add a task
    list             Show all tasks
    done 2           Mark task 2 complete
    rm 2             Delete task 2
    clear            Remove completed tasks
    stats            Show totals
HELP

Task = Struct.new(:done, :text)

def load_tasks
  return [] unless File.exist?(TASKS_FILE)

  tasks = []
  File.readlines(TASKS_FILE, chomp: true).each do |line|
    line = line.sub(/\r$/, "")
    if line.start_with?("- [ ] ")
      tasks << Task.new(false, line[6..])
    elsif line.start_with?("- [x] ")
      tasks << Task.new(true, line[6..])
    end
  end
  tasks
end

def save_tasks(tasks)
  body = tasks.map { |t| "#{t.done ? '- [x] ' : '- [ ] '}#{t.text}" }.join("\n")
  File.write(TASKS_FILE, body.empty? ? "" : "#{body}\n")
end

def parse_task_number(s, count)
  return nil unless s.match?(/\A\d+\z/)

  n = s.to_i
  return nil if n < 1 || n > count

  n - 1
end

tasks = load_tasks
args = ARGV

if args.empty? || %w[help -h --help].include?(args[0])
  puts HELP
  exit
end

command = args[0]

case command
when "add"
  if args.length < 2
    puts "Error: task text is required."
    exit
  end
  text = args[1..].join(" ")
  if text.strip.empty?
    puts "Error: task text is required."
    exit
  end
  tasks << Task.new(false, text)
  save_tasks(tasks)
  puts "Added: #{text}"

when "list"
  if tasks.empty?
    puts "No tasks yet."
    exit
  end
  tasks.each_with_index do |t, i|
    puts "#{i + 1}. [#{t.done ? 'x' : ' '}] #{t.text}"
  end

when "done"
  if args.length < 2
    puts "Error: invalid task number."
    exit
  end
  idx = parse_task_number(args[1], tasks.length)
  if idx.nil?
    puts "Error: invalid task number."
    exit
  end
  tasks[idx].done = true
  save_tasks(tasks)
  puts "Done: #{tasks[idx].text}"

when "rm"
  if args.length < 2
    puts "Error: invalid task number."
    exit
  end
  idx = parse_task_number(args[1], tasks.length)
  if idx.nil?
    puts "Error: invalid task number."
    exit
  end
  removed = tasks.delete_at(idx)
  save_tasks(tasks)
  puts "Removed: #{removed.text}"

when "clear"
  before = tasks.length
  tasks.reject! { |t| t.done }
  cleared = before - tasks.length
  save_tasks(tasks)
  puts "Cleared #{cleared} completed task(s)."

when "stats"
  total = tasks.length
  done = tasks.count { |t| t.done }
  remaining = total - done
  puts "Total: #{total} | Done: #{done} | Remaining: #{remaining}"

else
  puts "Error: unknown command '#{command}'."
  puts HELP
end
