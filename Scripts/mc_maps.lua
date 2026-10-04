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

-- Initial actions-section declarations.
local fixed = {}
for slot = 1, 8 do
    local position = ((slot - 1) % 4) + 1
    fixed[slot] = {
        id = 'SlotAction' .. slot,
        name = 'Slot ' .. slot,
        trigger = 'Tap|Hold',
        default = 0,
        action = { type = slot <= 4 and 'ability' or 'consumable', slot = position },
    }
end

local arrows = { 'Left', 'Top', 'Right', 'Bottom' }

local shared = {}
for slot = 1, 4 do
    shared[slot] = {
        id = 'FixedSlot' .. slot,
        name = 'Slot ' .. slot,
        trigger = 'Tap|Hold',
        default = 0,
        action = { type = 'selected', slot = slot },
    }
    shared[slot].override = {
        action = 'IA_Quickslot_' .. arrows[slot],
        value = 48 + slot,
    }
    fixed[slot].override = shared[slot].override
end

M.addSectionMap('module', {
        id='default',
        name='Default',
        value=0,
        contexts={'exploration','combat'},
        settings={
            {id='SwapOutsideCombat',name='Allow Swap outside of combat',kind='choice',default=1,
                values={0,1},labels={'Off','On'}},
            {id='HoldSwap',name='Hold to Swap, release to return',kind='choice',default=1,
                values={0,1},labels={'Off','On'}},
            {id='DefaultWheel',name='Default wheel',kind='choice',default=2,
                values={1,2},labels={'Abilities','Consumables'}},
        },
        holdSwap={enabled='HoldSwap', defaultWheel='DefaultWheel', outsideCombat='SwapOutsideCombat',
            action='IA_Combat_ToggleQuickslots'},
        map={},
    })

M.addSectionMap('actions', {
        id = 'grouped',
        name = 'Quickslot Groups',
        value = 1,
        contexts= {'exploration', 'combat'},
        -- The shared slot keys fire the focused wheel. Group keys show a wheel
        -- relative to the Default wheel, mirrored here from Default.
        map = {
            { name = 'Active Group', keys = { shared[1], shared[2], shared[3], shared[4] } },
            {
                name = 'Group Activation',
                settings = {
                    { id = 'DefaultGroup', name = 'Default Group',
                        mirror = { section = 'module', map = 'default', setting = 'DefaultWheel' } },
                },
                keys = {
                    {
                        id = 'GroupFocus2', name = 'Secondary Group',
                        trigger = 'Hold|Tap', sustained = true,
                        action = { type = 'focus', wheel = 'other' },
                        optional = true, default = 0,
                    },
                    {
                        id = 'GroupFocus1', name = 'Primary Group',
                        action = { type = 'focus', wheel = 'default' },
                        trigger = 'Hold|Tap', sustained = true,
                        optional = true, default = 0,
                    },
                },
            },
        },
    })

M.addSectionMap('actions', {
        id = 'global',
        name = 'Global',
        value = 2,
        contexts= {'exploration', 'combat'},
        map = {
            { name = 'Global Bindings', keys = fixed },
        },
    })

return M
