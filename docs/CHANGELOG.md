# Changelog

## v1.4.0

- MCC's settings are the **Controls** tab of the ModCore Settings page, its second tab
  after Settings, instead of four pages picked from the top (Options, Visuals,
  Key & Mouse, Controller). ModCore Controls' entry in the mod list opens it. Top to
  bottom: the Quickslots template picker with the chosen template's settings right under
  it, then **Mappings**, then **Behaviours**. Apply saves into MCC's `config.ini`; saved
  bindings and settings are unchanged.
- **Mappings** holds three links, **Group Keys**, **Global Keys** and **Controller**,
  each opening the **Mappings** page on that tab; the page's title row picks the tab.
  The page has its own Apply, a key bound twice is marked across Group Keys and Global
  Keys as it is edited, and Back returns to the Controls tab with the link selected.
  The Control Map picker is gone with the Key & Mouse page.
- **Behaviours** holds two subgroups: **Quickslot Wheels** (was "Default": Allow Swap
  outside of combat, Hold to Swap, Default wheel) and **Shortcuts** (was "Key Press
  Behaviour": Instant Tap, Tap vs Hold Threshold, Show key outline).
- The Quickslots template picker heads its section; the "Quickslots Visuals" heading and
  the heading naming the template are gone.
- Tap vs Hold Threshold: Low and High may be as little as 10 ms apart (was 50 ms).
- Log levels no longer come from `log_level.txt`. With the UE4SS Lua Log Bridge
  installed, set them in the Logs section of the **Extensions** tab of the ModCore
  Settings page or under `[Levels]` in the bridge's `config.ini`; without it, WARN and
  above are logged.
- Fixes a quick press of a Tap key that does not act on press (Instant Tap off, or
  sharing its key with a Hold) showing no rim; it now stays lit until Low.
- Fixes changed keys and Tap vs Hold Threshold values not refreshing input on Apply.

## v1.3.2

- Settings and keys have clearer descriptions, and every key and the Control Map picker has one.
- Quickslots Visuals lists the Template picker under its heading, then the chosen
  template's settings under the template's own heading.
- Requires UE4SSLuaEventBridge 1.3.0 and ModCore Settings 1.9.0 or newer.
- New **Key Press Behaviour** block on the Options page:
  - **Tap vs Hold Threshold** replaces the fixed 200 ms: a window from Low to High,
    100-350 ms by default, adjustable within 100-500 ms in 10 ms steps and at least
    50 ms apart. A Hold key acts at High. A Tap sharing its key with a Hold fires on a
    release before High. Changes apply at once, without a restart.
  - **Instant Tap when no Hold for same key** (On by default): a key bound only to Tap
    fires on press. Off fires it on release or at High, whichever comes first, so a
    tap always acts.
  - **Show key outline**: None, Hold, or Tap & Hold (the default) chooses which HUD
    key hints get a rim. A Hold key's rim fills while held: from press for a lone
    Hold, from Low when a Tap shares the key. A key that acts on press flashes its
    rim for Low from the press, however long it is held; another Tap key's rim is
    full while pressed and stays lit long enough for a quick press to show. Hold
    keys keep their rim under every choice; with None it does not fill.
- A Groups key fills its rim only on the wheel that was focused when it was pressed.
- Quickslot keys set to Hold are underlined on their HUD key hint. The underline
  follows its key when ModCore Templates changes the quickslot layout.
- Quickslots 1-4 left on their default inherit the player's game key as an MCC
  binding: they act on press and their hints get MCC's glyph and rim.
- The Default wheel is Abilities out of the box (was Consumables). A saved choice is kept.
- MCC publishes `controls.slots.global`, the quickslots with a working Global key,
  so templates can leave those slots undimmed while their wheel is unfocused.
- Fixes a possible crash while the game sets up its input and HUD.

## v1.0.12

- Requires ModCore Settings 1.6.0 or later.
- A wheel key set to Hold shows its wheel while held and returns to Default on
  release, even if another wheel key is still held.
- Hold to Swap works exactly like Swap to set to Hold on the Toggle Quickslots key:
  releasing it always returns to the Default wheel.
- Controls attach as soon as the game sets up its own gameplay input, after starting
  or loading a game and after a death, seconds before the loading screen fades out.
  Loading a save no longer sometimes leaves your keys unbound until the game is
  restarted.
- A key copied from the game's controls, or a native action MCC overrides, that is
  not available yet when controls attach is tried again shortly after.
- Using a skill no longer stutters the game, and MCC's keys stay in place when a
  skill lifts the game's controls for a moment.
- Controls attach faster after a load or a death.
- After a load, the Default wheel is shown, and the other one dimmed, as soon as
  the game's HUD exists, before MCC attaches its keys, which can take a moment.
  Loading from the main menu no longer leaves both wheels bright, or the key
  labels showing the game's keys, until the loading screen has faded out.
- Swapping wheels changes the game's own active wheel, as its toggle does, so the
  quickslot keys fire the wheel shown. With a ModCore Templates quickslot template,
  the keys no longer fire consumables out of combat and abilities in combat,
  whatever the focus.

## v1.0.11

- Controls reattach on their own after a save load. Before, the game's own
  quickslot keys could stay active and the wheels stuck until the game was restarted.
- Reattaching selects the Default wheel and announces it again, so wheel focus
  and its dimming are correct after a save load.

## v1.0.10

- Requires ModCore Settings 1.5.0 or later. No change to controls or settings.

## v1.0.9

- Requires ModCore Settings 1.4.0 or later. No change to controls or settings.

## v1.0.8

- Requires UE4SSLuaEventBridge 1.2.0 or later. Requirements follow minor versions
  now, so ModCore Settings 1.3.0 or later are enough. No change to controls or settings.

## v1.0.7

- Requires ModCore Settings 1.3.1 or later. No change to controls or settings.

## v1.0.6

- Requires UE4SSLuaEventBridge 1.1.0 or later and ModCore Settings 1.3.0 or later.
  No change to controls or settings.

## v1.0.5

- Updates the shared ModCore Settings menu support. No change to controls or settings.

## v1.0.4

- Control focus events start with no group until the first group transition.
- Fewer repeated lookups for missing game actions.
- Cleanup with no change to controls or settings.

## v1.0.3

- Requires ModCore Settings 1.1.0 or later.
- Less work while playing: a control rebuild with nothing changed leaves MCC's keys
  alone, and entering or leaving combat no longer rereads the game's key settings.
  Lost keys are still restored.
- Settings retired before the first release are ignored, and `config.ini` is no
  longer rewritten at startup.
- A key that focuses group 3, which has no game target yet, is accepted only when
  declared inactive; before, it passed the declaration and failed at startup and Apply.
- While controls are not attached, retries back off to every 12 s (100 ms, 500 ms,
  3 s, 6 s, then 12 s). Controls still attach as soon as gameplay input appears.
- Inherited keys follow the same rule the key editor shows them with, so the menu
  and the bindings agree.

## v1.0.2

- Using an ability or anything else that woke MCC no longer reattached all controls.
- Fixes a crash when loading a save from a running game.
- Requires UE4SSLuaEventBridge 1.0.12 (API 6). With an older bridge,
  controls do not attach and the log says why.

## v1.0.1

- The Visuals page's "Quickslots Visuals" template picker shows at Category
  heading size, with the quickslot settings indented beneath it (requires the
  matching ModCoreSettings).
- A key and trigger bind one setting. Apply rejects the same key with the same
  trigger on two rows, with a message naming the key, its trigger and both rows, so
  it is fixed before saving; the same key with another trigger is a separate
  binding. A saved config that already has such a pair keeps the first binding at
  startup and logs a warning for the skipped one. While editing, such a pair shows
  a dim red key background, and the page picker turns red when the pair is on
  different pages.
- A UTF-8 byte order mark at the start of `config.ini` no longer hides the first
  section's saved controls; saving drops it.
- Release packages include `enabled.txt`, so the mod is enabled when installed.
- Menus that build many rows are no longer slowed down by MCC.
- Global's eight slot keys are optional.
- Controller button rows show their actions in a wider 13pt column that wraps at
  commas.
- Pickers and mirrors accept `cycle=true`: one button under the key column that
  shows the current choice and moves to the next on click, and `tab=true`. Swap back
  to default uses the cycle button.
- A key's default trigger is the first it declares. Swap to <wheel>, Activate
  Abilities and Activate Consumables declare Hold|Tap, so a newly bound key starts
  on Hold.
- The swap key set to Tap acts on press; explicit activation keys keep a real Tap.
  Group focus and swap changes apply within the same input frame, so a game slot
  action on the same key sees the new focus.
- Group Activation becomes two sections. **Alternate Activation** holds **Swap to
  <wheel>** (the former Secondary Group key, same settings) and **Swap back to
  default** (the Default wheel). **Explicit Activation** adds **Activate Abilities**
  and **Activate Consumables**, optional and unbound, which always focus their own
  wheel and never swap. The relative Primary Group key is removed.
- Hold to Swap and Swap to <wheel> describe how they interact when selected: a
  Swap key bound to the Toggle Quickslots key uses its own Tap or Hold there.
  Declared descriptions reach the menu: a setting, key or mirror `description` is
  the row's description, a map group's `description` is help text under its
  heading, and a section's description leads the help text under the first heading
  of each of its pages. A description is one line of up to 4096 characters without
  control characters.
- An inherited key that cannot be resolved, such as an unbound Toggle Quickslots
  key, skips only the bindings that use it; every other binding attaches. It is
  reported once as a warning and attaches once the player binds a key. A key the
  game refuses to map, or a binding that cannot be built, likewise skips only
  itself, with one warning until it succeeds.
- A native action MCC overrides that the game replaces during play takes the
  override again on the next sync.
- An Apply made while controls are updating is applied right after, instead of
  being dropped.
- Key & Mouse lists only sections that have maps; empty sections no longer show as
  pages, and with Actions alone there is no Section picker.
- The Quickslot Groups control map is named Groups again; saved keys are kept.
- An input callback that fails logs its binding and phase.
- The Controller page reads the local player's own input.
- Key names compare without regard to case, as the game does: a hand-edited single
  letter such as `j` reads as `J`.
- A key name the game does not know is skipped with one warning instead of being
  mapped as a dead key.
- The definition rejects bindings whose ids differ only in punctuation.
- The Controls page shows the release's version.
- Log at levels TRACE, DEBUG, INFO, WARN, ERROR and CRITICAL, writing WARN and above
  by default.
- Configuration never prevents startup: an invalid or repeated saved value falls
  back to its default, and an unusable set of saved controls starts input on the
  defaults while saving stays refused until the leftover files are reviewed.
- Each binding is one setting with one text value, `none` or `<FKey>|<trigger>`
  (`J|Hold`; number keys as digits, `1|Tap`), shown as a single keybind row with
  its own trigger control. Existing bindings return to their defaults once.
- Map declarations use typed settings: every setting has `id`, `name`, `type` and
  an optional `default`, with its type's arguments in `params` (`picker`,
  `keybind`, `mirror`). A group's settings show in declared order. Unknown fields
  are rejected.
