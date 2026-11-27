local TASKS_FILE = "tasks.md"

local HELP = [[Usage: tasks <command> [args]

Commands:
  add "Buy milk"   Add a task
  list             Show all tasks
  done 2           Mark task 2 complete
  rm 2             Delete task 2
  clear            Remove completed tasks
  stats            Show totals
]]

local function load_tasks()
    local tasks = {}
    local f = io.open(TASKS_FILE, "r")
    if not f then
        return tasks
    end
    for line in f:lines() do
        line = line:gsub("\r$", "")
        if line:sub(1, 6) == "- [ ] " then
            tasks[#tasks + 1] = { done = false, text = line:sub(7) }
        elseif line:sub(1, 6) == "- [x] " then
            tasks[#tasks + 1] = { done = true, text = line:sub(7) }
        end
    end
    f:close()
    return tasks
end

local function save_tasks(tasks)
    local f = io.open(TASKS_FILE, "w")
    if not f then
        io.stderr:write("Error: could not write " .. TASKS_FILE .. "\n")
        return
    end
    for _, t in ipairs(tasks) do
        if t.done then
            f:write("- [x] " .. t.text .. "\n")
        else
            f:write("- [ ] " .. t.text .. "\n")
        end
    end
    f:close()
end

local function parse_task_number(s, count)
    local n = tonumber(s)
    if not n or n ~= math.floor(n) then
        return nil
    end
    if n < 1 or n > count then
        return nil
    end
    return n
end

local tasks = load_tasks()
local args = arg

if #args == 0 or args[1] == "help" or args[1] == "-h" or args[1] == "--help" then
    io.write(HELP)
    return
end

local command = args[1]

if command == "add" then
    if #args < 2 then
        print("Error: task text is required.")
        return
    end
    local text = table.concat(args, " ", 2, #args)
    if text:match("%S") == nil then
        print("Error: task text is required.")
        return
    end
    tasks[#tasks + 1] = { done = false, text = text }
    save_tasks(tasks)
    print("Added: " .. text)
    return
end

if command == "list" then
    if #tasks == 0 then
        print("No tasks yet.")
        return
    end
    for i, t in ipairs(tasks) do
        print(string.format("%d. [%s] %s", i, t.done and "x" or " ", t.text))
    end
    return
end

if command == "done" then
    if #args < 2 then
        print("Error: invalid task number.")
        return
    end
    local idx = parse_task_number(args[2], #tasks)
    if not idx then
        print("Error: invalid task number.")
        return
    end
    tasks[idx].done = true
    save_tasks(tasks)
    print("Done: " .. tasks[idx].text)
    return
end

if command == "rm" then
    if #args < 2 then
        print("Error: invalid task number.")
        return
    end
    local idx = parse_task_number(args[2], #tasks)
    if not idx then
        print("Error: invalid task number.")
        return
    end
    local removed = tasks[idx]
    table.remove(tasks, idx)
    save_tasks(tasks)
    print("Removed: " .. removed.text)
    return
end

if command == "clear" then
    local before = #tasks
    local kept = {}
    for _, t in ipairs(tasks) do
        if not t.done then
            kept[#kept + 1] = t
        end
    end
    local cleared = before - #kept
    -- replace contents in place
    for i = #tasks, 1, -1 do
        tasks[i] = nil
    end
    for i, t in ipairs(kept) do
        tasks[i] = t
    end
    save_tasks(tasks)
    print(string.format("Cleared %d completed task(s).", cleared))
    return
end

if command == "stats" then
    local total = #tasks
    local done = 0
    for _, t in ipairs(tasks) do
        if t.done then
            done = done + 1
        end
    end
    local remaining = total - done
    print(string.format("Total: %d | Done: %d | Remaining: %d", total, done, remaining))
    return
end

print("Error: unknown command '" .. command .. "'.")
io.write(HELP)
