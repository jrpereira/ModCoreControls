# Developer guide

ModCore Controls reads menu definitions from three files:

- `Scripts/mc_sections.lua` defines the ordered section registry.
- `Scripts/mc_maps.lua` registers maps against their sections.
- `Scripts/mc_triggers.lua` converts Tap/Hold choices to Enhanced Input values.

`mc_menu.lua` validates those declarations and creates the shared menu model.
The model is independent of DMM presentation and persistence.

## Sections

The initial sections are Module, Actions, Movement, and System. Module holds
module-wide settings (the Default map); its maps feed the runtime plan with
Actions. Add declarations to
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

These registries are local to each Lua state. `ModCoreControls.addSection()` and
`addSectionMap()` reject calls after that state's definition is built. Declare
sections and maps in the source modules before gameplay or DMM loads them;
there is no runtime registration transport between those Lua states. Only Actions
maps have runtime output today; other sections can describe menu choices but
have no input adapter. `description` and `sets` remain reserved registry data.

## DMM page

ModCoreSettings is MCC's only route into DMM. At startup `main.lua` publishes
one page through the vendored `menu_contributions.lua`: id `ModCoreControls`,
`attach` set to the mod folder, `hooks` naming `Scripts/mcs_page.lua`, and the
mod folder as `configDirectory`. It publishes before input startup, so the
page survives an input failure. Descriptor files go to `cache/`.

