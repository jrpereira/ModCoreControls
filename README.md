# ModCore Controls

Input is what the player does physically. Actions are what happens in the game.
They are separate, connected through input actions, bindings, and mappings.

For example, pressing J is an input. `InputAction_JumpOrDiveOrClimb` can select
`Action_Jump` while the player is grounded, `Action_Climb` while latched to a
rope, or `Action_Dive` while underwater. A binding connects J to that input
action; a mapping is a collection of bindings.

## Sections

MCC groups related input actions into extensible sections. The initial sections
are Actions, Movement, and System. Each section is
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
section and contain named groups of key definitions. The initial Actions maps
are Grouped and Global. Their declarations live in `Scripts/mc_maps.lua`.

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
            keys = {
                { id = 'DemoAbility1', name = 'Ability 1', trigger = 'Tap|Hold',
                  default = 49, action = { type = 'ability', slot = 1 } },
            },
        },
    },
})
```

The menu definition sources are:

- `Scripts/mc_sections.lua`
- `Scripts/mc_maps.lua`
- `Scripts/mc_triggers.lua`

`mod_settings.ini` contains only DMM discovery metadata. The DMM extension
reads these Lua definitions and creates the settings schema when DMM builds its
Controls page.

## DMM and storage

Controls is presented through DMM. Its first row is a Section picker marked
`mcNavigation=1` and `mcHeading=true`, with Actions, Movement, and System as its
choices. This picker is transient navigation state:
it controls which section is visible and is never written to `config.ini`.

Persistent choices use MCC's sectioned INI format:

```ini
[ModCoreControls.actions]
map=default
default.SwapOutsideCombat=1
default.HoldSwap=0
default.DefaultWheel=2
global.SlotAction1.key=74
global.SlotAction1.trigger=0
```

Only the selected section's rows are visible. Actions shows **Control Map** with
**Default | Grouped | Global | Advanced**, followed by the selected map's controls.
Default owns the wheel swap on the player's Toggle Quickslots key and suppresses
the game's `IA_Combat_ToggleQuickslots` with an override. It has three settings.
**Allow Swap outside of combat** makes the swap usable in open world as well as
in combat. **Hold to Swap, release to return** turns the key into press and
release edges: holding shows the wheel other than the default and releasing
returns; with it off, each press flips the wheels. **Default wheel** picks the
wheel focused at rest. Default is the base map: its Default wheel stays in effect
under Grouped, Global, and Advanced, which override only what they bind. MCC
activates it after settings load, and released or re-tapped group keys return to
it. Focus enables the focused wheel and disables the other
when a layout has moved the wheels out of the native switcher; native slot keys
follow the enabled wheel. Leaving Default removes the override.
Grouped, Global, and Advanced do not expose these settings. Grouped titles its
sections after the Default wheel: **Group 1** is the Default wheel, with its Group
key and the four shared slot keys, which fire the focused wheel; **Group 2** is
the other wheel, with its Group key on the inherited Toggle Quickslots key.
Advanced has three four-slot sections: Ability slots 1–4, Consumable slots 5–8,
and reserved slots 9–12. Each section has an optional **Group** hold/tap binding.
An optional key with `defaultControl` stores zero while inheriting that standard
game control dynamically. Advanced Group 2 inherits `IA_Combat_ToggleQuickslots`;
a custom nonzero key replaces the inheritance.
When a Group is bound, its four slot fields become dim, borderless static aliases.
Slots 1–8 use the unassigned virtual-key identifiers `0xC1`–`0xC8` for those
display aliases; they cannot be captured or mapped as physical keys. Their HUD
prompts reuse the group input action, including its key and Tap/Hold mode.
Slots 9–12 are saved for future use but do not create gameplay bindings yet. Sections
without maps have no controls yet. Each Lua map group becomes a visible DMM
heading with its keys kept together beneath it. DMM owns key capture, Apply,
and Restore.

## Enhanced Input runtime

At startup, MCC reads the selected Actions map from the sectioned INI and turns
its bindings into generated Enhanced Input actions. MCC creates no mapping
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
positions, Grouped/Global wheel focus, and their HUD key indicators. Selected maps
replace declared native actions with root-captured chord gates. Existing gates
are reused, and detach removes only MCC-owned gates while retaining them in a
bounded process-lifetime pool.

## Installation

Install and enable this mod as `Mods/_ModCore_2_Controls`. Install its
ModCoreSettings dependency as `Mods/_ModCore_1_Settings`. Preserve `config.ini`
when updating.

Map-level `override` lists apply for the whole selected map. A key-level
descriptor such as `{ action='IA_Name', value=164 }` uses `value` as that key's
default and applies the override while the key is active. Setting a key to
Unbound disables that MCC binding; it does not necessarily suppress the native
action. Map-level overrides remain active independently of individual keys.

## Documentation

- [Developer guide](docs/DEVELOPERS.md)
- [Build guide](docs/BUILD.md)
- [Changelog](CHANGELOG.md)
