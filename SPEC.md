# Tasks - Same App in Every Language
## Piece 0 - Shared Spec (applies to Python, C, C++, Rust, TypeScript, and any later language)
Goal: Build the exact same complete CLI app in each language, so you can compare how each language feels.
### App name
tasks
### Commands
* tasks add "Buy milk" - adds a task
* tasks list - shows all tasks with numbers
* tasks done 2 - marks task 2 complete
* tasks rm 2 - deletes task 2
* tasks clear - removes completed tasks
* tasks stats - shows total, done, and remaining
### Storage
One markdown file, one task per line.
Format per line: `- [ ] Buy milk` for open, `- [x] Buy milk` for done.
Exact format: dash, space, [, space or lowercase x, ], space, then task text. No other variants.
File lives next to the app / in the working directory as `tasks.md` for this experiment.
If the file does not exist on first run, treat it as empty. Do not crash.
No JSON, no external libraries, no markdown library. Standard library only, just string prefix checks.
### Output - keep identical across languages
* list when empty: `No tasks yet.`
* list with tasks: numbered from 1, e.g. `1. [ ] Buy milk` and `2. [x] Walk dog`
* add: `Added: Buy milk`
* done: `Done: Buy milk`
* rm: `Removed: Buy milk`
* clear: `Cleared N completed task(s).`
* stats: `Total: 3 | Done: 1 | Remaining: 2`
* help / no args: show the command list above.
### Edge cases - must handle in every language
* add with no text: `Error: task text is required.`
* done / rm with missing number, non-number, or out-of-range number: `Error: invalid task number.`
* clear when nothing is completed: `Cleared 0 completed task(s).`
### Test script - run this in every language
1. tasks add "Buy milk"
2. tasks add "Walk dog"
3. tasks add "Read 10 pages"
4. tasks list
5. tasks done 2
6. tasks list
7. tasks stats
8. tasks rm 1
9. tasks list
10. tasks clear
11. tasks list
### Folder layout
* Tasks - Same App in Every Language/ - this spec lives here
* python/ - Python version
* Future: c/, cpp/, rust/, typescript/ - one folder per language, same spec, same test script.
### Rule for this experiment
Piece by piece. Do not jump ahead to the full app. Next piece after this spec is Piece 1 for Python only.
