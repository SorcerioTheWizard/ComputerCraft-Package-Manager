---
id: SOC-3
title: Announce CCPM on r/ComputerCraft
status: todo
priority: 2
requires: [SOC-2, SOC-5]
metadata: {}
---

# Announce CCPM on r/ComputerCraft

Post an announcement of CCPM to [r/ComputerCraft](https://www.reddit.com/r/ComputerCraft/).

## What the post should cover

- The problem it solves: `pastebin run` works for one program, but installing and updating several programs and their libraries gets messy. SquidDev described exactly this in [CC: Tweaked issue #425](https://github.com/cc-tweaked/CC-Tweaked/issues/425).
- The one command install, copied from the README.
- That every [Pinestore](https://pinestore.cc) project installs by name as `pinestore/<name>`, and that installs through CCPM still count as downloads on Pinestore, so authors keep their stats.
- Dependency resolution with version ranges, checks against the computer's ComputerCraft and Minecraft versions, and `ccpm.requires` for programs that install what they need.
- How to publish: `uv run ccpm-registry new` in the registry repository.
- Links to the main repository and the registry, and the demo GIF or video.

## Before posting

- Recommended: make sure Pinestore's author knows CCPM mirrors their catalog and reports downloads, so they do not hear about it from the post.
- This ticket requires the demo video (SOC-2) and CCPM's Pinestore page (SOC-5), so the post can link both.
- One or two more native packages in the registry would also make the post stronger, but that is not required.
- Refer to it as "CCPM, the ComputerCraft Package Manager", since two dormant, unrelated projects have used the name `ccpm` before ([schroffl/ccpm](https://github.com/schroffl/ccpm) and a [forum post](https://forums.computercraft.cc/index.php?topic=169.0)).
