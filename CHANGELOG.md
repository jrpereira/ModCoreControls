# Changelog

## Unreleased

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
