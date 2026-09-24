# ModCore Controls

Define reusable control layouts, action mappings, cancellation of core actions,
and extensions to core apps, with explicit lifecycle management.

Register gameplay callbacks once and map them through selectable layouts.
Controls handles input ownership; your callback still has to do the interesting part.

## Features

- Grouped, Flat, and Advanced quickslot controls with configurable key/mode pairs.
- Reusable action/layout APIs and control-phase events.
- Generation checks that reject callbacks from retired binding installations.
- Suppression of allowlisted native actions while replacement controls are active.

## Requirements and installation

Use UE4SS with Lua 5.4. Install under `Mods/_ModCore_Controls` and enable the mod.
Native input requires the separately installed
[UE4SSLuaEventBridge](https://github.com/jrpereira/UE4SSLuaEventBridge), loaded
before Controls. The bridge DLL is not included in Controls.

Dawnwalker Mod Menu and ModCoreSettings provide the configurable controls page.
The quickslot input host runs independently of ModCoreTemplates visual selection.
Restart after changing native dependencies.

## Integration boundary

The current quickslot host binds four ability and four consumable directions.
Layout declarations can describe additional positions, but those declarations
alone do not add live game actions. Native suppression is limited to its allowlist.
Offline lifecycle tests cover simulated boundaries; validate input and cleanup
in the target game.

## Documentation

- [Developer guide](docs/DEVELOPERS.md): integration contracts and examples.
- [Build guide](docs/BUILD.md): source preparation and tests.
- [Changelog](CHANGELOG.md): changes by version.
