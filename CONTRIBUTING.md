# Contributing to CCPM

Thanks for helping make CCPM better!
This repository holds the `ccpm` client that runs on ComputerCraft computers.
Packages themselves are published in [CCPM-Registry](https://github.com/SorcerioTheWizard/CCPM-Registry), which has its own contributing guide.

* [Contributing to CCPM](#contributing-to-ccpm)
    * [Ways to Contribute](#ways-to-contribute)
    * [Development Setup](#development-setup)
    * [Making a Change](#making-a-change)
    * [Public Contracts](#public-contracts)
    * [Code Style](#code-style)
    * [Pull Requests](#pull-requests)
    * [Releasing](#releasing)

## Ways to Contribute

- **Report a bug** by opening an issue with the output of `ccpm env`, the command you ran, and what happened.
- **Suggest a feature** by opening an issue describing the problem it solves before starting on a large change.
- **Fix a bug or build a feature** by opening a pull request, as described below.
- **Publish a package** in [CCPM-Registry](https://github.com/SorcerioTheWizard/CCPM-Registry); packages never go in this repository.

## Development Setup

1. Install [CraftOS-PC](https://www.craftos-pc.cc), which runs the specs in throwaway headless computers.
2. Clone this repository and run the specs from its root:

    ```bash
    scripts/test.sh              # Run every spec
    scripts/test.sh semver       # Run the specs whose file names contain `semver`
    ```

3. Set `CRAFTOS` to the CraftOS-PC console executable when `craftos` is not on the `PATH`, like `CRAFTOS="C:/Program Files/CraftOS-PC/CraftOS-PC_console.exe"`.

For editor support, install the [Lua language server](https://luals.github.io).
`.luarc.json` and the stubs in `types/` teach it the ComputerCraft APIs.

To try your changes on a computer, copy `src/` to `/ccpm` on a CraftOS-PC computer and run `/ccpm/bin/ccpm.lua setup`.

## Making a Change

The source tree mirrors where files are installed on a computer:

| Folder             | Installed to   | Holds                                                               |
| ------------------ | -------------- | ------------------------------------------------------------------- |
| `src/bin/`         | `/ccpm/bin/`   | The `ccpm` program.                                                 |
| `src/lib/ccpm/`    | `/ccpm/lib/`   | Every module, required as `ccpm.<module>`, and the `ccpm` library.  |
| `install.lua`      | nothing        | The one command installer.                                          |
| `tests/`           | nothing        | The test harness, fakes, and specs.                                 |
| `types/`           | nothing        | Type stubs for the Lua language server.                             |

Every change needs specs:

- Specs live in `tests/spec/<name>_spec.lua` and use `describe`, `it`, `beforeEach`, `afterEach`, and `check`.
- Call `sandbox.use()` from `tests/support/sandbox.lua` so each test gets a fresh CCPM root.
- Never let a spec touch the network. Serve packages with `tests/support/fake_registry.lua` and responses with `tests/support/fake_http.lua`.
- A bug fix should come with a spec that fails without the fix.

## Public Contracts

Some things are relied on by computers and programs we cannot update, so they must never break:

- **The installer URL.** `install.lua` on `master` is the command everyone runs; it must never move or stop working.
- **The `ccpm` library.** Functions in `src/lib/ccpm/init.lua` are a public API. Add to it freely, but never remove a function or change what an existing one does.
- **The bootstrap snippet** in the README relies on `/ccpm/lib/ccpm/init.lua` existing.
- **Version ranges.** `src/lib/ccpm/semver.lua` must accept exactly the same ranges as the registry's `semver.py`; change both together.
- **The index format.** The client must keep reading the `index.json` format the registry publishes; the registry bumps its format number for any change the client cannot safely ignore.

## Code Style

The full rules are in [CLAUDE.md](CLAUDE.md). In short:

- Every module starts with a title, a blank comment line, and a one line description, and is split into `-- MARK: Imports`, `-- MARK: Constants`, `-- MARK: Functions`, and similar sections.
- Functions are documented with LuaLS annotations: a `---` summary, then `---@param` and `---@return` lines.
- Nearly every logical block gets a short imperative comment, like `-- Check the hash`.
- Use American English, never use em dashes, and keep each sentence of prose on one line.

## Pull Requests

1. Branch from `master`.
2. Make your change with specs, and update the README and `CLAUDE.md` where behavior or structure changed.
3. Run `scripts/test.sh` and make sure every spec passes.
4. Open a pull request; the default template covers features and general changes.
   For a bug fix, use the bug template by adding `?template=bug.md` to the pull request URL, like `https://github.com/SorcerioTheWizard/ComputerCraft-Package-Manager/compare/master...<your branch>?template=bug.md`.
5. CI runs every spec in CraftOS-PC on Linux; it must pass before merging.

Commit messages are a short imperative subject line with no body, like `Add hosts command`.

## Releasing

Maintainers release a new version of CCPM by publishing it to the registry:

1. Merge the change to `master` here and wait for CI to pass.
2. In CCPM-Registry, write the version manifest, pinned to the released commit:

    ```bash
    uv run ccpm-registry manifest ccpm <version> src/bin/ccpm.lua=bin/ccpm.lua src/lib/ccpm=lib/ccpm --github SorcerioTheWizard/ComputerCraft-Package-Manager --ref <commit> --cc ">=1.100"
    ```

3. Commit it as `Release ccpm <version>` and push; computers get it with `ccpm upgrade`.
