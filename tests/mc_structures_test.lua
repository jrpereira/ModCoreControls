package.path = 'Scripts/?.lua;' .. package.path

local registry = require('mc_sections')
local count = 0
for name, section in pairs(registry.sections) do
    assert(section.description == '' and next(section.sets) == nil, name)
    count = count + 1
end
assert(count == 3)
for _, name in ipairs({ 'actions', 'movement', 'system' }) do
    assert(registry.sections[name])
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
local actions = maps.maps.actions
assert(#actions.flat.map[1].keys == 8)
assert(#actions.grouped.map[2].keys == 4)
assert(actions.flat.map[2].keys[1].optional == true)
assert(actions.flat.map[2].keys[1].override.value == 164)
assert(actions.flat.map[1].keys[1] ~= actions.grouped.map[2].keys[1])
assert(actions.grouped.map[1].keys[1].override.action=='IA_Combat_ToggleQuickslots')
assert(actions.grouped.map[1].keys[1].override.value==164)
assert(actions.grouped.override[1]=='IA_Combat_ToggleQuickslots')
local flight = maps.addSectionMap('flight', { id='direct', name='Direct', value=0, map={} })
assert(flight == maps.maps.flight.direct and maps.order.flight[1] == 'direct')
assert(not pcall(maps.addSectionMap, 'flight', flight))
assert(not pcall(maps.addSectionMap, '', { id='bad' }))
assert(not pcall(maps.addSectionMap, 'flight', { name='Missing ID' }))

print('PASS initial sections, trigger conversion, and actions maps')
