---
id: SOC-5
title: Register CCPM on Pinestore
status: todo
priority: 2
requires: []
metadata: {}
---

# Register CCPM on Pinestore

Publish CCPM as a project on [Pinestore](https://pinestore.cc), so people browsing Pinestore discover it.

## Project details

- Install command: the same one command install as the README, `wget run https://raw.githubusercontent.com/SorcerioTheWizard/ComputerCraft-Package-Manager/master/install.lua`.
- Repository: the main [ComputerCraft-Package-Manager](https://github.com/SorcerioTheWizard/ComputerCraft-Package-Manager) repository.
- Description: lead with installing any Pinestore project by name, since that is the reason a Pinestore visitor would want it.
- Media: the demo GIF (`repo/demo.gif`) and any screenshots.

## Follow-up in the registry

The daily Pinestore sync will mirror this new project into the registry as an installer package named `pinestore/<slug>`, which would let `ccpm install` reinstall CCPM through its own installer. Once the project exists, add an override to `external/pinestore/overrides.json` in [CCPM-Registry](https://github.com/SorcerioTheWizard/CCPM-Registry) keyed by its Pinestore project ID, with `"skip": true` and a `note` explaining that CCPM is already published natively as `ccpm`.
