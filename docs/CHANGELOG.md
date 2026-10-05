# Changelog

## v1.0.1

- Release packages include `enabled.txt`, so the mod is enabled when installed.
- MCC no longer hooks `PanelWidget:AddChild`, which ran Lua for every widget the
  game added, slowing menus that build many rows. Quickslot key indicators are
  updated at the end of each sync, and on the next game-thread turn after a
  control mapping rebuild or the construction of a quickslot Bindings widget.
- Global's eight slot keys are optional.
- Controller button rows show their actions in a wider 13pt column that wraps at
  commas.
- Pickers and mirrors accept `cycle=true`: one button under the key column that
  shows the current choice and moves to the next on click. Swap back to default
  uses it instead of tabs.
- A key's default trigger is the first it declares. Swap to <wheel>, Activate
  Abilities and Activate Consumables declare Hold|Tap, so a newly bound key starts
  on Hold.
- The swap key set to Tap acts on press (a Pressed trigger) instead of on release;
  explicit activation keys keep a real Tap. Swap back to default shows its wheels
  as tabs; map pickers and mirrors accept `tab=true`.
  Group focus and swap changes apply within the input frame on the game thread
  instead of on the next queued update, so a native slot action on the same key
  can see the new focus.
- Group Activation becomes two sections. **Alternate Activation** holds **Swap to
  <wheel>** (the former Secondary Group key, same config ID and settings) and
  **Swap back to default** (the Default wheel). **Explicit Activation** adds
  **Activate Abilities** and **Activate Consumables**, optional and unbound, which
  always focus their own wheel and never swap. The relative Primary Group key is
  removed; its saved `grouped.GroupFocus1` line is ignored.
- Hold to Swap and Swap to <wheel> describe how they interact when selected: a
  Swap key bound to the Toggle Quickslots key uses its own Tap or Hold there.
  Declared descriptions pass through to DMM: a setting, key or mirror
  `description` is the row's description, a map group's `description` is help
  text under its heading, and a section's description (`addSection`) leads the
  help text under the first heading of each of its pages. A description is one
  line of up to 4096 characters without control characters.
- An inherited key that cannot be resolved, such as an unbound Toggle Quickslots
  key, skips only the bindings that use it; every other binding attaches. It is
  reported once as a warning and attaches once the player binds a key.
- Log at levels TRACE, DEBUG, INFO, WARN, ERROR and CRITICAL, writing WARN and above
  by default; `log_level.txt` in the mod folder sets the level. Key-profile
  lookups, pending syncs and mappings no longer reach the log by default.
- Configuration never prevents startup: an invalid or repeated saved value falls
  back to its default, an unusable set of saved controls starts input on the
  defaults, and an unresolved config transaction starts on the defaults while
  saving stays refused until the leftover files are reviewed.
- Stop registering LoadMap hooks; map changes are picked up through the
  controller, pawn, mapping-context and object-creation events.
- Move the README and changelog into `docs/`. Release packages are built from
  `release-manifest.json` and publish every document from `docs/` at the mod
  root. `mod.json` declares UE4SSLuaEventBridge and ModCoreSettings. GitHub
  Actions build, test and publish the release archive and its checksum from a
  `release/vX.Y.Z` branch.

- Each binding is one setting with one text value, `none` or `<FKey>|<trigger>`
  (`J|Hold`; number keys as digits, `1|Tap`), shown as a single ModCoreSettings
  keybind row with its own trigger control. The separate trigger rows and their
  `Pair=` link are gone. Old `.key`/`.trigger` config lines are ignored, so
  existing bindings return to their defaults once. Override descriptors name
  their key instead of a key code; the key-code table is removed.
- Map declarations use typed settings: every setting has `id`, `name`, `type`
  and an optional `default`, with its type's arguments in `params` (`picker`,
  `keybind`, `mirror`). A group's `keys` and `settings` merge into one
  `settings` list shown in declared order. Unknown fields are rejected, and map
  settings can no longer be keys.
- Keys with a `defaultControl` can declare `override=true`, suppressing that
  native action while the player binds a custom key in its place. On the
  default key such a key adds no MCC binding, so Quickslot 1–4 no longer bind
  beside the native slot actions.
- Group 2 declares `override=true`, so by default it no longer shares the Toggle
  Quickslots key with Default's swap. Tap swap now sticks with Hold to Swap off,
  and Swap outside of combat off is respected.
- Default's swap steps aside while a player key is bound on its inherited key.
- Inherited keys come only from the Settings key profile; MCC no longer queries
  the keys mapped in the applied contexts first.
- An inherited key bound to several keyboard keys in the profile is attached on
  each of them, where it previously failed the sync. The swap steps aside only
  on the key a custom binding claims.
- Apply writes key values as integers (`164`, not `164.0`).
- The Controls page is published through ModCoreSettings page hooks: MCC no
  longer installs a DMM extension or ships `mod_settings.ini`. Requires
  ModCoreSettings with page hooks (descriptor contract 3).