- Keys with a `defaultControl` can declare `override=true`, suppressing that native
  action while the player binds a custom key in its place.
- Default's swap owns the player's Toggle Quickslots key and steps aside on a key a
  custom binding claims. **Allow Swap outside of combat** chooses whether the swap
  works in open world; **Hold to Swap, release to return** (on by default) swaps
  while held.
- Maps coexist: Default, Groups and Global are active together and the Control Map
  picker only navigates between their pages. The same key and trigger in two maps
  is rejected at Apply. Slot and Group keys start Unbound.
- Default is the base map, in a Module section for module-wide settings: its
  Default wheel applies under every map and is where released or re-tapped group
  keys return.
- The Controls page has Options, Visuals (ModCore Templates' quickslot selection),
  Key & Mouse and Controller (gamepad buttons with their current actions) pages.
- Inherited keys come from the game's key settings, and a native action bound to
  several keyboard keys inherits each of them.
- MCC's keys work in exploration and combat alike, and switching between them keeps
  them.
- Native quickslot key hints show MCC's bindings, refresh after Apply, and return to
  the game's own when MCC's input is removed.
- The installed mod folder is `2_ModCore_Controls`.

## 0.1.1

- Refine controls-page grouping.

## 0.1.0

- Action registration, selectable layouts, and Grouped/Flat/Advanced controls.
- Control context, group, and action-phase events.
