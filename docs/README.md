# ModCore Controls

Input is what the player does physically. Actions are what happens in the game.
They are separate, connected through input actions, bindings, and mappings.

For example, pressing J is an input. `InputAction_JumpOrDiveOrClimb` can select
`Action_Jump` while the player is grounded, `Action_Climb` while latched to a
rope, or `Action_Dive` while underwater. A binding connects J to that input
action; a mapping is a collection of bindings.

## Sections

MCC groups related input actions into extensible sections. The initial sections
are Module, Actions, Movement, and System. Module holds settings that apply
across sections, such as the wheel swap. Each section is
initialized as:

```lua
{ description = "", sets = {} }
```

The registries expose `addSection(section, description)` and
`addSectionMap(section, map)` for static source declarations. Gameplay and DMM
load separate Lua states and build their definitions independently; calling
these functions after startup does not update either existing model. Only the
Actions section currently produces runtime input. Movement and System are menu
placeholders. See the developer guide for the supported declaration shape.

## Triggers

| Action | Trigger | Behavior | Enhanced Input value |
| --- | --- | --- | --- |
| Immediate | Tap | Trigger on a qualifying release within the Tap threshold. | `0` |
| Immediate | Hold | Trigger after holding for the configured time. | `1` |
| Sustained | Tap | Tap to turn on; tap again to turn off. | `0` |
| Sustained | Hold | Active while held. | `2` |

## Maps

A map is a group of keys that work together as one input style. Maps point to a
section and contain named groups of key definitions. A section's maps coexist:
all of their bound keys are active together. Module has one map, Default; the
Actions maps are Quickslot Groups and Global. Their declarations live in `Scripts/mc_maps.lua`.

```lua
-- Add this static declaration in mc_maps.lua before the registry is consumed.
M.addSectionMap('actions', {
    id = 'single_slot_demo',
    name = 'Single Slot Demo',
    value = 2,
    contexts = { 'exploration', 'combat' },
    map = {
        {
            name = 'Fixed Controls',
            settings = {
                { id = 'DemoAbility1', name = 'Ability 1', type = 'keybind', default = '1|Tap',
                  params = { trigger = 'Tap|Hold', action = { type = 'ability', slot = 1 } } },
            },
        },
    },
})
```

Every setting has an `id`, a `name`, a `type` and an optional `default`; the
arguments specific to its type sit in `params`, and any other field is rejected.
Map-level `settings` are `picker`s (`params={values,labels}`). A group's
`settings` list its `keybind`s (`params={trigger,action,optional,defaultControl,
override,sustained,…}`) and `mirror`s (`params={section,map,setting}`) in the
order the page shows them.

The menu definition sources are:

- `Scripts/mc_sections.lua`
- `Scripts/mc_maps.lua`
- `Scripts/mc_triggers.lua`

MCC installs no DMM extension and ships no `mod_settings.ini`. At startup it
publishes the Controls page to ModCoreSettings, which builds the page's settings
from these Lua definitions through `Scripts/mcs_page.lua` each time the menu
opens. The page appears once MCC has started.

## DMM and storage

Controls is presented through DMM. Its first row is a Page picker marked
`mcNavigation=1` and `mcHeading=true`: **Options | Visuals | Key & Mouse |
Controller**. Options shows the Module section's settings. Visuals is reserved
for ModCore Templates' quickslot template selection and shows a placeholder until
ModCoreSettings supports contributing rows into another mod's page. Key & Mouse
has a **Section** picker (Actions, Movement, System) and each section's controls.
Controller lists every gamepad button with the actions currently assigned to it,
read from the game when the menu is built, and a work-in-progress note. Page,
Section and Control Map are transient navigation state and are never written to
`config.ini`.

Persistent choices use MCC's sectioned INI format:

```ini
[ModCoreControls.module]
default.SwapOutsideCombat=1
default.HoldSwap=1
default.DefaultWheel=2
[ModCoreControls.actions]
global.AbilitySlot1=J|Hold
global.AbilitySlot2=1|Tap
grouped.QuickSlot1=none
```

A binding is one value: `none`, or the key's Unreal name and its trigger, joined
by `|`. Number keys are written as their digit (`1`, not `One`). `default` reads
as the declared binding. Lines from earlier versions (`….key=74`, `….trigger=0`)
are ignored, so those bindings return to their defaults.

