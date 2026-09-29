# Developer guide

ModCore Controls reads menu definitions from three files:

- `Scripts/mc_sections.lua` defines the ordered section registry.
- `Scripts/mc_maps.lua` registers maps against their sections.
- `Scripts/mc_triggers.lua` converts Tap/Hold choices to Enhanced Input values.

`mc_menu.lua` validates those declarations and creates the shared menu model.
The model is independent of DMM presentation and persistence.

## Sections

The initial sections are Actions, Movement, and System. Add declarations to
the source modules before DMM or gameplay loads them. For example:

```lua
-- In mc_sections.lua:
M.addSection('flight', 'Flying controls')
-- In mc_maps.lua:
M.addSectionMap('flight', {
    id = 'direct',
    name = 'Direct',
    value = 0,
    map = {},
})
```

Each section starts as `{ description = "", sets = {} }`. `mc_maps.lua` returns
a registry with `maps`, per-section `order`, and `addSectionMap(section, map)`.
Each map supplies a stable `id`; the registry records which section owns it.
Sections without maps remain visible in the
MCC navigation and have no controls on the right.

These registries are local to each Lua state. Runtime calls to the exposed
`ModCoreControls.addSection()` or `addSectionMap()` do not rebuild gameplay's
startup definition or transport a registration to DMM. Only selected Actions
maps have runtime output today; other sections can describe menu choices but
have no input adapter. `description` and `sets` remain reserved registry data.

## DMM page

`mod_settings.ini` contains only the `[Mod]` identity DMM needs for discovery.
When DMM builds Controls, `dmm_extension.lua` asks `mc_dmm.lua` to convert the
Lua definitions into DMM choices. The first generated setting is the Section
picker:

```ini
[Setting.MCC_Section]
Type=picker
Label=Section
PresetLabels=Actions|Movement|System
PresetValues=0|1|2
Default=0
mcNavigation=1
mcLevel=1
```

Every section row uses `VisibleWhen=MCC_Section` and its corresponding numeric
value, directly or through that section's Control Map picker. DMM therefore
shows only the selected section. `mcNavigation=1` keeps the Section choice out
of persistence and Apply events. `mcLevel=1` places it first in DMM's Controls
header area.

Every named `map` group becomes a visible DMM category heading. Its key and
trigger rows share that category, so DMM renders them together beneath the Lua
group name.

`Scripts/dmm_extension.lua` supplies both the generated choices and MCC's
storage adapter through DMM's extension entrypoint.

## Storage

DMM saves through `mc_config.lua`. Each section owns an INI section:

```ini
[ModCoreControls.actions]
map=flat
flat.SlotAction1.key=74
flat.SlotAction1.trigger=0
```

Map IDs are strings. Keys and triggers are integers. Choice keys include their
map ID so switching maps does not discard the other map's values. Active section
navigation is transient and is never saved.

Saving preserves unrelated INI content. It refuses to overwrite a file changed
since the menu opened and uses a temporary file plus rollback copy while replacing
the original.

## Input runtime

`mc_input_plan.lua` converts the selected Actions map and current values into
active native bindings. An Actions map needs a unique section-local `id`, a
unique numeric `value`, supported `contexts` (`exploration` or `combat`), and
groups of keys. A runtime key needs a unique `id`, a supported trigger and
an `action` descriptor (`ability` or `consumable` with slot 1–4, `selected`
with slot 1–4, or `focus` with group 1–2). Use a supported virtual-key default;
zero means Unbound. These are static declarations, not a runtime registration
transport.

`mc_input_context.lua` owns generated Input Actions and mapping contexts.
`mc_native_callbacks.lua` owns the bridge target and its phase subscriptions.
`mc_overrides.lua` owns root-captured chord gates for native actions declared by
map- or key-level `override` metadata. A key descriptor can use
`{ action='IA_Name', value=164 }`; `value` becomes its default key.
A map can use `override={'IA_First','IA_Second'}`; those overrides remain active
for the selected map independently of individual key values.
`mc_input_host.lua` discovers the live player stack, orders binding before
attachment, replaces bindings when the component or subsystem changes, and
rejects callbacks from retired generations. `mc_quickslots.lua` is the current
Actions output adapter. `mc_key_indicators.lua` assigns the generated actions to
the native HUD widgets and restores their original actions when the gameplay
context detaches or the host is replaced or deactivated.

`main.lua` builds a plan on startup and subscribes to the ModCoreSettings
`settings_api` provider `ModCoreControls`. A successful DMM Apply schedules a
fresh read and runtime replacement on the game thread. Persistence success does
not by itself establish that the new plan is active; native resources may still
be pending or cleanup may need a retry.

InputTriggerTap qualifies on release within its threshold. Immediate Hold
fires after its threshold. Selected-slot gestures retain the group selected at
press start through their terminal phase. A key-level override applies while
that key is bound; Unbound may expose the native binding. Map-level overrides
do not depend on individual key values. MCC retains its initial exploration
fallback only before a native context has been observed for the current stack.
Use a full game restart after changing MCC Lua; hot reload is not a supported
recovery path for owned native hooks and provider subscriptions.

The runtime requires UE4SSLuaEventBridge Enhanced Input API 4 or newer. Bridge
resolution is lazy so an undefined marker-based load order does not permanently
disable input; later lifecycle events retry it.

Override gates are attached only after replacement callbacks and contexts are
ready. Detach removes the MCC chord from native trigger arrays while preserving
foreign triggers; the finite named gate objects remain rooted for reuse.
