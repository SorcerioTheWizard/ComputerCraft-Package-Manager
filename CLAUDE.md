# CLAUDE.md

## General

- We use American English here.
- We *are not* lazy developers. We implement things the *right* way based on informed and reasoned hypotheses. If something is beyond the explicit scope of a ticket but it is the correct answer, then it is the proper course of action.
- We keep our code DRY and lean. If something is reused, it should be shared; not duplicated into multiple places.

## Environment

This project is a package manager for Minecraft's Computer Craft mod.

### Lua

Lua code is written here and executed in-game or on a ComputerCraft simulator like [CraftOS-PC](https://www.craftos-pc.cc) or [CCEmuX](https://emux.cc).

Documentation for ComputerCraft: Tweaked is found [here](https://tweaked.cc).

The source tree mirrors where files are installed on a computer:

- `src/bin/` is installed to `/ccpm/bin/`, which is added to the shell path.
- `src/lib/` is installed to `/ccpm/lib/`, which is added to the `require` path. Modules are required as `ccpm.<module>`.
- `/startup/00_ccpm.lua` is not shipped as a file. `ccpm setup` generates it (see `src/lib/ccpm/setup.lua`), because packages may only install into `bin/`, `lib/<name>/`, and `share/<name>/`.
- `install.lua` is the bootstrap installer. Its URL on `master` is public and must never move.
- `types/` holds type stubs for the Lua language server. It is never installed; add ComputerCraft APIs there when the editor flags them as undefined.

The package registry lives in a separate repository, [CCPM-Registry](https://github.com/SorcerioTheWizard/CCPM-Registry).

#### Testing

Specs live in `tests/spec/` as `<name>_spec.lua` and run inside a throwaway headless CraftOS-PC computer.

- Run them with `scripts/test.sh`, optionally passing a substring to filter spec file names.
- Set `CRAFTOS` to the CraftOS-PC console executable when `craftos` is not on the `PATH` (on this machine: `D:\AppData\CraftOS-PC\CraftOS-PC_console.exe`).
- Specs use the globals `describe`, `it`, `beforeEach`, `afterEach`, and `check` from `tests/harness.lua`.
- Never let a spec touch the network. Use the fakes in `tests/support/`.

### Python

Any Python used in this project is managed by `uv`.

- Always run Python through `uv`, as in `uv run python ...` and `uv run pytest`. Never call a bare `python`, `pip`, or the `.venv` interpreter directly.
- Add and remove dependencies with `uv add` and `uv remove`, never by editing `pyproject.toml` by hand.

## Code Style

Match existing style exactly:

- `# MARK: Imports` / `# MARK: Constants` / `# MARK: Functions` / `# MARK: Classes` / etc, section headers in every module.
- Module docstring: title line, blank line, one-line description.
- Function docstrings are in Google Style. Backticks around code refs. Backticks around code refs.
- Inline comment above nearly every logical block, **short** imperative ("# Stash the changes").
- Class body order: Properties, Initializer, Dunders, Private Functions, Functions.
- No em dashes anywhere, in code, comments, docs, or output.
- **Never** break a line mid-sentence in prose/docs/comments. One sentence stays on one line, word wrap handles width.

### Lua

The rules above apply to Lua with these translations:

- Section headers are `-- MARK: Imports`, `-- MARK: Constants`, `-- MARK: Functions`, etc.
- The module docstring is a `--` comment block at the top of the file: title line, blank `--` line, one-line description.
- Function docs are LuaLS annotations: a `---` summary line, then `---@param name type Description.` and `---@return type name Description.` in place of Google Style `Args:` and `Returns:`.
- Inline comments are `-- Stash the changes`.
- Modules return a single table, declared right after `-- MARK: Functions`. Private helpers are `local function`s above it.

## Commits

- Plain messages only. Do NOT add a `Co-Authored-By` or `Generated with` trailer unless explicitly asked.
- Short subject line expressing what was done as a short imperative.
- Subject line only. No body, no additional text.
- Never commit unprompted. Verify (compile and test), report ready for review, then wait for review.
- When presenting code for review (ie: when you stop at Phases or Checkpoints), stage the code you believe should be merged at this review stage and use the `commit-message` skill (or fall back to repo style if the command does not exist) to draft the commit subject alongside it.
