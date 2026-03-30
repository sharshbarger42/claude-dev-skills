## Quality Gate — Pre-Push Checks

Run these checks **before** staging and committing code. This prevents CI failures from formatting, lint, or test regressions.

### Procedure

1. **Detect the project toolchain.** Check which files exist in the repo root to determine the stack:

   | Marker file | Stack | Format command | Lint command | Test command |
   |-------------|-------|---------------|-------------|-------------|
   | `pyproject.toml` | Python (uv) | `uv run ruff format {files}` | `uv run ruff check --fix {files}` | `uv run pytest tests/ -x -q` |
   | `package.json` | Node | `npx prettier --write {files}` | `npx eslint --fix {files}` | `npm test` |
   | `go.mod` | Go | `gofmt -w {files}` | `go vet ./...` | `go test ./...` |

   If multiple markers exist, run checks for each applicable stack. If none match, skip formatting/linting but still look for a test command.

   **Scope `{files}` to only the files you changed** — use `git diff --name-only HEAD` (unstaged) or track which files you edited. Never format/lint the entire repo.

2. **Auto-format changed files.** Run the format command for the detected stack. This modifies files in place — that's expected. Example for Python:

   ```bash
   uv run ruff format path/to/changed_file.py path/to/other_file.py
   ```

3. **Lint changed files with auto-fix.** Run the lint command. The `--fix` flag resolves auto-fixable issues (import sorting, unused imports, etc.). Example for Python:

   ```bash
   uv run ruff check --fix path/to/changed_file.py path/to/other_file.py
   ```

   If lint errors remain after `--fix`, read the output and fix them manually before proceeding.

4. **Run tests.** Run the test command for the detected stack. If tests fail, fix the failures before committing.

   ```bash
   uv run pytest tests/ -x -q
   ```

   If no test suite exists or tests are not relevant to the change (e.g., docs-only change), skip this step.

5. **Verify clean.** Run the format check (dry-run) to confirm nothing was missed:

   ```bash
   uv run ruff format --check path/to/changed_file.py path/to/other_file.py
   uv run ruff check path/to/changed_file.py path/to/other_file.py
   ```

   Both must exit 0 before you proceed to `git add` and `git commit`.

### Important

- Run this gate on **every** commit, not just the final push.
- If formatting changes files, those changes must be included in the same commit as your code changes.
- Do not skip the gate because "it's just a small change" — small changes cause CI failures too.
- If the repo has a `ruff.toml`, `pyproject.toml [tool.ruff]`, `.prettierrc`, or similar config, the tools will pick it up automatically — do not override settings.
