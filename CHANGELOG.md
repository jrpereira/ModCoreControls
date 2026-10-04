# Changelog

## Unreleased

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
- Rename the installed mod folder to `_ModCore_2_Controls` and resolve
  ModCoreSettings from `_ModCore_1_Settings`.
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
  controller, pawn, mapping-context, object-creation, and map-load lifecycle events.
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
