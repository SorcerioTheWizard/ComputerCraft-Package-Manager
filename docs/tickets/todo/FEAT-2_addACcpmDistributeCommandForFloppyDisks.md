---
id: FEAT-2
title: Add a Ccpm Distribute Command for Floppy Disks
status: todo
priority: 2
requires: []
metadata: {}
---

# Add a Ccpm Distribute Command for Floppy Disks

Add `ccpm distribute`, which lets the user pick installed programs and copies them, with everything they depend on, onto a floppy disk in an attached disk drive, so they can be installed on other computers without the network.

## Why

Many servers restrict or disable HTTP, and moving programs between computers by hand means knowing every file and dependency. CCPM already records exactly which files each package owns and what it depends on, so it can pack them reliably.

## Proposed behavior

1. Find attached disk drives with a disk in them through the `disk` API (`disk.isPresent`, `disk.getMountPath`). With none, explain how to attach one; with several, ask which to use.
2. Show the installed packages the user asked for (`explicit` records in `ccpm.state`) and let them pick one or more. Build the picker in `ccpm.ui` as a reusable, package agnostic control, following the rule that all output goes through `ui.lua`.
3. Collect each picked package's dependencies recursively from the installed records, and show the full list, total size, and the disk's free space (`fs.getFreeSpace`) before asking to continue. Floppy disks are small (125 KB by default), so refuse clearly when it will not fit.
4. Copy each package's files and its install record onto the disk.

## Installing from the disk

The disk also needs a way to install what it carries on the other computer. Proposed: `ccpm install --from <disk path>` (or `ccpm install disk/...`) reads the records on the disk, checks each file against the `sha256` in its record, and installs through the normal installer, so ownership checks, boot stubs, and orphan tracking all still apply. Offline installs must not refresh the registry index.

## Open questions

- **Target computers without CCPM.** Should the disk also carry CCPM itself, with an install program on the disk that sets it up offline? This would make the disk work on any computer, but costs about 70 KB of the disk.
- **Disk startup.** Avoid writing `startup.lua` to the disk by default: disk startup runs automatically when the disk is inserted (if `shell.allow_disk_startup` is on), which would install software without asking. An explicit program on the disk is safer.
- **Installer packages** (`kind` `installer`, like many Pinestore projects) have no tracked files, so they cannot be copied. Exclude them from the picker, or list them with the reason.
- **Library only packages.** Should the picker offer only packages with programs, or everything installed explicitly?

## Tests

Specs will need a fake disk drive and disk API in `tests/support/`, in the style of `fake_http.lua`, plus coverage for dependency collection, the free space check, the round trip onto a disk and back, and a file whose hash no longer matches.
