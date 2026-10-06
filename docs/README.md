# ModCore Controls

ModCore Controls (MCC) connects keyboard and mouse bindings to Dawnwalker's
quickslot actions. It saves bindings, applies them through Enhanced Input, and
updates the HUD key indicators.

## Choose the right module

| Module | Responsibility |
| --- | --- |
| ModCoreSettings (MCS) | Menu controls, pending edits and Apply |
| ModCoreControls (MCC) | Input bindings and quickslot actions |
| ModCoreTemplates (MCT) | Visual templates, settings and object lifecycle |

Start with the [developer guide](DEVELOPERS.md) to add a control map to MCC's
source. Maps are static declarations; MCC has no cross-mod runtime registration API.

## Requirements and installation

Use Dawnwalker, UE4SS with Lua 5.4, UE4SSLuaEventBridge Enhanced Input API 4 or
newer, and ModCoreSettings with Dawnwalker Mod Menu (DMM). Install and enable
MCC under `Mods/2_ModCore_Controls`. Preserve `config.ini` when updating and
fully restart the game after changing Lua files.

## Menu behavior

| Controls page | Contents |
| --- | --- |
| Options | Default wheel and Toggle Quickslots behavior |
| Visuals | MCT quickslot template selection and settings, when contributed |
| Key & Mouse | Actions maps; Movement and System are placeholders |
| Controller | Read-only list of the player's current gamepad mappings |

Every map's bindings stay active together. **Control Map** selects which rows
to display; it does not enable or disable a map. Apply rejects a custom key used
by two rows, even when one uses Tap and the other Hold.

Quickslot Groups operates on the focused wheel; Global addresses individual
ability or consumable slots. An optional binding with `defaultControl` inherits
the game's control while unbound. Default's swap yields a key claimed by a custom
binding. See the [runtime reference](RUNTIME.md) for timing and overrides.

## Storage and logging

Bindings are text: `none`, `J|Hold`, or `1|Tap`. For example:

```ini
[ModCoreControls.actions]
global.AbilitySlot1=J|Hold
```

Navigation choices are never saved. A successful Apply saves the configuration;
activation can remain pending until the player's native input resources are ready.

Logs appear in `UE4SS.log`. The default level is WARN. For more detail, put
`debug` in `Mods/2_ModCore_Controls/log_level.txt` and restart.

## Documentation

- [Developer guide](DEVELOPERS.md): add a map and understand its settings.
- [Runtime reference](RUNTIME.md): native input, overrides and events.
- [Build guide](BUILD.md): offline tests and in-game checks.
- [Changelog](CHANGELOG.md): version history.