- Enable Hold to Swap by default; saved choices remain in effect.
- Maps coexist: Default, Grouped and Global are active together and Control Map
  only navigates between their pages; it is no longer saved. The same key and
  trigger in two maps is rejected at Apply. Slot and Group keys start Unbound,
  and Grouped's Group 2 no longer inherits the Toggle Quickslots key, which
  Default's swap owns. Removed the Advanced map and Global's Show Controls key.
  On first open, saved `map=` and the entries of unselected and removed maps are
  dropped.
- Rename Grouped to Quickslot Groups (config ID `grouped` unchanged). Its
  sections are Active Group (shared slot keys) and Group Activation: Default
  Group, a mirror of Default's Default wheel, then Secondary and Primary Group
  keys labelled after the wheel they show. Primary is optional and Unbound.
- Move Default to a new Module section for module-wide settings; Actions keeps
  Quickslot Groups and Global. Saved `default.*` lines move from
  `[ModCoreControls.actions]` to `[ModCoreControls.module]` on first open.
- Replace the Section picker with a Page picker: Options (Module settings),
  Visuals (placeholder for ModCore Templates' quickslot selection), Key & Mouse
  (Section picker and controls) and Controller (gamepad buttons with their
  current actions, read when the menu builds; work in progress).
- Activate the Default wheel as an action: MCC publishes `controls.group.focus`
  after settings load (first transition has no `from`, encoded `-`) and when
  retirement resets to Default. Removed assumed starting groups.
- Default is the base map: its Default wheel applies under every map and is
  where released or re-tapped group keys return. Grouped's sections are now
  Group 1 (Default wheel: Group key and slots) and Group 2 (other wheel), titled
  after the wheel they show. Saved Group keys keep their config IDs but now
  follow the Default wheel instead of a fixed wheel.
- Resolve inherited keys from the Settings key profile when no applied context
  maps the action, so Grouped, Global, and Advanced attach in open world.
- Create no mapping contexts. A map's `contexts` say where its keys can be
  used; MCC maps them into the game's own contexts while those are applied:
  `IMC_Base` for keys usable everywhere, so they survive combat transitions,
  and `IMC_OW` or `IMC_RTCombat` for keys limited to one, removes only its own entries, and waits while no game
  context is applied. MCC's actions now live in the transient package.
- Default owns the wheel swap on the player's Toggle Quickslots key and
  suppresses the native toggle. **Allow Swap outside of combat** chooses whether
  the swap works in open world; **Hold to Swap, release to return** makes it
  press and release edges. MCC no longer rewrites the native action's triggers
  or copies its key into `IMC_OW`.
- Route native slot keys to the focused wheel by enabling it and disabling the
  other when a layout moves the wheels out of the native switcher.
- Rename the Flat control map to Global. Saved `map=flat` and `flat.*` keys
  migrate to `global` the first time MCC opens `config.ini`.
- Unregister lifecycle function hooks with their names and both UE4SS IDs;
  report and retain failed removals for retry.
- Reject late section and map registration after a definition is built, and
  clean up the input host if startup fails before publishing the facade.
- Rename the installed mod folder to `2_ModCore_Controls` and resolve
  ModCoreSettings from `1_ModCore_Settings`.
- Add coupled mapping-hook lifecycle regressions and deterministic offline work
  counts for the Audit 6 hardening pass. Live native timing remains unverified.
- Clarify static declaration scope, Actions-only runtime behavior, Tap release
  timing, Unbound/native override behavior, initial exploration fallback, and
  the difference between saved choices and active input.
- Return a section-scoped map registry from `mc_maps.lua` and expose
  `addSectionMap(section, map)` beside section registration.
- Update native quickslot key indicators from MCC's generated actions, refresh
  them after Apply, and restore the original actions on gameplay-context detach
  or host retirement.
- Apply map- and key-level native action overrides through reusable root-captured
  chord gates, and remove MCC-owned gates on detach.
- Define extensible input sections, maps, key choices, and trigger choices in Lua.
- Present the definitions through DMM using a transient Section navigation picker.
- Keep `mod_settings.ini` to discovery metadata and generate DMM choices from
  the Lua definitions at runtime.
- Convert the selected Actions map into generated Enhanced Input actions and
  gameplay mapping contexts.
- Bind native input phases through UE4SSLuaEventBridge and retire callbacks when
  their input generation is replaced.
- Refresh live input after ModCoreSettings Apply and retry attachment across
  controller, pawn, mapping-context, and object-creation lifecycle events.
- Route Grouped and Flat callbacks to the native ability and consumable wheels.
- Save choices to sectioned `config.ini` data such as
  `[ModCoreControls.actions]` and `map=flat`.
- Remove the previous general layout API and compatibility surface from this
  rewrite; the new runtime consumes the section/map model directly.

## 0.1.1

- Refine controls-page grouping and metadata.
- Consolidate integration documentation and add project metadata.

- Keep UE4SSLuaEventBridge as a separate native dependency.
- Add rooted, reusable native-action gates and offline ownership tests.

## 0.1.0

The source declares version 0.1.0. This entry describes the source baseline;
it does not assert a published release or live-game acceptance.

- Provide action registration, selectable layouts, and Grouped/Flat/Advanced controls.
- Publish control context, group, and action-phase events.
- Reject queued callbacks from successfully retired binding generations.
