# KEngine Controls (KEC)

KEC separates **actions** (what a mod does) from **controls** (which input calls
that action). Players can choose an Actions Layout and change bindings without
requiring each skill or gameplay mod to implement its own input system.

The only UE4SS mod folder is `_KEngineControls`. KEC's Lua library lives in
`Scripts/kec/`. Its `dlls/main.dll` is the verified
[UE4SSLuaEventBridge v1.0.1](https://github.com/jrpereira/UE4SSLuaEventBridge/releases/tag/v1.0.1)
release DLL. The bridge is a component of KEC, with no separate bridge mod folder.

## Current integration

The first integration moves the existing quickslot input engine into KEC.
Its **Extended Controls** mod menu begins with **Actions & Quickslots** and
owns **Access Method** (Grouped, Flat, Advanced), the controls
shown for that method, directional actions, and Tap/Hold bindings. KEngineTemplates
keeps template selection and wheel visuals. KEC starts its own native quickslot
input host from saved controls and refreshes it on KEC Apply, whether or not a
KET visual template is selected. The reusable action/layout API is available
for new mod actions. During player load, the host retries until a live player
controller, pawn input component, and that controller's Enhanced Input local
player subsystem are available, then adds KEC's mapping context to the
subsystem. It does not wait for Dawnwalker's native context on initial player
load. It stops retrying after attachment and resumes on a later gameplay
lifecycle change.

The menu shows numbered controls. Flat presents Ability 1–4 and Consumable
1–4 as paired key and Tap/Hold rows. Advanced adds an optional **Activate** key
for each Flat action and separate group overrides. A bound Activate key must
be held while pressing the Flat action key. Unbound Activate keys let the
action key work alone.
Grouped and Advanced use columns 1–4 within each group. Columns map to the
native Left, Top, Right, and Bottom positions in that order. The player changes
each key directly; retired Assignment picker values in older configs are
ignored.
Grouped mode presents **Group Key** (Abilities and Consumables) followed by
**Slot Key** (Slots 1–4). A Group Key selects a whole row; its four Slot Keys
trigger positions in that row. Each Tap/Hold picker is paired with its key
capture.

`templates/default.tpl` defines **Basic Slots**: two four-position ability
groups and one four-position consumable group. The second ability group begins
hidden. `templates/skill_slots.tpl` defines Weapon, day Witchcraft or night
Vampire, and Consumables, with two positions initially shown in each skill
group. `templates/flexi_slots.tpl` defines the 12x1, 6x2, and 4+2x4 grouping
presets and the ability/consumable order. Each layout has twelve active
positions and Basic/Skill provide three group rows: a row key selects the
group, then numbered keys select its columns. KEC resolves extra position
visibility from ability assignments and equipped skill limits reported by the
game, with no hardcoded level thresholds. The source files are declarative;
they do not execute Lua.

`KEngineControls.defaultLayout()`, `skillLayout()`, and `flexiLayout()` load
the definitions. `resolveLayout(layout, phase, available)` and
`flexiGroups(layout, preset, order)` compute their active positions. The
existing `newTopology({groups=..., dispatch=...})` accepts Basic's groups,
`activeGroups(skill, phase)`, or `flexiGroups(...).groups`. In Groups mode,
selecting a row routes shared column controls to that row's actions. The
`readGameSlots(quickslotSubsystem, characterDevelopmentSubsystem)` adapter
collects the player's current game state on the game thread. Its parameters
are the live game subsystems, and it does not mutate them. The
current native quickslot host still binds the existing HUD's four ability and
four consumable directional actions; connecting additional ability positions
to live game actions and displaying them is the next runtime integration.

`kec.core` lets a producer register a stable action ID, label, and callback.
Layouts independently bind those IDs to Unreal key names and Tap/Hold triggers.
The bundled bridge backend turns a plan into Enhanced Input bindings. A consumer
must call `activate` on the game thread with a backend whose target resolver
returns exact live input component and subsystem paths.

```lua
local Core = require('kec.core')
local controls = Core.new({backend = backend})
controls:registerAction({id='my_mod.dash', label='Dash', execute=function(event)
    dash(event)
end})
controls:registerLayout({id='default', label='Default', bindings={
    ['my_mod.dash']={key='F10', trigger='Tap'},
}})
controls:selectLayout('default')
controls:activate('combat')
```

The runtime uses Lua 5.4. `tests/` contains offline checks for layout behavior,
quickslot planning, mapping, lifecycle, and dispatch. In-game acceptance is
still required after installation.

## Control events

KEC publishes stable string identifiers. A consumer in another UE4SS Lua state
can load `kec.event_transport` from `_KEngineControls/Scripts` and call
`subscribe(name, callback)`. The returned function unsubscribes. Local users of
`kec.core` or `kec.topology` can call `:subscribe(name, callback)` on their
instance. Listener errors do not interrupt input delivery.

| Event | Callback arguments |
| --- | --- |
| `ControlContextAttached`, `ControlContextDetached` | `context` |
| `ControlGroupFocused`, `ControlGroupUnfocused` | `controls, group` |
| `ControlActionStarted`, `ControlActionTriggered`, `ControlActionCompleted`, `ControlActionCanceled` | `controls, group, action` |

Action phases match Unreal Enhanced Input. Quickslot IDs use
`player.quickslots`, `ability` or
`consumable`, and names such as `quickslot.ability.left`.
