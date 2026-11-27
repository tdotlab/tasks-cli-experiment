#!/usr/bin/env lua
-- tasks.lua - Todo CLI v2 (Lua, stdlib only, no rocks)
-- Same spec + same tasks.md as Python / C / C++ / Go / Zig / TypeScript / JavaScript / C# / Rust / Java / Ruby v2.
-- Run: lua tasks.lua  |  lua tasks.lua list  |  lua tasks.lua add "Buy milk #home"
-- Or: chmod +x tasks.lua && ./tasks.lua
-- Needs: lua 5.3+ (for utf8), stty (for raw mode), /dev/tty

local TASKS_FILE = "tasks.md"
local BACKUP_FILE = "tasks.md.bak"
local MAX_INPUT = 4096

local tasks = {}

-- ---------- helpers ----------
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function collapse_spaces(s)
  local parts = {}
  for w in s:gmatch("%S+") do table.insert(parts, w) end
  return table.concat(parts, " ")
end

local function today_str()
  return os.date("%Y-%m-%d")
end

local function is_overdue(t)
  return t.due ~= "" and t.due < today_str()
end

local function is_today(t)
  return t.due ~= "" and t.due == today_str()
end

-- UTF-8 char helpers (Lua 5.3+ has utf8 lib)
local function chars_of(s)
  local out = {}
  if utf8 and utf8.charpattern then
    for ch in s:gmatch(utf8.charpattern) do table.insert(out, ch) end
  else
    -- fallback: byte-wise
    for i = 1, #s do table.insert(out, s:sub(i, i)) end
  end
  return out
end

local function chars_join(tbl)
  return table.concat(tbl)
end

-- ---------- parsing / formatting ----------
local function parse_line(line)
  if line:sub(1, 3) ~= "- [" then return nil end
  if #line < 5 then return nil end
  local mark = line:sub(4, 4)
  if mark ~= " " and mark ~= "x" then return nil end
  if line:sub(5, 5) ~= "]" then return nil end
  local t = { done = (mark == "x"), priority = "", due = "", text = "" }
  local rest = trim(line:sub(6))
  if rest:sub(1, 4) == "(P1)" or rest:sub(1, 4) == "(P2)" or rest:sub(1, 4) == "(P3)" then
    t.priority = rest:sub(2, 3)
    rest = trim(rest:sub(5))
  end
  if rest:sub(1, 4) == "due:" and #rest >= 14 then
    local d = rest:sub(5, 14)
    if #d == 10 and d:sub(5, 5) == "-" and d:sub(8, 8) == "-" then
      t.due = d
      rest = trim(rest:sub(15))
    end
  end
  t.text = trim(rest)
  return t
end

local function format_task(t)
  local s = "- [" .. (t.done and "x" or " ") .. "]"
  if t.priority ~= "" then s = s .. " (" .. t.priority .. ")" end
  if t.due ~= "" then s = s .. " due:" .. t.due end
  s = s .. " " .. t.text
  return s
end

local function load_tasks()
  tasks = {}
  local f = io.open(TASKS_FILE, "r")
  if not f then return end
  for raw in f:lines() do
    local line = raw:gsub("\r$", "")
    if trim(line) ~= "" then
      local t = parse_line(line)
      if t then table.insert(tasks, t) end
    end
  end
  f:close()
end

local function copy_file(src, dst)
  local inf = io.open(src, "rb")
  if not inf then return false end
  local data = inf:read("*a")
  inf:close()
  local outf = io.open(dst, "wb")
  if not outf then return false end
  outf:write(data)
  outf:close()
  return true
end

local function save_tasks()
  local f = io.open(TASKS_FILE, "r")
  if f then f:close(); copy_file(TASKS_FILE, BACKUP_FILE) end
  local out = io.open(TASKS_FILE, "w")
  if not out then return end
  for _, t in ipairs(tasks) do
    out:write(format_task(t) .. "\n")
  end
  out:close()
end

