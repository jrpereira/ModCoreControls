# Developer guide

MCC builds a menu model from Lua declarations, then turns the saved choices into
input bindings. A **section** groups maps; a **map** groups settings and bindings.
Only Actions maps produce quickslot input. Module's Default map supplies shared
wheel settings; adding a section does not add a gameplay adapter.

## Add a control map

Edit `Scripts/mc_maps.lua` before its final `return M`. This complete declaration
adds one optional binding to ability slot 1:

```lua
M.addSectionMap('actions', {
    id = 'demo',
    name = 'Demo',
    value = 3, -- 1 and 2 are already used by Actions maps
    contexts = {'exploration', 'combat'},
    map = {
        {name = 'Demo actions', settings = {
            {id = 'Ability1', name = 'Ability 1', type = 'keybind',
                description = 'Activate ability slot 1.',
                default = 'none',
                params = {
                    trigger = 'Tap|Hold',
                    action = {type = 'ability', slot = 1},
                    optional = true,
                }},
        }},
    },
})
```

Restart, open **Controls → Key & Mouse → Actions → Demo**, bind an unused key,
and Apply. The saved key is `demo.Ability1` in `[ModCoreControls.actions]`.
Keep map IDs, setting IDs and map values stable after users save settings.

The registry is sealed when that Lua state builds its definition. Gameplay and
the menu use separate Lua states, so a late `addSectionMap()` cannot update both.

## Declaration reference

| Location | Required fields | Optional fields |
| --- | --- | --- |
| Map | `id`, `name`, unique section-local numeric `value`, `contexts`, `map` | `settings`, `override`, wheel-swap metadata used by Default |
| Group inside `map` | `name`, `settings` | `description` |
| Setting | `id`, `name`, `type` | `default`, `description`, `params` |

Type-specific options belong inside `params`. Unknown setting and parameter
fields are rejected. Descriptions must be one line, at most 4096 bytes.

| Type | Placement | `params` |
| --- | --- | --- |
| `picker` | Map's `settings` | `values`, `labels`; optional `tab` or `cycle` |
| `keybind` | Group's `settings` | `trigger`, `action`; optional options below |
| `mirror` | Group's `settings` | `section`, `map`, `setting`; optional `tab` or `cycle` |

Keybind action shapes are `{type='ability',slot=1}`, `{type='consumable',slot=1}`,
`{type='selected',slot=1}` (slots 1–4), and `{type='focus',group=1}` (1 abilities,
2 consumables). Focus can instead use `wheel='default'` or `wheel='other'`.
Supported contexts are `exploration` and `combat`.

Keybind options include `optional`, `defaultControl`, `override`, `sustained`,
`inactive`, `groupedBy` and `displayAlias`. Start with the options in the example;
use the [runtime reference](RUNTIME.md) before adding inheritance or overrides.

A mirror repeats another picker without owning a config key:

```lua
{id='DefaultGroup', name='Default wheel', type='mirror',
    params={section='module', map='default', setting='DefaultWheel'}}
```

Editing the mirror updates its source on Apply. Conflicting edits to both rows
reject the Apply.

## Values and persistence

A binding stores `none` or `<FKey>|<trigger>`, such as `J|Hold` or `1|Tap`.
A bare default key uses the first declared trigger. `none` and numeric `0` in a
declaration mean unbound; picker choices are integers. Legacy numeric key codes
are not the current keybind format.

`mc_config.lua` preserves unrelated INI content and refuses to overwrite a file
changed since the menu opened. Unreadable saved bindings fall back to their
current declarations. Old `.key` and `.trigger` assignments are ignored.

## How the menu reaches gameplay

1. `main.lua` publishes the `ModCoreControls` page through MCS's
   `menu_contributions.lua`, before input startup.
2. MCS loads `mcs_page.lua` in the menu state. `mc_dmm.lua` generates the manifest
   and supplies `load`/`apply` hooks for MCC's storage.
3. Apply resolves mirrors, validates all maps together, and saves `config.ini`.
4. MCC receives the Apply notification, rereads its config on the game thread,
   and replaces the runtime plan when native resources are ready.

Page, Section and Control Map are navigation only. Key & Mouse lists only sections
that have maps; the Section picker appears once two of them do. Visuals declares the
`controls:visuals` slot for MCT; the placeholder remains if no valid rows arrive.
MCC installs no DMM extension or `mod_settings.ini`.

## Check your change

Run the [offline tests](BUILD.md), then check key capture, Apply, reopening the
menu, and input in exploration and combat. Verify Tap/Hold behavior and that
clearing your binding restores the intended native control.
