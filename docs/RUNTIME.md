# Runtime reference

Start with the [developer guide](DEVELOPERS.md) for declaration examples.
This page describes MCC's current quickslot input adapter.

## Triggers

| Action | Tap | Hold |
| --- | --- | --- |
| Immediate | Qualifying release within the Tap threshold | Fires after the Hold threshold |
| Sustained | Toggles on/off | Active until release or cancellation |

The grouped **Swap to** key is special: Tap swaps on press. Default's
**Hold to Swap** is the same binding as **Swap to** set to Hold on the inherited
Toggle Quickslots key: it does not wait for a Hold threshold.
Explicit focus keys keep their declared Tap/Hold behavior: a held focus key shows
its wheel on press and returns to Default on release. Selected-slot gestures
retain the wheel selected at press start through their terminal phase.

## Inherited keys and overrides

`defaultControl='IA_Name'` resolves the player's keyboard keys for a native action
from the Settings key profile while the setting is unbound. Without it, unbound
means no input. MCC refreshes inherited keys after `ApplyPendingKeyboardMappings`.
The keys come from ModCoreSettings' vendored `standard_keys.lua`, the rule its key
editor uses to show them, so a row shows the keys MCC binds. Of several actions with
the name, the one in the game's input folder is used; if that does not single one
out, the key stays unbound.

| Declaration | Behavior |
| --- | --- |
| Key `override=true` with `defaultControl` | Custom key suppresses that native action; unbound leaves the action to the game |
| Key `override={action='IA_Name'}` | Overrides that action while bound; declare the key separately in `default` |
| Map `override={'IA_First','IA_Second'}` | Overrides remain active independently of individual keys |

A map cannot use `override=true`. Clearing a key does not disable a map-level
override. A custom binding on Default's inherited Toggle Quickslots key suppresses
that swap key until the custom binding moves.

## Native ownership

`mc_input_plan.lua` combines Module's Default settings with every Actions map.
`mc_input_context.lua` creates Input Actions and adds MCC bindings to applied game
contexts. Bindings usable in both contexts prefer `IMC_Base`; otherwise they use
`IMC_OW` or `IMC_RTCombat`. If Base is absent, each binding falls back to its own
contexts. MCC creates no mapping context and removes only its own entries.

`mc_input_host.lua` handles player/component changes and rejects callbacks from
retired generations. It prepares mappings inside the owning player's
`RequestRebuildControlMappings` pre-hook, including forced rebuilds, without
requesting another rebuild from that path.

The game adding one of its gameplay mapping contexts (`IMC_OW`, `IMC_RTCombat` or
`IMC_Base`, through `DWSystemBlueprintFunctionLibrary:AddInputMappingContext`) is the
signal that a new player's input is set up: after starting or loading a game, and
after a death, seconds before the loading screen fades out. It re-reads the player's
keys and override actions and attaches to the current player, detaching from a
replaced one. Other contexts, such as focus mode, are ignored, and so is an add while
MCC owns the live player's current input component; the hook reads only the context
it was given and checks the owner after the call. Two other hooks also wake input:
`PlayerController:ClientRestart`, for possession, and `ApplyPendingKeyboardMappings`,
for new keys from the game's settings. MCC observes
no object construction.

Only those signals, and attaching, scan the game's objects for the player and HUD.
Every other sync, including the one inside each rebuild request, reuses the kept
player while it lives and still owns its input. When the game lifts every gameplay
context for a moment, the same player keeps MCC's input: its keys stay in the game's
contexts and apply again when they return.

A sync that cannot attach yet, or attaches with an inherited key or override action
still missing, is retried after 100 ms, 500 ms, 3 s, 6 s and 12 s; the next gameplay
context the game adds starts the schedule again. If that hook cannot be registered, the retries
continue every 12 s. Bridge resolution follows the same schedule.

`mc_overrides.lua` installs chord gates after replacement callbacks and contexts
are ready. Detach removes MCC gates from native trigger arrays and preserves
foreign triggers. The bounded set of named gate objects remains rooted for reuse.
`mc_key_indicators.lua` updates HUD actions and restores originals on detach,
replacement or deactivation.

Stopping unregisters named UE4SS function hooks with both callback IDs; failed
removals remain owned for retry. Use a full game restart after Lua changes.

## Wheel focus events

A successful change emits `controls.group.focus` through `mc_events.lua`:

```lua
{group = {from = 1, to = 2}} -- abilities → consumables
```

The first transition may omit `from`. No event is sent for a failed or unchanged
selection. Default activation, hold release, cancellation and a successful reset
also emit transitions. A failed reset keeps the previous state and leaves Default
pending. Focus calls the HUD's own `Set AA Quickslots Showed`, as the game's toggle
does: that sets the game's active wheel, the one the slot keys fire, wherever the
wheels sit, and selects the matching page of the HUD's `QuickslotsSwitcher` when
the wheels are in it. MCC never reads or changes the wheels; their display is
ModCore Templates' job.

A sync presents the wheel as soon as it has found the player and its HUD, before
it attaches input, so Default shows without waiting for the attach. After a load
the player is often found before the game creates its HUD; while the wheel cannot
be presented, only the presentation is tried again after 100 ms, 250 ms, 500 ms,
1 s and 2 s, stopping once the wheel is shown.

MCT stores the latest transition in `params.state.controls.group` and can deliver
it to template event callbacks. Events are not logged on every swap. Use
`Events.format` for diagnostics when needed.
