# Tasks CLI Experiment

The same task-management application implemented in twelve languages to compare syntax, idioms, tooling, and ergonomics against a common behavioral baseline. The current implementations extend the original CLI with an interactive terminal UI.

See [docs/SPEC.md](docs/SPEC.md) for the original shared specification and manual test sequence. It is preserved as the historical baseline; the current v2 implementations have additional commands and storage metadata.

## Implementations

Each language has its own directory under `src/`. Run these examples from that directory.

| Language | Entry point | Example build/run |
| --- | --- | --- |
| C | [`src/c/tasks.c`](src/c/tasks.c) | `cc -O2 tasks.c -o tasks` then `./tasks` |
| C++ | [`src/cpp/tasks.cpp`](src/cpp/tasks.cpp) | `c++ -std=c++17 -O2 tasks.cpp -o tasks` then `./tasks` |
| C# | [`src/csharp/tasks.cs`](src/csharp/tasks.cs) | `dotnet run --project tasks.csproj` (.NET 8) |
| Go | [`src/go/tasks.go`](src/go/tasks.go) | `go run tasks.go` |
| Java | [`src/java/Tasks.java`](src/java/Tasks.java) | `javac Tasks.java` then `java Tasks` |
| JavaScript | [`src/javascript/tasks.js`](src/javascript/tasks.js) | `node tasks.js` |
| Lua | [`src/lua/tasks.lua`](src/lua/tasks.lua) | `lua tasks.lua` (Lua 5.3+) |
| Python | [`src/python/tasks.py`](src/python/tasks.py) | `python3 tasks.py` |
| Ruby | [`src/ruby/tasks.rb`](src/ruby/tasks.rb) | `ruby tasks.rb` |
| Rust | [`src/rust/tasks.rs`](src/rust/tasks.rs) | `rustc -O tasks.rs -o tasks` then `./tasks` |
| TypeScript | [`src/typescript/tasks.ts`](src/typescript/tasks.ts) | `npm install` then `npm run build` and `npm start` |
| Zig | [`src/zig/tasks.zig`](src/zig/tasks.zig) | `zig build-exe tasks.zig -O ReleaseSafe` then `./tasks` (Zig 0.13/0.14 targeted) |

## Current v2 behavior

The implementations provide an interactive TUI by default, plus CLI commands including `add`, `list`, `done`, `undone`, `rm`, `edit`, `search`, `clear`, `stats`, `undo`, and `help`. For command-line arguments with C#, use `dotnet run -- list`; with TypeScript, use `npm start -- list`.

The intended shared storage format is `tasks.md` in the working directory, with optional priority, due date, tags, and projects. Example: `- [ ] (P1) due:2026-11-30 Buy milk #home +groceries`. Undo uses `tasks.md.bak`. Use separate working directories for independent comparisons until interoperability is tested.

The TUIs need an interactive terminal. Some implementations use POSIX terminal APIs or `stty`; Python uses `curses`. Ruby uses `io/console` raw mode, Rust uses direct Linux termios FFI (targeted at glibc on x86_64/aarch64), and Zig uses POSIX termios with date APIs targeting Zig 0.13/0.14. Platform and compiler compatibility may vary.

## Status

All twelve v2 implementations synchronized from Google Drive, including the C# project and TypeScript build configuration. Build/run examples are illustrative; compilation, runtime behavior, and cross-language conformance have not yet been verified. The original shared spec remains unchanged.
