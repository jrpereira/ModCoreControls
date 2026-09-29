-- Section-scoped map declarations. These describe choices, not live bindings.
local M = { maps = {}, order = {} }

function M.addSectionMap(section, map)
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

-- Initial actions-section declarations.
local fixed = {}
for slot = 1, 8 do
    local position = ((slot - 1) % 4) + 1
    fixed[slot] = {
        id = 'SlotAction' .. slot,
        name = 'Slot ' .. slot,
        trigger = 'Tap|Hold',
        default = 48 + slot,
        action = { type = slot <= 4 and 'ability' or 'consumable', slot = position },
    }
end

local arrows = { 'Left', 'Top', 'Right', 'Bottom' }

local shared = {}
for slot = 1, 4 do
    shared[slot] = {
        id = 'FixedSlot' .. slot,
        name = 'Slot ' .. slot .. ' (or ' .. (slot + 4) .. ')',
        trigger = 'Tap|Hold',
        default = 48 + slot,
        action = { type = 'selected', slot = slot },
    }
    shared[slot].override = {
        action = 'IA_Quickslot_' .. arrows[slot],
        value = 48 + slot,
    }
    fixed[slot].override = shared[slot].override
end

M.addSectionMap('actions', {
        id = 'grouped',
        name = 'Grouped',
        value = 0,
        contexts= {'exploration', 'combat'},
        override = { 'IA_Combat_ToggleQuickslots' },
        map = {
            {
                name = 'Group Focus',
                keys = {
                    {
                        id = 'GroupFocus2', name = 'Alternative',
                        trigger = 'Hold|Tap', sustained = true,
                        action = { type = 'focus', group = 2 },
                        override = { action = 'IA_Combat_ToggleQuickslots', value = 164 },
                    },
                    {
                        id = 'GroupFocus1', name = 'Default',
                        action = { type = 'focus', group = 1 },
                        trigger = 'Hold|Tap', sustained = true,
                        optional = true, default = 0,
                    }
                },
            },
            { name = 'Slot Activation', keys = shared },
        },
    })

M.addSectionMap('actions', {
        id = 'flat',
        name = 'Flat',
        value = 1,
        contexts= {'exploration', 'combat'},
        override = { 'IA_Combat_ToggleQuickslots' },
        map = {
            { name = 'Fixed Controls', keys = fixed },
            {
                name = 'Optional',
                keys = {
                    {
                        id = 'FixedGroupFocus2', name = 'Preview',
                        action = { type = 'focus', group = 2 },
                        trigger = 'Hold|Tap', sustained = true, optional = true,
                        override = { action = 'IA_Combat_ToggleQuickslots', value = 164 },
                    },
                },
            },
        },
    })

return M
