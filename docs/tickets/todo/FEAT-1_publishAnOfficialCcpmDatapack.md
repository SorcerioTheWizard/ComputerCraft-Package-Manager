---
id: FEAT-1
title: Publish an Official CCPM Datapack
status: todo
priority: 2
requires: []
metadata: {}
---

# Publish an Official CCPM Datapack

Publish an official datapack that makes `ccpm` available on every computer in a world or modpack, with no `wget run` step, on Modrinth (and possibly CurseForge).

## Why

CC: Tweaked lets datapacks add files to every computer's read only ROM through `data/computercraft/lua/rom/...` (see the official [datapack example](https://github.com/cc-tweaked/datapack-example) and [discussion #1201](https://github.com/cc-tweaked/CC-Tweaked/discussions/1201)). Programs in `rom/programs/` run by name on every computer. That gives server owners and modpack makers a one file way to ship CCPM, which is also the most realistic path to CCPM being "built in", since CC: Tweaked itself declined to bundle a package manager ([issue #425](https://github.com/cc-tweaked/CC-Tweaked/issues/425)).

## The design problem

A copy of CCPM in the ROM is read only and only changes when the datapack is updated, while `ccpm upgrade` and the one command installer put CCPM in `/ccpm`. Shipping the whole client in the ROM would leave two copies fighting over which runs.

## Proposed approach

Ship a tiny `rom/programs/ccpm.lua` stub rather than the whole client:

1. When `/ccpm/bin/ccpm.lua` exists, the stub runs it with the same arguments, so the installed copy is always what runs and `ccpm upgrade` keeps working.
2. When it does not, the stub runs the same bootstrap as `install.lua`, then runs the newly installed `ccpm` with the arguments.

The stub must forward rather than shadow, because `rom/programs` comes before `/ccpm/bin` on the shell path. It should almost never need to change, which keeps datapack updates rare. Reuse `install.lua`'s logic rather than duplicating it; for example, have the stub fetch and run `install.lua` itself.

## Distribution

- **Modrinth** first. CC: Tweaked publishes there, and Modrinth supports datapack projects with a declared dependency on CC: Tweaked.
- **CurseForge** is optional. CC: Tweaked is still listed on [CurseForge](https://www.curseforge.com/minecraft/mc-mods/cc-tweaked) with about 80M downloads, but it is no longer published there; the last files are from September 2024, and new releases are Modrinth only. A CurseForge listing would only reach modpacks built in the CurseForge app on those older CC: Tweaked versions. Decide whether that audience is worth maintaining a second project page for; CurseForge also requires datapacks to be a separate project type from mods.

## Things to check before building

- The `data/computercraft/lua/rom` layout and `pack.mcmeta` `pack_format` for each Minecraft version CCPM supports (CCPM's own `compat` is CC: Tweaked `>=1.100`). One datapack may need several builds.
- Datapacks apply per world. Document how server owners add it to `world/datapacks`, and how modpacks apply it globally (typically with a global datapack mod).
- A datapack cannot change a server's HTTP rules, so the stub still needs `raw.githubusercontent.com` allowed; its errors should say so, like the installer's do.
- Add a CI job that builds the datapack zip from the repository so it never drifts from `install.lua`.
