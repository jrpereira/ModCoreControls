# Runtime reference

Start with the [developer guide](DEVELOPERS.md) for declaration examples.
This page describes MCC's current quickslot input adapter.

## Triggers

| Action | Tap | Hold |
| --- | --- | --- |
| Immediate | Qualifying release within the Tap threshold | Fires after the Hold threshold |
| Sustained | Toggles on/off | Active until release or cancellation |

The grouped **Swap to** key is special: Tap swaps on press. Default's
**Hold to Swap** uses press/release edges, so it does not wait for a Hold threshold.
Explicit focus keys keep their declared Tap/Hold behavior. Selected-slot gestures
retain the wheel selected at press start through their terminal phase.

## Inherited keys and overrides

`defaultControl='IA_Name'` resolves the player's keyboard keys for a native action
from the Settings key profile while the setting is unbound. Without it, unbound
means no input. MCC refreshes inherited keys after `ApplyPendingKeyboardMappings`.

| Declaration | Behavior |
| --- | --- |
| Key `override=true` with `defaultControl` | Custom key suppresses that native action; unbound leaves the action to the game |
| Key `override={action='IA_Name',value=164}` | Overrides that action while bound; `value` supplies the legacy default key |
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
requesting another rebuild from that path. Bridge resolution is retried through
lifecycle events if it was unavailable at startup.

`mc_overrides.lua` installs chord gates after replacement callbacks and contexts
are ready. Detach removes MCC gates from native trigger arrays and preserves
foreign triggers. The bounded set of named gate objects remains rooted for reuse.
`mc_key_indicators.lua` updates HUD actions and restores originals on detach,
replacement or deactivation.

Stopping unregisters named UE4SS function hooks with both callback IDs; failed
removals remain owned for retry. Notifications without removal handles remain
protected by the stopped state. Use a full game restart after Lua changes.

## Wheel focus events

A successful change emits `controls.group.focus` through `mc_events.lua`:

```lua
{group = {from = 1, to = 2}} -- abilities → consumables
```

The first transition may omit `from`. No event is sent for a failed or unchanged
selection. Default activation, hold release, cancellation and a successful reset
also emit transitions. A failed reset keeps the previous state and leaves Default
pending. Focus enables the selected wheel when MCT has moved the wheels outside
the native switcher.

MCT stores the latest transition in `params.state.controls.group` and can deliver
it to template event callbacks. Events are not logged on every swap. Use
`Events.format` for diagnostics when needed.
