# Developer guide

- [Quickslot integration](#quickslot-integration)
- [Action and layout API](#action-and-layout-api)
- [Deferred work and lifecycle](#deferred-work-and-lifecycle)
- [Control events](#control-events)

ModCoreControls owns action mappings, layouts, and input lifetimes. Consumers
own gameplay callbacks; ModCoreTemplates owns visual template selection.
Lua imports retain the `mc.*` namespace.

Native input requires the separately installed
[UE4SSLuaEventBridge](https://github.com/jrpereira/UE4SSLuaEventBridge).
Controls does not bundle its DLL. Make the bridge available before activating
native bindings; missing bridge APIs leave input attachment pending.

## Quickslot integration

Its mod menu begins with **Actions & Quickslots** and
owns **Control Layout** (Grouped or Flat), the controls
shown for that method, directional actions, and Tap/Hold bindings. ModCoreTemplates
keeps template selection and wheel visuals. ModCoreControls starts its own native quickslot
input host from saved controls and refreshes it on ModCoreControls Apply, whether or not a
ModCoreTemplates visual template is selected. The reusable action/layout API is available
for new mod actions. During player load, the host retries until a live player
controller, pawn input component, and that controller's Enhanced Input local
player subsystem are available, then adds ModCoreControls's mapping context to the
subsystem. It does not wait for Dawnwalker's native context on initial player
load. Lifecycle and object-creation events wake a pending attachment attempt.

The menu shows numbered controls. Flat presents Ability 1–4 and Consumable
1–4 as paired key and Tap/Hold rows. Their defaults use distinct keys 1–8;
duplicate bindings are rejected when the Flat plan is built. Grouped uses columns 1–4 within each group. Columns map to the
native Left, Top, Right, and Bottom positions in that order. The player changes
each key directly. Configuration supports only the displayed Grouped and Flat
methods and rejects unsupported selector modes.
The machine-readable style, control, action, default-key, and mode definitions
live in `Scripts/ModCore/control_styles.lua`; the menu generator consumes that
file as its source of truth.
Flat puts the eight slots under **Fixed Controls** and has an optional
**Preview Alternative** key below them. Its Tap mode toggles the visible wheel
until pressed again; Hold selects the alternative while pressed and restores
the primary wheel on release. The preview key is unbound by default, and its
mode defaults to Hold.
Grouped mode presents **Group Key** (Abilities and Consumables) followed by
**Slot Key** (Slots 1–4). A Group Key selects a whole row; its four Slot Keys
trigger positions in that row. Each Tap/Hold picker is paired with its key
capture.
Grouped's Alternative key offers the same Tap and Hold behavior, with Hold as
its default. Saved configurations without the new mode field also use Hold.

`Scripts/ModCore/default.tpl` defines **Basic Slots**: two four-position ability
groups and one four-position consumable group. The second ability group begins
hidden. `Scripts/ModCore/skill_slots.tpl` defines Weapon, day Witchcraft or night
Vampire, and Consumables, with two positions initially shown in each skill
group. `Scripts/ModCore/flexi_slots.tpl` defines the 12x1, 6x2, and 4+2x4 grouping
presets and the ability/consumable order. Each layout has twelve active
positions and Basic/Skill provide three group rows: a row key selects the
group, then numbered keys select its columns. ModCoreControls resolves extra position
visibility from ability assignments and equipped skill limits reported by the
game, with no hardcoded level thresholds. The source files are declarative;
they do not execute Lua.

`ModCoreControls.defaultLayout()`, `skillLayout()`, and `flexiLayout()` load
the definitions. `resolveLayout(layout, phase, available)` and
`flexiGroups(layout, preset, order)` compute their active positions. The
existing `newTopology({groups=..., dispatch=...})` accepts Basic's groups,
`activeGroups(skill, phase)`, or `flexiGroups(...).groups`. In Groups mode,
selecting a row routes shared column controls to that row's actions. The
`readGameSlots(quickslotSubsystem, characterDevelopmentSubsystem)` adapter
collects the player's current game state on the game thread. Its parameters
are the live game subsystems, and it does not mutate them. The
current native quickslot host binds the existing HUD's four ability and
four consumable directional actions; additional declared ability positions are not yet connected to live game
actions or displayed by this host.

## Action and layout API

`mc.core` lets a producer register a stable action ID, label, and callback.
Layouts independently bind those IDs to Unreal key names and Tap/Hold triggers.
The bridge backend turns a plan into Enhanced Input bindings. A consumer
must call `activate` on the game thread with a backend whose target resolver
returns exact live input component and subsystem paths.

```lua
local Core = require('mc.core')
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

## Deferred work and lifecycle

Backend-delivered action callbacks receive `execute(event, executionContext)`.
Existing callbacks accepting only `event` need no changes. ModCoreControls automatically
rejects queued delivery from successfully deactivated or replaced installations.
Consumers scheduling additional work can retain the optional context:

```lua
execute=function(event, executionContext)
    queueWork(function()
        if executionContext and not executionContext.isValidGeneration() then return end
        dash(event)
    end)
end
```

`isValidGeneration()` describes the installation that delivered the callback,
not whichever binding is current. Once retired, that context stays invalid even
when the same action is rebound. Failed installation or failed closure of the
previous installation leaves the previous generation valid; rejected replacement
callbacks never become valid. Check again after any delay or yield before doing
more work. This does not interrupt work already executing. Explicit
`controls:dispatch(actionId, event)` remains independent of bindings and supplies
no execution context. Control-event subscriber arguments are unchanged.

## Control events

ModCoreControls publishes stable string identifiers. A consumer in another UE4SS Lua state
can load `mc.event_transport` from `_ModCore_Controls/Scripts` and call
`subscribe(name, callback)`. The returned function unsubscribes. Local users of
`mc.core` or `mc.topology` can call `:subscribe(name, callback)` on their
instance. Listener errors do not interrupt input delivery.

| Event | Callback arguments |
| --- | --- |
| `ControlContextAttached`, `ControlContextDetached` | `context` |
| `ControlGroupFocused`, `ControlGroupUnfocused` | `controls, group` |
| `ControlActionStarted`, `ControlActionTriggered`, `ControlActionCompleted`, `ControlActionCanceled` | `controls, group, action` |

Action phases match Unreal Enhanced Input. Quickslot IDs use
`player.quickslots`, `ability` or
`consumable`, and names such as `quickslot.ability.left`.
