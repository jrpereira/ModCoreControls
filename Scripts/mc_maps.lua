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
        default = 48 + slot,
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
        id='default',
        name='Default',
        value=0,
        contexts={'exploration','combat'},
        settings={
            {id='SwapOutsideCombat',name='Allow Swap outside of combat',kind='choice',default=1,
                values={0,1},labels={'Off','On'}},
            {id='HoldSwap',name='Hold to Swap, release to return',kind='choice',default=0,
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
        name = 'Grouped',
        value = 1,
        contexts= {'exploration', 'combat'},
        -- Group 1 is the Default wheel, in effect at rest; the shared slot keys
        -- fire the focused wheel. Group 2 is the other wheel.
        map = {
            {
                name = 'Group 1', wheel = 'default',
                keys = {
                    {
                        id = 'GroupFocus1', name = 'Group',
                        action = { type = 'focus', wheel = 'default' },
                        trigger = 'Hold|Tap', sustained = true,
                        optional = true, default = 0,
                    },
                    shared[1], shared[2], shared[3], shared[4],
                },
            },
            {
                name = 'Group 2', wheel = 'other',
                keys = {
                    {
                        id = 'GroupFocus2', name = 'Group',
                        trigger = 'Hold|Tap', sustained = true,
                        action = { type = 'focus', wheel = 'other' },
                        defaultControl = 'IA_Combat_ToggleQuickslots',
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
            {
                name = 'Optional',
                keys = {
                    {
                        id = 'FixedGroupFocus2', name = 'Show Controls (if hidden)',
                        action = { type = 'focus', group = 2 },
                        trigger = 'Hold|Tap', sustained = true, optional = true,
                        default = 0, defaultControl = 'IA_Combat_ToggleQuickslots'
                    },
                },
            },
        },
    })

local function advancedSlots(first,kind,group,inactive)
    local keys={
        {
            id='AdvancedGroup'..group, name='Group', trigger='Hold|Tap',
            sustained=true, optional=true, default=0,
            defaultControl=group==2 and 'IA_Combat_ToggleQuickslots' or nil,
            action={type='focus',group=group}, inactive=inactive,
        },
    }
    for offset=0,3 do
        keys[#keys+1]={
            id='AdvancedSlot'..(first+offset), name='Slot '..(first+offset),
            trigger='Tap|Hold', default=inactive and 0 or 48+first+offset,
            action={type=kind,slot=offset+1}, inactive=inactive,
            groupedBy='AdvancedGroup'..group,
            -- Unassigned virtual-key range, used only as a stable display
            -- alias for Slots 1–8.  It is never offered to key capture or
            -- emitted as an Enhanced Input mapping.
            displayAlias=not inactive and first+offset+0xC0 or nil,
        }
    end
    return {name='Slots '..first..'–'..(first+3)..' · Global',keys=keys}
end

M.addSectionMap('actions', {
        id='advanced',
        name='Advanced',
        value=3,
        contexts={'exploration','combat'},
        map={
            advancedSlots(1,'ability',1,false),
            advancedSlots(5,'consumable',2,false),
            -- Saved now, deliberately inactive until a third game group exists.
            advancedSlots(9,'ability',3,true),
        },
    })

return M
