# Tasks CLI Experiment

The same task-management command-line application implemented in ten languages to compare their syntax, idioms, tooling, and ergonomics against a common behavioral specification.

See [SPEC.md](SPEC.md) for the shared commands, storage format, expected output, edge cases, and manual test sequence. The spec also preserves the original planning notes.

## Implementations

| Language | Entry point | Example build/run (from its directory) |
| --- | --- | --- |
| C | [`c/tasks.c`](c/tasks.c) | `cc tasks.c -o tasks` then `./tasks` |
| C++ | [`cpp/tasks.cpp`](cpp/tasks.cpp) | `c++ -std=c++17 tasks.cpp -o tasks` then `./tasks` |
| Go | [`go/tasks.go`](go/tasks.go) | `go run tasks.go` |
| Java | [`java/Tasks.java`](java/Tasks.java) | `javac Tasks.java` then `java Tasks` |
| Lua | [`lua/tasks.lua`](lua/tasks.lua) | `lua tasks.lua` |
| Python | [`python/tasks.py`](python/tasks.py) | `python3 tasks.py` |
| Ruby | [`ruby/tasks.rb`](ruby/tasks.rb) | `ruby tasks.rb` |
| Rust | [`rust/tasks.rs`](rust/tasks.rs) | `rustc tasks.rs -o tasks` then `./tasks` |
| TypeScript | [`typescript/tasks.ts`](typescript/tasks.ts) | `npx tsx tasks.ts` (requires Node.js and tsx) |
| Zig | [`zig/tasks.zig`](zig/tasks.zig) | `zig build-exe tasks.zig` then `./tasks` |

Append `add "Buy milk"`, `list`, `done 1`, `rm 1`, `clear`, or `stats` to the invocation. Each implementation uses a `tasks.md` file in its working directory. Run in separate working directories for independent test data.

## Status

Source snapshot imported from Google Drive, including Ruby and Lua. The implementation files are unchanged; toolchain compatibility and behavioral conformance have not yet been verified. Build/run examples are illustrative, not a tested compatibility matrix.
