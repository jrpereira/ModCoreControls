[b]ModCore Controls[/b]

ModCore Controls (MCC) lets you configure Dawnwalker's keyboard and mouse quickslot controls in the mod menu. It saves bindings, applies them through Enhanced Input and updates the HUD key indicators.

[b]Features and benefits[/b]
[list]
[*]Bind individual abilities and consumables, use slots on the focused wheel, or select a wheel directly.
[*]Choose the default wheel and Toggle Quickslots behavior, including hold-to-swap.
[*]Configure Tap/Hold bindings for supported actions in exploration and combat.
[*]Use all control maps together; selecting a map only changes the rows displayed in the menu.
[*]Apply checks duplicate custom keys across maps and saves successful changes between sessions.
[*]HUD key hints reflect MCC bindings; MCC restores original indicators when its modifications are removed.
[*]Native input integration handles player/input-resource changes, inherited game keys and declared overrides.
[*]Wheel-focus events let ModCore Templates coordinate visuals with controls; the Controls page also hosts contributed quickslot visual settings.
[/list]

[b]Requirements and installation[/b]

Requires The Blood of Dawnwalker, UE4SS with Lua 5.4, UE4SSLuaEventBridge 1.0.9 or newer (API 6), and ModCore Settings with Dawnwalker Mod Menu. Install and enable under Mods/2_ModCore_Controls. Preserve config.ini when updating and fully restart after changing Lua files.

Controller mappings are read-only. Movement and System pages are placeholders. Developers can add static maps to MCC's source; there is no cross-mod runtime map-registration API.

[b]The ModCore modules[/b]

ModCore Settings provides menu integration; MCC handles quickslot input; ModCore Templates manages visual templates and object lifecycle.

[b]Documentation[/b]

[url=https://github.com/jrpereira/ModCoreControls/blob/main/docs/README.md]Full README and installation details[/url]
[url=https://github.com/jrpereira/ModCoreControls/blob/main/docs/DEVELOPERS.md]Developer guide[/url]
[url=https://github.com/jrpereira/ModCoreControls/blob/main/docs/RUNTIME.md]Runtime reference[/url]
[url=https://github.com/jrpereira/ModCoreControls/blob/main/docs/CHANGELOG.md]Changelog[/url]
