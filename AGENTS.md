# Agent instructions

- `README.md` is the repository map and usage guide; `docs/SPEC.md` is the common behavioral specification.
- Keep project-wide Markdown documentation in `docs/`, except root-level `README.md`, `AGENTS.md`, and `CLAUDE.md`.
- Each language lives in its own root-level directory. Keep language-specific source, build files, and tests there.
- Preserve comparable commands, output, edge cases, and Markdown storage across implementations. Avoid introducing dependencies or language-specific features that alter the experiment unless requested.
- Run the shared manual test sequence and edge cases in isolated working directories when modifying an implementation. Record actual toolchain versions and test results; do not claim unverified conformance.
- Keep generated binaries, compiled artifacts, and local `tasks.md` data out of commits.
