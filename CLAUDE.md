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

## Commits

- Plain messages only. Do NOT add a `Co-Authored-By` or `Generated with` trailer unless explicitly asked.
- Short subject line expressing what was done as a short imperative.
- Subject line only. No body, no additional text.
- Never commit unprompted. Verify (compile and test), report ready for review, then wait for review.
- When presenting code for review (ie: when you stop at Phases or Checkpoints), stage the code you believe should be merged at this review stage and use the `commit-message` skill (or fall back to repo style if the command does not exist) to draft the commit subject alongside it.
