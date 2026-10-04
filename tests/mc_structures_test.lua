package.path = 'Scripts/?.lua;' .. package.path

local registry = require('mc_sections')
local count = 0
for name, section in pairs(registry.sections) do
    assert(section.description == '' and next(section.sets) == nil, name)
    count = count + 1
end
assert(count == 4)
for index, name in ipairs({ 'module', 'actions', 'movement', 'system' }) do
    assert(registry.sections[name] and registry.order[index] == name)
end
local added = registry.addSection('flight', 'Flying controls')
assert(added == registry.sections.flight and added.description == 'Flying controls')
added.sets.example = {}
assert(next(registry.sections.movement.sets) == nil)
assert(not pcall(registry.addSection, 'flight', 'Duplicate'))
assert(registry.sections.flight == added)
assert(not pcall(registry.addSection, '', 'Invalid'))
assert(not pcall(registry.addSection, 'invalid', false))

local trigger = require('mc_triggers').toEnhancedInput
assert(trigger('Tap', false) == 0)
assert(trigger('Tap', true) == 0)
assert(trigger('Hold', false) == 1)
assert(trigger('Hold', true) == 2)
assert(trigger('Hold') == 1)
assert(not pcall(trigger, 'Tap|Hold', true))
assert(not pcall(trigger, 'Hold', 'false'))

local maps = require('mc_maps')
assert(type(maps.addSectionMap) == 'function')
for section, sectionMaps in pairs(maps.maps) do
    assert(registry.sections[section])
    for _, mapId in ipairs(maps.order[section]) do
        local definition = assert(sectionMaps[mapId])
        assert(definition.id == mapId)
        local ids = {}
        for _, group in ipairs(definition.map) do
            for _, key in ipairs(group.keys) do
                assert(key.id and not ids[key.id], 'missing or duplicate key ID')
                ids[key.id] = true
                for choice in key.trigger:gmatch('[^|]+') do
                    assert(type(trigger(choice, key.sustained)) == 'number')
                end
            end
        end
    end
end
-- Default holds module-wide settings, so it lives in the Module section.
assert(maps.maps.module.default and maps.maps.actions.default == nil)
local actions = maps.maps.actions
assert(#actions.global.map[1].keys == 8)
-- Quickslot Groups: Active Group holds the shared slots; Group Activation mirrors
-- Default's Default wheel, then the Secondary and Primary Group keys.
local grouped = actions.grouped
assert(grouped.name == 'Quickslot Groups' and #grouped.map == 2)
assert(grouped.map[1].name == 'Active Group' and #grouped.map[1].keys == 4
    and grouped.map[1].keys[1].action.type == 'selected')
local activation = grouped.map[2]
assert(activation.name == 'Group Activation' and #activation.keys == 2)
assert(activation.settings[1].mirror.map == 'default' and activation.settings[1].mirror.setting == 'DefaultWheel')
assert(activation.keys[1].id == 'GroupFocus2' and activation.keys[1].action.wheel == 'other'
    and activation.keys[2].id == 'GroupFocus1' and activation.keys[2].action.wheel == 'default',
    'Group keys keep their config IDs')
assert(#actions.global.map == 1, 'Global has no optional focus key')
assert(actions.global.map[1].keys[1] ~= actions.grouped.map[1].keys[1])
-- Maps coexist with Default's swap on the Toggle Quickslots key, so no other key
-- inherits it, and nothing is bound by default.
assert(activation.keys[1].override == nil and activation.keys[1].defaultControl == nil)
assert(actions.grouped.override == nil and actions.global.override == nil)
assert(actions.global.map[1].keys[1].override.action=='IA_Quickslot_Left')
for _, mapId in ipairs({'grouped', 'global'}) do
    for _, group in ipairs(actions[mapId].map) do
        for _, key in ipairs(group.keys) do
            assert(key.default == 0, 'key must default to Unbound: ' .. key.id)
        end
    end
end
assert(actions.advanced == nil, 'Advanced was removed')
local flight = maps.addSectionMap('flight', { id='direct', name='Direct', value=0, map={} })
assert(flight == maps.maps.flight.direct and maps.order.flight[1] == 'direct')
assert(not pcall(maps.addSectionMap, 'flight', flight))
assert(not pcall(maps.addSectionMap, '', { id='bad' }))
assert(not pcall(maps.addSectionMap, 'flight', { name='Missing ID' }))

print('PASS initial sections, trigger conversion, and actions maps')
