# CCPM: Computer Craft Package Manager

A package manager for ComputerCraft. It installs, updates, and removes programs and libraries, and pulls in whatever they depend on.

Pinestore's catalogue is supported out of the box. Every Pinestore project is installable both as a package and as a declared dependency by name like `pinestore/<name>` so each install still counts as a download for its author.

## Features

- Resolves dependencies and version ranges like `^1.2.0`.
- Downloads and hash checks every file before writing anything keeping a failed install from leaving a computer half set up.
- Checks that a package supports your ComputerCraft and Minecraft version (if bounds are supplied for the package).
- Installed programs run by name from anywhere on the computer, and libraries can be required from any program.
- Programs can automatically (with permission prompt) install their own dependencies with `ccpm.requires("pinestore/pixelbox")`.
- The system is self contained and never needs to touch your `startup.lua`.

## Install

Use the Pinestore install button to copy an install command.

If it fails with `Unable to install program. Make sure pinestore.cc is whitelisted!`, your server hasn't whitelisted Pinestore. Instead, install from the official GitHub repository instead:

```bash
wget run https://raw.githubusercontent.com/SorcerioTheWizard/ComputerCraft-Package-Manager/master/install.lua
```

## Registering Your Package

For developers, registering your package as a native package gets you more direct support.

Native packages can depend on other packages with version ranges, declare which ComputerCraft and Minecraft versions they support, have every file hash checked on install, and get tracked so `ccpm update` and `ccpm remove` handle them cleanly.

Your current hosting does not have to change. All it takes is registering it with in the [CCPM Registry](https://github.com/SorcerioTheWizard/CCPM-Registry#publishing-a-package).

A publishing wizard that walks you through the process is included, so no need to get deep into the schemas.

## More Info

Full docs are on [GitHub](https://github.com/SorcerioTheWizard/ComputerCraft-Package-Manager), and packages are published through the [CCPM Registry](https://github.com/SorcerioTheWizard/CCPM-Registry). Found a bug? [Open an issue](https://github.com/SorcerioTheWizard/ComputerCraft-Package-Manager/issues).
