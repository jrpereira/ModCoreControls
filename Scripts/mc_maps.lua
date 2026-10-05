-- Section-scoped map declarations. These describe choices, not live bindings.
local M = { maps = {}, order = {}, sealed = false }

function M.addSectionMap(section, map)
    assert(not M.sealed, 'map registration closed after definition')
    assert(type(section) == 'string' and section:match('%S'),
        'section must be a non-empty string')
    assert(type(map) == 'table', 'map must be a table')
    assert(type(map.id) == 'string' and map.id:match('%S'),
        'map id must be a non-empty string')
    local sectionMaps = M.maps[section]
    if not sectionMaps then
        sectionMaps = {}
        M.maps[section] = sectionMaps
        M.order[section] = {}
    end
    assert(sectionMaps[map.id] == nil,
        'map already exists in section ' .. section .. ': ' .. map.id)
    sectionMaps[map.id] = map
    M.order[section][#M.order[section] + 1] = map.id
    return map
end

function M.seal() M.sealed=true end

-- Every setting has an id, a name and a type; what is specific to its type sits in
-- params. Map settings are pickers. A group lists its keybinds and mirrors in the
-- order the page shows them.
M.addSectionMap('module', {
        id='default',
        name='Default',
        value=0,
        contexts={'exploration','combat'},
        settings={
            {id='SwapOutsideCombat',name='Allow Swap outside of combat',type='picker',default=1,
                params={values={0,1},labels={'Off','On'}}},
            {id='HoldSwap',name='Hold to Swap, release to return',type='picker',default=1,
                description='Applies to the Toggle Quickslots key. If you bind Swap to that same key'
                    ..' in Quickslot Groups, the Swap key\'s own Tap or Hold is used instead.',
                params={values={0,1},labels={'Off','On'}}},
            {id='DefaultWheel',name='Default wheel',type='picker',default=2,
                params={values={1,2},labels={'Abilities','Consumables'}}},
        },
        holdSwap={enabled='HoldSwap', defaultWheel='DefaultWheel', outsideCombat='SwapOutsideCombat',
            action='IA_Combat_ToggleQuickslots'},
        map={},
    })


local arrows = { 'Left', 'Top', 'Right', 'Bottom' }

local grouped = {}
for slot = 1, 4 do
    grouped[slot] = {
        id = 'QuickSlot' .. slot,
        name = 'Quickslot ' .. slot,
        type = 'keybind',
        params = {
            trigger = 'Tap|Hold',
            action = { type = 'selected', slot = slot },
            defaultControl = 'IA_Quickslot_' .. arrows[slot],
            override = true,
            optional = true,
        },
    }
end

M.addSectionMap('actions', {
        id = 'grouped',
        name = 'Quickslot Groups',
        value = 1,
        contexts= {'exploration', 'combat'},
        -- The grouped slot keys fire the focused wheel. Alternate Activation swaps
        -- between the Default wheel, mirrored here from Default, and the other one;
        -- Explicit Activation focuses a fixed wheel and never swaps.
        map = {
            { name = 'Active Group', settings = grouped },
            {
                name = 'Alternate Activation',
                settings = {
                    -- {wheel} is the name of the wheel the key shows.
                    { id = 'GroupFocus2', name = 'Swap to {wheel}', type = 'keybind', default = 0,
                        description = 'Tap swaps, and tapping again swaps back. Hold shows the wheel until'
                            .. ' release. Unbound, it uses the Toggle Quickslots key and Hold to Swap.',
                        params = {
                            trigger = 'Hold|Tap', sustained = true,
                            action = { type = 'focus', wheel = 'other' },
                            optional = true,
                            defaultControl = 'IA_Combat_ToggleQuickslots',
                            override = true,
                        },
                    },
                    { id = 'DefaultGroup', name = 'Swap back to default', type = 'mirror',
                        params = { section = 'module', map = 'default', setting = 'DefaultWheel', cycle = true } },
                },
            },
            {
                name = 'Explicit Activation',
                settings = {
                    { id = 'ActivateAbilities', name = 'Activate Abilities', type = 'keybind', default = 0,
                        params = {
                            trigger = 'Hold|Tap', sustained = true,
                            action = { type = 'focus', group = 1 },
                            optional = true,
                        },
                    },
                    { id = 'ActivateConsumables', name = 'Activate Consumables', type = 'keybind', default = 0,
                        params = {
                            trigger = 'Hold|Tap', sustained = true,
                            action = { type = 'focus', group = 2 },
                            optional = true,
                        },
                    },
                },
            },
        },
    })


-- Initial actions-section declarations.
local abilities = {}
local consumables = {}

for slot = 1, 4 do
    abilities[slot] = {
        id = 'AbilitySlot' .. slot,
        name = 'Ability Slot ' .. slot,
        type = 'keybind',
        default = 0,
        params = { trigger = 'Tap|Hold', action = { type = 'ability', slot = slot }, optional = true },
    }
    consumables[slot] = {
        id = 'ConsumableSlot' .. slot,
        name = 'Consumable Slot ' .. slot,
        type = 'keybind',
        default = 0,
        params = { trigger = 'Tap|Hold', action = { type = 'consumable', slot = slot }, optional = true },
    }
end

M.addSectionMap('actions', {
        id = 'global',
        name = 'Global',
        value = 2,
        contexts= {'exploration', 'combat'},
        map = {
            { name = 'Abilities', settings = abilities },
            { name = 'Consumables', settings = consumables },
        },
    })

return M