ModCoreSettings loads `mcs_page.lua` in its menu state. Its `manifest` hook
calls `mc_dmm.manifest()`, which converts the Lua definitions into the page's
settings on every menu build. `load` and `apply` are MCC's storage (see
[Storage](#storage)). The first generated setting is the Page picker:

```ini
[Setting.MCC_Page]
Type=picker
Label=Page
PresetLabels=Options|Visuals|Key & Mouse|Controller
PresetValues=0|1|2|3
Default=0
mcNavigation=1
mcHeading=true
```

The Module section's rows use `VisibleWhen=MCC_Page` with Options. Key & Mouse
holds the `MCC_Section` picker over the other sections; their rows use
`VisibleWhen=MCC_Section`, directly or through that section's Control Map
picker. DMM visibility is transitive, so a row is shown only while every picker
above it is shown and matches. `mcNavigation=1` keeps Page, Section and Control
Map out of persistence and Apply events: a section's maps coexist, so Control
Map only picks which map's rows are shown.

Visuals and Controller use read-only rows (`mcReadOnly=1`, two equal labels that
ModCoreSettings collapses to one). `mc_gamepad.lua` reads Controller's rows when
DMM builds the page: every standard gamepad button with the actions mapped to it
in the player's applied contexts and Settings key profile. Outside gameplay one
row says the list is available in game.

Every named `map` group becomes a visible DMM category heading. Each keybind is
one `Type=keybind` row of ModCoreSettings (`Triggers`, `Optional`,
`DefaultControl`); its editor shows the key, its trigger and the default keys on
that row. There is no separate trigger row.

## Storage

The page's `load` hook opens `config.ini` through `mc_config.lua` and returns
every stored value by id, mirrors included. `apply` receives every stored value
and the edited ones, resolves mirrors, validates the combined plan with
`mc_input_plan.build`, saves through the store `load` opened, and returns the
saved values. A raised error rejects the Apply and keeps the page dirty.

Each section owns an INI section:

```ini
[ModCoreControls.module]
default.DefaultWheel=2
[ModCoreControls.actions]
global.AbilitySlot1=J|Hold
grouped.QuickSlot1=none
```

A keybind is one text value, `none` or `<FKey>|<trigger>` (`mc_menu.keybind`
gives the canonical form). Number keys are stored as digits and bound by their
FKey name (`mc_menu.binding`). On read, `default` is the declared binding and an
unreadable value falls back to it; old `.key`/`.trigger` lines are ignored.
Choices are integers. Keys include their map ID. Section and map
navigation is transient and is never saved. Files from before maps coexisted
carry `map=<ID>`: on open, MCC drops it with the entries of every map it did not
select (Default's entries stay), plus removed maps and keys, so no saved key
activates silently. Default's `default.*` lines then move from
`[ModCoreControls.actions]` to `[ModCoreControls.module]`.

Saving preserves unrelated INI content. It refuses to overwrite a file changed
since the menu opened and uses a temporary file plus rollback copy while replacing
the original.

## Input runtime

`mc_input_plan.lua` converts every Actions map and current values into
active native bindings. An Actions map needs a unique section-local `id`, a
unique numeric `value`, supported `contexts` (`exploration` or `combat`), and
groups of settings. Every declared setting has `id`, `name`, `type` and an
optional `default`; the arguments specific to its type sit in `params`, and
unknown fields in either place are rejected. Map-level settings are `picker`s
(`params={values,labels}`). A group's `settings` hold `keybind`s and `mirror`s
in display order; `mc_menu` splits them into the group's `keys`, `settings` and
ordered `items`. A `keybind` needs a unique `id` and, in `params`, a supported
`trigger` and an `action` descriptor (`ability` or `consumable` with slot 1–4,
`selected` with slot 1–4, or `focus` with group 1–2); its other params are
`optional`, `defaultControl`, `override`, `sustained`, `inactive`, `groupedBy`
and `displayAlias`. A keybind's `default` is `none` (or 0), `<FKey>` (Tap) or
`<FKey>|<trigger>`. These are static declarations, not a runtime registration
transport.

`mc_input_context.lua` owns generated Input Actions and maps their keys into the
game's applied contexts: `IMC_Base` for bindings usable in both gameplay
contexts, otherwise `IMC_OW` for `exploration` and `IMC_RTCombat` for `combat`.
Without an applied `IMC_Base`, every binding falls back to its own contexts. It never creates or applies a mapping context, and removes only its own
entries. A binding may narrow where it applies with its own `contexts`.
The host also pre-hooks `RequestRebuildControlMappings` for its owning player.
It prepares MCC mappings inline before the request executes, including forced
rebuilds. Nested requests during MCC operations are ignored; this path does not
request another rebuild after reconfiguration. Queuing on the game thread alone
does not guarantee execution after the engine's rebuild.
Default generates its own swap bindings on the inherited
`IA_Combat_ToggleQuickslots` key and overrides the native action. Hold off
generates one Pressed `flip` binding; Hold on generates `holdSwapEdge` press and
release bindings. Their `contexts` are `{'combat'}`, or both contexts when swap
outside of combat is on. `Quickslots.flip` and focus enable the focused wheel and
disable the other when the wheels are outside the native switcher. Swap bindings
carry `swap=true`; when a custom (nonzero) key resolves to one of a swap
binding's key names, the host records it in that binding's `suppressed`
(key name → claimant ID) and leaves only that key unmapped until it moves.

Optional key declarations may set `defaultControl` to a standard Enhanced Input
action ID. Their stored zero value means “inherit”; the runtime resolves the
player's keyboard keys for that action from the Settings key profile into
`keyNames`, maps the binding on each of them, and refreshes them after `ApplyPendingKeyboardMappings`. The profile holds the key
whether or not an applied context maps the action, as for the combat toggle in
open world. Without `defaultControl`, zero remains unbound.
`mc_native_callbacks.lua` owns the bridge target and its phase subscriptions.
`mc_overrides.lua` owns root-captured chord gates for native actions declared by
map- or key-level `override` metadata. A key descriptor can use
`{ action='IA_Name', value=164 }`; `value` becomes its default key.
`override=true` is valid only with `defaultControl`. It overrides that action
while the key holds a custom (nonzero) value. While the key inherits the default
control, the plan creates no binding for it: the native action keeps that key. Maps cannot use `override=true`.
A map can use `override={'IA_First','IA_Second'}`; those overrides remain active
for that map independently of individual key values.
`mc_input_host.lua` discovers the live player stack, orders binding before
attachment, replaces bindings when the component or subsystem changes, and
rejects callbacks from retired generations. `mc_quickslots.lua` is the current
Actions output adapter. `mc_key_indicators.lua` assigns the generated actions to
the native HUD widgets and restores their original actions when the gameplay
context detaches or the host is replaced or deactivated.

Stopping the host unregisters named UE4SS function hooks with both callback IDs.
Failed removals remain owned for a later stop attempt. UE4SS does not expose
removal handles for object notifications or map hooks in this API; their callbacks
remain guarded by the stopped state until UE4SS unloads the mod.

`main.lua` builds a plan on startup and subscribes to the ModCoreSettings
`settings_api` provider `ModCoreControls`. A successful DMM Apply schedules a
fresh read and runtime replacement on the game thread. Persistence success does
not by itself establish that the new plan is active; native resources may still
be pending or cleanup may need a retry.

InputTriggerTap qualifies on release within its threshold. Immediate Hold
fires after its threshold. Selected-slot gestures retain the group selected at
press start through their terminal phase. A key-level override applies while
that key is bound; Unbound may expose the native binding. Map-level overrides
do not depend on individual key values. MCC attaches only while one of the
map's game contexts is applied.
Use a full game restart after changing MCC Lua; hot reload is not a supported
recovery path for owned native hooks and provider subscriptions.

Every successful change of the active wheel emits `controls.group.focus` with the
payload `{group={from=<number|nil>,to=<number>}}`. Group 1 is abilities and group 2
is consumables. Activating the plan's Default wheel is such a change: after
settings load, MCC activates it and publishes the first transition with no `from`
(shared-variable form `<revision> - <to>`). Hold release, cancellation and the
reset to Default on retirement emit their transitions too. Failed selection and an
unchanged group emit nothing; a failed reset keeps the last published group and
leaves Default pending for the next presentation. The Default map's Default wheel
is in effect under every map. A focus action names a fixed `group`, or a `wheel`
of `'default'` or `'other'` that the plan resolves against the Default wheel, and
its key row is labelled after that wheel. A map group can list `mirror` settings
that repeat another map's choice, such as Quickslot Groups' Default Group:
`{id='DefaultGroup', name='Default Group', type='mirror', params={section='module',
map='default', setting='DefaultWheel'}}`. A mirror
is a DMM row with no config key. MCC's storage loads it from the mirrored
setting and writes a change back on Apply; changing both to different values in
one Apply is rejected. Emissions are not logged:
writing the log on every swap made swapping lag. `Events.format` still renders
the stable JSON-shaped form for diagnostics, for example
`controls.group.focus {"group":{"from":1,"to":2}}`.

`mc_events.lua` owns the category-independent event name, validation,
serialization and cross-Lua notification helpers. ModCoreTemplates consumes the
same contract and keeps the latest transition in its own runtime state.

The runtime requires UE4SSLuaEventBridge Enhanced Input API 4 or newer. Bridge
resolution is lazy so an undefined marker-based load order does not permanently
disable input; later lifecycle events retry it.

Override gates are attached only after replacement callbacks and contexts are
ready. Detach removes the MCC chord from native trigger arrays while preserving
foreign triggers; the finite named gate objects remain rooted for reuse.
