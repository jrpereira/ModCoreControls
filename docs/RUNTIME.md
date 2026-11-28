# Runtime reference

Start with the [developer guide](DEVELOPERS.md) for declaration examples.
This page describes how MCC's quickslot keys behave in game.

## Triggers

| Action | Tap | Hold |
| --- | --- | --- |
| Immediate | Fires on press. With **Instant Tap when no Hold for same key** off: on release or at High, whichever comes first. When the same key is also bound as Hold: on a release before High | Fires at High |
| Sustained | Toggles on/off | Active until release or cancellation |

These settings sit under **Behaviours → Shortcuts** on the Controls tab. The window is
**Tap vs Hold Threshold**, a range from Low to High: 100-350 ms by default, 100 to 500 ms
in 10 ms steps, at least 10 ms apart. It only matters for Hold keys, for a Tap that
shares its key with a Hold, and for the key outline. A changed threshold applies on
Apply, without a restart.

## Key outline

While a key set to Hold is held, its HUD key hint's rim fills from press to High,
where the key acts; when a Tap shares its key, it stays empty until Low and fills
from there, as the game's own hold prompts do. It empties when the action fires or
the key is released. A key set to Tap shows the rim too: one that acts on press
flashes it for Low from the press, however long the key is held; any other Tap key
is lit from press until it fires. A Tap sharing its key with a Hold fires on a
release before High, or goes dark when the Hold fires at High, and from Low the
Hold's rim fills beside it. A press shorter than Low stays lit until Low from the
press, so even a quick press shows.

**Show key outline** chooses which keys do this: None, Hold, or Tap & Hold (the
default). A Hold key always keeps its rim; with None it just does not fill. A Group
key fills the hint of the wheel focused when it was pressed.

Quickslot keys set to Hold are also underlined on their HUD key hint. The underline
moves, scales, hides and fades with its key, including when ModCore Templates
changes the quickslot layout.

A Group Keys slot key left on its default control (Quickslot 1-4) uses the player's
game key for that slot, acts on press as the game's action does, and gets MCC's key
hint and rim. A key the player binds elsewhere to the same key takes it over.

## Wheels

Quickslot Wheels' **Hold to Swap** is the same binding as **Swap to** set to Hold on
the inherited Toggle Quickslots key: it does not wait for a Hold threshold. Explicit
focus keys keep their declared Tap/Hold behavior: a held focus key shows its wheel on
press and returns to Default on release. Selected-slot gestures keep the wheel
selected when the press started until they end.

Swapping wheels changes the game's own active wheel, as its toggle does, so the slot
keys fire the wheel that is shown.

## Inherited keys and overrides

`defaultControl='IA_Name'` makes an unbound setting use the player's keyboard keys for
that native action, as set in the game's controls; when the player changes them, MCC
follows. Without it, unbound means no input. A native action the player left without a
keyboard key inherits none. If several native actions share the name and the game's
own one cannot be told apart, the key stays unbound and the log says so.

| Declaration | Behavior |
| --- | --- |
| Key `override=true` with `defaultControl` | Custom key suppresses that native action; unbound leaves the action to the game, except a slot (`selected`) key, which inherits the player's key and still suppresses it |
| Key `override='IA_Name'` | Overrides that action while bound; declare the key separately in `default` |
| Map `override={'IA_First','IA_Second'}` | Overrides remain active independently of individual keys |

A map cannot use `override=true`. Clearing a key does not disable a map-level
override. A custom binding on Default's inherited Toggle Quickslots key suppresses
that swap key until the custom binding moves. Removing MCC's bindings restores the
game's own controls and key hints.

## When controls attach

Controls attach when the game sets up the player's input: after starting or loading
a game and after a death, seconds before the loading screen fades out. An inherited
key or overridden action not available yet is tried again shortly after. After a load
the Default wheel is shown as soon as the HUD exists, even before the keys attach.
A load that keeps the player's input but gives it a new HUD, as after a fast travel,
keeps the keys attached; the new HUD shows Default and MCC's key hints once it is built.
Use a full game restart after changing Lua files.

## Wheel focus events

A successful wheel change emits `controls.group.focus`:

```lua
{group = {from = 1, to = 2}} -- abilities → consumables
```

The first transition may omit `from`. No event is sent for a failed or unchanged
selection. Default activation, hold release, cancellation and a successful reset
also emit transitions. A failed reset keeps the previous state and leaves Default
pending. MCC never moves or shows the wheels; their display is ModCore Templates' job.

ModCore Templates passes the latest transition to template event callbacks as
`params.state.controls.group`.

## Global slot events

`controls.slots.global` reports which quickslots have a working Global key: a key on
the Global map (`AbilitySlot1-4`, `ConsumableSlot1-4`) that is bound and not skipped
as a duplicate. Those keys fire whichever wheel has focus.

```lua
{global = {[1] = {true, false, false, false},  -- wheel 1, abilities
           [2] = {false, false, false, false}}} -- wheel 2, consumables
```

Slots run Left, Top, Right, Bottom. MCC sends the event each time controls attach
(startup, Apply, save load), even when the set is unchanged.