Only the selected page's and section's rows are visible.
Actions shows **Control Map** with **Quickslot Groups | Global**, followed by
that map's controls. Control Map is
navigation only, like the Section picker: every map's bound keys are active
together, and a key and trigger bound in two maps is rejected at Apply. Slot and
Group keys are Unbound until the player binds them.
Default owns the wheel swap on the player's Toggle Quickslots key and suppresses
the game's `IA_Combat_ToggleQuickslots` with an override. It has three settings.
**Allow Swap outside of combat** makes the swap usable in open world as well as
in combat. **Hold to Swap, release to return** is on by default and turns the key into press and
release edges: holding shows the wheel other than the default and releasing
returns; with it off, each press flips the wheels. **Default wheel** picks the
wheel focused at rest. Default's settings are module-wide: its Default wheel
stays in effect under Quickslot Groups and Global, which add only what they bind. MCC
activates it after settings load, and released or re-tapped group keys return to
it. Focus enables the focused wheel and disables the other
when a layout has moved the wheels out of the native switcher; native slot keys
follow the enabled wheel.
Quickslot Groups has three sections. **Active Group** holds the four shared slot
keys, which fire the focused wheel. **Alternate Activation** has **Swap to
<wheel>**, a Hold/Tap key labelled after the wheel other than Default: tapping
it shows that wheel and tapping again swaps back, and holding shows it until
release. It inherits the Toggle Quickslots key while unbound. **Swap back to
default** repeats Default's Default wheel. **Explicit Activation** has
**Activate Abilities** and **Activate Consumables**, optional and unbound by
default: each always focuses its own wheel and never swaps. The swap key set to
Tap acts on press; explicit keys keep a real Tap. Global binds the four
ability and four consumable slots directly. An optional key with `defaultControl`
stores zero while inheriting that standard game control dynamically; a custom
nonzero key replaces the inheritance. Sections
without maps have no controls yet. Each Lua map group becomes a visible DMM
heading with its keys kept together beneath it. DMM owns key capture, Apply,
and Restore.

## Enhanced Input runtime

At startup, MCC reads every Actions map from the sectioned INI and turns
their bindings into generated Enhanced Input actions. MCC creates no mapping
context: a map's `contexts` say where its keys can be used, and MCC maps them
into the game's own contexts while they are applied. Keys usable in both open
world and combat go into `IMC_Base`, which stays applied across those
transitions; keys limited to one go into `IMC_OW` (exploration) or
`IMC_RTCombat` (combat). Detaching removes only MCC's entries; entries the
game drops are mapped again on the next sync.

Native callbacks are owned through UE4SSLuaEventBridge API 4 or newer. Tap and
immediate Hold bindings deliver `Triggered`; sustained Hold bindings deliver
`Started`, `Completed`, and `Canceled`, allowing Alternative focus to return to
the default wheel on release or cancellation. Callback generations are retired
when the input component changes or controls are reapplied.

Default's swap is an MCC action bound like any other. With Hold on, a hold
delivers a press and a release `Triggered`.

Successful DMM Apply notifications request a runtime reload of `config.ini`.
Saving choices and activating them are separate steps; attachment may remain
pending or fail if native resources are unavailable. Controller restart, pawn
assignment, mapping changes, object creation, and map load events retry pending
attachment. A full game restart is required for a reliable MCC script reload.

MCC assigns its generated slot actions to the native quickslot key indicators.
Apply reassigns those actions so CommonUI refreshes glyphs when a key changes.
Gameplay-context detach, replacement, and deactivation restore the original
indicator actions.

This runtime currently drives the eight native ability/consumable quickslot
positions, Quickslot Groups/Global wheel focus, and their HUD key indicators. Maps
replace declared native actions with root-captured chord gates. Existing gates
are reused, and detach removes only MCC-owned gates while retaining them in a
bounded process-lifetime pool.

## Installation

Install and enable this mod as `Mods/2_ModCore_Controls`. Install its
ModCoreSettings dependency as `Mods/1_ModCore_Settings`. Preserve `config.ini`
when updating.

Map-level `override` lists apply for as long as the map is loaded. A key-level
descriptor such as `{ action='IA_Name', value=164 }` uses `value` as that key's
default and applies the override while the key is active. Setting a key to
Unbound disables that MCC binding; it does not necessarily suppress the native
action. Map-level overrides remain active independently of individual keys.
A key with a `defaultControl` can declare `override=true`: while the player
binds a custom key in its place, the native `defaultControl` action is
suppressed; on its default key MCC adds no binding and leaves that key to the
native action.

A player key bound on the key Default's swap inherits from Toggle Quickslots
takes that key over: the swap steps aside until the key is free again.

## Logging

ModCore Controls writes to the UE4SS log at levels TRACE, DEBUG, INFO, WARN, ERROR
and CRITICAL. Only WARN and above are written by default. To see more, create
`Mods/2_ModCore_Controls/log_level.txt` containing one level name and restart the
game: `info` adds attachment and swap notices, `debug` adds pending syncs and
mappings, and `trace` adds key-profile lookups.

## Documentation

- [Developer guide](DEVELOPERS.md)
- [Build guide](BUILD.md)
- [Changelog](CHANGELOG.md)
