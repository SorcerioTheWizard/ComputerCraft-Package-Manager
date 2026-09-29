# Computer Craft Package Manager

> The package manager for ComputerCraft and ComputerCraft: Tweaked with Pinestore (and more) support.

## Install

Run this on any ComputerCraft computer:

```
wget run https://raw.githubusercontent.com/SorcerioTheWizard/ComputerCraft-Package-Manager/master/install.lua
```

The installer downloads CCPM from the [registry](https://github.com/SorcerioTheWizard/CCPM-Registry), checks every file against its published hash, and sets the computer up so installed programs run by name and installed libraries can be required from anywhere.
Run it again at any time to update or repair CCPM.

To install from a different registry, pass its URL: `wget run <installer URL> <registry URL>`.

## Installing Packages

```
ccpm search <words>          Find packages
ccpm install <package>       Install a package and everything it needs
ccpm update                  Update installed packages
ccpm remove <package>        Remove a package and anything only it needed
ccpm help                    List every command
```

Projects from [Pinestore](https://pinestore.cc) are mirrored into the registry every day and install the same way, as `pinestore/<name>`.
Pinestore projects that download a single file are tracked like any other package.
Projects that run their own installer show the exact command and ask before running it, and CCPM cannot remove the files such an installer creates.
Installs of Pinestore projects are reported to Pinestore so their authors keep their download counts.

## Using CCPM in Your Programs

Programs can load the packages they need with `require("ccpm")`.
Paste this at the top of a program to also install CCPM on computers that do not have it yet:

```lua
-- Install CCPM if needed, then load it
if not fs.exists("/ccpm/lib/ccpm/init.lua") then
    shell.run("wget", "run", "https://raw.githubusercontent.com/SorcerioTheWizard/ComputerCraft-Package-Manager/master/install.lua")
end
package.path = "/ccpm/lib/?.lua;/ccpm/lib/?/init.lua;" .. package.path
local ccpm = require("ccpm")
```

Then declare what the program needs where you would call `require`:

```lua
local json = ccpm.requires("json", "^1.0")
```

If the package is missing or too old, CCPM shows what it will install and asks first.
The package then stays installed, so later runs load it immediately without touching the network.

| Function                               | Description                                                                                                  |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `ccpm.requires(name, range, options)`  | Installs a package if needed, then returns its library, or `true` if it only has programs. `range` defaults to any version. Pass `{ auto = true }` to install without asking, for unattended programs. |
| `ccpm.installed(name)`                 | The installed version of a package, or `nil`.                                                                |
| `ccpm.version()`                       | The installed version of CCPM.                                                                               |
| `ccpm.env()`                           | The computer's ComputerCraft and Minecraft versions, kind, and color support.                                |
| `ccpm.dataPath(name, file)`            | A folder for a program's own settings and saves, created if needed, or a file inside it.                     |
| `ccpm.sharePath(name, file)`           | The folder of a package's read-only assets, or a file inside it.                                             |
| `ccpm.preventTerminate()`              | Stops Ctrl+T from closing programs until `ccpm.allowTerminate()` or a reboot, for door locks and kiosks.     |
| `ccpm.withoutTerminate(fn, ...)`       | Runs a function Ctrl+T cannot interrupt, then allows it again, even if the function fails.                   |
| `ccpm.runAtStartup(name, program)`     | Runs a program every time the computer boots, alongside CCPM's other boot entries.                           |
| `ccpm.removeFromStartup(name)`         | Stops running a program added with `runAtStartup`.                                                           |
