# Runtime reference

Start with the [developer guide](DEVELOPERS.md) for declaration examples.
This page describes MCC's current quickslot input adapter.

## Triggers

| Action | Tap | Hold |
| --- | --- | --- |
| Immediate | Fires on press. With **Instant Tap when no Hold for same key** off: on release or at the high mark, whichever comes first. When the same key is also bound as Hold: on a release before the high mark | Fires at the high mark |
| Sustained | Toggles on/off | Active until release or cancellation |

While a key set to Hold is held, its HUD key indicator's rim fills from press to the
high mark, where the key acts; when a Tap shares its key, it stays empty until the low
mark and fills from there. This follows the game's own hold prompts (`OnActionProgress` on the indicator, from the action's `Ongoing` events); it
empties when the action fires or the key is released. A key set to Tap shows the rim
too (`SetHoldDisplayOverride`): full while the key is down, and at least until the low
mark after a press so a quick one still shows. A Tap sharing its key with a Hold is lit
from press until it fires on release, or until the Hold fires at the high mark; from the
low mark the Hold's rim fills beside it. A press shorter than low never shows the Hold
filling. These extra phases only drive the rim; they are never delivered as input.
The Options page's **Show key outline** chooses which keys do this: None, Hold, or
Tap & Hold (the default). A Hold key always keeps its rim; with None it just does not
fill. A Groups key fills the hint of the wheel focused when it was pressed.

A Groups slot key left on its default control (Quickslot 1-4) is an MCC binding too:
it inherits the player's key for the game's `IA_Quickslot_<position>`, acts on press as
the game's action does, and suppresses that action. Its hint, glyph and rim are MCC's
like any other key. A player key bound elsewhere on the same key takes it over.

A player's input keeps its own copy of each action's triggers, made when it first
uses the action. When MCC rebuilds triggers (a new threshold, or Tap changed to
Hold), it removes the player's instance of each rebuilt action from
`EnhancedPlayerInput.ActionInstanceData`, so the change applies at once.

These settings sit under **Key Press Behaviour** on the Options page. The window is
**Tap vs Hold Threshold**, a low-high range: 100-350 ms by
default, 100 to 500 ms in 10 ms steps, at least 50 ms apart. It only matters for Hold
keys, for a Tap that shares its key with a Hold, and for the rim. A changed high mark
rebuilds the triggers on Apply.

Default's
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

## Global slot events

`controls.slots.global` reports which quickslots have a working Global key: a key
on the actions section's Global map (`AbilitySlot1-4`, `ConsumableSlot1-4`) that is
in the active plan, so bound and not skipped as a duplicate. Those keys fire
whichever wheel has focus.

```lua
{global = {[1] = {true, false, false, false},  -- wheel 1, abilities
           [2] = {false, false, false, false}}} -- wheel 2, consumables
```

Slots run Left, Top, Right, Bottom, as in `mc_maps.lua`. The shared value is
`'<revision> <8 bits>'`, wheel 1 first. MCC publishes it on every attach (startup,
Apply, save load), so each new player hears it even when the set is unchanged, and
publishes all `false` when controls are disabled.

A sync presents the wheel as soon as it has found the player and its HUD, before
it attaches input, so Default shows without waiting for the attach. After a load
the player is often found before the game creates its HUD; while the wheel cannot
be presented, only the presentation is tried again after 100 ms, 250 ms, 500 ms,
1 s and 2 s, stopping once the wheel is shown.

MCT stores the latest transition in `params.state.controls.group` and can deliver
it to template event callbacks. Events are not logged on every swap. Use
`Events.format` for diagnostics when needed.

## Hold marks

A quickslot key indicator whose key is set to Hold gets a black underline
(`mc_hold_marks.lua`). The indicator is a leaf widget, so the mark is a sibling in
the key's overlay: an 85x85 `SizeBox` named `MCC_HoldMark_<wheel>_<position>`
holding a black bar, 51 wide, 11 thick, centred, with its bottom edge 15 above the box's
bottom (layout units). The box copies its key's slot padding and alignment, render
transform and pivot, visibility and render opacity, so it moves, scales, hides and
fades with the key under any layout.

Placement is copied on every indicator refresh (attach, Apply, a new HUD) and on
each `templates.layout.changed` event for `player.quickslots`, which ModCore
Templates publishes once per layout pass. Only changed placements are written.
Marks are removed when their key stops being Hold, when controls are disabled and
on stop; marks left by an earlier Lua state are found by name and reused or removed.