local function parse_add_text(full)
  local t = { done = false, priority = "", due = "", text = "" }
  local text = trim(full)
  if text:sub(1, 3) == "P1 " or text:sub(1, 3) == "P2 " or text:sub(1, 3) == "P3 " then
    t.priority = text:sub(1, 2)
    text = trim(text:sub(4))
  elseif text:sub(1, 4) == "(P1)" or text:sub(1, 4) == "(P2)" or text:sub(1, 4) == "(P3)" then
    t.priority = text:sub(2, 3)
    text = trim(text:sub(5))
  end
  local pos = text:find("due:", 1, true)
  if pos and #text >= pos + 13 then
    local cand = text:sub(pos + 4, pos + 13)
    if #cand == 10 and cand:sub(5, 5) == "-" and cand:sub(8, 8) == "-" then
      t.due = cand
      local before = trim(text:sub(1, pos - 1))
      local after = trim(text:sub(pos + 14))
      text = trim(before .. " " .. after)
    end
  end
  t.text = collapse_spaces(text)
  return t
end

local function parse_task_number(s, n)
  local v = tonumber(trim(s))
  if not v then return nil end
  v = math.floor(v)
  if v < 1 or v > n then return nil end
  return v
end

local function matches_mode(t, mode)
  if mode == "todo" then return not t.done end
  if mode == "done" then return t.done end
  if mode == "overdue" then return not t.done and is_overdue(t) end
  if mode == "today" then return not t.done and is_today(t) end
  return true
end

local function matches_search(t, q)
  if not q or q == "" then return true end
  return t.text:lower():find(q:lower(), 1, true) ~= nil
end

local function filtered_indices(mode, search)
  local out = {}
  for i, t in ipairs(tasks) do
    if matches_mode(t, mode) and matches_search(t, search) then
      table.insert(out, i)
    end
  end
  return out
end

local function count_done()
  local c = 0
  for _, t in ipairs(tasks) do if t.done then c = c + 1 end end
  return c
end

local function count_overdue()
  local c = 0
  for _, t in ipairs(tasks) do if not t.done and is_overdue(t) then c = c + 1 end end
  return c
end

local function has_tag(t, tag)
  local want = tag:sub(1, 1) == "#" and tag:sub(2) or tag
  for tok in t.text:gmatch("%S+") do
    if #tok > 1 and tok:sub(1, 1) == "#" then
      if tok == tag or tok:sub(2) == want then return true end
    end
  end
  return false
end

local function has_project(t, proj)
  local want = proj:sub(1, 1) == "+" and proj:sub(2) or proj
  for tok in t.text:gmatch("%S+") do
    if #tok > 1 and tok:sub(1, 1) == "+" then
      if tok == proj or tok:sub(2) == want then return true end
    end
  end
  return false
end

local function print_task(idx, t)
  local mark = t.done and "x" or " "
  local s = string.format("%d. [%s] ", idx, mark)
  if t.priority ~= "" then s = s .. t.priority .. " " end
  if t.due ~= "" then s = s .. t.due .. " " end
  s = s .. t.text
  print(s)
end

local function cli_list(args)
  local tag, project, priority, search, mode = "", "", "", "", "all"
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--tag" and i + 1 <= #args then tag = args[i + 1]; i = i + 2
    elseif a == "--project" and i + 1 <= #args then project = args[i + 1]; i = i + 2
    elseif a == "--priority" and i + 1 <= #args then priority = args[i + 1]; i = i + 2
    elseif a == "--search" and i + 1 <= #args then search = args[i + 1]; i = i + 2
    elseif a == "--overdue" then mode = "overdue"; i = i + 1
    elseif a == "--today" then mode = "today"; i = i + 1
    elseif a == "--done" then mode = "done"; i = i + 1
    elseif a == "--todo" then mode = "todo"; i = i + 1
    else i = i + 1 end
  end
  local shown = 0
  for _, idx in ipairs(filtered_indices(mode, search)) do
    local t = tasks[idx]
    if tag ~= "" and not has_tag(t, tag) then goto continue end
    if project ~= "" and not has_project(t, project) then goto continue end
    if priority ~= "" and t.priority ~= priority then goto continue end
    print_task(idx, t)
    shown = shown + 1
    ::continue::
  end
  if shown == 0 then print("No tasks.") end
end

