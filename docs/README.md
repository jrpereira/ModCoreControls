# ModCore Controls

ModCore Controls (MCC) connects keyboard and mouse bindings to Dawnwalker's
quickslot actions. It saves your bindings, applies them in game, and updates the
HUD key indicators.

## Features and benefits

- **Choose how to access quickslots:** bind individual ability or consumable
  slots, act on the focused wheel, or select a wheel directly.
- **Configure wheel switching:** choose the default wheel and Toggle Quickslots
  behavior, including hold-to-swap. A wheel key set to Hold shows its wheel
  while held and returns to the default wheel on release.
- **Set the Tap vs Hold Threshold:** a window from Low to High (100-350 ms by default,
  within 100-500 ms): a Hold key acts at High, its rim filling up to it; a Tap fires
  on press, or on a release before High when the same key is also a Hold. With
  **Instant Tap** off, a Tap alone on its key fires on release or at High, whichever
  comes first.
- **Use keyboard and mouse bindings with Tap/Hold:** configure supported actions
  in the menu and activate them in exploration and combat.
- **Keep all control maps available:** every map's bindings work together; each
  map's page only shows its keys for editing.
- **Save validated bindings:** Apply checks for duplicate custom keys across
  maps and saves successful changes for the next session.
- **Keep HUD hints aligned:** key indicators reflect MCC bindings, with original
  values restored when those modifications are removed. Keys set to Hold are
  underlined, and a key's outline fills while it is held (**Show key outline**:
  None, Hold, or Tap & Hold).
- **Follow the game's own controls:** keys left on the game's default follow the
  game's key settings, and custom keys replace the game action they stand in for.
- **Coordinate controls and visuals:** ModCore Templates quickslot templates follow
  wheel focus and Global keys, and their settings sit at the top of the Controls tab.

## Choose the right module

| Module | Responsibility |
| --- | --- |
| ModCoreSettings (MCS) | Menu controls, pending edits and Apply |
| ModCoreControls (MCC) | Input bindings and quickslot actions |
| ModCoreTemplates (MCT) | Visual templates, settings and object lifecycle |

Start with the [developer guide](DEVELOPERS.md) to add a control map to MCC's
source. Maps are static declarations; MCC has no cross-mod runtime registration API.

## Requirements and installation

Use Dawnwalker, UE4SS with Lua 5.4, UE4SSLuaEventBridge 1.3.0 or newer (API 6 or newer),
and ModCoreSettings 1.9.0 or newer with Dawnwalker Mod
Menu (DMM). With an older bridge, controls do not attach and the log says why.
Install and enable
MCC under `Mods/2_ModCore_Controls`. Preserve `config.ini` when updating and
fully restart the game after changing Lua files.

## Menu behavior

MCC's settings are the **Controls** tab of the ModCore Settings page, its second tab,
after Settings. ModCore Controls' entry in the mod list opens it. Top to bottom:

| Section | Contents |
| --- | --- |
| Quickslots | MCT quickslot template selection and settings, when contributed |
| Mappings | Links (**edit**) **Group Keys** (the Groups map), **Global Keys** (the Global map) and **Controller** (a read-only list of the player's current gamepad mappings), each opening the **Mappings** page on that tab |
| Behaviours | Quickslot Wheels (default wheel and Toggle Quickslots behavior) and Shortcuts (Instant Tap, Tap vs Hold Threshold and key outline) |

Apply on the Controls tab saves these settings into MCC's `config.ini`. The
Mappings page's title row picks its tab, Group Keys, Global Keys or Controller; the page
has its own Apply, and Back returns to the Controls tab with the link that opened it
selected. Every map's bindings stay active together; its tab only shows them. The same
key with the same trigger on two rows is marked as it is edited, on Group Keys and
Global Keys alike (the tab picker is marked too when the pair is on two tabs), and Apply
rejects it on either page; the same key with Tap on one row and Hold on another is two
separate bindings.

Group Keys act on the focused wheel; Global Keys address individual
ability or consumable slots. Some keys use the game's own control while you leave them
unbound. The Toggle Quickslots swap gives way on a key you bind to something else.
See the [runtime reference](RUNTIME.md) for Tap/Hold timing and overrides.

## Storage and logging

Bindings are text: `none`, `J|Hold`, or `1|Tap`. For example:

```ini
[ModCoreControls.actions]
global.AbilitySlot1=J|Hold
```

Navigation choices are never saved. A successful Apply saves the configuration;
new bindings take effect once you are in game.

Logs appear in `UE4SS.log`. The default level is WARN. For more detail, install the
UE4SS Lua Log Bridge and raise ModCoreControls's level on its Logs page, or set
`ModCoreControls=DEBUG` under `[Levels]` in the bridge's `config.ini`.

## Documentation

- [Nexus description](https://github.com/jrpereira/ModCoreControls/blob/main/docs/NEXUS.bb): condensed, paste-ready module description in BBCode.
- [Developer guide](DEVELOPERS.md): add a map and understand its settings.
- [Runtime reference](RUNTIME.md): Tap/Hold timing, inherited keys, overrides and events.
- [Build guide](BUILD.md): offline tests and in-game checks.
- [Changelog](CHANGELOG.md): version history.
