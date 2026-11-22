[b]ModCore Controls[/b]

[center][b]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/b]
[size=4][b]Tested for The Blood of Dawnwalker 1.2[/b][/size]
[b]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/b][/center]

ModCore Controls (MCC) lets you configure Dawnwalker's keyboard and mouse quickslot controls in the mod menu. It saves your bindings, applies them in game and updates the HUD key indicators.

[b]Features[/b]
[list]
[*]One Controls page: MCC's settings are the Controls tab of the ModCore Settings page, with the Quickslots template picker, Mappings and Behaviours. ModCore Controls' entry in the mod list opens it.
[*]Mappings page with three tabs: Group Keys act on the focused wheel or select a wheel directly, Global Keys address individual ability and consumable slots, and Controller lists your current gamepad mappings (read-only).
[*]Tap and Hold bindings for keyboard and mouse keys, in exploration and combat.
[*]Tap vs Hold Threshold: an adjustable window from Low to High (100-350 ms by default, within 100-500 ms); Instant Tap fires a lone Tap on press.
[*]Quickslot Wheels: choose the default wheel, allow swapping outside of combat, and hold to swap, release to return.
[*]HUD key hints show your bindings, Hold keys are underlined, and a key's outline fills while it is held (Show key outline: None, Hold, or Tap & Hold).
[*]A key bound twice is marked as you edit, across Group Keys and Global Keys, and Apply refuses it; saved bindings carry over between sessions.
[*]Keys left on the game's default follow the game's key settings; custom keys replace the game action they stand in for.
[*]ModCore Templates quickslot templates follow wheel focus and Global keys, and their settings head the Controls tab.
[/list]

[b]Requirements and installation[/b]

Requires The Blood of Dawnwalker, UE4SS with Lua 5.4, UE4SS Lua Extensions 1.4.0 or newer, and ModCore Settings 1.10.0 or newer with Dawnwalker Mod Menu. Install and enable under Mods/2_ModCore_Controls. Preserve config.ini when updating and fully restart after changing Lua files.

Controller mappings are read-only. Developers can add static maps to MCC's source; there is no cross-mod runtime map-registration API.

[b]The ModCore modules[/b]

ModCore Settings provides menu integration; MCC handles quickslot input; ModCore Templates manages visual templates and object lifecycle.

[b]Documentation[/b]

[url=https://github.com/jrpereira/ModCoreControls/blob/main/docs/README.md]Full README and installation details[/url]
[url=https://github.com/jrpereira/ModCoreControls/blob/main/docs/DEVELOPERS.md]Developer guide[/url]
[url=https://github.com/jrpereira/ModCoreControls/blob/main/docs/RUNTIME.md]Runtime reference[/url]
[url=https://github.com/jrpereira/ModCoreControls/blob/main/docs/CHANGELOG.md]Changelog[/url]