-- [STRIPPED 77 bytes] TUI - AUDITED FIXES (same as C / C++ / JS / C# / Rust / Java / Ruby / Python / Go / Zig / TS)
-- 1. Prompt has NO small char limit: reads bytes one-by-one in raw mode into
--    a growing char table, 4096 cap, horizontal scroll. No fixed
--    [64]/[256] buffer, no io.read("*l") with width truncation.
-- 2. Exit is explicit: q, Q, Esc, Ctrl-C, Ctrl-D, Ctrl-Q all quit from
--    main list, footer always shows "q / Esc / Ctrl-C to quit". In a
--    prompt, Enter saves, Esc / Ctrl-C cancels back to list.
--    Raw mode is via `stty` (stdlib only): original settings saved with
--    `stty -g` and restored on exit, so terminal is not left broken.
-- [STRIPPED 75 bytes]

local function get_term_size()
  local f = io.popen("stty size < /dev/tty 2>/dev/null", "r")
  if f then
    local out = f:read("*a") or ""
    f:close()
    local r, c = out:match("(%d+)%s+(%d+)")
    r = tonumber(r); c = tonumber(c)
    if r and c and r > 0 and c > 0 then return r, c end
  end
  local r = tonumber(os.getenv("LINES") or "24") or 24
  local c = tonumber(os.getenv("COLUMNS") or "80") or 80
  if r <= 0 then r = 24 end
  if c <= 0 then c = 80 end
  return r, c
end

local function stty_get()
  local f = io.popen("stty -g < /dev/tty 2>/dev/null", "r")
  if not f then return "" end
  local out = trim(f:read("*a") or "")
  f:close()
  return out
end

local function stty_set(args)
  os.execute("stty " .. args .. " < /dev/tty 2>/dev/null")
end

local function enable_raw()
  local orig = stty_get()
  stty_set("raw -echo -isig min 1 time 0")
  -- unbuffered stdin so io.read(1) returns each byte
  pcall(function() io.stdin:setvbuf("no") end)
  return orig
end

local function disable_raw(orig)
  if orig and orig ~= "" then stty_set(orig)
  else stty_set("sane") end
  print()
end

-- Byte reading: io.read(1) in raw mode returns 1 byte.
local function read_byte()
  local b = io.read(1)
  if not b or #b == 0 then return nil end
  return b:byte(1)
end

-- Timeout read: temporarily set VMIN=0 VTIME=1 (0.1s), try read, restore.
local function read_byte_timeout()
  stty_set("raw -echo -isig min 0 time 1")
  local b = io.read(1)
  stty_set("raw -echo -isig min 1 time 0")
  if not b or #b == 0 then return nil end
  return b:byte(1)
end

local function decode_utf8_char(first)
  if first < 0x80 then return string.char(first) end
  local need = 0
  if first >= 0xC2 and first <= 0xDF then need = 1
  elseif first >= 0xE0 and first <= 0xEF then need = 2
  elseif first >= 0xF0 and first <= 0xF4 then need = 3
  else return "\239\191\189" end -- U+FFFD
  local bytes = { first }
  for _ = 1, need do
    local b = read_byte_timeout()
    if not b then break end
    table.insert(bytes, b)
  end
  return string.char(table.unpack(bytes))
end

-- read_key returns {kind=..., ch=...}
-- kind: "char", "esc", "up", "down", "left", "right", "home", "end", "del",
--       "enter", "backspace", "ctrl_c", "ctrl_d", "ctrl_q", "ctrl_a",
--       "ctrl_e", "ctrl_u", "ctrl_k", "ctrl_w", "other"
local function read_key()
  local b = read_byte()
  if not b then return { kind = "other" } end
  if b == 13 or b == 10 then return { kind = "enter" } end
  if b == 3 then return { kind = "ctrl_c" } end
  if b == 4 then return { kind = "ctrl_d" } end
  if b == 17 then return { kind = "ctrl_q" } end
  if b == 1 then return { kind = "ctrl_a" } end
  if b == 5 then return { kind = "ctrl_e" } end
  if b == 21 then return { kind = "ctrl_u" } end
  if b == 11 then return { kind = "ctrl_k" } end
  if b == 23 then return { kind = "ctrl_w" } end
  if b == 127 or b == 8 then return { kind = "backspace" } end
  if b == 27 then
    local b2 = read_byte_timeout()
    if not b2 then return { kind = "esc" } end
    if b2 ~= 91 and b2 ~= 79 then return { kind = "esc" } end -- not '[' or 'O'
    local b3 = read_byte_timeout()
    if not b3 then return { kind = "esc" } end
    if b3 == 65 then return { kind = "up" } end
    if b3 == 66 then return { kind = "down" } end
    if b3 == 67 then return { kind = "right" } end
    if b3 == 68 then return { kind = "left" } end
    if b3 == 72 then return { kind = "home" } end
    if b3 == 70 then return { kind = "end" } end
    if b3 == 51 then read_byte_timeout(); return { kind = "del" } end -- consume ~
    return { kind = "esc" }
  end
  if b >= 0x80 then
    return { kind = "char", ch = decode_utf8_char(b) }
  end
  if b >= 32 then return { kind = "char", ch = string.char(b) } end
  return { kind = "other" }
end

-- prompt_input: returns trimmed string or nil if cancelled.
-- Dynamic char table, no small limit, 4096 cap, horizontal scroll.
local function prompt_input(label)
  local chars = {} -- array of chars
  local cursor = 0 -- char index
  local offset = 0
  local label_len = #label + 1 -- label + space
  while true do
    local rows, cols = get_term_size()
    local avail = cols - label_len - 1
    if avail < 10 then avail = 10 end
    if cursor < offset then offset = cursor end
    if cursor >= offset + avail then offset = cursor - avail + 1 end
    io.write(string.format("\27[%d;1H\27[2KEnter=save  Esc / Ctrl-C=cancel", rows - 1))
    io.write(string.format("\27[%d;1H\27[2K", rows))
    io.write(label .. " ")
    local ending = math.min(offset + avail, #chars)
    if offset < #chars then
      local slice = {}
      for i = offset + 1, ending do table.insert(slice, chars[i]) end
      io.write(table.concat(slice))
    end
    local cursor_x = label_len + (cursor - offset) + 1
    if cursor_x > cols then cursor_x = cols end
    io.write(string.format("\27[%d;%dH", rows, cursor_x))
    io.flush()
    local k = read_key()
    if k.kind == "enter" then break end
    if k.kind == "esc" or k.kind == "ctrl_c" or k.kind == "ctrl_d" then return nil end
    if k.kind == "backspace" then
      if cursor > 0 then table.remove(chars, cursor); cursor = cursor - 1 end
    elseif k.kind == "del" then
      if cursor < #chars then table.remove(chars, cursor + 1) end
    elseif k.kind == "left" then
      if cursor > 0 then cursor = cursor - 1 end
    elseif k.kind == "right" then
      if cursor < #chars then cursor = cursor + 1 end
    elseif k.kind == "home" or k.kind == "ctrl_a" then
      cursor = 0
    elseif k.kind == "end" or k.kind == "ctrl_e" then
      cursor = #chars
    elseif k.kind == "ctrl_u" then
      chars = {}; cursor = 0; offset = 0
    elseif k.kind == "ctrl_k" then
      while #chars > cursor do table.remove(chars) end
    elseif k.kind == "ctrl_w" then
      while cursor > 0 and chars[cursor] == " " do table.remove(chars, cursor); cursor = cursor - 1 end
      while cursor > 0 and chars[cursor] ~= " " do table.remove(chars, cursor); cursor = cursor - 1 end
    elseif k.kind == "up" or k.kind == "down" then
      -- ignore
    elseif k.kind == "char" then
      if #chars < MAX_INPUT then
        table.insert(chars, cursor + 1, k.ch)
        cursor = cursor + 1
      end
    end
  end
  return trim(table.concat(chars))
end

local function run_tui()
  local orig = enable_raw()
  local selected = 1 -- 1-based into visible list
  local filters = { "all", "todo", "done", "overdue", "today" }
  local filter_idx = 1
  local search = ""
  local status = "Press q or Esc to quit - j/k move, Space toggle, a add, e edit, d delete, / search, f filter"
  local ok, err = pcall(function()
    while true do
      local rows, cols = get_term_size()
      local filter_mode = filters[filter_idx]
      local visible = filtered_indices(filter_mode, search)
      if #visible == 0 then selected = 1
      else
        if selected > #visible then selected = #visible end
        if selected < 1 then selected = 1 end
      end
      io.write("\27[2J\27[H")
      local total = #tasks
      local done_n = count_done()
      local overdue_n = count_overdue()
      print("tasks - " .. total .. " total | " .. done_n .. " done | " .. overdue_n .. " overdue | filter: " .. filter_mode .. " | search: " .. search)
      print("#    []  P    Due         Text")
      print(string.rep("-", math.min(80, cols)))
      local max_rows = math.max(5, rows - 5)
      for i = 1, math.min(#visible, max_rows) do
        local idx = visible[i]
        local t = tasks[idx]
        local mark = t.done and "x" or " "
        local line = string.format("%-4d", idx) .. " [" .. mark .. "] "
        if t.priority ~= "" then line = line .. "(" .. t.priority .. ") " end
        if t.due ~= "" then line = line .. "due:" .. t.due .. " " end
        line = line .. t.text
        if #line > cols then line = line:sub(1, math.max(0, cols)) end
        if i == selected then
          print("\27[7m" .. line .. "\27[0m")
        elseif t.done then
          print("\27[2m" .. line .. "\27[0m")
        else
          print(line)
        end
      end
      io.write(string.format("\27[%d;1H\27[2K%s", rows - 1, status))
      io.write(string.format("\27[%d;1H\27[2K", rows))
      io.write("q / Esc / Ctrl-C to quit - j/k move - Space toggle - a add - e edit - d delete - / search - f filter - u undo - c clear - s stats")
      io.write(string.format("\27[%d;1H", rows))
      io.flush()
      local k = read_key()
      -- EXIT - checked FIRST, from main list view
      if k.kind == "esc" or k.kind == "ctrl_c" or k.kind == "ctrl_d" or k.kind == "ctrl_q" then break end
      if k.kind == "char" and (k.ch == "q" or k.ch == "Q") then break end

      if k.kind == "down" or (k.kind == "char" and k.ch == "j") then
        if selected + 1 <= #visible then selected = selected + 1 end
      elseif k.kind == "up" or (k.kind == "char" and k.ch == "k") then
        if selected > 1 then selected = selected - 1 end
      elseif k.kind == "char" and k.ch == "g" then
        selected = 1
      elseif k.kind == "char" and k.ch == "G" then
        if #visible > 0 then selected = #visible end
      elseif k.kind == "char" and k.ch == " " then
        if #visible > 0 then
          local idx = visible[selected]
          tasks[idx].done = not tasks[idx].done
          save_tasks()
          status = tasks[idx].done and "Marked done" or "Marked todo"
        end
      elseif k.kind == "char" and k.ch == "a" then
        local s = prompt_input("Add:")
        if s and s ~= "" then
          local nt = parse_add_text(s)
          table.insert(tasks, nt)
          save_tasks()
          selected = #tasks
          status = "Added: " .. nt.text
        else
          status = "Add cancelled - press q or Esc to quit"
        end
      elseif k.kind == "char" and k.ch == "e" then
        if #visible > 0 then
          local idx = visible[selected]
          local old = tasks[idx]
          local s = prompt_input("Edit [" .. old.text .. "]:")
          if s and s ~= "" then
            local nt = parse_add_text(s)
            if nt.priority == "" then nt.priority = old.priority end
            if nt.due == "" then nt.due = old.due end
            nt.done = old.done
            tasks[idx] = nt
            save_tasks()
            status = "Edited"
          end
        end
      elseif k.kind == "char" and k.ch == "d" then
        if #visible > 0 then
          local idx = visible[selected]
          local removed = tasks[idx].text
          table.remove(tasks, idx)
          save_tasks()
          status = "Deleted: " .. removed
          if selected >= #visible and selected > 1 then selected = selected - 1 end
        end
      elseif k.kind == "char" and k.ch == "/" then
        local s = prompt_input("Search:")
        if s ~= nil then
          search = s
          selected = 1
          status = search ~= "" and ("Search: " .. search) or "Search cleared - press q or Esc to quit"
        end
      elseif k.kind == "char" and k.ch == "f" then
        filter_idx = filter_idx % #filters + 1
        selected = 1
        status = "Filter: " .. filters[filter_idx]
      elseif k.kind == "char" and k.ch == "u" then
        local bf = io.open(BACKUP_FILE, "r")
        if bf then bf:close(); copy_file(BACKUP_FILE, TASKS_FILE); load_tasks(); status = "Undone"
        else status = "No backup to undo" end
      elseif k.kind == "char" and k.ch == "c" then
        local before = #tasks
        local kept = {}
        for _, t in ipairs(tasks) do if not t.done then table.insert(kept, t) end end
        tasks = kept
        save_tasks()
        status = "Cleared " .. (before - #tasks) .. " done"
        selected = 1
      elseif k.kind == "char" and k.ch == "s" then
        local total2 = #tasks
        local done_n2 = count_done()
        local overdue_n2 = count_overdue()
        status = "Total " .. total2 .. " - Done " .. done_n2 .. " - Todo " .. (total2 - done_n2) .. " - Overdue " .. overdue_n2
      elseif k.kind == "char" and k.ch == "?" then
        status = "Keys: q/Esc quit, j/k move, Space toggle, a add, e edit, d delete, / search, f filter, u undo, c clear, s stats"
      end
    end
  end)
  disable_raw(orig)
  if not ok then print("TUI error: " .. tostring(err)) end
end

local function print_help()
  print("Usage:")
  print("  tasks tui                    Interactive TUI (default, no args = tui)")
  print("  tasks add [--priority P1] [--due YYYY-MM-DD] <text>")
  print("  tasks list [--tag X] [--project Y] [--priority P1] [--search Q] [--overdue|--today|--done|--todo]")
  print("  tasks done <n>")
  print("  tasks undone <n>")
  print("  tasks rm <n>")
  print("  tasks edit <n> <new text>")
  print("  tasks search <query>")
  print("  tasks clear")
  print("  tasks stats")
  print("  tasks undo")
  print("  tasks help")
  print()
  print("Format: tasks.md lines are - [ ] (P1) due:2026-11-30 Buy milk #home +groceries")
  print("Tags start with #, projects with +. Priority P1/P2/P3, due YYYY-MM-DD.")
  print("TUI keys: j/k or arrows move, Space toggle, a add, e edit, d delete,")
  print("  / search, f filter, u undo, c clear done, s stats, q / Esc / Ctrl-C to quit")
  print("  In a prompt: Enter saves, Esc / Ctrl-C cancels")
end

load_tasks()

local args = arg or {}
local cmd = args[1]

if not cmd or cmd == "tui" then
  run_tui()
  print("Exited TUI - back to shell. Use: lua tasks.lua list")
  os.exit(0)
end

if cmd == "help" or cmd == "--help" or cmd == "-h" then
  print_help()
elseif cmd == "add" then
  local priority, due = "", ""
  local parts = {}
  local i = 2
  while i <= #args do
    if args[i] == "--priority" and i + 1 <= #args then priority = args[i + 1]; i = i + 2
    elseif args[i] == "--due" and i + 1 <= #args then due = args[i + 1]; i = i + 2
    else table.insert(parts, args[i]); i = i + 1 end
  end
  local buf = table.concat(parts, " ")
  if trim(buf) == "" then print("Usage: tasks add <text>"); os.exit(0) end
  local t = parse_add_text(buf)
  if priority ~= "" then t.priority = priority end
  if due ~= "" then t.due = due end
  table.insert(tasks, t)
  save_tasks()
  print("Added: " .. t.text)
elseif cmd == "list" then
  local rest = {}
  for i = 2, #args do table.insert(rest, args[i]) end
  cli_list(rest)
elseif cmd == "done" then
  if #args < 2 then print("Usage: tasks done <n>"); os.exit(0) end
  local idx = parse_task_number(args[2], #tasks)
  if not idx then print("Invalid task number"); os.exit(0) end
  tasks[idx].done = true
  save_tasks()
  print("Done: " .. tasks[idx].text)
elseif cmd == "undone" then
  if #args < 2 then print("Usage: tasks undone <n>"); os.exit(0) end
  local idx = parse_task_number(args[2], #tasks)
  if not idx then print("Invalid task number"); os.exit(0) end
  tasks[idx].done = false
  save_tasks()
  print("Todo: " .. tasks[idx].text)
elseif cmd == "rm" then
  if #args < 2 then print("Usage: tasks rm <n>"); os.exit(0) end
  local idx = parse_task_number(args[2], #tasks)
  if not idx then print("Invalid task number"); os.exit(0) end
  local removed = tasks[idx].text
  table.remove(tasks, idx)
  save_tasks()
  print("Deleted: " .. removed)
elseif cmd == "edit" then
  if #args < 3 then print("Usage: tasks edit <n> <new text>"); os.exit(0) end
  local idx = parse_task_number(args[2], #tasks)
  if not idx then print("Invalid task number"); os.exit(0) end
  local rest = {}
  for i = 3, #args do table.insert(rest, args[i]) end
  local nt = parse_add_text(table.concat(rest, " "))
  local old = tasks[idx]
  if nt.priority == "" then nt.priority = old.priority end
  if nt.due == "" then nt.due = old.due end
  nt.done = old.done
  tasks[idx] = nt
  save_tasks()
  print("Edited " .. idx .. ": " .. nt.text)
elseif cmd == "search" then
  if #args < 2 then print("Usage: tasks search <query>"); os.exit(0) end
  local rest = {}
  for i = 2, #args do table.insert(rest, args[i]) end
  local q = table.concat(rest, " ")
  local found = false
  for i, t in ipairs(tasks) do
    if matches_search(t, q) then print_task(i, t); found = true end
  end
  if not found then print("No matches.") end
elseif cmd == "clear" then
  local before = #tasks
  local kept = {}
  for _, t in ipairs(tasks) do if not t.done then table.insert(kept, t) end end
  tasks = kept
  save_tasks()
  print("Cleared " .. (before - #tasks) .. " done tasks")
elseif cmd == "stats" then
  local total = #tasks
  local done_n = count_done()
  local overdue_n = count_overdue()
  local today_n = 0
  for _, t in ipairs(tasks) do if not t.done and is_today(t) then today_n = today_n + 1 end end
  print("Total: " .. total .. "\nDone: " .. done_n .. "\nTodo: " .. (total - done_n) .. "\nOverdue: " .. overdue_n .. "\nDue today: " .. today_n)
  local c1, c2, c3 = 0, 0, 0
  for _, t in ipairs(tasks) do
    if t.priority == "P1" then c1 = c1 + 1 end
    if t.priority == "P2" then c2 = c2 + 1 end
    if t.priority == "P3" then c3 = c3 + 1 end
  end
  if c1 > 0 or c2 > 0 or c3 > 0 then
    print("By priority:")
    if c1 > 0 then print("  P1: " .. c1) end
    if c2 > 0 then print("  P2: " .. c2) end
    if c3 > 0 then print("  P3: " .. c3) end
  end
  local tag_counts = {}
  for _, t in ipairs(tasks) do
    for tok in t.text:gmatch("%S+") do
      if #tok > 1 and tok:sub(1, 1) == "#" then tag_counts[tok] = (tag_counts[tok] or 0) + 1 end
    end
  end
  local keys = {}
  for k in pairs(tag_counts) do table.insert(keys, k) end
  if #keys > 0 then
    table.sort(keys)
    print("By tag:")
    for _, k in ipairs(keys) do print("  " .. k .. ": " .. tag_counts[k]) end
  end
elseif cmd == "undo" then
  local bf = io.open(BACKUP_FILE, "r")
  if not bf then print("No backup to undo"); os.exit(0) end
  bf:close()
  copy_file(BACKUP_FILE, TASKS_FILE)
  print("Undone - restored from backup")
else
  print("Unknown command: " .. cmd)
  print_help()
end
